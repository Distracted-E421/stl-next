const std = @import("std");
const http = std.http;

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
// IMPORTANT: Never hardcode API keys! Use environment or secret files.
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
    Forbidden,
    ServerError,
};

const BASE_URL = "https://api.nexusmods.com/v1";
const USER_AGENT = "STL-Next/0.5.4 (Linux; Zig)";

/// User information returned by /v1/users/validate.json
pub const UserInfo = struct {
    user_id: u64,
    key: []const u8,
    name: []const u8,
    email: ?[]const u8,
    is_premium: bool,
    is_supporter: bool,
    profile_url: []const u8,

    pub fn deinit(self: *UserInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
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
    picture_url: ?[]const u8,

    pub fn deinit(self: *ModInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.domain_name);
        allocator.free(self.name);
        allocator.free(self.summary);
        allocator.free(self.version);
        allocator.free(self.author);
        if (self.picture_url) |p| allocator.free(p);
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
    size_kb: u64,
    file_name: []const u8,
    uploaded_timestamp: i64,
    mod_version: []const u8,
    description: []const u8,

    pub fn deinit(self: *FileInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.category_name);
        allocator.free(self.file_name);
        allocator.free(self.mod_version);
        allocator.free(self.description);
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

    pub fn deinit(self: *RateLimitInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.hourly_reset);
        allocator.free(self.daily_reset);
    }
};

/// Tracked mod entry
pub const TrackedMod = struct {
    mod_id: u64,
    domain_name: []const u8,

    pub fn deinit(self: *TrackedMod, allocator: std.mem.Allocator) void {
        allocator.free(self.domain_name);
    }
};

