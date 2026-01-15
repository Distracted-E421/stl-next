const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════════
// VDF PARSER: Valve Data Format
// ═══════════════════════════════════════════════════════════════════════════════
//
// Handles both TEXT and BINARY VDF formats used by Steam:
//
// TEXT VDF (localconfig.vdf, libraryfolders.vdf):
//   "key" "value"
//   "key" { nested }
//
// BINARY VDF (appinfo.vdf, shortcuts.vdf):
//   Type-prefixed binary blobs with specific control bytes
//
// Performance target: Parse 200MB appinfo.vdf in <10ms via streaming/seeking
//
// ═══════════════════════════════════════════════════════════════════════════════

/// Binary VDF type markers
pub const BinaryType = enum(u8) {
    map_start = 0x00,
    string = 0x01,
    int32 = 0x02,
    float32 = 0x03,
    pointer = 0x04, // Rarely used
    wstring = 0x05, // Wide string
    color = 0x06,
    uint64 = 0x07,
    map_end = 0x08,
    int64 = 0x0A,
    binary_end = 0x0B, // End of binary block
    _,
};

/// A parsed VDF value
pub const Value = union(enum) {
    string: []const u8,
    int32: i32,
    int64: i64,
    uint64: u64,
    float32: f32,
    map: Map,
};

pub const Map = std.StringHashMap(Value);

/// Text VDF Parser - Recursive descent
pub const TextParser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Self {
        return .{
            .allocator = allocator,
            .source = source,
        };
    }

    pub fn parse(self: *Self) !Map {
        return self.parseMap();
    }

    fn parseMap(self: *Self) !Map {
        var map = Map.init(self.allocator);

        while (self.pos < self.source.len) {
            self.skipWhitespace();

            if (self.pos >= self.source.len) break;

            const c = self.source[self.pos];

            // End of map
            if (c == '}') {
                self.pos += 1;
                break;
            }

            // Parse key
            if (c != '"') {
                // Could be a comment or invalid
                if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
                    self.skipLine();
                    continue;
                }
                return error.ExpectedQuotedString;
            }

            const key = try self.parseString();
            self.skipWhitespace();

            if (self.pos >= self.source.len) return error.UnexpectedEof;

            // Parse value (string or nested map)
            const next = self.source[self.pos];
            if (next == '"') {
                const value = try self.parseString();
                try map.put(key, .{ .string = value });
            } else if (next == '{') {
                self.pos += 1;
                const nested = try self.parseMap();
                try map.put(key, .{ .map = nested });
            } else {
                return error.ExpectedValueOrMap;
            }
        }

        return map;
    }

    fn parseString(self: *Self) ![]const u8 {
        if (self.source[self.pos] != '"') return error.ExpectedQuote;
        self.pos += 1;

        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != '"') {
            // Handle escape sequences
            if (self.source[self.pos] == '\\' and self.pos + 1 < self.source.len) {
                self.pos += 2;
            } else {
                self.pos += 1;
            }
        }

        if (self.pos >= self.source.len) return error.UnterminatedString;

        const end = self.pos;
        self.pos += 1; // Skip closing quote

        return self.source[start..end];
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
            } else {
                break;
            }
        }
    }

    fn skipLine(self: *Self) void {
        while (self.pos < self.source.len and self.source[self.pos] != '\n') {
            self.pos += 1;
        }
        if (self.pos < self.source.len) self.pos += 1;
    }

    pub fn deinit(self: *Self) void {
        // Note: strings reference the source buffer, so we don't free them
        // Only free the map structures
        _ = self;
    }
};

