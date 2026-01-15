const std = @import("std");
pub const vortex = @import("vortex.zig");
pub const stardrop = @import("stardrop.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// MOD MANAGER INTEGRATION (Phase 7 - Stardrop + Collections)
// ═══════════════════════════════════════════════════════════════════════════════
//
// IMPORTANT: This module exists because of bugs like the STL URL truncation issue
// where forward slashes in NXM URLs were stripped by Wine's command parsing.
//
// We handle ALL URL encoding/escaping properly to avoid such issues.
//
// Supports:
//   - Vortex (via Wine/Proton)
//   - MO2 (via Wine/Proton)  
//   - Stardrop (native Linux) - RECOMMENDED for Stardew Valley
//   - Direct NXM download handling
//   - Nexus Collections Import (KILLER FEATURE!)
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const ModManager = enum {
    None,
    MO2,
    Vortex,
    Stardrop,
    Custom,
};

pub const ModManagerConfig = struct {
    manager: ModManager = .None,
    executable_path: ?[]const u8 = null,
    instance_path: ?[]const u8 = null,
    profile_name: ?[]const u8 = null,
    usvfs_enabled: bool = true,
};

pub const ModManagerContext = struct {
    allocator: std.mem.Allocator,
    config: ModManagerConfig,
    wine_prefix: []const u8,
    game_install_dir: []const u8,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        wine_prefix: []const u8,
        game_install_dir: []const u8,
    ) !Self {
        return Self{
            .allocator = allocator,
            .config = .{},
            .wine_prefix = try allocator.dupe(u8, wine_prefix),
            .game_install_dir = try allocator.dupe(u8, game_install_dir),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.wine_prefix);
        self.allocator.free(self.game_install_dir);
        if (self.config.executable_path) |p| self.allocator.free(p);
        if (self.config.instance_path) |p| self.allocator.free(p);
        if (self.config.profile_name) |p| self.allocator.free(p);
    }

    pub fn detectMO2(self: *Self) !bool {
        const mo2_paths = [_][]const u8{
            "/drive_c/Modding/MO2/ModOrganizer.exe",
            "/drive_c/Program Files/Mod Organizer 2/ModOrganizer.exe",
            "/drive_c/MO2/ModOrganizer.exe",
        };

        for (mo2_paths) |suffix| {
            const full_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}{s}",
                .{ self.wine_prefix, suffix },
            );
            
            if (std.fs.accessAbsolute(full_path, .{})) {
                self.config.manager = .MO2;
                self.config.executable_path = full_path;
                std.log.info("Mod Manager: Detected MO2 at {s}", .{full_path});
                return true;
            } else |_| {
                self.allocator.free(full_path);
            }
        }

        return false;
    }

    pub fn detectVortex(self: *Self) !bool {
        const vortex_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/drive_c/Program Files/Black Tree Gaming Ltd/Vortex/Vortex.exe",
            .{self.wine_prefix},
        );

        if (std.fs.accessAbsolute(vortex_path, .{})) {
            self.config.manager = .Vortex;
            self.config.executable_path = vortex_path;
            std.log.info("Mod Manager: Detected Vortex", .{});
            return true;
        } else |_| {
            self.allocator.free(vortex_path);
        }

        return false;
    }

    pub fn getUsvfsDllOverrides(self: *Self) !?[]const u8 {
        if (self.config.manager != .MO2 or !self.config.usvfs_enabled) {
            return null;
        }
        return try self.allocator.dupe(u8, "nxmhandler=n;usvfs_proxy_x86=n;usvfs_proxy_x64=n");
    }

    pub fn getModManagerEnv(self: *Self, env: *std.process.EnvMap) !void {
        if (self.config.manager == .None) return;

        if (self.config.manager == .MO2) {
            if (self.config.instance_path) |instance| {
                try env.put("MO2_INSTANCE", instance);
            }
            if (self.config.profile_name) |profile| {
                try env.put("MO2_PROFILE", profile);
            }
        }

        if (try self.getUsvfsDllOverrides()) |overrides| {
            defer self.allocator.free(overrides);
            
            const existing = env.get("WINEDLLOVERRIDES");
            if (existing) |e| {
                const combined = try std.fmt.allocPrint(
                    self.allocator,
                    "{s};{s}",
                    .{ e, overrides },
                );
                try env.put("WINEDLLOVERRIDES", combined);
            } else {
                try env.put("WINEDLLOVERRIDES", overrides);
            }
        }
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// NXM PROTOCOL HANDLER (HARDENED)
// ═══════════════════════════════════════════════════════════════════════════════
//
// This is critical code. The original STL had a bug where Wine stripped forward
// slashes from URLs (interpreting them as command switches). We handle this
// properly by:
// 1. Validating URLs completely before processing
// 2. URL-encoding when passing to Wine
// 3. Preserving ALL parts including /revisions/N for collections
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const NxmError = error{
    InvalidScheme,
    MissingGameDomain,
    MissingModId,
    MissingFileId,
    InvalidModId,
    InvalidFileId,
    InvalidRevisionId,
    MalformedUrl,
    UrlTooLong,
    EmptyUrl,
};

pub const NxmLinkType = enum {
    Mod,        // nxm://game/mods/123/files/456
    Collection, // nxm://game/collections/abc/revisions/100
    Unknown,
};

pub const NxmLink = struct {
    link_type: NxmLinkType,
    game_domain: []const u8,
    
    // For mods
    mod_id: ?u32 = null,
    file_id: ?u32 = null,
    
    // For collections
    collection_slug: ?[]const u8 = null,
    revision_id: ?u32 = null,
    
    // Query params
    key: ?[]const u8 = null,
    expires: ?u64 = null,
    
    // Original URL preserved
    original_url: []const u8,

    const Self = @This();

    /// Parse an NXM URL with full validation
    /// Handles both mod URLs and collection URLs (including revisions!)
    pub fn parse(allocator: std.mem.Allocator, url: []const u8) !Self {
        // Validate not empty
        if (url.len == 0) return NxmError.EmptyUrl;
        
        // Validate length (prevent DoS)
        if (url.len > 2048) return NxmError.UrlTooLong;
        
        // Validate scheme
        if (!std.mem.startsWith(u8, url, "nxm://")) {
            return NxmError.InvalidScheme;
        }

        const path = url[6..]; // Skip "nxm://"
        if (path.len == 0) return NxmError.MissingGameDomain;
        
        // Split path from query string
        var path_part = path;
        var query_part: ?[]const u8 = null;
        if (std.mem.indexOf(u8, path, "?")) |q_pos| {
            path_part = path[0..q_pos];
            query_part = path[q_pos + 1..];
        }
        
        // Parse path segments
        var segments = std.mem.splitScalar(u8, path_part, '/');
        
        // First segment is game domain
        const game_domain = segments.next() orelse return NxmError.MissingGameDomain;
        if (game_domain.len == 0) return NxmError.MissingGameDomain;
        
        // Second segment determines type (mods or collections)
        const type_segment = segments.next() orelse return NxmError.MalformedUrl;
        
        var link = Self{
            .link_type = .Unknown,
            .game_domain = try allocator.dupe(u8, game_domain),
            .original_url = try allocator.dupe(u8, url),
        };
        errdefer {
            allocator.free(link.game_domain);
            allocator.free(link.original_url);
            if (link.collection_slug) |s| allocator.free(s);
            if (link.key) |k| allocator.free(k);
        }
        
        if (std.mem.eql(u8, type_segment, "mods")) {
            link.link_type = .Mod;
            
            // Parse mod ID
            const mod_id_str = segments.next() orelse return NxmError.MissingModId;
            link.mod_id = std.fmt.parseInt(u32, mod_id_str, 10) catch return NxmError.InvalidModId;
            
            // Skip "files"
            const files_segment = segments.next();
            if (files_segment) |fs| {
                if (!std.mem.eql(u8, fs, "files")) {
                    // Might be directly the file ID in some URL variants
                    link.file_id = std.fmt.parseInt(u32, fs, 10) catch null;
                } else {
                    // Get file ID
                    const file_id_str = segments.next() orelse return NxmError.MissingFileId;
                    link.file_id = std.fmt.parseInt(u32, file_id_str, 10) catch return NxmError.InvalidFileId;
                }
            }
            
        } else if (std.mem.eql(u8, type_segment, "collections")) {
            link.link_type = .Collection;
            
            // Parse collection slug
            const slug = segments.next() orelse return NxmError.MalformedUrl;
            link.collection_slug = try allocator.dupe(u8, slug);
            
            // CRITICAL: Parse revisions segment - this is what STL was dropping!
            const revisions_segment = segments.next();
            if (revisions_segment) |rs| {
                if (std.mem.eql(u8, rs, "revisions")) {
                    const revision_str = segments.next();
                    if (revision_str) |rev| {
                        link.revision_id = std.fmt.parseInt(u32, rev, 10) catch return NxmError.InvalidRevisionId;
                    }
                }
            }
        } else {
            link.link_type = .Unknown;
        }
        
        // Parse query parameters
        if (query_part) |qp| {
            var params = std.mem.splitScalar(u8, qp, '&');
            while (params.next()) |param| {
                if (std.mem.indexOf(u8, param, "=")) |eq_pos| {
                    const key = param[0..eq_pos];
                    const value = param[eq_pos + 1..];
                    
                    if (std.mem.eql(u8, key, "key")) {
                        link.key = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, key, "expires")) {
                        link.expires = std.fmt.parseInt(u64, value, 10) catch null;
                    }
                }
            }
        }
        
        return link;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.game_domain);
        allocator.free(self.original_url);
        if (self.collection_slug) |s| allocator.free(s);
        if (self.key) |k| allocator.free(k);
    }
    
    /// Check if this is a valid, complete link
    pub fn isValid(self: *const Self) bool {
        return switch (self.link_type) {
            .Mod => self.mod_id != null,
            .Collection => self.collection_slug != null,
            .Unknown => false,
        };
    }
    
    /// Get a display-safe representation
    pub fn toDisplayString(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self.link_type) {
            .Mod => blk: {
                if (self.file_id) |fid| {
                    break :blk try std.fmt.allocPrint(
                        allocator,
                        "Mod: {s}/mods/{d}/files/{d}",
                        .{ self.game_domain, self.mod_id.?, fid },
                    );
                } else {
                    break :blk try std.fmt.allocPrint(
                        allocator,
                        "Mod: {s}/mods/{d}",
                        .{ self.game_domain, self.mod_id.? },
                    );
                }
            },
            .Collection => blk: {
                if (self.revision_id) |rid| {
                    break :blk try std.fmt.allocPrint(
                        allocator,
                        "Collection: {s}/collections/{s}/revisions/{d}",
                        .{ self.game_domain, self.collection_slug.?, rid },
                    );
                } else {
                    break :blk try std.fmt.allocPrint(
                        allocator,
                        "Collection: {s}/collections/{s}",
                        .{ self.game_domain, self.collection_slug.? },
                    );
                }
            },
            .Unknown => try allocator.dupe(u8, "Unknown NXM link type"),
        };
    }
    
    /// URL-encode for safe passing to Wine
    /// This is the FIX for the STL bug!
    pub fn encodeForWine(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        // Wine interprets / as command switches, so we encode them
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(allocator);
        
        // Keep the scheme as-is
        try result.appendSlice(allocator, "nxm://");
        
        // Encode the rest - replace / with %2F
        const rest = self.original_url[6..];
        for (rest) |c| {
            switch (c) {
                '/' => try result.appendSlice(allocator, "%2F"),
                ' ' => try result.appendSlice(allocator, "%20"),
                '"' => try result.appendSlice(allocator, "%22"),
                else => try result.append(allocator, c),
            }
        }
        
        return result.toOwnedSlice(allocator);
    }
};

