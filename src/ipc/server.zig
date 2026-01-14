const std = @import("std");
const protocol = @import("protocol.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// IPC SERVER (Phase 4 - Refined)
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
    
    // Tinker states
    mangohud_enabled: bool,
    gamescope_enabled: bool,
    gamemode_enabled: bool,

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
            .countdown = 10,
            .should_stop = false,
            .mangohud_enabled = false,
            .gamescope_enabled = false,
            .gamemode_enabled = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        self.allocator.free(self.socket_path);
    }

    pub fn start(self: *Self) !void {
        std.fs.deleteFileAbsolute(self.socket_path) catch {};
        
        const socket = try std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM,
            0,
        );
        errdefer std.posix.close(socket);
        
        var addr: std.posix.sockaddr.un = .{ .path = undefined, .family = std.posix.AF.UNIX };
        @memset(&addr.path, 0);
        @memcpy(addr.path[0..self.socket_path.len], self.socket_path);
        
        try std.posix.bind(socket, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
        try std.posix.listen(socket, 5);
        
        self.server = socket;
        self.state = .WAITING;
        
        std.log.info("IPC Server: Listening on {s}", .{self.socket_path});
    }

    pub fn stop(self: *Self) void {
        if (self.server) |socket| {
            std.posix.close(socket);
            self.server = null;
        }
        std.fs.deleteFileAbsolute(self.socket_path) catch {};
    }

    pub fn pollOnce(self: *Self) !bool {
        const socket = self.server orelse return false;
        
        var pfd = [_]std.posix.pollfd{.{
            .fd = socket,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        
        const poll_result = try std.posix.poll(&pfd, 0);
        if (poll_result == 0) return false;
        
        const client_socket = try std.posix.accept(socket, null, null, 0);
        defer std.posix.close(client_socket);
        
        var buf: [4096]u8 = undefined;
        const n = try std.posix.read(client_socket, &buf);
        if (n == 0) return false;
        
        const message_data = buf[0..n];
        std.log.debug("IPC Server: Received: {s}", .{message_data});
        
        self.handleMessage(client_socket, message_data);
        
        return true;
    }

    fn handleMessage(self: *Self, client_socket: std.posix.socket_t, data: []const u8) void {
        // Parse action
        const action = protocol.Action.fromString(data) orelse .GET_STATUS;
        
        switch (action) {
            .PAUSE_LAUNCH => {
                self.state = .WAITING;
                std.log.info("IPC: Paused by client", .{});
            },
            .RESUME_LAUNCH => {
                self.state = .COUNTDOWN;
                std.log.info("IPC: Resumed by client", .{});
            },
            .PROCEED => {
                self.state = .LAUNCHING;
                self.should_stop = true;
                std.log.info("IPC: Launch requested by client", .{});
            },
            .ABORT => {
                self.state = .FINISHED;
                self.should_stop = true;
                std.log.info("IPC: Aborted by client", .{});
            },
            .TOGGLE_TINKER => {
                // Check which tinker to toggle
                if (std.mem.indexOf(u8, data, "\"tinker_id\":\"mangohud\"") != null) {
                    self.mangohud_enabled = !self.mangohud_enabled;
                    std.log.info("IPC: MangoHud toggled to {}", .{self.mangohud_enabled});
                } else if (std.mem.indexOf(u8, data, "\"tinker_id\":\"gamescope\"") != null) {
                    self.gamescope_enabled = !self.gamescope_enabled;
                    std.log.info("IPC: Gamescope toggled to {}", .{self.gamescope_enabled});
                } else if (std.mem.indexOf(u8, data, "\"tinker_id\":\"gamemode\"") != null) {
                    self.gamemode_enabled = !self.gamemode_enabled;
                    std.log.info("IPC: GameMode toggled to {}", .{self.gamemode_enabled});
                }
            },
            else => {},
        }
        
        // Send response
        self.sendStatus(client_socket);
    }
    
    fn sendStatus(self: *Self, client_socket: std.posix.socket_t) void {
        const msg = protocol.DaemonMessage{
            .state = self.state,
            .countdown_seconds = self.countdown,
            .game_name = self.game_name,
            .app_id = self.app_id,
            .mangohud_enabled = self.mangohud_enabled,
            .gamescope_enabled = self.gamescope_enabled,
            .gamemode_enabled = self.gamemode_enabled,
        };
        
        const response = msg.serialize(self.allocator) catch return;
        defer self.allocator.free(response);
        
        _ = std.posix.write(client_socket, response) catch {};
    }

    pub fn tickCountdown(self: *Self) bool {
        if (self.state == .COUNTDOWN and self.countdown > 0) {
            self.countdown -= 1;
            if (self.countdown == 0) {
                self.state = .LAUNCHING;
                self.should_stop = true;
                return true;
            }
        }
        return false;
    }
    
    /// Load initial tinker states from config
    pub fn loadTinkerStates(self: *Self, mangohud: bool, gamescope: bool, gamemode: bool) void {
        self.mangohud_enabled = mangohud;
        self.gamescope_enabled = gamescope;
        self.gamemode_enabled = gamemode;
    }
    
    /// Get current tinker states for applying to launch
    pub fn getTinkerStates(self: *Self) struct { mangohud: bool, gamescope: bool, gamemode: bool } {
        return .{
            .mangohud = self.mangohud_enabled,
            .gamescope = self.gamescope_enabled,
            .gamemode = self.gamemode_enabled,
        };
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

test "server tinker loading" {
    var server = try Server.init(std.testing.allocator, 413150, "Test Game");
    defer server.deinit();
    
    server.loadTinkerStates(true, false, true);
    
    const states = server.getTinkerStates();
    try std.testing.expect(states.mangohud);
    try std.testing.expect(!states.gamescope);
    try std.testing.expect(states.gamemode);
}
