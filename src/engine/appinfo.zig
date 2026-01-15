const std = @import("std");
const vdf = @import("vdf.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// APPINFO.VDF PARSER: Steam Game Metadata Database
// ═══════════════════════════════════════════════════════════════════════════════
//
// The appinfo.vdf file is a binary database containing metadata for ALL games
// in the Steam catalog. It can exceed 200MB for large libraries.
//
// Performance Strategy: STREAMING + SEEKING
// - Use BufferedReader with 4KB chunks to minimize syscalls
// - Parse only the header + size for each entry
// - Seek past unneeded entries (O(1) per skip vs O(N) bytes parsed)
// - Only fully deserialize the target AppID's data
//
// Target: Find any game in a 200MB appinfo.vdf in <10ms
//
// ═══════════════════════════════════════════════════════════════════════════════

/// AppInfo.vdf file header
/// Format varies by version (0x07DC for newer, 0x07D7 for older)
pub const AppInfoHeader = struct {
    magic: u32,          // 0x07DC5627 or similar
    universe: u32,       // Usually 1 (Steam public)
    
    pub fn isValid(self: AppInfoHeader) bool {
        // Known magic values for appinfo.vdf
        return self.magic == 0x07DC5627 or   // Version 27DC (newer)
               self.magic == 0x07D75627 or   // Version 27D7
               self.magic == 0x27645627 or
               self.magic == 0x07564429;     // Version 29 (2025)     // Some versions
    }
};

/// Individual app entry header within appinfo.vdf
pub const AppEntryHeader = struct {
    app_id: u32,
    size: u32,
    info_state: u32,
    last_updated: u32,
    pics_token: u64,
    sha1_hash: [20]u8,
    change_number: u32,
    
    // The actual data follows this header
};

/// Extracted game information (high-level)
pub const GameInfo = struct {
    app_id: u32,
    name: []const u8,
    install_dir: []const u8,
    executable: ?[]const u8,
    launch_options: []const LaunchOption,
    is_installed: bool,
    last_played: u64,
    playtime_minutes: u32,
    
    pub const LaunchOption = struct {
        id: u32,
        executable: []const u8,
        arguments: ?[]const u8,
        description: ?[]const u8,
        os_list: ?[]const u8,
    };
    
    pub fn deinit(self: *GameInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.install_dir);
        if (self.executable) |exe| allocator.free(exe);
        for (self.launch_options) |opt| {
            allocator.free(opt.executable);
            if (opt.arguments) |args| allocator.free(args);
            if (opt.description) |desc| allocator.free(desc);
            if (opt.os_list) |os| allocator.free(os);
        }
        allocator.free(self.launch_options);
    }
};

