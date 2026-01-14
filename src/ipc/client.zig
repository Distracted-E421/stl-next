const std = @import("std");
const protocol = @import("protocol.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// IPC CLIENT (Phase 4 - GUI Side)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Connects to the STL daemon to control game launch
//
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
        const msg = protocol.ClientMessage{ .action = action };
        const request = try msg.serialize(self.allocator);
        defer self.allocator.free(request);
        
        _ = try std.posix.write(socket, request);
        
        // Read response
        var buf: [4096]u8 = undefined;
        const n = try std.posix.read(socket, &buf);
        
        if (n == 0) return error.EmptyResponse;
        
        // Parse response (simplified - extract key fields)
        return self.parseResponse(buf[0..n]);
    }

    fn parseResponse(self: *Self, data: []const u8) !protocol.DaemonMessage {
        _ = self;
        
        var msg = protocol.DaemonMessage{
            .state = .WAITING,
        };
        
        // Simple parsing for state
        if (std.mem.indexOf(u8, data, "WAITING") != null) {
            msg.state = .WAITING;
        } else if (std.mem.indexOf(u8, data, "COUNTDOWN") != null) {
            msg.state = .COUNTDOWN;
        } else if (std.mem.indexOf(u8, data, "LAUNCHING") != null) {
            msg.state = .LAUNCHING;
        } else if (std.mem.indexOf(u8, data, "RUNNING") != null) {
            msg.state = .RUNNING;
        } else if (std.mem.indexOf(u8, data, "FINISHED") != null) {
            msg.state = .FINISHED;
        }
        
        // Extract countdown (look for countdown_seconds: N)
        if (std.mem.indexOf(u8, data, "countdown_seconds\":")) |pos| {
            const start = pos + 19;
            if (start < data.len) {
                var end = start;
                while (end < data.len and data[end] >= '0' and data[end] <= '9') : (end += 1) {}
                if (end > start) {
                    msg.countdown_seconds = std.fmt.parseInt(u8, data[start..end], 10) catch 0;
                }
            }
        }
        
        return msg;
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
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "client init" {
    var client = try Client.init(std.testing.allocator, 413150);
    defer client.deinit();
    try std.testing.expectEqual(@as(u32, 413150), client.app_id);
}

