const std = @import("std");
const protocol = @import("protocol.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// IPC CLIENT (Phase 4 - Hardened)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Robust error handling for:
// - Connection timeouts
// - Socket errors
// - Malformed responses
// - Daemon crashes
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const ClientError = error{
    DaemonNotRunning,
    ConnectionTimeout,
    ConnectionRefused,
    EmptyResponse,
    ResponseTooLarge,
    SocketError,
    InvalidResponse,
    Timeout,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    app_id: u32,
    timeout_ms: u32,
    max_retries: u8,

    const Self = @This();
    const DEFAULT_TIMEOUT_MS = 5000;
    const DEFAULT_MAX_RETRIES = 3;
    const MAX_RESPONSE_SIZE = 64 * 1024; // 64KB max response

    pub fn init(allocator: std.mem.Allocator, app_id: u32) !Self {
        const socket_path = try protocol.getSocketPath(allocator, app_id);
        return Self{
            .allocator = allocator,
            .socket_path = socket_path,
            .app_id = app_id,
            .timeout_ms = DEFAULT_TIMEOUT_MS,
            .max_retries = DEFAULT_MAX_RETRIES,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.socket_path);
    }
    
    /// Configure timeout
    pub fn setTimeout(self: *Self, timeout_ms: u32) void {
        self.timeout_ms = timeout_ms;
    }

    /// Send an action to the daemon and get response
    pub fn sendAction(self: *Self, action: protocol.Action) ClientError!protocol.DaemonMessage {
        return self.sendMessage(.{ .action = action });
    }
    
    /// Send a message with retry logic
    pub fn sendMessage(self: *Self, msg: protocol.ClientMessage) ClientError!protocol.DaemonMessage {
        var last_error: ClientError = ClientError.DaemonNotRunning;
        
        var attempt: u8 = 0;
        while (attempt < self.max_retries) : (attempt += 1) {
            if (self.trySendMessage(msg)) |response| {
                return response;
            } else |err| {
                last_error = err;
                
                // Some errors shouldn't be retried
                switch (err) {
                    ClientError.DaemonNotRunning => return err,
                    else => {},
                }
                
                // Wait before retry
                if (attempt < self.max_retries - 1) {
                    std.time.sleep(100 * std.time.ns_per_ms);
                }
            }
        }
        
        return last_error;
    }
    
    fn trySendMessage(self: *Self, msg: protocol.ClientMessage) ClientError!protocol.DaemonMessage {
        // Check if daemon is running first
        if (!self.isRunning()) {
            return ClientError.DaemonNotRunning;
        }
        
        // Create socket
        const socket = std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM | std.posix.SOCK.NONBLOCK,
            0,
        ) catch {
            return ClientError.SocketError;
        };
        defer std.posix.close(socket);
        
        // Prepare address
        var addr: std.posix.sockaddr.un = .{ .path = undefined, .family = std.posix.AF.UNIX };
        @memset(&addr.path, 0);
        
        if (self.socket_path.len > addr.path.len) {
            std.log.err("IPC Client: Socket path too long", .{});
            return ClientError.SocketError;
        }
        @memcpy(addr.path[0..self.socket_path.len], self.socket_path);
        
        // Connect (non-blocking)
        std.posix.connect(socket, @ptrCast(&addr), @sizeOf(@TypeOf(addr))) catch |err| {
            if (err == error.WouldBlock or err == error.Again) {
                // Wait for connection with timeout
                if (!self.waitForSocket(socket, std.posix.POLL.OUT)) {
                    return ClientError.ConnectionTimeout;
                }
            } else if (err == error.ConnectionRefused) {
                return ClientError.ConnectionRefused;
            } else {
                return ClientError.SocketError;
            }
        };
        
        // Serialize and send message
        const request = msg.serialize(self.allocator) catch {
            return ClientError.SocketError;
        };
        defer self.allocator.free(request);
        
        _ = std.posix.write(socket, request) catch {
            return ClientError.SocketError;
        };
        
        // Wait for response
        if (!self.waitForSocket(socket, std.posix.POLL.IN)) {
            return ClientError.Timeout;
        }
        
        // Read response
        var buf: [MAX_RESPONSE_SIZE]u8 = undefined;
        const n = std.posix.read(socket, &buf) catch {
            return ClientError.SocketError;
        };
        
        if (n == 0) return ClientError.EmptyResponse;
        
        return protocol.DaemonMessage.parseFromJson(self.allocator, buf[0..n]);
    }
    
    fn waitForSocket(self: *Self, socket: std.posix.socket_t, events: i16) bool {
        var pfd = [_]std.posix.pollfd{.{
            .fd = socket,
            .events = events,
            .revents = 0,
        }};
        
        const timeout_ticks: i32 = @intCast(self.timeout_ms);
        const result = std.posix.poll(&pfd, timeout_ticks) catch return false;
        
        return result > 0 and (pfd[0].revents & events) != 0;
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
