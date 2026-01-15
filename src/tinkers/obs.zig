const std = @import("std");
const interface = @import("interface.zig");
const Context = interface.Context;
const EnvMap = interface.EnvMap;
const ArgList = interface.ArgList;

// ═══════════════════════════════════════════════════════════════════════════════
// OBS CAPTURE TINKER (Phase 6)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Integration with OBS Studio for game streaming/recording.
//
// Features:
//   - Start/stop OBS recording with game
//   - Game capture scene switching
//   - OBS websocket control
//   - Auto-configure game capture source
//
// Requirements:
//   - OBS Studio with obs-websocket (built-in since OBS 28)
//   - obs-cli or direct websocket connection
//
// ═══════════════════════════════════════════════════════════════════════════════

/// OBS configuration
pub const ObsConfig = struct {
    /// Enable OBS integration
    enabled: bool = false,
    /// Auto-start recording when game launches
    auto_record: bool = false,
    /// Auto-start streaming when game launches
    auto_stream: bool = false,
    /// Switch to a specific scene for this game
    game_scene: ?[]const u8 = null,
    /// OBS websocket host
    websocket_host: []const u8 = "localhost",
    /// OBS websocket port
    websocket_port: u16 = 4455,
    /// OBS websocket password (if set)
    websocket_password: ?[]const u8 = null,
    /// Delay before starting recording (ms)
    start_delay_ms: u32 = 2000,
    /// Stop recording when game exits
    stop_on_exit: bool = true,
    /// Game capture source name in OBS
    capture_source: ?[]const u8 = null,
    /// Use replay buffer instead of recording
    use_replay_buffer: bool = false,
    /// Save replay on specific events
    save_replay_on_exit: bool = false,
};

/// OBS websocket message types
const ObsRequest = struct {
    op: u8 = 6, // Request
    d: RequestData,

    const RequestData = struct {
        requestType: []const u8,
        requestId: []const u8,
        requestData: ?std.json.Value = null,
    };
};

/// Simple OBS control via CLI (fallback when websocket unavailable)
const ObsCli = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ObsCli {
        return .{ .allocator = allocator };
    }

    pub fn startRecording(self: *ObsCli) !void {
        try self.runCommand(&[_][]const u8{ "obs-cmd", "recording", "start" });
    }

    pub fn stopRecording(self: *ObsCli) !void {
        try self.runCommand(&[_][]const u8{ "obs-cmd", "recording", "stop" });
    }

    pub fn startStreaming(self: *ObsCli) !void {
        try self.runCommand(&[_][]const u8{ "obs-cmd", "streaming", "start" });
    }

    pub fn stopStreaming(self: *ObsCli) !void {
        try self.runCommand(&[_][]const u8{ "obs-cmd", "streaming", "stop" });
    }

    pub fn switchScene(self: *ObsCli, scene_name: []const u8) !void {
        try self.runCommand(&[_][]const u8{ "obs-cmd", "scene", "switch", scene_name });
    }

    pub fn saveReplayBuffer(self: *ObsCli) !void {
        try self.runCommand(&[_][]const u8{ "obs-cmd", "replay", "save" });
    }

    fn runCommand(self: *ObsCli, argv: []const []const u8) !void {
        var child = std.process.Child.init(argv, self.allocator);
        child.spawn() catch |err| {
            std.log.warn("OBS: Failed to run obs-cmd: {s}", .{@errorName(err)});
            return err;
        };
        _ = child.wait() catch {};
    }
};

/// State for cleanup
var obs_started_recording = false;
var obs_started_streaming = false;
var obs_original_scene: ?[]const u8 = null;

fn isEnabled(ctx: *const Context) bool {
    // Check game config for OBS settings
    _ = ctx;
    return false; // Will be enabled via config
}

fn preparePrefix(ctx: *const Context) anyerror!void {
    _ = ctx;
    // Check if OBS is running
    const obs_running = checkObsRunning();
    if (!obs_running) {
        std.log.warn("OBS: OBS Studio is not running, skipping integration", .{});
        return;
    }

    std.log.info("OBS: OBS Studio detected, integration enabled", .{});
}