/// Nexus Mods API Client
pub const NexusClient = struct {
    allocator: std.mem.Allocator,
    api_key: ?[]const u8,
    last_rate_limit: ?RateLimitInfo,

    const Self = @This();

    /// Initialize client (call discoverApiKey() or setApiKey() after)
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .api_key = null,
            .last_rate_limit = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.api_key) |key| {
            self.allocator.free(key);
        }
        if (self.last_rate_limit) |*rl| {
            rl.deinit(self.allocator);
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
    /// Priority: 1. ENV, 2. Config file, 3. NixOS secrets
    pub fn discoverApiKey(self: *Self) !void {
        // Priority 1: Environment variable
        if (std.posix.getenv("STL_NEXUS_API_KEY")) |env_key| {
            try self.setApiKey(env_key);
            std.log.info("Nexus: API key loaded from STL_NEXUS_API_KEY", .{});
            return;
        }

        const home = std.posix.getenv("HOME") orelse return error.NoApiKey;

        // Priority 2: Config file
        const config_path = try std.fmt.allocPrint(self.allocator, "{s}/.config/stl-next/nexus_api_key", .{home});
        defer self.allocator.free(config_path);

        if (readKeyFromFile(config_path)) |key| {
            try self.setApiKey(key);
            std.log.info("Nexus: API key loaded from {s}", .{config_path});
            return;
        }

        // Priority 3: NixOS sops-nix/agenix location
        const nix_secret_paths = [_][]const u8{
            "/run/secrets/nexus_api_key",
            "/run/agenix/nexus_api_key",
        };

        for (nix_secret_paths) |secret_path| {
            if (readKeyFromFile(secret_path)) |key| {
                try self.setApiKey(key);
                std.log.info("Nexus: API key loaded from NixOS secret: {s}", .{secret_path});
                return;
            }
        }

        return error.NoApiKey;
    }

    /// Load API key from a file containing the key
    pub fn loadApiKeyFromFile(self: *Self, path: []const u8) !void {
        const key = readKeyFromFile(path) orelse return error.NoApiKey;
        try self.setApiKey(key);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // API ENDPOINTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Validate API key and get user info
    /// Endpoint: GET /v1/users/validate.json
    pub fn validateKey(self: *Self) !UserInfo {
        const api_key = self.api_key orelse return error.NoApiKey;

        const url = BASE_URL ++ "/users/validate.json";
        const response = try self.makeRequest(url, api_key, null);
        defer self.allocator.free(response);

        // Debug: log response (uncomment for troubleshooting)
        // std.log.debug("Nexus API response ({d} bytes): {s}", .{ response.len, response[0..@min(200, response.len)] });

        // Parse JSON response
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| {
            std.log.err("JSON parse error: {}", .{err});
            std.log.err("Response: {s}", .{response});
            return error.ParseError;
        };
        defer parsed.deinit();

        const root = parsed.value.object;

        // Note: Nexus API uses both "is_premium" and "is_premium?" - handle both
        const is_premium = if (root.get("is_premium")) |p| p.bool else if (root.get("is_premium?")) |p| p.bool else false;
        const is_supporter = if (root.get("is_supporter")) |s| s.bool else if (root.get("is_supporter?")) |s| s.bool else false;

        return UserInfo{
            .user_id = @intCast(root.get("user_id").?.integer),
            .key = try self.allocator.dupe(u8, root.get("key").?.string),
            .name = try self.allocator.dupe(u8, root.get("name").?.string),
            .email = if (root.get("email")) |e| switch (e) {
                .string => |s| try self.allocator.dupe(u8, s),
                else => null,
            } else null,
            .is_premium = is_premium,
            .is_supporter = is_supporter,
            .profile_url = try self.allocator.dupe(u8, root.get("profile_url").?.string),
        };
    }

    /// Get mod information
    /// Endpoint: GET /v1/games/{game_domain}/mods/{mod_id}.json
    pub fn getMod(self: *Self, game_domain: []const u8, mod_id: u64) !ModInfo {
        const api_key = self.api_key orelse return error.NoApiKey;

        const url = try std.fmt.allocPrint(self.allocator, "{s}/games/{s}/mods/{d}.json", .{ BASE_URL, game_domain, mod_id });
        defer self.allocator.free(url);

        const response = try self.makeRequest(url, api_key, null);
        defer self.allocator.free(response);

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch {
            return error.ParseError;
        };
        defer parsed.deinit();

        const root = parsed.value.object;

        return ModInfo{
            .mod_id = @intCast(root.get("mod_id").?.integer),
            .game_id = @intCast(root.get("game_id").?.integer),
            .domain_name = try self.allocator.dupe(u8, root.get("domain_name").?.string),
            .name = try self.allocator.dupe(u8, root.get("name").?.string),
            .summary = try self.allocator.dupe(u8, root.get("summary").?.string),
            .version = try self.allocator.dupe(u8, root.get("version").?.string),
            .author = try self.allocator.dupe(u8, root.get("author").?.string),
            .category_id = @intCast(root.get("category_id").?.integer),
            .endorsement_count = @intCast(root.get("endorsement_count").?.integer),
            .created_timestamp = root.get("created_timestamp").?.integer,
            .updated_timestamp = root.get("updated_timestamp").?.integer,
            .picture_url = if (root.get("picture_url")) |p| switch (p) {
                .string => |s| try self.allocator.dupe(u8, s),
                else => null,
            } else null,
        };
    }

    /// List files for a mod
    /// Endpoint: GET /v1/games/{game_domain}/mods/{mod_id}/files.json
    pub fn getModFiles(self: *Self, game_domain: []const u8, mod_id: u64) ![]FileInfo {
        const api_key = self.api_key orelse return error.NoApiKey;

        const url = try std.fmt.allocPrint(self.allocator, "{s}/games/{s}/mods/{d}/files.json", .{ BASE_URL, game_domain, mod_id });
        defer self.allocator.free(url);

        const response = try self.makeRequest(url, api_key, null);
        defer self.allocator.free(response);

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch {
            return error.ParseError;
        };
        defer parsed.deinit();

        const files_array = parsed.value.object.get("files").?.array;
        var files = try self.allocator.alloc(FileInfo, files_array.items.len);
        var i: usize = 0;

        for (files_array.items) |file_val| {
            const f = file_val.object;
            files[i] = FileInfo{
                .file_id = @intCast(f.get("file_id").?.integer),
                .name = try self.allocator.dupe(u8, f.get("name").?.string),
                .version = try self.allocator.dupe(u8, f.get("version").?.string),
                .category_id = @intCast(f.get("category_id").?.integer),
                .category_name = try self.allocator.dupe(u8, f.get("category_name").?.string),
                .is_primary = f.get("is_primary").?.bool,
                .size_kb = @intCast(f.get("size_kb").?.integer),
                .file_name = try self.allocator.dupe(u8, f.get("file_name").?.string),
                .uploaded_timestamp = f.get("uploaded_timestamp").?.integer,
                .mod_version = try self.allocator.dupe(u8, f.get("mod_version").?.string),
                .description = try self.allocator.dupe(u8, f.get("description").?.string),
            };
            i += 1;
        }

        return files;
    }

    /// Generate download link (PREMIUM ONLY for direct access)
    /// Non-premium users must use NXM links with key and expiry from browser
    /// Endpoint: GET /v1/games/{game_domain}/mods/{mod_id}/files/{file_id}/download_link.json
    pub fn getDownloadLink(
        self: *Self,
        game_domain: []const u8,
        mod_id: u64,
        file_id: u64,
        nxm_key: ?[]const u8,
        nxm_expiry: ?i64,
    ) ![]DownloadLink {
        const api_key = self.api_key orelse return error.NoApiKey;

        var url: []u8 = undefined;
        if (nxm_key != null and nxm_expiry != null) {
            url = try std.fmt.allocPrint(
                self.allocator,
                "{s}/games/{s}/mods/{d}/files/{d}/download_link.json?key={s}&expires={d}",
                .{ BASE_URL, game_domain, mod_id, file_id, nxm_key.?, nxm_expiry.? },
            );
        } else {
            url = try std.fmt.allocPrint(
                self.allocator,
                "{s}/games/{s}/mods/{d}/files/{d}/download_link.json",
                .{ BASE_URL, game_domain, mod_id, file_id },
            );
        }
        defer self.allocator.free(url);

        const response = try self.makeRequest(url, api_key, null);
        defer self.allocator.free(response);

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch {
            return error.ParseError;
        };
        defer parsed.deinit();

        const links_array = parsed.value.array;
        var links = try self.allocator.alloc(DownloadLink, links_array.items.len);
        var i: usize = 0;

        for (links_array.items) |link_val| {
            const l = link_val.object;
            links[i] = DownloadLink{
                .name = try self.allocator.dupe(u8, l.get("name").?.string),
                .short_name = try self.allocator.dupe(u8, l.get("short_name").?.string),
                .uri = try self.allocator.dupe(u8, l.get("URI").?.string),
            };
            i += 1;
        }

        return links;
    }

    /// Track a mod for updates
    /// Endpoint: POST /v1/user/tracked_mods.json
    pub fn trackMod(self: *Self, game_domain: []const u8, mod_id: u64) !void {
        const api_key = self.api_key orelse return error.NoApiKey;

        const url = BASE_URL ++ "/user/tracked_mods.json";
        const body = try std.fmt.allocPrint(self.allocator, "domain_name={s}&mod_id={d}", .{ game_domain, mod_id });
        defer self.allocator.free(body);

        const response = try self.makeRequest(url, api_key, body);
        self.allocator.free(response);
    }

    /// Get tracked mods
    /// Endpoint: GET /v1/user/tracked_mods.json
    pub fn getTrackedMods(self: *Self) ![]TrackedMod {
        const api_key = self.api_key orelse return error.NoApiKey;

        const url = BASE_URL ++ "/user/tracked_mods.json";
        const response = try self.makeRequest(url, api_key, null);
        defer self.allocator.free(response);

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch {
            return error.ParseError;
        };
        defer parsed.deinit();

        const mods_array = parsed.value.array;
        var mods = try self.allocator.alloc(TrackedMod, mods_array.items.len);
        var i: usize = 0;

        for (mods_array.items) |mod_val| {
            const m = mod_val.object;
            mods[i] = TrackedMod{
                .mod_id = @intCast(m.get("mod_id").?.integer),
                .domain_name = try self.allocator.dupe(u8, m.get("domain_name").?.string),
            };
            i += 1;
        }

        return mods;
    }

    /// Endorse a mod
    /// Endpoint: POST /v1/games/{game_domain}/mods/{mod_id}/endorse.json
    pub fn endorseMod(self: *Self, game_domain: []const u8, mod_id: u64, version: []const u8) !void {
        const api_key = self.api_key orelse return error.NoApiKey;

        const url = try std.fmt.allocPrint(self.allocator, "{s}/games/{s}/mods/{d}/endorse.json", .{ BASE_URL, game_domain, mod_id });
        defer self.allocator.free(url);

        const body = try std.fmt.allocPrint(self.allocator, "version={s}", .{version});
        defer self.allocator.free(body);

        const response = try self.makeRequest(url, api_key, body);
        self.allocator.free(response);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HTTP
    // ═══════════════════════════════════════════════════════════════════════════

    fn makeRequest(self: *Self, url: []const u8, api_key: []const u8, body: ?[]const u8) ![]u8 {
        _ = body; // TODO: Handle POST bodies properly in the future
        
        // Use curl subprocess for reliable HTTP handling (handles compression, TLS, etc.)
        // This is simpler and more reliable than fighting Zig 0.15.x HTTP API changes
        const argv = [_][]const u8{
            "curl",
            "-s",                      // Silent
            "-f",                      // Fail on HTTP errors
            "--compressed",            // Handle compressed responses
            "-H", "Accept: application/json",
            "-H",                      // API key header (dynamically set below)
        };
        
        // Build API key header
        const apikey_header = std.fmt.allocPrint(self.allocator, "apikey: {s}", .{api_key}) catch return error.OutOfMemory;
        defer self.allocator.free(apikey_header);
        
        var args: std.ArrayList([]const u8) = .{};
        defer args.deinit(self.allocator);
        
        args.appendSlice(self.allocator, &argv) catch return error.OutOfMemory;
        args.append(self.allocator, apikey_header) catch return error.OutOfMemory;
        args.append(self.allocator, url) catch return error.OutOfMemory;
        
        var child = std.process.Child.init(args.items, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        
        child.spawn() catch return error.NetworkError;
        
        var stdout_list: std.ArrayList(u8) = .{};
        var stderr_list: std.ArrayList(u8) = .{};
        child.collectOutput(self.allocator, &stdout_list, &stderr_list, 1024 * 1024) catch return error.NetworkError;
        defer stderr_list.deinit(self.allocator);
        
        const result = child.wait() catch return error.NetworkError;
        
        // Check curl exit code
        if (result.Exited != 0) {
            stdout_list.deinit(self.allocator);
            // curl exit codes: 22 = HTTP error 4xx, 6 = couldn't resolve host
            if (result.Exited == 22) {
                // Check stderr for HTTP code hints
                if (std.mem.indexOf(u8, stderr_list.items, "401")) |_| return error.InvalidApiKey;
                if (std.mem.indexOf(u8, stderr_list.items, "403")) |_| return error.NotPremium;
                if (std.mem.indexOf(u8, stderr_list.items, "404")) |_| return error.ModNotFound;
                if (std.mem.indexOf(u8, stderr_list.items, "429")) |_| return error.RateLimited;
            }
            return error.NetworkError;
        }
        
        return stdout_list.toOwnedSlice(self.allocator) catch return error.OutOfMemory;
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

fn readKeyFromFile(path: []const u8) ?[]const u8 {
    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    var buf: [256]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch return null;

    if (bytes_read == 0) return null;

    // Trim whitespace
    var end = bytes_read;
    while (end > 0 and (buf[end - 1] == '\n' or buf[end - 1] == '\r' or buf[end - 1] == ' ')) {
        end -= 1;
    }

    if (end == 0) return null;
    return buf[0..end];
}

/// Save API key to config file (with proper permissions)
pub fn saveApiKey(allocator: std.mem.Allocator, api_key: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoApiKey;

    // Ensure config directory exists
    const config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/stl-next", .{home});
    defer allocator.free(config_dir);
    std.fs.makeDirAbsolute(config_dir) catch |e| {
        if (e != error.PathAlreadyExists) return e;
    };

    // Write API key with restricted permissions (0600)
    const key_path = try std.fmt.allocPrint(allocator, "{s}/nexus_api_key", .{config_dir});
    defer allocator.free(key_path);

    const file = try std.fs.createFileAbsolute(key_path, .{ .mode = 0o600 });
    defer file.close();
    try file.writeAll(api_key);

    std.log.info("Nexus: API key saved to {s} (mode 0600)", .{key_path});
}

/// Generate NixOS module example for secret management
pub fn generateNixOsSecretExample(allocator: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(allocator,
        \\# STL-Next Nexus Mods Secret Configuration
        \\# ========================================
        \\#
        \\# Option 1: Environment variable
        \\# environment.sessionVariables.STL_NEXUS_API_KEY = "YOUR_KEY";
        \\#
        \\# Option 2: sops-nix (recommended)
        \\# sops.secrets.nexus_api_key = {{
        \\#   owner = config.users.users.YOUR_USERNAME.name;
        \\#   mode = "0400";
        \\# }};
        \\#
        \\# Option 3: agenix
        \\# age.secrets.nexus_api_key = {{
        \\#   file = ./secrets/nexus_api_key.age;
        \\#   owner = "YOUR_USERNAME";
        \\# }};
        \\
    , .{});
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

test "save and read api key" {
    // This test would require actual file system access
    // Skipped in automated tests
}
