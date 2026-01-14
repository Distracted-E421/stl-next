const std = @import("std");
const protocol = @import("protocol.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// IPC CLIENT (Phase 4 - Refined)
// ═══════════════════════════════════════════════════════════════════════════════

pub const Client = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    app_id: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, app_id: u32) !Self {
        const socket_path = try protocol.getSocketPath(allocator, app_id);
        return Self{
            .allocator = allocator,
            .socket_path = socket_path,
            .app_id = app_id,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.socket_path);
    }

    /// Send an action to the daemon and get response
    pub fn sendAction(self: *Self, action: protocol.Action) !protocol.DaemonMessage {
        return self.sendMessage(.{ .action = action });
    }
    
    /// Send a message with optional parameters
    pub fn sendMessage(self: *Self, msg: protocol.ClientMessage) !protocol.DaemonMessage {
        // Connect to server
        const socket = try std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM,
            0,
        );
        defer std.posix.close(socket);
        
        var addr: std.posix.sockaddr.un = .{ .path = undefined, .family = std.posix.AF.UNIX };
        @memset(&addr.path, 0);
        @memcpy(addr.path[0..self.socket_path.len], self.socket_path);
        
        try std.posix.connect(socket, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
        
        // Send message
        const request = try msg.serialize(self.allocator);
        defer self.allocator.free(request);
        
        _ = try std.posix.write(socket, request);
        
        // Read response
        var buf: [4096]u8 = undefined;
        const n = try std.posix.read(socket, &buf);
        
        if (n == 0) return error.EmptyResponse;
        
        return protocol.DaemonMessage.parseFromJson(self.allocator, buf[0..n]);
    }

    // Convenience methods
    pub fn pauseLaunch(self: *Self) !protocol.DaemonMessage {
        return self.sendAction(.PAUSE_LAUNCH);
    }

    pub fn resumeLaunch(self: *Self) !protocol.DaemonMessage {
        return self.sendAction(.RESUME_LAUNCH);
    }

    pub fn proceed(self: *Self) !protocol.DaemonMessage {
        return self.sendAction(.PROCEED);
    }

    pub fn abort(self: *Self) !protocol.DaemonMessage {
        return self.sendAction(.ABORT);
    }

    pub fn getStatus(self: *Self) !protocol.DaemonMessage {
        return self.sendAction(.GET_STATUS);
    }
    
    /// Toggle a tinker on/off
    pub fn toggleTinker(self: *Self, tinker_id: []const u8) !protocol.DaemonMessage {
        // Build message with tinker_id
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        
        try buf.appendSlice("{\"action\":\"TOGGLE_TINKER\",\"tinker_id\":\"");
        try buf.appendSlice(tinker_id);
        try buf.appendSlice("\"}");
        
        // Connect and send
        const socket = try std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM,
            0,
        );
        defer std.posix.close(socket);
        
        var addr: std.posix.sockaddr.un = .{ .path = undefined, .family = std.posix.AF.UNIX };
        @memset(&addr.path, 0);
        @memcpy(addr.path[0..self.socket_path.len], self.socket_path);
        
        try std.posix.connect(socket, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
        _ = try std.posix.write(socket, buf.items);
        
        // Read response
        var resp_buf: [4096]u8 = undefined;
        const n = try std.posix.read(socket, &resp_buf);
        if (n == 0) return error.EmptyResponse;
        
        return protocol.DaemonMessage.parseFromJson(self.allocator, resp_buf[0..n]);
    }
    
    /// Check if daemon is running
    pub fn isRunning(self: *Self) bool {
        std.fs.accessAbsolute(self.socket_path, .{}) catch return false;
        return true;
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "client init" {
    var client = try Client.init(std.testing.allocator, 413150);
    defer client.deinit();
    try std.testing.expectEqual(@as(u32, 413150), client.app_id);
}

test "client socket path" {
    var client = try Client.init(std.testing.allocator, 413150);
    defer client.deinit();
    try std.testing.expect(std.mem.endsWith(u8, client.socket_path, "413150.sock"));
}
