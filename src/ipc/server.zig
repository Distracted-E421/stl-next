const std = @import("std");
const net = std.net;
const protocol = @import("protocol.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// IPC SERVER (Phase 4 - Daemon Side)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Unix Domain Socket server for receiving commands from GUI client
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const Server = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    server: ?std.posix.socket_t,
    state: protocol.DaemonState,
    game_name: []const u8,
    app_id: u32,
    countdown: u8,
    should_stop: bool,
    on_action: ?*const fn(action: protocol.Action, payload: ?[]const u8) void,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        app_id: u32,
        game_name: []const u8,
    ) !Self {
        const socket_path = try protocol.getSocketPath(allocator, app_id);
        
        return Self{
            .allocator = allocator,
            .socket_path = socket_path,
            .server = null,
            .state = .INITIALIZING,
            .game_name = game_name,
            .app_id = app_id,
            .countdown = 10, // Default 10 second countdown
            .should_stop = false,
            .on_action = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        self.allocator.free(self.socket_path);
    }

    /// Start listening for connections
    pub fn start(self: *Self) !void {
        // Remove existing socket if present
        std.fs.deleteFileAbsolute(self.socket_path) catch {};
        
        // Create Unix Domain Socket
        const socket = try std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM,
            0,
        );
        errdefer std.posix.close(socket);
        
        // Bind to path
        var addr: std.posix.sockaddr.un = .{ .path = undefined, .family = std.posix.AF.UNIX };
        @memset(&addr.path, 0);
        @memcpy(addr.path[0..self.socket_path.len], self.socket_path);
        
        try std.posix.bind(socket, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
        try std.posix.listen(socket, 5);
        
        self.server = socket;
        self.state = .WAITING;
        
        std.log.info("IPC Server: Listening on {s}", .{self.socket_path});
    }

    /// Stop the server
    pub fn stop(self: *Self) void {
        if (self.server) |socket| {
            std.posix.close(socket);
            self.server = null;
        }
        std.fs.deleteFileAbsolute(self.socket_path) catch {};
    }

    /// Set the action callback
    pub fn setCallback(self: *Self, callback: *const fn(protocol.Action, ?[]const u8) void) void {
        self.on_action = callback;
    }

    /// Accept and handle one connection (non-blocking check)
    pub fn pollOnce(self: *Self) !bool {
        const socket = self.server orelse return false;
        
        // Set non-blocking for poll
        var pfd = [_]std.posix.pollfd{.{
            .fd = socket,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        
        const poll_result = try std.posix.poll(&pfd, 0); // Immediate return
        if (poll_result == 0) return false; // No connection waiting
        
        // Accept connection
        const client_socket = try std.posix.accept(socket, null, null, 0);
        defer std.posix.close(client_socket);
        
        // Read message
        var buf: [4096]u8 = undefined;
        const n = try std.posix.read(client_socket, &buf);
        if (n == 0) return false;
        
        const message_data = buf[0..n];
        std.log.debug("IPC Server: Received: {s}", .{message_data});
        
        // Parse and handle
        self.handleMessage(client_socket, message_data);
        
        return true;
    }

    fn handleMessage(self: *Self, client_socket: std.posix.socket_t, data: []const u8) void {
        // Simple action parsing (look for action string)
        var action: protocol.Action = .GET_STATUS;
        
        if (std.mem.indexOf(u8, data, "PAUSE_LAUNCH") != null) {
            action = .PAUSE_LAUNCH;
            self.state = .WAITING;
        } else if (std.mem.indexOf(u8, data, "RESUME_LAUNCH") != null) {
            action = .RESUME_LAUNCH;
            self.state = .COUNTDOWN;
        } else if (std.mem.indexOf(u8, data, "PROCEED") != null) {
            action = .PROCEED;
            self.state = .LAUNCHING;
            self.should_stop = true;
        } else if (std.mem.indexOf(u8, data, "ABORT") != null) {
            action = .ABORT;
            self.state = .FINISHED;
            self.should_stop = true;
        }
        
        // Invoke callback if set
        if (self.on_action) |callback| {
            callback(action, null);
        }
        
        // Send response
        const response = protocol.statusResponse(
            self.allocator,
            self.state,
            self.game_name,
            self.app_id,
            self.countdown,
        ) catch return;
        defer self.allocator.free(response);
        
        _ = std.posix.write(client_socket, response) catch {};
    }

    /// Update countdown (called from main loop)
    pub fn tickCountdown(self: *Self) bool {
        if (self.state == .COUNTDOWN and self.countdown > 0) {
            self.countdown -= 1;
            if (self.countdown == 0) {
                self.state = .LAUNCHING;
                self.should_stop = true;
                return true; // Time to launch!
            }
        }
        return false;
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "server init" {
    var server = try Server.init(std.testing.allocator, 413150, "Test Game");
    defer server.deinit();
    try std.testing.expectEqual(protocol.DaemonState.INITIALIZING, server.state);
}