/// Handle an NXM link with proper validation and encoding
pub fn handleNxmLink(
    allocator: std.mem.Allocator,
    url: []const u8,
    ctx: ?*ModManagerContext,
) !void {
    var link = NxmLink.parse(allocator, url) catch |err| {
        std.log.err("NXM: Failed to parse URL: {}", .{err});
        std.log.err("NXM: URL was: {s}", .{url});
        return err;
    };
    defer link.deinit(allocator);

    // Log what we parsed
    const formatted = try link.toDisplayString(allocator);
    defer allocator.free(formatted);
    std.log.info("NXM: Parsed: {s}", .{formatted});
    
    if (!link.isValid()) {
        std.log.err("NXM: Link is incomplete or invalid", .{});
        return NxmError.MalformedUrl;
    }
    
    // Special handling for collections
    if (link.link_type == .Collection) {
        if (link.revision_id == null) {
            std.log.warn("NXM: Collection URL missing revision ID", .{});
            std.log.warn("NXM: This may cause issues - collections need /revisions/N", .{});
        } else {
            std.log.info("NXM: Collection revision: {d}", .{link.revision_id.?});
        }
    }

    if (ctx) |c| {
        if (c.config.manager == .MO2 or c.config.manager == .Vortex) {
            // Get the Wine-safe encoded URL
            const encoded = try link.encodeForWine(allocator);
            defer allocator.free(encoded);
            
            std.log.info("NXM: Wine-safe URL: {s}", .{encoded});
            std.log.info("NXM: Would forward to {s}", .{
                if (c.config.manager == .MO2) "MO2" else "Vortex"
            });
        }
    } else {
        std.log.info("NXM: No mod manager configured", .{});
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS - Comprehensive edge cases
// ═══════════════════════════════════════════════════════════════════════════════

test "parse mod link - basic" {
    var link = try NxmLink.parse(
        std.testing.allocator,
        "nxm://stardewvalley/mods/12345/files/67890",
    );
    defer link.deinit(std.testing.allocator);

    try std.testing.expectEqual(NxmLinkType.Mod, link.link_type);
    try std.testing.expectEqual(@as(u32, 12345), link.mod_id.?);
    try std.testing.expectEqual(@as(u32, 67890), link.file_id.?);
    try std.testing.expectEqualStrings("stardewvalley", link.game_domain);
}

test "parse collection link - with revision (THE BUG FIX)" {
    // This is the exact URL format that STL was truncating!
    var link = try NxmLink.parse(
        std.testing.allocator,
        "nxm://stardewvalley/collections/tckf0m/revisions/100",
    );
    defer link.deinit(std.testing.allocator);

    try std.testing.expectEqual(NxmLinkType.Collection, link.link_type);
    try std.testing.expectEqualStrings("stardewvalley", link.game_domain);
    try std.testing.expectEqualStrings("tckf0m", link.collection_slug.?);
    try std.testing.expectEqual(@as(u32, 100), link.revision_id.?);
}

test "parse collection link - without revision" {
    var link = try NxmLink.parse(
        std.testing.allocator,
        "nxm://skyrimse/collections/abc123",
    );
    defer link.deinit(std.testing.allocator);

    try std.testing.expectEqual(NxmLinkType.Collection, link.link_type);
    try std.testing.expectEqualStrings("abc123", link.collection_slug.?);
    try std.testing.expect(link.revision_id == null);
}

test "parse mod link - with query params" {
    var link = try NxmLink.parse(
        std.testing.allocator,
        "nxm://skyrimse/mods/1000/files/2000?key=abc123&expires=9999999",
    );
    defer link.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 1000), link.mod_id.?);
    try std.testing.expectEqual(@as(u32, 2000), link.file_id.?);
    try std.testing.expectEqualStrings("abc123", link.key.?);
    try std.testing.expectEqual(@as(u64, 9999999), link.expires.?);
}