/// Binary VDF Parser - Streaming with seeking capability
pub const BinaryParser = struct {
    allocator: std.mem.Allocator,
    reader: std.fs.File.Reader,
    file: std.fs.File,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.openFileAbsolute(path, .{});
        return .{
            .allocator = allocator,
            .reader = file.reader(),
            .file = file,
        };
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
    }

    /// Parse the appinfo.vdf header
    pub fn parseAppInfoHeader(self: *Self) !AppInfoHeader {
        const magic = try self.reader.readInt(u32, .little);
        const universe = try self.reader.readInt(u32, .little);

        return .{
            .magic = magic,
            .universe = universe,
        };
    }

    /// Seek to a specific AppID in appinfo.vdf
    /// Returns true if found, false if not present
    pub fn seekToAppId(self: *Self, target_app_id: u32) !bool {
        // Skip header (8 bytes: magic + universe)
        try self.file.seekTo(8);

        while (true) {
            // Read AppID (4 bytes)
            const app_id = self.reader.readInt(u32, .little) catch |err| {
                if (err == error.EndOfStream) return false;
                return err;
            };

            // Check for end marker
            if (app_id == 0) return false;

            // Read entry size
            const size = try self.reader.readInt(u32, .little);

            if (app_id == target_app_id) {
                // Found it! Position is now at the start of the data
                return true;
            }

            // Skip this entry (size doesn't include the 8-byte header we just read)
            try self.file.seekBy(@intCast(size));
        }
    }

    /// Read a null-terminated string
    fn readNullString(self: *Self) ![]const u8 {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);

        while (true) {
            const byte = try self.reader.readByte();
            if (byte == 0) break;
            try buf.append(self.allocator, byte);
        }

        return try buf.toOwnedSlice(self.allocator);
    }

    /// Parse a binary VDF value
    pub fn parseValue(self: *Self) !Value {
        const type_byte = try self.reader.readByte();
        const vdf_type: BinaryType = @enumFromInt(type_byte);

        return switch (vdf_type) {
            .string => .{ .string = try self.readNullString() },
            .int32 => .{ .int32 = try self.reader.readInt(i32, .little) },
            .int64 => .{ .int64 = try self.reader.readInt(i64, .little) },
            .uint64 => .{ .uint64 = try self.reader.readInt(u64, .little) },
            .float32 => .{ .float32 = @bitCast(try self.reader.readInt(u32, .little)) },
            .map_start => {
                var map = Map.init(self.allocator);
                try self.parseMapInto(&map);
                return .{ .map = map };
            },
            .map_end, .binary_end => error.UnexpectedMapEnd,
            else => error.UnknownVdfType,
        };
    }

    fn parseMapInto(self: *Self, map: *Map) !void {
        while (true) {
            const type_byte = try self.reader.readByte();
            const vdf_type: BinaryType = @enumFromInt(type_byte);

            if (vdf_type == .map_end or vdf_type == .binary_end) break;

            // Read key
            const key = try self.readNullString();

            // Read value based on type
            const value = switch (vdf_type) {
                .string => Value{ .string = try self.readNullString() },
                .int32 => Value{ .int32 = try self.reader.readInt(i32, .little) },
                .int64 => Value{ .int64 = try self.reader.readInt(i64, .little) },
                .uint64 => Value{ .uint64 = try self.reader.readInt(u64, .little) },
                .float32 => Value{ .float32 = @bitCast(try self.reader.readInt(u32, .little)) },
                .map_start => blk: {
                    var nested = Map.init(self.allocator);
                    try self.parseMapInto(&nested);
                    break :blk Value{ .map = nested };
                },
                else => return error.UnknownVdfType,
            };

            try map.put(key, value);
        }
    }
};

pub const AppInfoHeader = struct {
    magic: u32,
    universe: u32,
};

// ═══════════════════════════════════════════════════════════════════════════════
// CONVENIENCE FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Parse a text VDF file
pub fn parseTextFile(allocator: std.mem.Allocator, path: []const u8) !Map {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const stat = try file.stat();
    const source = try allocator.alloc(u8, stat.size);
    defer allocator.free(source);

    _ = try file.readAll(source);

    var parser = TextParser.init(allocator, source);
    return parser.parse();
}

/// Get a nested value by path (e.g., "UserLocalConfigStore/Software/Valve/Steam/Apps/413150")
pub fn getByPath(map: *const Map, path: []const u8) ?*const Value {
    var current = map;
    var iter = std.mem.splitSequence(u8, path, "/");

    while (iter.next()) |key| {
        if (current.get(key)) |value| {
            switch (value) {
                .map => |*m| current = m,
                else => return &value,
            }
        } else {
            return null;
        }
    }

    return null;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

// TODO: Fix memory management in VDF test
// test "parse simple text vdf" { ... }

test "binary vdf type enum" {
    try std.testing.expectEqual(BinaryType.map_start, @as(BinaryType, @enumFromInt(0x00)));
    try std.testing.expectEqual(BinaryType.string, @as(BinaryType, @enumFromInt(0x01)));
    try std.testing.expectEqual(BinaryType.int32, @as(BinaryType, @enumFromInt(0x02)));
    try std.testing.expectEqual(BinaryType.map_end, @as(BinaryType, @enumFromInt(0x08)));
}

