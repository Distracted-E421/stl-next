const std = @import("std");
const ipc = @import("../ipc/mod.zig");
const compat = @import("../compat.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// TUI - Terminal User Interface (Phase 4 - Zig 0.15.x)
// ═══════════════════════════════════════════════════════════════════════════════

pub const TUI = struct {
    allocator: std.mem.Allocator,
    client: ipc.Client,
    game_name: []const u8,
    app_id: u32,
    running: bool,
    last_status: ?ipc.DaemonMessage,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, app_id: u32, game_name: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .client = try ipc.Client.init(allocator, app_id),
            .game_name = game_name,
            .app_id = app_id,
            .running = true,
            .last_status = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }

    pub fn run(self: *Self) !void {
        const stdout = compat.stdout();
        const stdin = compat.stdin();

        // Check if daemon is running
        if (!self.client.isRunning()) {
            compat.print("⚠️  No daemon running for AppID {d}\n", .{self.app_id});
            compat.print("   Start one with: stl-next wait {d}\n", .{self.app_id});
            return;
        }

        // Clear screen and draw header
        try stdout.writeAll("\x1B[2J\x1B[H");
        try self.drawHeader();

        while (self.running) {
            // Get status from daemon
            const status = self.client.getStatus() catch |err| {
                compat.print("\r\x1B[K⚠️  Connection lost: {}\n", .{err});
                std.Thread.sleep(500 * std.time.ns_per_ms);
                if (!self.client.isRunning()) {
                    self.running = false;
                }
                continue;
            };
            self.last_status = status;

            // Draw current state
            try self.drawStatus(status);

            // Check for input (non-blocking)
            var poll_fds = [_]std.posix.pollfd{.{
                .fd = stdin.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            }};

            const poll_result = std.posix.poll(&poll_fds, 200) catch 0;
            if (poll_result > 0) {
                var buf: [16]u8 = undefined;
                const n = stdin.read(&buf) catch 0;
                if (n > 0) {
                    try self.handleInput(buf[0]);
                }
            }

            // Check if daemon finished
            if (status.state == .LAUNCHING or status.state == .FINISHED or status.state == .RUNNING) {
                self.running = false;
            }
        }

        try compat.stdout().writeAll("\n\x1B[0m"); // Reset colors
    }

    fn drawHeader(self: *Self) !void {
        // Truncate game name if needed
        const max_name_len = 54;
        const display_name = if (self.game_name.len > max_name_len) 
            self.game_name[0..max_name_len] 
        else 
            self.game_name;
        
        compat.print(
            \\
            \\\x1B[36m╔══════════════════════════════════════════════════════════════════╗
            \\║\x1B[1m                    STL-NEXT WAIT REQUESTER                       \x1B[0m\x1B[36m ║
            \\╠══════════════════════════════════════════════════════════════════╣\x1B[0m
            \\║ Game: \x1B[1;33m{s: <58}\x1B[0m ║
            \\║ AppID: \x1B[1;33m{d: <57}\x1B[0m ║
            \\\x1B[36m╠══════════════════════════════════════════════════════════════════╣
            \\║\x1B[0m Commands:                                                          \x1B[36m║
            \\║\x1B[0m   \x1B[1;32m[P]\x1B[0m Pause    \x1B[1;32m[R]\x1B[0m Resume    \x1B[1;32m[L]\x1B[0m Launch    \x1B[1;31m[Q]\x1B[0m Quit          \x1B[36m║
            \\║\x1B[0m   \x1B[1;35m[M]\x1B[0m MangoHud \x1B[1;35m[G]\x1B[0m Gamescope \x1B[1;35m[F]\x1B[0m GameMode                \x1B[36m║
            \\╚══════════════════════════════════════════════════════════════════╝\x1B[0m
            \\
        , .{
            display_name,
            self.app_id,
        });
    }

    fn drawStatus(self: *Self, status: ipc.DaemonMessage) !void {
        _ = self;
        
        // Move to status line
        compat.print("\x1B[14;1H\x1B[K", .{});
        
        // State indicator
        switch (status.state) {
            .INITIALIZING => compat.print("  ⏳ \x1B[33mInitializing...\x1B[0m", .{}),
            .WAITING => compat.print("  ⏸️  \x1B[33mPaused\x1B[0m - Press [R] to resume", .{}),
            .COUNTDOWN => {
                const filled = 10 - @min(status.countdown_seconds, 10);
                compat.print("  ⏱️  Launching in \x1B[1;36m{d}s\x1B[0m [", .{status.countdown_seconds});
                var i: u8 = 0;
                while (i < 10) : (i += 1) {
                    if (i < filled) {
                        compat.print("\x1B[32m█\x1B[0m", .{});
                    } else {
                        compat.print("\x1B[90m░\x1B[0m", .{});
                    }
                }
                compat.print("]", .{});
            },
            .LAUNCHING => compat.print("  🚀 \x1B[1;32mLaunching game!\x1B[0m", .{}),
            .RUNNING => compat.print("  🎮 \x1B[1;32mGame running\x1B[0m", .{}),
            .FINISHED => compat.print("  ✅ \x1B[32mComplete\x1B[0m", .{}),
            .ERROR => compat.print("  ❌ \x1B[31mError\x1B[0m", .{}),
        }
        
        // Draw tinker status on next line
        compat.print("\x1B[15;1H\x1B[K", .{});
        compat.print("  Tinkers: ", .{});
        
        if (status.mangohud_enabled) {
            compat.print("\x1B[32m[MangoHud]\x1B[0m ", .{});
        } else {
            compat.print("\x1B[90m[MangoHud]\x1B[0m ", .{});
        }
        
        if (status.gamescope_enabled) {
            compat.print("\x1B[32m[Gamescope]\x1B[0m ", .{});
        } else {
            compat.print("\x1B[90m[Gamescope]\x1B[0m ", .{});
        }
        
        if (status.gamemode_enabled) {
            compat.print("\x1B[32m[GameMode]\x1B[0m", .{});
        } else {
            compat.print("\x1B[90m[GameMode]\x1B[0m", .{});
        }
    }

    fn handleInput(self: *Self, key: u8) !void {
        // Move to message line
        compat.print("\x1B[17;1H\x1B[K", .{});
        
        switch (key) {
            'p', 'P' => {
                _ = try self.client.pauseLaunch();
                compat.print("  📋 \x1B[33mPaused\x1B[0m", .{});
            },
            'r', 'R' => {
                _ = try self.client.resumeLaunch();
                compat.print("  ▶️  \x1B[32mResumed\x1B[0m", .{});
            },
            'l', 'L' => {
                _ = try self.client.proceed();
                compat.print("  🚀 \x1B[1;32mLaunching!\x1B[0m", .{});
                self.running = false;
            },
            'q', 'Q' => {
                _ = try self.client.abort();
                compat.print("  ❌ \x1B[31mAborted\x1B[0m", .{});
                self.running = false;
            },
            'm', 'M' => {
                const status = try self.client.toggleTinker("mangohud");
                if (status.mangohud_enabled) {
                    compat.print("  🔧 MangoHud \x1B[32mENABLED\x1B[0m", .{});
                } else {
                    compat.print("  🔧 MangoHud \x1B[31mDISABLED\x1B[0m", .{});
                }
            },
            'g', 'G' => {
                const status = try self.client.toggleTinker("gamescope");
                if (status.gamescope_enabled) {
                    compat.print("  🔧 Gamescope \x1B[32mENABLED\x1B[0m", .{});
                } else {
                    compat.print("  🔧 Gamescope \x1B[31mDISABLED\x1B[0m", .{});
                }
            },
            'f', 'F' => {
                const status = try self.client.toggleTinker("gamemode");
                if (status.gamemode_enabled) {
                    compat.print("  🔧 GameMode \x1B[32mENABLED\x1B[0m", .{});
                } else {
                    compat.print("  🔧 GameMode \x1B[31mDISABLED\x1B[0m", .{});
                }
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