/// High-performance AppInfo parser with streaming and seeking
pub const AppInfoParser = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    buffered_reader: BufferedReader,
    header: ?AppInfoHeader,
    current_pos: u64,
    
    const BUFFER_SIZE = 4096; // 4KB buffer for efficient I/O
    const BufferedReader = std.io.BufferedReader(BUFFER_SIZE, std.fs.File.Reader);
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.openFileAbsolute(path, .{});
        errdefer file.close();
        
        var parser = Self{
            .allocator = allocator,
            .file = file,
            .buffered_reader = std.io.bufferedReader(file.reader()),
            .header = null,
            .current_pos = 0,
        };
        
        // Parse and validate header
        parser.header = try parser.readHeader();
        
        return parser;
    }
    
    pub fn deinit(self: *Self) void {
        self.file.close();
    }
    
    /// Read the appinfo.vdf file header
    fn readHeader(self: *Self) !AppInfoHeader {
        const reader = self.buffered_reader.reader();
        
        const magic = try reader.readInt(u32, .little);
        const universe = try reader.readInt(u32, .little);
        
        self.current_pos = 8;
        
        const header = AppInfoHeader{
            .magic = magic,
            .universe = universe,
        };
        
        if (!header.isValid()) {
            std.log.warn("Unknown appinfo.vdf magic: 0x{X:0>8}", .{magic});
        }
        
        return header;
    }
    
    /// Fast seek to a specific AppID
    /// Returns the entry header if found, null if not present
    pub fn seekToAppId(self: *Self, target_app_id: u32) !?AppEntryHeader {
        // Reset to start of entries (after header)
        try self.file.seekTo(8);
        self.buffered_reader = std.io.bufferedReader(self.file.reader());
        self.current_pos = 8;
        
        const reader = self.buffered_reader.reader();
        
        while (true) {
            // Read AppID
            const app_id = reader.readInt(u32, .little) catch |err| {
                if (err == error.EndOfStream) return null;
                return err;
            };
            
            // Check for end marker (AppID 0)
            if (app_id == 0) return null;
            
            // Read entry size
            const size = try reader.readInt(u32, .little);
            
            // Check if this is our target
            if (app_id == target_app_id) {
                // Read remaining header fields
                const info_state = try reader.readInt(u32, .little);
                const last_updated = try reader.readInt(u32, .little);
                const pics_token = try reader.readInt(u64, .little);
                
                var sha1_hash: [20]u8 = undefined;
                _ = try reader.readAll(&sha1_hash);
                
                const change_number = try reader.readInt(u32, .little);
                
                self.current_pos += 8 + 4 + 4 + 8 + 20 + 4; // Update position tracking
                
                return AppEntryHeader{
                    .app_id = app_id,
                    .size = size,
                    .info_state = info_state,
                    .last_updated = last_updated,
                    .pics_token = pics_token,
                    .sha1_hash = sha1_hash,
                    .change_number = change_number,
                };
            }
            
            // Skip this entry - size is the total bytes after the app_id+size fields
            // But we need to account for the header fields we didn't read
            try self.file.seekBy(@intCast(size));
            self.buffered_reader = std.io.bufferedReader(self.file.reader());
        }
    }
    
    /// Parse the binary VDF data for the current entry
    pub fn parseCurrentEntry(self: *Self) !vdf.Map {
        var map = vdf.Map.init(self.allocator);
        errdefer map.deinit();
        
        const reader = self.buffered_reader.reader();
        
        try self.parseMapInto(reader, &map);
        
        return map;
    }
    
    fn parseMapInto(self: *Self, reader: anytype, map: *vdf.Map) !void {
        while (true) {
            const type_byte = reader.readByte() catch |err| {
                if (err == error.EndOfStream) return;
                return err;
            };
            
            const vdf_type: vdf.BinaryType = @enumFromInt(type_byte);
            
            // End of map markers
            if (vdf_type == .map_end or vdf_type == .binary_end) return;
            
            // Read key (null-terminated string)
            const key = try self.readNullString(reader);
            
            // Read value based on type
            const value: vdf.Value = switch (vdf_type) {
                .map_start => blk: {
                    var nested = vdf.Map.init(self.allocator);
                    try self.parseMapInto(reader, &nested);
                    break :blk vdf.Value{ .map = nested };
                },
                .string => vdf.Value{ .string = try self.readNullString(reader) },
                .wstring => vdf.Value{ .string = try self.readNullString(reader) }, // Treat as regular string
                .int32 => vdf.Value{ .int32 = try reader.readInt(i32, .little) },
                .int64 => vdf.Value{ .int64 = try reader.readInt(i64, .little) },
                .uint64 => vdf.Value{ .uint64 = try reader.readInt(u64, .little) },
                .float32 => vdf.Value{ .float32 = @bitCast(try reader.readInt(u32, .little)) },
                .color => vdf.Value{ .int32 = try reader.readInt(i32, .little) }, // Color as int
                .pointer => vdf.Value{ .uint64 = try reader.readInt(u64, .little) },
                else => {
                    std.log.warn("Unknown VDF type byte: 0x{X:0>2}", .{type_byte});
                    continue;
                },
            };
            
            try map.put(key, value);
        }
    }
    
    fn readNullString(self: *Self, reader: anytype) ![]const u8 {
        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(self.allocator);
        
        while (true) {
            const byte = try reader.readByte();
            if (byte == 0) break;
            try buf.append(self.allocator, byte);
        }
        
        return buf.toOwnedSlice(self.allocator);
    }
    
    /// Extract high-level game information from parsed VDF data
    pub fn extractGameInfo(self: *Self, app_id: u32, data: *const vdf.Map) !GameInfo {
        // Navigate to common section for game name
        const name = blk: {
            if (data.get("appinfo")) |appinfo| {
                switch (appinfo) {
                    .map => |m| {
                        if (m.get("common")) |common| {
                            switch (common) {
                                .map => |cm| {
                                    if (cm.get("name")) |n| {
                                        switch (n) {
                                            .string => |s| break :blk try self.allocator.dupe(u8, s),
                                            else => {},
                                        }
                                    }
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            }
            // Fallback name
            break :blk try std.fmt.allocPrint(self.allocator, "Game {d}", .{app_id});
        };
        
        // Get install directory
        const install_dir = blk: {
            if (data.get("appinfo")) |appinfo| {
                switch (appinfo) {
                    .map => |m| {
                        if (m.get("config")) |config| {
                            switch (config) {
                                .map => |cfg| {
                                    if (cfg.get("installdir")) |dir| {
                                        switch (dir) {
                                            .string => |s| break :blk try self.allocator.dupe(u8, s),
                                            else => {},
                                        }
                                    }
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            }
            break :blk try self.allocator.dupe(u8, "");
        };
        
        // Get primary executable (first launch option)
        var executable: ?[]const u8 = null;
        var launch_options: std.ArrayList(GameInfo.LaunchOption) = .{};
        errdefer launch_options.deinit(self.allocator);
        
        if (data.get("appinfo")) |appinfo| {
            switch (appinfo) {
                .map => |m| {
                    if (m.get("config")) |config| {
                        switch (config) {
                            .map => |cfg| {
                                if (cfg.get("launch")) |launch| {
                                    switch (launch) {
                                        .map => |launch_map| {
                                            var iter = launch_map.iterator();
                                            while (iter.next()) |entry| {
                                                switch (entry.value_ptr.*) {
                                                    .map => |opt_map| {
                                                        const exe = if (opt_map.get("executable")) |e|
                                                            switch (e) {
                                                                .string => |s| try self.allocator.dupe(u8, s),
                                                                else => null,
                                                            }
                                                        else
                                                            null;
                                                        
                                                        if (exe) |e| {
                                                            if (executable == null) executable = try self.allocator.dupe(u8, e);
                                                            
                                                            try launch_options.append(self.allocator, .{
                                                                .id = std.fmt.parseInt(u32, entry.key_ptr.*, 10) catch 0,
                                                                .executable = e,
                                                                .arguments = if (opt_map.get("arguments")) |a| switch (a) {
                                                                    .string => |s| try self.allocator.dupe(u8, s),
                                                                    else => null,
                                                                } else null,
                                                                .description = if (opt_map.get("description")) |d| switch (d) {
                                                                    .string => |s| try self.allocator.dupe(u8, s),
                                                                    else => null,
                                                                } else null,
                                                                .os_list = if (opt_map.get("oslist")) |o| switch (o) {
                                                                    .string => |s| try self.allocator.dupe(u8, s),
                                                                    else => null,
                                                                } else null,
                                                            });
                                                        }
                                                    },
                                                    else => {},
                                                }
                                            }
                                        },
                                        else => {},
                                    }
                                }
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }
        
        return GameInfo{
            .app_id = app_id,
            .name = name,
            .install_dir = install_dir,
            .executable = executable,
            .launch_options = try launch_options.toOwnedSlice(self.allocator),
            .is_installed = false, // Determined externally
            .last_played = 0,
            .playtime_minutes = 0,
        };
    }
    
    /// Iterate through all entries (for listing games)
    pub fn iterateEntries(self: *Self) EntryIterator {
        return EntryIterator.init(self);
    }
    
    pub const EntryIterator = struct {
        parser: *AppInfoParser,
        started: bool,
        
        pub fn init(parser: *AppInfoParser) EntryIterator {
            return .{
                .parser = parser,
                .started = false,
            };
        }
        
        pub fn next(self: *EntryIterator) !?struct { app_id: u32, size: u32 } {
            if (!self.started) {
                // Reset to start of entries
                try self.parser.file.seekTo(8);
                self.parser.buffered_reader = std.io.bufferedReader(self.parser.file.reader());
                self.started = true;
            }
            
            const reader = self.parser.buffered_reader.reader();
            
            // Read AppID
            const app_id = reader.readInt(u32, .little) catch |err| {
                if (err == error.EndOfStream) return null;
                return err;
            };
            
            // Check for end marker
            if (app_id == 0) return null;
            
            // Read size
            const size = try reader.readInt(u32, .little);
            
            // Skip to next entry
            try self.parser.file.seekBy(@intCast(size));
            self.parser.buffered_reader = std.io.bufferedReader(self.parser.file.reader());
            
            return .{ .app_id = app_id, .size = size };
        }
    };
};

// ═══════════════════════════════════════════════════════════════════════════════
// CONVENIENCE FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Quick lookup of a single game's info
pub fn lookupGame(allocator: std.mem.Allocator, appinfo_path: []const u8, app_id: u32) !?GameInfo {
    var parser = try AppInfoParser.init(allocator, appinfo_path);
    defer parser.deinit();
    
    const entry = try parser.seekToAppId(app_id) orelse return null;
    _ = entry;
    
    var data = try parser.parseCurrentEntry();
    defer {
        var iter = data.iterator();
        while (iter.next()) |e| {
            freeValue(allocator, e.value_ptr);
        }
        data.deinit();
    }
    
    return try parser.extractGameInfo(app_id, &data);
}

fn freeValue(allocator: std.mem.Allocator, value: *vdf.Value) void {
    switch (value.*) {
        .string => |s| allocator.free(s),
        .map => |*m| {
            var iter = m.iterator();
            while (iter.next()) |e| {
                allocator.free(e.key_ptr.*);
                freeValue(allocator, e.value_ptr);
            }
            m.deinit();
        },
        else => {},
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "AppInfoHeader validation" {
    const valid = AppInfoHeader{ .magic = 0x07DC5627, .universe = 1 };
    try std.testing.expect(valid.isValid());
    
    const invalid = AppInfoHeader{ .magic = 0x12345678, .universe = 1 };
    try std.testing.expect(!invalid.isValid());
}

test "BinaryType enum values" {
    try std.testing.expectEqual(@as(u8, 0x00), @intFromEnum(vdf.BinaryType.map_start));
    try std.testing.expectEqual(@as(u8, 0x01), @intFromEnum(vdf.BinaryType.string));
    try std.testing.expectEqual(@as(u8, 0x02), @intFromEnum(vdf.BinaryType.int32));
    try std.testing.expectEqual(@as(u8, 0x08), @intFromEnum(vdf.BinaryType.map_end));
}
