const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════════
// NEXUS MODS API CLIENT
// ═══════════════════════════════════════════════════════════════════════════════
//
// Official Nexus Mods API v1 client for STL-Next.
// 
// Base URL: https://api.nexusmods.com/v1
//
// Features:
//   - API key authentication
//   - Rate limiting awareness (2500/day, 100/hour after limit)
//   - Premium download link generation
//   - Mod info retrieval
//   - User tracking and endorsements
//
// API Key Sources (in order of priority):
//   1. STL_NEXUS_API_KEY environment variable
//   2. ~/.config/stl-next/nexus_api_key file
//   3. sops-nix/agenix decrypted secret (NixOS)
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const NexusError = error{
    NoApiKey,
    InvalidApiKey,
    RateLimited,
    NotPremium,
    ModNotFound,
    FileNotFound,
    NetworkError,
    ParseError,
    OutOfMemory,
};

/// User information returned by /v1/users/validate.json
pub const UserInfo = struct {
    user_id: u64,
    name: []const u8,
    email: ?[]const u8,
    is_premium: bool,
    is_supporter: bool,
    profile_url: []const u8,

    pub fn deinit(self: *UserInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.email) |e| allocator.free(e);
        allocator.free(self.profile_url);
    }
};

/// Mod information
pub const ModInfo = struct {
    mod_id: u64,
    game_id: u64,
    domain_name: []const u8,
    name: []const u8,
    summary: []const u8,
    version: []const u8,
    author: []const u8,
    category_id: u64,
    endorsement_count: u64,
    created_timestamp: i64,
    updated_timestamp: i64,

    pub fn deinit(self: *ModInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.domain_name);
        allocator.free(self.name);
        allocator.free(self.summary);
        allocator.free(self.version);
        allocator.free(self.author);
    }
};

/// File information for a mod
pub const FileInfo = struct {
    file_id: u64,
    name: []const u8,
    version: []const u8,
    category_id: u64,
    category_name: []const u8,
    is_primary: bool,
    size: u64, // Size in bytes
    file_name: []const u8,
    uploaded_timestamp: i64,
    mod_version: []const u8,
    external_virus_scan_url: ?[]const u8,
    description: []const u8,
    changelog_html: ?[]const u8,

    pub fn deinit(self: *FileInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.category_name);
        allocator.free(self.file_name);
        allocator.free(self.mod_version);
        if (self.external_virus_scan_url) |u| allocator.free(u);
        allocator.free(self.description);
        if (self.changelog_html) |c| allocator.free(c);
    }
};

/// Download link (requires Premium or NXM key+expiry)
pub const DownloadLink = struct {
    name: []const u8,
    short_name: []const u8,
    uri: []const u8,

    pub fn deinit(self: *DownloadLink, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.short_name);
        allocator.free(self.uri);
    }
};

/// Rate limit information from response headers
pub const RateLimitInfo = struct {
    hourly_limit: u32,
    hourly_remaining: u32,
    hourly_reset: []const u8,
    daily_limit: u32,
    daily_remaining: u32,
    daily_reset: []const u8,
};

