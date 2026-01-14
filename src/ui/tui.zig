const std = @import("std");
const ipc = @import("../ipc/mod.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// TUI - Terminal User Interface (Phase 4)
// ═══════════════════════════════════════════════════════════════════════════════
//
// A simple terminal-based wait requester for:
// - Headless servers
// - SSH sessions
// - Users who prefer terminal
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const TUI = struct {
    allocator: std.mem.Allocator,
    client: ipc.Client,
    game_name: []const u8,
    app_id: u32,
    running: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, app_id: u32, game_name: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .client = try ipc.Client.init(allocator, app_id),
            .game_name = game_name,
            .app_id = app_id,
            .running = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }

    pub fn run(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn();

        // Clear screen and draw header
        try stdout.print("\x1B[2J\x1B[H", .{}); // Clear + home
        try self.drawHeader(stdout);

        while (self.running) {
            // Get status from daemon
            const status = self.client.getStatus() catch |err| {
                try stdout.print("\r\x1B[K⚠️  Connection error: {}\n", .{err});
                std.time.sleep(1 * std.time.ns_per_s);
                continue;
            };

            // Draw current state
            try self.drawStatus(stdout, status);

            // Check for input (non-blocking)
            var poll_fds = [_]std.posix.pollfd{.{
                .fd = stdin.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            }};

            const poll_result = std.posix.poll(&poll_fds, 100) catch 0;
            if (poll_result > 0) {
                var buf: [16]u8 = undefined;
                const n = stdin.read(&buf) catch 0;
                if (n > 0) {
                    try self.handleInput(buf[0], stdout);
                }
            }

            // Check if we should exit
            if (status.state == .LAUNCHING or status.state == .FINISHED or status.state == .RUNNING) {
                self.running = false;
            }
        }

        try stdout.print("\n", .{});
    }

    fn drawHeader(self: *Self, writer: anytype) !void {
        try writer.print(
            \\
            \\╔════════════════════════════════════════════════════════════════════╗
            \\║                    STL-NEXT WAIT REQUESTER                         ║
            \\╠════════════════════════════════════════════════════════════════════╣
            \\║ Game: {s: <58} ║
            \\║ AppID: {d: <57} ║
            \\╠════════════════════════════════════════════════════════════════════╣
            \\║ Commands:                                                          ║
            \\║   [P] Pause countdown    [R] Resume countdown                      ║
            \\║   [L] Launch now         [Q] Quit/Abort                            ║
            \\║   [M] Toggle MangoHud    [G] Toggle Gamescope                      ║
            \\╚════════════════════════════════════════════════════════════════════╝
            \\
        , .{
            self.game_name[0..@min(58, self.game_name.len)],
            self.app_id,
        });
    }

    fn drawStatus(self: *Self, writer: anytype, status: ipc.DaemonMessage) !void {
        _ = self;
        
        const state_str = switch (status.state) {
            .INITIALIZING => "⏳ Initializing...",
            .WAITING => "⏸️  Paused - Press [R] to resume",
            .COUNTDOWN => "⏱️  Launching in...",
            .LAUNCHING => "🚀 Launching game!",
            .RUNNING => "🎮 Game running",
            .FINISHED => "✅ Complete",
            .ERROR => "❌ Error",
        };

        try writer.print("\r\x1B[K{s}", .{state_str});

        if (status.state == .COUNTDOWN) {
            try writer.print(" {d}s ", .{status.countdown_seconds});
            // Progress bar
            const filled = 10 - @min(status.countdown_seconds, 10);
            try writer.writeAll("[");
            var i: u8 = 0;
            while (i < 10) : (i += 1) {
                if (i < filled) {
                    try writer.writeAll("█");
                } else {
                    try writer.writeAll("░");
                }
            }
            try writer.writeAll("]");
        }
    }

    fn handleInput(self: *Self, key: u8, writer: anytype) !void {
        switch (key) {
            'p', 'P' => {
                _ = try self.client.pauseLaunch();
                try writer.print("\n📋 Paused\n", .{});
            },
            'r', 'R' => {
                _ = try self.client.resumeLaunch();
                try writer.print("\n▶️  Resumed\n", .{});
            },
            'l', 'L' => {
                _ = try self.client.proceed();
                try writer.print("\n🚀 Launching!\n", .{});
                self.running = false;
            },
            'q', 'Q' => {
                _ = try self.client.abort();
                try writer.print("\n❌ Aborted\n", .{});
                self.running = false;
            },
            'm', 'M' => {
                try writer.print("\n🔧 MangoHud toggled\n", .{});
                // Would send toggle action
            },
            'g', 'G' => {
                try writer.print("\n🔧 Gamescope toggled\n", .{});
                // Would send toggle action
            },
            else => {},
        }
    }
};

/// Run the TUI client
pub fn runTUI(allocator: std.mem.Allocator, app_id: u32, game_name: []const u8) !void {
    var tui = try TUI.init(allocator, app_id, game_name);
    defer tui.deinit();
    try tui.run();
}

