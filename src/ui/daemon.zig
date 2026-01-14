const std = @import("std");
const ipc = @import("../ipc/mod.zig");
const config = @import("../core/config.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// WAIT REQUESTER DAEMON (Phase 4)
// ═══════════════════════════════════════════════════════════════════════════════
//
// The daemon that:
// 1. Shows pre-launch countdown
// 2. Accepts IPC commands from GUI/TUI clients
// 3. Manages tinker configuration
// 4. Triggers the actual game launch
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const WaitRequester = struct {
    allocator: std.mem.Allocator,
    server: ipc.Server,
    game_config: *config.GameConfig,
    countdown_seconds: u8,
    auto_launch: bool,
    result: Result,

    const Self = @This();

    pub const Result = enum {
        PENDING,
        LAUNCH,
        ABORT,
        ERROR,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        app_id: u32,
        game_name: []const u8,
        game_config: *config.GameConfig,
    ) !Self {
        var requester = Self{
            .allocator = allocator,
            .server = try ipc.Server.init(allocator, app_id, game_name),
            .game_config = game_config,
            .countdown_seconds = 10, // Default countdown
            .auto_launch = true,
            .result = .PENDING,
        };

        // Check environment for countdown override
        if (std.posix.getenv("STL_COUNTDOWN")) |val| {
            requester.countdown_seconds = std.fmt.parseInt(u8, val, 10) catch 10;
        }

        // Check for skip flag
        if (std.posix.getenv("STL_SKIP_WAIT")) |_| {
            requester.result = .LAUNCH;
            return requester;
        }

        return requester;
    }

    pub fn deinit(self: *Self) void {
        self.server.deinit();
    }

    /// Run the wait requester loop
    /// Returns true if game should launch, false if aborted
    pub fn run(self: *Self) !bool {
        // If already decided, skip
        if (self.result != .PENDING) {
            return self.result == .LAUNCH;
        }

        try self.server.start();

        std.log.info("Wait Requester: Starting countdown ({d}s)", .{self.countdown_seconds});
        std.log.info("Wait Requester: Connect client to {s}", .{self.server.socket_path});

        self.server.countdown = self.countdown_seconds;
        self.server.state = .COUNTDOWN;

        var last_second: u64 = 0;
        const start_time = std.time.milliTimestamp();

        while (self.result == .PENDING) {
            // Check IPC
            _ = try self.server.pollOnce();

            // Handle server state changes
            if (self.server.should_stop) {
                if (self.server.state == .LAUNCHING) {
                    self.result = .LAUNCH;
                } else if (self.server.state == .FINISHED) {
                    self.result = .ABORT;
                }
                break;
            }

            // Countdown tick (every second)
            const elapsed_ms = std.time.milliTimestamp() - start_time;
            const elapsed_seconds = @as(u64, @intCast(@divFloor(elapsed_ms, 1000)));

            if (elapsed_seconds != last_second and self.server.state == .COUNTDOWN) {
                last_second = elapsed_seconds;
                
                if (elapsed_seconds < self.countdown_seconds) {
                    self.server.countdown = @intCast(self.countdown_seconds - elapsed_seconds);
                    std.log.info("Wait Requester: {d}s remaining", .{self.server.countdown});
                } else {
                    // Countdown complete
                    self.server.state = .LAUNCHING;
                    self.result = .LAUNCH;
                    std.log.info("Wait Requester: Countdown complete, launching", .{});
                }
            }

            // Small sleep to prevent busy-waiting
            std.time.sleep(50 * std.time.ns_per_ms);
        }

        self.server.stop();

        return self.result == .LAUNCH;
    }

    /// Skip the wait and launch immediately
    pub fn skipWait(self: *Self) void {
        self.result = .LAUNCH;
    }

    /// Abort the launch
    pub fn abort(self: *Self) void {
        self.result = .ABORT;
    }
};

/// Quick check if wait should be shown (checks env vars)
pub fn shouldShowWait() bool {
    // Skip if STL_SKIP_WAIT is set
    if (std.posix.getenv("STL_SKIP_WAIT")) |_| return false;
    
    // Skip if not a TTY
    // if (!std.io.getStdIn().isTty()) return false;
    
    return true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "wait requester init" {
    var game_config = config.GameConfig.defaults(413150);
    var requester = try WaitRequester.init(
        std.testing.allocator,
        413150,
        "Test Game",
        &game_config,
    );
    defer requester.deinit();
    try std.testing.expectEqual(WaitRequester.Result.PENDING, requester.result);
}