/// Nexus Mods API Client
pub const NexusClient = struct {
    allocator: std.mem.Allocator,
    api_key: ?[]const u8,
    user_agent: []const u8,
    last_rate_limit: ?RateLimitInfo,

    const Self = @This();
    const BASE_URL = "https://api.nexusmods.com/v1";
    const DEFAULT_USER_AGENT = "STL-Next/0.5.4 (Linux; Zig)";

    /// Initialize with automatic API key discovery
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .api_key = null,
            .user_agent = DEFAULT_USER_AGENT,
            .last_rate_limit = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.api_key) |key| {
            self.allocator.free(key);
        }
    }

    /// Set API key manually
    pub fn setApiKey(self: *Self, key: []const u8) !void {
        if (self.api_key) |old| {
            self.allocator.free(old);
        }
        self.api_key = try self.allocator.dupe(u8, key);
    }

    /// Discover API key from environment and config files
    pub fn discoverApiKey(self: *Self) !void {
        // Priority 1: Environment variable
        if (std.posix.getenv("STL_NEXUS_API_KEY")) |env_key| {
            try self.setApiKey(env_key);
            std.log.info("Nexus API key loaded from STL_NEXUS_API_KEY environment variable", .{});
            return;
        }

        // Priority 2: Config file
        const home = std.posix.getenv("HOME") orelse return NexusError.NoApiKey;
        const config_path = try std.fmt.allocPrint(self.allocator, "{s}/.config/stl-next/nexus_api_key", .{home});
        defer self.allocator.free(config_path);

        if (std.fs.openFileAbsolute(config_path, .{})) |file| {
            defer file.close();
            var buf: [256]u8 = undefined;
            const bytes_read = file.readAll(&buf) catch return NexusError.NoApiKey;
            if (bytes_read > 0) {
                // Trim whitespace
                var end = bytes_read;
                while (end > 0 and (buf[end - 1] == '\n' or buf[end - 1] == '\r' or buf[end - 1] == ' ')) {
                    end -= 1;
                }
                if (end > 0) {
                    try self.setApiKey(buf[0..end]);
                    std.log.info("Nexus API key loaded from {s}", .{config_path});
                    return;
                }
            }
        } else |_| {}

        // Priority 3: NixOS sops-nix/agenix location
        const nix_secret_paths = [_][]const u8{
            "/run/secrets/nexus_api_key",
            "/run/agenix/nexus_api_key",
        };

        for (nix_secret_paths) |secret_path| {
            if (std.fs.openFileAbsolute(secret_path, .{})) |file| {
                defer file.close();
                var buf: [256]u8 = undefined;
                const bytes_read = file.readAll(&buf) catch continue;
                if (bytes_read > 0) {
                    var end = bytes_read;
                    while (end > 0 and (buf[end - 1] == '\n' or buf[end - 1] == '\r' or buf[end - 1] == ' ')) {
                        end -= 1;
                    }
                    if (end > 0) {
                        try self.setApiKey(buf[0..end]);
                        std.log.info("Nexus API key loaded from NixOS secret: {s}", .{secret_path});
                        return;
                    }
                }
            } else |_| {}
        }

        return NexusError.NoApiKey;
    }

    /// Validate API key and get user info
    pub fn validateKey(self: *Self) NexusError!UserInfo {
        const key = self.api_key orelse return NexusError.NoApiKey;
        _ = key;

        // TODO: Implement actual HTTP request using std.http.Client
        // For now, return placeholder
        return NexusError.NetworkError;
    }

    /// Get mod information
    pub fn getMod(self: *Self, game_domain: []const u8, mod_id: u64) NexusError!ModInfo {
        const key = self.api_key orelse return NexusError.NoApiKey;
        _ = key;
        _ = game_domain;
        _ = mod_id;

        // TODO: Implement actual HTTP request
        return NexusError.NetworkError;
    }

    /// Get files for a mod
    pub fn getModFiles(self: *Self, game_domain: []const u8, mod_id: u64) NexusError![]FileInfo {
        const key = self.api_key orelse return NexusError.NoApiKey;
        _ = key;
        _ = game_domain;
        _ = mod_id;

        // TODO: Implement actual HTTP request
        return NexusError.NetworkError;
    }

    /// Generate download link (PREMIUM ONLY for direct access)
    /// Non-premium users must use NXM links with key and expiry from browser
    pub fn getDownloadLink(
        self: *Self,
        game_domain: []const u8,
        mod_id: u64,
        file_id: u64,
        nxm_key: ?[]const u8,
        nxm_expiry: ?i64,
    ) NexusError![]DownloadLink {
        const key = self.api_key orelse return NexusError.NoApiKey;
        _ = key;
        _ = game_domain;
        _ = mod_id;
        _ = file_id;
        _ = nxm_key;
        _ = nxm_expiry;

        // Note: If nxm_key and nxm_expiry are null, requires Premium membership
        // TODO: Implement actual HTTP request
        return NexusError.NetworkError;
    }

    /// Track a mod for updates
    pub fn trackMod(self: *Self, game_domain: []const u8, mod_id: u64) NexusError!void {
        const key = self.api_key orelse return NexusError.NoApiKey;
        _ = key;
        _ = game_domain;
        _ = mod_id;

        // TODO: Implement actual HTTP request
        return NexusError.NetworkError;
    }

    /// Endorse a mod
    pub fn endorseMod(self: *Self, game_domain: []const u8, mod_id: u64, version: []const u8) NexusError!void {
        const key = self.api_key orelse return NexusError.NoApiKey;
        _ = key;
        _ = game_domain;
        _ = mod_id;
        _ = version;

        // TODO: Implement actual HTTP request
        return NexusError.NetworkError;
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// SECRET MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Save API key to config file
pub fn saveApiKey(allocator: std.mem.Allocator, api_key: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;

    // Ensure config directory exists
    const config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/stl-next", .{home});
    defer allocator.free(config_dir);
    std.fs.makeDirAbsolute(config_dir) catch |e| {
        if (e != error.PathAlreadyExists) return e;
    };

    // Write API key with restricted permissions
    const key_path = try std.fmt.allocPrint(allocator, "{s}/nexus_api_key", .{config_dir});
    defer allocator.free(key_path);

    const file = try std.fs.createFileAbsolute(key_path, .{ .mode = 0o600 });
    defer file.close();
    try file.writeAll(api_key);

    std.log.info("API key saved to {s} with mode 600", .{key_path});
}

/// Generate NixOS module for secret management
pub fn generateNixOsSecretConfig(allocator: std.mem.Allocator, output_path: []const u8) !void {
    const config =
        \\# STL-Next Nexus Mods API Key Configuration
        \\#
        \\# Option 1: Using sops-nix (recommended)
        \\# Add to your flake.nix or configuration.nix:
        \\#
        \\# sops.secrets.nexus_api_key = {
        \\#   sopsFile = ./secrets/nexus.yaml;
        \\#   owner = config.users.users.YOUR_USERNAME.name;
        \\# };
        \\#
        \\# Then create secrets/nexus.yaml:
        \\# nexus_api_key: YOUR_API_KEY_HERE
        \\#
        \\# Option 2: Using agenix
        \\# age.secrets.nexus_api_key = {
        \\#   file = ./secrets/nexus_api_key.age;
        \\#   owner = "YOUR_USERNAME";
        \\# };
        \\#
        \\# Option 3: Environment variable in systemd service
        \\# systemd.services.stl-next.environment = {
        \\#   STL_NEXUS_API_KEY = "\${config.sops.secrets.nexus_api_key.path}";
        \\# };
        \\#
        \\# The decrypted secret will be available at:
        \\# /run/secrets/nexus_api_key (sops-nix)
        \\# /run/agenix/nexus_api_key (agenix)
        \\
    ;

    const file = try std.fs.createFileAbsolute(output_path, .{});
    defer file.close();
    try file.writeAll(config);
    _ = allocator;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "nexus client init" {
    var client = NexusClient.init(std.testing.allocator);
    defer client.deinit();

    try std.testing.expect(client.api_key == null);
}

test "nexus client set api key" {
    var client = NexusClient.init(std.testing.allocator);
    defer client.deinit();

    try client.setApiKey("test_key_12345");
    try std.testing.expect(client.api_key != null);
    try std.testing.expectEqualStrings("test_key_12345", client.api_key.?);
}