fn checkObsRunning() bool {
    // Check if OBS process is running
    var child = std.process.Child.init(&[_][]const u8{ "pgrep", "-x", "obs" }, std.heap.page_allocator);
    child.spawn() catch return false;
    const result = child.wait() catch return false;
    return result.Exited == 0;
}

fn modifyEnv(ctx: *const Context, env: *EnvMap) anyerror!void {
    // Set OBS-related environment variables
    _ = ctx;

    // OBS game capture works best with certain Vulkan settings
    try env.put("OBS_VKCAPTURE", "1");

    // For X11 game capture
    try env.put("OBS_USE_EGL", "1");
}

fn modifyArgs(ctx: *const Context, args: *ArgList) anyerror!void {
    // OBS doesn't modify game arguments
    _ = ctx;
    _ = args;
}

fn cleanup(ctx: *const Context) void {
    _ = ctx;

    // Stop recording/streaming if we started them
    var cli = ObsCli.init(std.heap.page_allocator);

    if (obs_started_recording) {
        std.log.info("OBS: Stopping recording", .{});
        cli.stopRecording() catch {};
        obs_started_recording = false;
    }

    if (obs_started_streaming) {
        std.log.info("OBS: Stopping streaming", .{});
        cli.stopStreaming() catch {};
        obs_started_streaming = false;
    }

    // Restore original scene if we switched
    if (obs_original_scene) |scene| {
        std.log.info("OBS: Restoring scene: {s}", .{scene});
        cli.switchScene(scene) catch {};
        obs_original_scene = null;
    }
}

/// Start OBS recording/streaming for a game
pub fn startObsCapture(allocator: std.mem.Allocator, config: ObsConfig) !void {
    var cli = ObsCli.init(allocator);

    // Switch scene if configured
    if (config.game_scene) |scene| {
        std.log.info("OBS: Switching to scene: {s}", .{scene});
        try cli.switchScene(scene);
    }

    // Delay before starting
    if (config.start_delay_ms > 0) {
        std.time.sleep(config.start_delay_ms * std.time.ns_per_ms);
    }

    // Start recording
    if (config.auto_record) {
        std.log.info("OBS: Starting recording", .{});
        try cli.startRecording();
        obs_started_recording = true;
    }

    // Start streaming
    if (config.auto_stream) {
        std.log.info("OBS: Starting streaming", .{});
        try cli.startStreaming();
        obs_started_streaming = true;
    }
}

/// Generate OBS scene collection JSON for a game
pub fn generateGameScene(allocator: std.mem.Allocator, game_name: []const u8, capture_source: ?[]const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const w = result.writer();

    const source_name = capture_source orelse "Game Capture";

    try w.print(
        \\{{
        \\  "name": "{s}",
        \\  "sources": [
        \\    {{
        \\      "name": "{s}",
        \\      "type": "game_capture",
        \\      "settings": {{
        \\        "capture_mode": "auto",
        \\        "capture_any_fullscreen": true
        \\      }}
        \\    }}
        \\  ]
        \\}}
    , .{ game_name, source_name });

    return result.toOwnedSlice();
}

pub const tinker = interface.Tinker{
    .id = "obs",
    .name = "OBS Capture",
    .priority = interface.Priority.OVERLAY_LATE,
    .isEnabledFn = isEnabled,
    .preparePrefixFn = preparePrefix,
    .modifyEnvFn = modifyEnv,
    .modifyArgsFn = modifyArgs,
    .cleanupFn = cleanup,
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "default config" {
    const config = ObsConfig{};
    try std.testing.expect(!config.enabled);
    try std.testing.expect(!config.auto_record);
    try std.testing.expectEqual(@as(u16, 4455), config.websocket_port);
}

test "scene generation" {
    const allocator = std.testing.allocator;

    const result = try generateGameScene(allocator, "Stardew Valley", null);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "Stardew Valley") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "game_capture") != null);
}

