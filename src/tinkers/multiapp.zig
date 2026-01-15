const std = @import("std");
const interface = @import("interface.zig");
const Tinker = interface.Tinker;
const Context = interface.Context;
const EnvMap = interface.EnvMap;
const ArgList = interface.ArgList;
const Priority = interface.Priority;
const config = @import("../core/config.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// MULTI-APP LAUNCHER TINKER
// ═══════════════════════════════════════════════════════════════════════════════
//
// Launches helper applications alongside the main game:
//   - Discord Rich Presence apps
//   - OBS (for streaming)
//   - Performance overlays
//   - Custom tools and utilities
//
// ═══════════════════════════════════════════════════════════════════════════════

// Re-export from config
pub const AppLaunchTiming = config.AppLaunchTiming;
pub const AppClosePolicy = config.AppClosePolicy;
pub const HelperApp = config.HelperApp;

// Track launched processes for cleanup
var launched_pids: std.ArrayListUnmanaged(std.process.Child.Id) = .{};
var pids_allocator: ?std.mem.Allocator = null;

fn initPids(allocator: std.mem.Allocator) void {
    if (pids_allocator == null) {
        pids_allocator = allocator;
    }
}

fn launchApp(allocator: std.mem.Allocator, app: HelperApp, global_delay: u32) !void {
    // Apply delay
    const delay = if (app.delay_ms > 0) app.delay_ms else global_delay;
    if (delay > 0) {
        std.Thread.sleep(delay * std.time.ns_per_ms);
    }

    std.log.info("MultiApp: Launching {s}", .{app.name});
    std.log.debug("MultiApp: Command: {s}", .{app.command});

    // Build argv
    var argv: std.ArrayListUnmanaged([]const u8) = .{};
    defer argv.deinit(allocator);

    try argv.append(allocator, app.command);
    for (app.args) |arg| {
        try argv.append(allocator, arg);
    }

    // Spawn the process
    var child = std.process.Child.init(argv.items, allocator);

    // Set working directory
    if (app.working_dir) |wd| {
        child.cwd = wd;
    }

    // Spawn (detached, don't wait)
    _ = try child.spawn();

    // Track PID for cleanup
    if (pids_allocator) |alloc| {
        try launched_pids.append(alloc, child.id);
    }

    std.log.info("MultiApp: Launched {s} (PID: {d})", .{ app.name, child.id });
}

fn isEnabled(ctx: *const Context) bool {
    return ctx.game_config.multiapp.enabled and ctx.game_config.multiapp.apps.len > 0;
}

fn preparePrefix(ctx: *const Context) anyerror!void {
    if (!isEnabled(ctx)) return;

    std.log.info("MultiApp: Preparing to launch {d} helper app(s)", .{ctx.game_config.multiapp.apps.len});

    initPids(ctx.allocator);

    // Launch "before_game" apps
    for (ctx.game_config.multiapp.apps) |app| {
        if (app.timing == .before_game) {
            try launchApp(ctx.allocator, app, ctx.game_config.multiapp.global_delay_ms);
        }
    }
}

fn modifyEnv(ctx: *const Context, env: *EnvMap) anyerror!void {
    _ = env;
    if (!isEnabled(ctx)) return;

    initPids(ctx.allocator);

    // Launch "with_game" apps
    for (ctx.game_config.multiapp.apps) |app| {
        if (app.timing == .with_game) {
            try launchApp(ctx.allocator, app, ctx.game_config.multiapp.global_delay_ms);
        }
    }
}

fn modifyArgs(ctx: *const Context, args: *ArgList) anyerror!void {
    _ = ctx;
    _ = args;
    // MultiApp doesn't modify command line arguments
}

fn cleanup(ctx: *const Context) void {
    if (!ctx.game_config.multiapp.enabled) return;

    std.log.info("MultiApp: Cleaning up helper apps", .{});

    // Kill processes that should be closed
    for (ctx.game_config.multiapp.apps) |app| {
        if (app.close_policy == .on_game_exit) {
            std.log.info("MultiApp: Would terminate: {s}", .{app.name});
        }
    }

    // Launch "after_game" apps
    for (ctx.game_config.multiapp.apps) |app| {
        if (app.timing == .after_game) {
            launchApp(ctx.allocator, app, ctx.game_config.multiapp.global_delay_ms) catch |err| {
                std.log.warn("MultiApp: Failed to launch {s}: {}", .{ app.name, err });
            };
        }
    }

    // Clean up PID tracking
    if (pids_allocator) |alloc| {
        launched_pids.deinit(alloc);
        pids_allocator = null;
    }
}

pub const multiapp_tinker = Tinker{
    .id = "multiapp",
    .name = "MultiApp",
    .priority = Priority.SETUP_EARLY, // Launch helper apps before other tinkers
    .isEnabledFn = isEnabled,
    .preparePrefixFn = preparePrefix,
    .modifyEnvFn = modifyEnv,
    .modifyArgsFn = modifyArgs,
    .cleanupFn = cleanup,
};

// ═══════════════════════════════════════════════════════════════════════════════
// PRESET HELPER APPS
// ═══════════════════════════════════════════════════════════════════════════════

pub const Presets = struct {
    /// OBS Studio for game capture
    pub const obs = HelperApp{
        .name = "OBS Studio",
        .command = "obs",
        .args = &.{"--startreplaybuffer"},
        .timing = .before_game,
        .close_policy = .leave_running,
        .minimize = true,
    };

    /// Discord with game activity
    pub const discord = HelperApp{
        .name = "Discord",
        .command = "discord",
        .timing = .before_game,
        .close_policy = .leave_running,
    };

    /// MangoHud config tool
    pub const mangohud_config = HelperApp{
        .name = "MangoHud Config",
        .command = "mangohud",
        .args = &.{"--config"},
        .timing = .before_game,
        .close_policy = .on_game_exit,
    };

    /// GPU monitoring (nvtop/radeontop)
    pub const gpu_monitor = HelperApp{
        .name = "GPU Monitor",
        .command = "nvtop",
        .timing = .with_game,
        .close_policy = .on_game_exit,
    };
};

// ═══════════════════════════════════════════════════════════════════════════════
// CLI COMMANDS
// ═══════════════════════════════════════════════════════════════════════════════

pub fn showPresets() void {
    const compat = @import("../compat.zig");

    compat.print(
        \\Multi-App Presets
        \\━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        \\
        \\Available presets for common helper apps:
        \\
        \\  obs          - OBS Studio with replay buffer
        \\  discord      - Discord (stays open)
        \\  gpu_monitor  - nvtop/radeontop
        \\
        \\Configuration Example:
        \\  {{
        \\    "multiapp": {{
        \\      "enabled": true,
        \\      "apps": [
        \\        {{
        \\          "name": "OBS",
        \\          "command": "obs",
        \\          "args": ["--startreplaybuffer"],
        \\          "timing": "before_game",
        \\          "close_policy": "leave_running"
        \\        }}
        \\      ]
        \\    }}
        \\  }}
        \\
        \\━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        \\
    , .{});
}
