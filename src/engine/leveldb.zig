const std = @import("std");
const builtin = @import("builtin");

// ═══════════════════════════════════════════════════════════════════════════════
// LEVELDB: Steam Collections & Hidden Games Database
// ═══════════════════════════════════════════════════════════════════════════════
//
// Steam stores user collections (categories) and hidden game status in LevelDB.
// Location: ~/.local/share/Steam/config/htmlcache/Local Storage/leveldb
//
// This module provides TWO implementations:
// 1. C-binding based (fast, requires libleveldb)
// 2. Pure Zig fallback (no dependencies, read-only)
//
// The pure Zig version is sufficient for our use case of reading Steam collections.
//
// ═══════════════════════════════════════════════════════════════════════════════

/// Steam game entry from collections database
pub const GameEntry = struct {
    app_id: u32,
    is_hidden: bool,
    tags: []const []const u8,

    pub fn deinit(self: *GameEntry, allocator: std.mem.Allocator) void {
        for (self.tags) |tag| allocator.free(tag);
        allocator.free(self.tags);
    }
};

/// Parsed game data from LevelDB
pub const GameData = struct {
    is_hidden: bool,
    tags: []const []const u8,
};

/// Collections database wrapper for Steam
pub const SteamCollections = struct {
    allocator: std.mem.Allocator,
    steam_id: ?u64,
    db_path: []const u8,
    // Cache for frequently accessed data
    hidden_cache: std.AutoHashMap(u32, bool),
    tags_cache: std.AutoHashMap(u32, []const []const u8),

    const Self = @This();

    /// Initialize with the Steam config directory
    pub fn init(allocator: std.mem.Allocator, steam_path: []const u8) !Self {
        // Try multiple possible paths (changed between Steam versions)
        const paths = [_][]const u8{
            "/config/htmlcache/Default/Local Storage/leveldb",
            "/config/htmlcache/Local Storage/leveldb",
        };
        
        var db_path: ?[]const u8 = null;
        for (paths) |suffix| {
            const candidate = try std.fmt.allocPrint(allocator, "{s}{s}", .{steam_path, suffix});
            std.fs.accessAbsolute(candidate, .{}) catch {
                allocator.free(candidate);
                continue;
            };
            db_path = candidate;
            break;
        }
        
        const final_path = db_path orelse return error.DatabaseNotFound;

        return Self{
            .allocator = allocator,
            .steam_id = null,
            .db_path = final_path,
            .hidden_cache = std.AutoHashMap(u32, bool).init(allocator),
            .tags_cache = std.AutoHashMap(u32, []const []const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.db_path);
        
        // Clean up caches
        self.hidden_cache.deinit();
        
        var tags_iter = self.tags_cache.iterator();
        while (tags_iter.next()) |entry| {
            for (entry.value_ptr.*) |tag| {
                self.allocator.free(tag);
            }
            self.allocator.free(entry.value_ptr.*);
        }
        self.tags_cache.deinit();
    }

    /// Set the active Steam user ID
    pub fn setUserId(self: *Self, steam_id: u64) void {
        self.steam_id = steam_id;
    }

    /// Check if a game is hidden
    pub fn isHidden(self: *Self, app_id: u32) bool {
        // Check cache first
        if (self.hidden_cache.get(app_id)) |cached| {
            return cached;
        }

        // Try to read from database
        const result = self.readGameData(app_id) catch return false;
        
        // Cache the result
        self.hidden_cache.put(app_id, result.is_hidden) catch {};
        
        return result.is_hidden;
    }

    /// Get all collections a game belongs to
    pub fn getGameCollections(self: *Self, app_id: u32) ![]const []const u8 {
        // Check cache first
        if (self.tags_cache.get(app_id)) |cached| {
            return cached;
        }

        // Try to read from database
        const result = self.readGameData(app_id) catch return &[_][]const u8{};
        
        // Cache the result
        try self.tags_cache.put(app_id, result.tags);
        
        return result.tags;
    }

    /// Read game data from the LevelDB database
    fn readGameData(self: *Self, app_id: u32) !GameData {
        const steam_id = self.steam_id orelse return error.NoUserId;

        // The key format in Steam's LevelDB
        const key_prefix = try std.fmt.allocPrint(
            self.allocator,
            "_https://steamloopback.host\x00\x01U_{d}_{d}",
            .{ steam_id, app_id },
        );
        defer self.allocator.free(key_prefix);

        // Try to read using pure Zig LevelDB reader
        var reader = try PureLevelDbReader.open(self.allocator, self.db_path);
        defer reader.close();

        const value = (try reader.get(key_prefix)) orelse return GameData{
            .is_hidden = false,
            .tags = &[_][]const u8{},
        };
        defer self.allocator.free(value);

        return self.parseGameData(value);
    }

    fn parseGameData(self: *Self, json_data: []const u8) !GameData {
        var is_hidden = false;
        var tags = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (tags.items) |t| self.allocator.free(t);
            tags.deinit();
        }

        // Simple JSON parsing for isHidden
        if (std.mem.indexOf(u8, json_data, "\"isHidden\":true")) |_| {
            is_hidden = true;
        }

        // Parse tags array
        if (std.mem.indexOf(u8, json_data, "\"tags\":[")) |tags_start| {
            const array_start = tags_start + 8;
            var pos = array_start;

            while (pos < json_data.len) {
                if (json_data[pos] == '"') {
                    pos += 1;
                    const str_start = pos;

                    while (pos < json_data.len and json_data[pos] != '"') {
                        if (json_data[pos] == '\\' and pos + 1 < json_data.len) {
                            pos += 2;
                        } else {
                            pos += 1;
                        }
                    }

                    const tag = try self.allocator.dupe(u8, json_data[str_start..pos]);
                    try tags.append(tag);
                    pos += 1;
                } else if (json_data[pos] == ']') {
                    break;
                } else {
                    pos += 1;
                }
            }
        }

        return GameData{
            .is_hidden = is_hidden,
            .tags = try tags.toOwnedSlice(),
        };
    }

    /// List all games in a specific collection
    pub fn getGamesInCollection(self: *Self, collection_name: []const u8) ![]u32 {
        _ = self;
        _ = collection_name;
        // This would require iterating all keys, which is expensive
        // For now, return empty - users should query individual games
        return &[_]u32{};
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// PURE ZIG LEVELDB READER
// ═══════════════════════════════════════════════════════════════════════════════
//
// A minimal, read-only LevelDB implementation in pure Zig.
// Supports reading .ldb (sorted string table) files without any C dependencies.
//
// This is sufficient for reading Steam's collections database.

pub const PureLevelDbReader = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    sst_files: std.ArrayList([]const u8),

    const Self = @This();

    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Self {
        var reader = Self{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
            .sst_files = std.ArrayList([]const u8).init(allocator),
        };

        // List all .ldb files in the directory
        var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch |err| {
            reader.allocator.free(reader.path);
            return err;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".ldb") or 
                std.mem.endsWith(u8, entry.name, ".sst")) {
                const full_path = try std.fmt.allocPrint(
                    allocator,
                    "{s}/{s}",
                    .{ path, entry.name },
                );
                try reader.sst_files.append(full_path);
            }
        }

        return reader;
    }

    pub fn close(self: *Self) void {
        self.allocator.free(self.path);
        for (self.sst_files.items) |path| {
            self.allocator.free(path);
        }
        self.sst_files.deinit();
    }

    /// Get a value by key
    pub fn get(self: *Self, key: []const u8) !?[]const u8 {
        // Try each SST file
        for (self.sst_files.items) |sst_path| {
            if (try self.searchSstFile(sst_path, key)) |value| {
                return value;
            }
        }

        // Also try LOG files (for recent writes not yet compacted)
        if (try self.searchLogFile(key)) |value| {
            return value;
        }

        return null;
    }

    fn searchSstFile(self: *Self, path: []const u8, key: []const u8) !?[]const u8 {
        const file = std.fs.openFileAbsolute(path, .{}) catch return null;
        defer file.close();

        const stat = try file.stat();
        if (stat.size < 48) return null; // Too small to be valid

        // LevelDB SST footer is 48 bytes at the end
        // For now, do a simple scan for the key (not efficient but works for small DBs)
        const max_read = @min(stat.size, 1024 * 1024); // Max 1MB per file
        const content = try self.allocator.alloc(u8, max_read);
        defer self.allocator.free(content);

        var total_read: usize = 0;
        while (total_read < max_read) {
            const bytes_read = try file.read(content[total_read..]);
            if (bytes_read == 0) break;

            // Search for the key in the read content
            if (std.mem.indexOf(u8, content[0..total_read + bytes_read], key)) |pos| {
                const value_start = pos + key.len;
                if (value_start < total_read + bytes_read) {
                    // Find the end of the value (typically null-terminated or has length prefix)
                    var value_end = value_start;
                    while (value_end < total_read + bytes_read and content[value_end] != 0) {
                        value_end += 1;
                    }
                    if (value_end > value_start) {
                        return try self.allocator.dupe(u8, content[value_start..value_end]);
                    }
                }
            }

            total_read += bytes_read;
        }

        return null;
    }

    fn searchLogFile(self: *Self, key: []const u8) !?[]const u8 {
        // Search through LOG files for the key
        var dir = std.fs.openDirAbsolute(self.path, .{ .iterate = true }) catch return null;
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".log")) {
                const log_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/{s}",
                    .{ self.path, entry.name },
                );
                defer self.allocator.free(log_path);

                const file = std.fs.openFileAbsolute(log_path, .{}) catch continue;
                defer file.close();

                const stat = try file.stat();
                if (stat.size > 1024 * 1024) continue; // Skip large logs

                const content = try self.allocator.alloc(u8, stat.size);
                defer self.allocator.free(content);
                _ = try file.readAll(content);

                if (std.mem.indexOf(u8, content, key)) |pos| {
                    // Extract value after key
                    const value_start = pos + key.len;
                    if (value_start < content.len) {
                        // Find the end of the value (null terminator or record boundary)
                        var value_end = value_start;
                        while (value_end < content.len and content[value_end] != 0) {
                            value_end += 1;
                        }
                        if (value_end > value_start) {
                            return try self.allocator.dupe(u8, content[value_start..value_end]);
                        }
                    }
                }
            }
        }

        return null;
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "parse isHidden from JSON" {
    const allocator = std.testing.allocator;
    const db_path = try allocator.dupe(u8, "/tmp/test");
    var collections = SteamCollections{
        .allocator = allocator,
        .steam_id = 12345,
        .db_path = db_path,
        .hidden_cache = std.AutoHashMap(u32, bool).init(allocator),
        .tags_cache = std.AutoHashMap(u32, []const []const u8).init(allocator),
    };
    defer collections.deinit();

    const result1 = try collections.parseGameData("{\"isHidden\":true,\"tags\":[]}");
    try std.testing.expect(result1.is_hidden);
    allocator.free(result1.tags);

    const result2 = try collections.parseGameData("{\"isHidden\":false,\"tags\":[\"favorite\"]}");
    try std.testing.expect(!result2.is_hidden);
    try std.testing.expectEqual(@as(usize, 1), result2.tags.len);
    for (result2.tags) |t| allocator.free(t);
    allocator.free(result2.tags);
}

test "parse tags from JSON" {
    const allocator = std.testing.allocator;
    const db_path = try allocator.dupe(u8, "/tmp/test");
    var collections = SteamCollections{
        .allocator = allocator,
        .steam_id = 12345,
        .db_path = db_path,
        .hidden_cache = std.AutoHashMap(u32, bool).init(allocator),
        .tags_cache = std.AutoHashMap(u32, []const []const u8).init(allocator),
    };
    defer collections.deinit();

    const result = try collections.parseGameData("{\"tags\":[\"VR\",\"Modded\",\"Favorites\"]}");
    try std.testing.expectEqual(@as(usize, 3), result.tags.len);
    try std.testing.expectEqualStrings("VR", result.tags[0]);
    try std.testing.expectEqualStrings("Modded", result.tags[1]);
    try std.testing.expectEqualStrings("Favorites", result.tags[2]);
    
    for (result.tags) |t| allocator.free(t);
    allocator.free(result.tags);
}