test "encode for wine - slashes replaced" {
    var link = try NxmLink.parse(
        std.testing.allocator,
        "nxm://stardewvalley/collections/tckf0m/revisions/100",
    );
    defer link.deinit(std.testing.allocator);
    
    const encoded = try link.encodeForWine(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    
    // Verify no raw slashes after nxm://
    try std.testing.expect(std.mem.indexOf(u8, encoded[6..], "/") == null);
    // Verify encoded slashes present
    try std.testing.expect(std.mem.indexOf(u8, encoded, "%2F") != null);
}

test "invalid scheme" {
    const result = NxmLink.parse(std.testing.allocator, "https://nexusmods.com");
    try std.testing.expectError(NxmError.InvalidScheme, result);
}

test "empty url" {
    const result = NxmLink.parse(std.testing.allocator, "");
    try std.testing.expectError(NxmError.EmptyUrl, result);
}

test "missing game domain" {
    const result = NxmLink.parse(std.testing.allocator, "nxm://");
    try std.testing.expectError(NxmError.MissingGameDomain, result);
}

test "invalid mod id" {
    const result = NxmLink.parse(std.testing.allocator, "nxm://game/mods/notanumber/files/1");
    try std.testing.expectError(NxmError.InvalidModId, result);
}

test "url too long" {
    var long_url: [3000]u8 = undefined;
    @memset(&long_url, 'a');
    @memcpy(long_url[0..6], "nxm://");
    
    const result = NxmLink.parse(std.testing.allocator, &long_url);
    try std.testing.expectError(NxmError.UrlTooLong, result);
}

test "link validation" {
    var valid_link = try NxmLink.parse(
        std.testing.allocator,
        "nxm://game/mods/123/files/456",
    );
    defer valid_link.deinit(std.testing.allocator);
    try std.testing.expect(valid_link.isValid());
}
