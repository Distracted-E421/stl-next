// Zig 0.15.x Compatibility Layer
// Provides helpers for the new I/O and ArrayList APIs
//
// Changes in Zig 0.15.x:
// 1. ArrayList is now unmanaged - allocator passed to each method
// 2. std.io.getStdOut() removed - use std.fs.File directly
// 3. Writer API changed - needs buffer for File.writer()

const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════════
// I/O Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Get stdout file handle for writing
pub fn stdout() std.fs.File {
    return .{ .handle = std.posix.STDOUT_FILENO };
}

/// Get stderr file handle for writing
pub fn stderr() std.fs.File {
    return .{ .handle = std.posix.STDERR_FILENO };
}

/// Get stdin file handle for reading
pub fn stdin() std.fs.File {
    return .{ .handle = std.posix.STDIN_FILENO };
}

/// Print formatted output to stdout (for simple cases)
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [16384]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch {
        // Fallback for very long messages
        std.debug.print(fmt, args);
        return;
    };
    stdout().writeAll(msg) catch {};
}

/// Print formatted output to stderr
pub fn eprint(comptime fmt: []const u8, args: anytype) void {
    var buf: [8192]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch {
        std.debug.print(fmt, args);
        return;
    };
    stderr().writeAll(msg) catch {};
}

/// Buffered stdout writer for multiple writes
pub const BufferedWriter = struct {
    file: std.fs.File,
    buf: [8192]u8 = undefined,
    pos: usize = 0,

    pub fn init() BufferedWriter {
        return .{ .file = stdout() };
    }

    pub fn writeAll(self: *BufferedWriter, bytes: []const u8) !void {
        try self.file.writeAll(bytes);
    }

    pub fn print(self: *BufferedWriter, comptime fmt: []const u8, args: anytype) !void {
        const msg = std.fmt.bufPrint(&self.buf, fmt, args) catch return error.NoSpaceLeft;
        try self.file.writeAll(msg);
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// ArrayList Helpers (Zig 0.15.x uses unmanaged by default)
// ═══════════════════════════════════════════════════════════════════════════════

/// Create an empty ArrayList (Zig 0.15.x style)
/// Usage: var list = compat.arrayList(T);
pub fn arrayList(comptime T: type) std.ArrayList(T) {
    return .{};
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

test "compat stdout print" {
    print("Test output: {d}\n", .{42});
}

test "compat arrayList" {
    const allocator = std.testing.allocator;
    var list = arrayList(u8);
    try list.append(allocator, 'a');
    try list.append(allocator, 'b');
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    list.deinit(allocator);
}
