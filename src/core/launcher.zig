const std = @import("std");
const steam = @import("../engine/steam.zig");
const config = @import("config.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// LAUNCHER: Game Launch Orchestration
// ═══════════════════════════════════════════════════════════════════════════════
//
// Orchestrates the game launch process:
// 1. Build environment variables
// 2. Apply Tinker module modifications
// 3. Construct command vector
// 4. Execute (fork/exec)
//
// Performance target: <50ms from invocation to exec()
//
// ═══════════════════════════════════════════════════════════════════════════════

pub fn launch(
    allocator: std.mem.Allocator,
    steam_engine: *const steam.SteamEngine,
    app_id: u32,
    extra_args: []const []const u8,
) !void {
    _ = extra_args;

    // Phase 1: Build environment
    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();

    // Inherit current environment
    var inherited_env = try std.process.getEnvMap(allocator);
    defer inherited_env.deinit();
    var env_iter = inherited_env.iterator();
    while (env_iter.next()) |entry| {
        try env.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    // Phase 2: Load game config and apply Tinker modifications
    const game_config = config.loadGameConfig(allocator, app_id) catch config.GameConfig.defaults(app_id);

    // Apply MangoHud if enabled
    if (game_config.mangohud.enabled) {
        try env.put("MANGOHUD", "1");
        try env.put("MANGOHUD_DLSYM", "1");
        std.log.info("MangoHud: ENABLED", .{});
    }

    // Apply GameMode if enabled
    if (game_config.gamemode) {
        // GameMode is typically activated via LD_PRELOAD or wrapper
        std.log.info("GameMode: ENABLED", .{});
    }

    // Phase 3: Build command vector
    var cmd = std.ArrayList([]const u8).init(allocator);
    defer cmd.deinit();

    // Apply Gamescope wrapper if enabled
    if (game_config.gamescope.enabled) {
        const gs_args = try game_config.gamescope.buildArgs(allocator);
        for (gs_args) |arg| {
            try cmd.append(arg);
        }
    }

    // Find the game's executable
    const game_info = try steam_engine.getGameInfo(app_id);

    // Determine launch method (native vs Proton)
    if (game_config.use_native or game_info.proton_version == null) {
        // Native Linux game
        try cmd.append(game_info.executable);
    } else {
        // Proton game - need to wrap with Proton
        const proton_path = try findProtonBinary(allocator, steam_engine, game_info.proton_version);
        try cmd.append(proton_path);
        try cmd.append("run");
        try cmd.append(game_info.executable);
    }

    // Phase 4: Execute
    std.log.info("Launching: {s}", .{cmd.items[0]});

    // In a real implementation, we would use std.process.Child or execv
    // For now, just log what we would do
    std.log.debug("Command vector:", .{});
    for (cmd.items) |arg| {
        std.log.debug("  {s}", .{arg});
    }

    std.log.info("(Launch simulation - exec not yet implemented)", .{});
}

fn findProtonBinary(
    allocator: std.mem.Allocator,
    steam_engine: *const steam.SteamEngine,
    version: ?[]const u8,
) ![]const u8 {
    _ = version;

    // Search in compatibility tools directory
    const compat_path = try std.fmt.allocPrint(
        allocator,
        "{s}/compatibilitytools.d",
        .{steam_engine.steam_path},
    );
    defer allocator.free(compat_path);

    // For now, return a placeholder
    return try allocator.dupe(u8, "/usr/bin/proton");
}

// ═══════════════════════════════════════════════════════════════════════════════
// TINKER MODULE INTERFACE
// ═══════════════════════════════════════════════════════════════════════════════

/// The Tinker interface - all modules implement this
pub const Tinker = struct {
    /// Unique identifier for this tinker
    id: []const u8,

    /// Execution priority (lower = earlier)
    /// 0-50: Setup (prefix manipulation)
    /// 51-100: Environment (vars, LD_PRELOAD)
    /// 101-150: Command wrapping (gamescope)
    /// 151-200: Post-launch hooks
    priority: u8,

    /// Check if this tinker should be active
    isEnabled: *const fn (game_config: *const config.GameConfig) bool,

    /// Modify the Wine prefix before launch
    preparePrefix: ?*const fn (
        allocator: std.mem.Allocator,
        prefix_path: []const u8,
    ) anyerror!void = null,

    /// Modify environment variables
    modifyEnv: ?*const fn (
        allocator: std.mem.Allocator,
        env: *std.process.EnvMap,
    ) anyerror!void = null,

    /// Modify the command vector
    modifyCommand: ?*const fn (
        allocator: std.mem.Allocator,
        cmd: *std.ArrayList([]const u8),
    ) anyerror!void = null,

    /// Called after the game process starts
    postLaunch: ?*const fn (
        allocator: std.mem.Allocator,
        game_pid: std.process.Child.Id,
    ) anyerror!void = null,
};

// ═══════════════════════════════════════════════════════════════════════════════
// BUILT-IN TINKERS
// ═══════════════════════════════════════════════════════════════════════════════

pub const mangohud_tinker = Tinker{
    .id = "mangohud",
    .priority = 75,
    .isEnabled = struct {
        fn f(gc: *const config.GameConfig) bool {
            return gc.mangohud.enabled;
        }
    }.f,
    .modifyEnv = struct {
        fn f(allocator: std.mem.Allocator, env: *std.process.EnvMap) !void {
            _ = allocator;
            try env.put("MANGOHUD", "1");
            try env.put("MANGOHUD_DLSYM", "1");
        }
    }.f,
};

pub const gamemode_tinker = Tinker{
    .id = "gamemode",
    .priority = 60,
    .isEnabled = struct {
        fn f(gc: *const config.GameConfig) bool {
            return gc.gamemode;
        }
    }.f,
    .modifyCommand = struct {
        fn f(allocator: std.mem.Allocator, cmd: *std.ArrayList([]const u8)) !void {
            // Prepend gamemoderun
            try cmd.insert(0, try allocator.dupe(u8, "gamemoderun"));
        }
    }.f,
};

/// Registry of all available tinkers
pub const all_tinkers = [_]*const Tinker{
    &mangohud_tinker,
    &gamemode_tinker,
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "tinker priority ordering" {
    // Ensure tinkers are in the expected order
    try std.testing.expect(gamemode_tinker.priority < mangohud_tinker.priority);
}

test "mangohud tinker enables correctly" {
    var gc = config.GameConfig.defaults(12345);
    gc.mangohud.enabled = true;

    try std.testing.expect(mangohud_tinker.isEnabled(&gc));
}

