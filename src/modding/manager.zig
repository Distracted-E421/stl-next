const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════════
// MOD MANAGER INTEGRATION (Phase 4)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Support for:
// - Mod Organizer 2 (MO2)
// - Vortex
// - NXM Protocol Handling
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const ModManager = enum {
    None,
    MO2,
    Vortex,
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
    }

    /// Detect if MO2 is installed in the prefix
    pub fn detectMO2(self: *Self) !bool {
        // Common MO2 locations in Wine prefix
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
            defer self.allocator.free(full_path);

            if (std.fs.accessAbsolute(full_path, .{})) {
                self.config.manager = .MO2;
                self.config.executable_path = try self.allocator.dupe(u8, full_path);
                std.log.info("Mod Manager: Detected MO2 at {s}", .{full_path});
                return true;
            } else |_| {}
        }

        return false;
    }

    /// Detect if Vortex is installed
    pub fn detectVortex(self: *Self) !bool {
        const vortex_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/drive_c/Program Files/Black Tree Gaming Ltd/Vortex/Vortex.exe",
            .{self.wine_prefix},
        );
        defer self.allocator.free(vortex_path);

        if (std.fs.accessAbsolute(vortex_path, .{})) {
            self.config.manager = .Vortex;
            self.config.executable_path = try self.allocator.dupe(u8, vortex_path);
            std.log.info("Mod Manager: Detected Vortex", .{});
            return true;
        } else |_| {}

        return false;
    }

    /// Get Wine DLL overrides for USVFS
    pub fn getUsvfsDllOverrides(self: *Self) !?[]const u8 {
        if (self.config.manager != .MO2 or !self.config.usvfs_enabled) {
            return null;
        }

        return try self.allocator.dupe(u8, "nxmhandler=n;usvfs_proxy_x86=n;usvfs_proxy_x64=n");
    }

    /// Get environment variables for mod manager
    pub fn getModManagerEnv(self: *Self, env: *std.process.EnvMap) !void {
        if (self.config.manager == .None) return;

        // Set MO2-specific variables
        if (self.config.manager == .MO2) {
            if (self.config.instance_path) |instance| {
                try env.put("MO2_INSTANCE", instance);
            }
            if (self.config.profile_name) |profile| {
                try env.put("MO2_PROFILE", profile);
            }
        }

        // DLL overrides for USVFS
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
// NXM PROTOCOL HANDLER
// ═══════════════════════════════════════════════════════════════════════════════

pub const NxmLink = struct {
    mod_id: u32,
    file_id: u32,
    game_domain: []const u8,
    key: ?[]const u8,
    expires: ?u64,

    pub fn parse(allocator: std.mem.Allocator, url: []const u8) !NxmLink {
        // Format: nxm://gamename/mods/modid/files/fileid?key=xxx&expires=xxx
        
        if (!std.mem.startsWith(u8, url, "nxm://")) {
            return error.InvalidNxmUrl;
        }

        const path = url[6..]; // Skip "nxm://"
        
        // Find game domain
        var iter = std.mem.splitScalar(u8, path, '/');
        const game_domain = iter.next() orelse return error.InvalidNxmUrl;
        
        // Skip "mods"
        _ = iter.next();
        
        // Get mod ID
        const mod_id_str = iter.next() orelse return error.InvalidNxmUrl;
        const mod_id = try std.fmt.parseInt(u32, mod_id_str, 10);
        
        // Skip "files"
        _ = iter.next();
        
        // Get file ID (might have query params)
        const file_part = iter.next() orelse return error.InvalidNxmUrl;
        var file_iter = std.mem.splitScalar(u8, file_part, '?');
        const file_id_str = file_iter.next() orelse return error.InvalidNxmUrl;
        const file_id = try std.fmt.parseInt(u32, file_id_str, 10);
        
        return NxmLink{
            .mod_id = mod_id,
            .file_id = file_id,
            .game_domain = try allocator.dupe(u8, game_domain),
            .key = null,
            .expires = null,
        };
    }

    pub fn deinit(self: *NxmLink, allocator: std.mem.Allocator) void {
        allocator.free(self.game_domain);
        if (self.key) |k| allocator.free(k);
    }
};

/// Handle an NXM link by forwarding to the appropriate mod manager
pub fn handleNxmLink(
    allocator: std.mem.Allocator,
    url: []const u8,
    ctx: *ModManagerContext,
) !void {
    var link = try NxmLink.parse(allocator, url);
    defer link.deinit(allocator);

    std.log.info("NXM: Game={s} Mod={d} File={d}", .{
        link.game_domain,
        link.mod_id,
        link.file_id,
    });

    if (ctx.config.manager == .MO2) {
        // Forward to MO2's nxmhandler
        const nxm_handler = try std.fmt.allocPrint(
            allocator,
            "{s}/drive_c/Modding/MO2/nxmhandler.exe",
            .{ctx.wine_prefix},
        );
        defer allocator.free(nxm_handler);

        std.log.info("NXM: Forwarding to MO2 nxmhandler", .{});
        // Would spawn wine nxmhandler.exe "<url>"
    } else if (ctx.config.manager == .Vortex) {
        std.log.info("NXM: Forwarding to Vortex", .{});
        // Would use Vortex's download API
    } else {
        std.log.warn("NXM: No mod manager configured", .{});
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "parse nxm link" {
    var link = try NxmLink.parse(
        std.testing.allocator,
        "nxm://stardewvalley/mods/12345/files/67890",
    );
    defer link.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 12345), link.mod_id);
    try std.testing.expectEqual(@as(u32, 67890), link.file_id);
    try std.testing.expectEqualStrings("stardewvalley", link.game_domain);
}

test "parse nxm link with query" {
    var link = try NxmLink.parse(
        std.testing.allocator,
        "nxm://skyrimse/mods/1000/files/2000?key=abc&expires=123",
    );
    defer link.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 1000), link.mod_id);
    try std.testing.expectEqual(@as(u32, 2000), link.file_id);
}

