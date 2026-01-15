const std = @import("std");
const interface = @import("interface.zig");
const Context = interface.Context;
const EnvMap = interface.EnvMap;
const ArgList = interface.ArgList;
const Priority = interface.Priority;

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM COMMANDS TINKER
// ═══════════════════════════════════════════════════════════════════════════════
//
// Runs custom shell commands before and after game launch.
//
// Use cases:
//   - Start/stop services (syncthing, discord, etc.)
//   - Mount/unmount filesystems
//   - Kill conflicting processes
//   - Run game-specific fixup scripts
//   - Performance tuning (CPU governor, etc.)
//
// Environment variables available to commands:
//   - $STL_APP_ID: The Steam AppID
//   - $STL_GAME_NAME: Game name
//   - $STL_PREFIX_PATH: Wine prefix path
//   - $STL_INSTALL_DIR: Game installation directory
//   - $STL_CONFIG_DIR: STL configuration directory
//
// ═══════════════════════════════════════════════════════════════════════════════

/// Custom commands configuration
pub const CustomCommandsConfig = struct {
    enabled: bool = false,
    
    /// Commands to run BEFORE game launch
    pre_launch: []const CommandEntry = &.{},
    
    /// Commands to run AFTER game exits
    post_exit: []const CommandEntry = &.{},
    
    /// Commands to run if launch fails
    on_error: []const CommandEntry = &.{},
    
    /// Global timeout for all commands (seconds, 0 = no limit)
    timeout_seconds: u32 = 30,
    
    /// Continue launching if pre-launch command fails
    ignore_pre_errors: bool = false,
    
    /// Working directory for commands (null = game install dir)
    working_dir: ?[]const u8 = null,
};

/// Individual command entry
pub const CommandEntry = struct {
    /// Human-readable name for logging
    name: []const u8 = "Custom Command",
    
    /// The command to execute (shell command string)
    command: []const u8,
    
    /// Whether to wait for command to complete
    wait: bool = true,
    
    /// Timeout for this specific command (0 = use global)
    timeout_seconds: u32 = 0,
    
    /// Run command in background (don't wait for exit)
    background: bool = false,
    
    /// Only run for specific AppIDs (empty = all games)
    app_ids: []const u32 = &.{},
    
    /// Shell to use (default: /bin/sh)
    shell: []const u8 = "/bin/sh",
};

/// Stored pre-launch state for cleanup
var pre_launch_pids: std.ArrayList(std.process.Child.Id) = undefined;
var pre_launch_init: bool = false;

fn isEnabled(ctx: *const Context) bool {
    const cfg = ctx.game_config.custom_commands;
    return cfg.enabled and 
           (cfg.pre_launch.len > 0 or cfg.post_exit.len > 0);
}

fn preparePrefix(ctx: *const Context) !void {
    const cfg = ctx.game_config.custom_commands;
    
    if (cfg.pre_launch.len == 0) return;
    
    // Initialize PID tracking
    if (!pre_launch_init) {
        pre_launch_pids = std.ArrayList(std.process.Child.Id).init(ctx.allocator);
        pre_launch_init = true;
    }
    
    std.log.info("CustomCommands: Running {d} pre-launch command(s)", .{cfg.pre_launch.len});
    
    for (cfg.pre_launch) |entry| {
        // Check if command is filtered to specific AppIDs
        if (entry.app_ids.len > 0) {
            var found = false;
            for (entry.app_ids) |id| {
                if (id == ctx.app_id) {
                    found = true;
                    break;
                }
            }
            if (!found) continue;
        }
        
        const success = try runCommand(ctx, &entry, cfg);
        
        if (!success and !cfg.ignore_pre_errors) {
            return error.PreLaunchCommandFailed;
        }
    }
}

fn runCommand(ctx: *const Context, entry: *const CommandEntry, cfg: CustomCommandsConfig) !bool {
    std.log.info("CustomCommands: [{s}] {s}", .{ entry.name, entry.command[0..@min(60, entry.command.len)] });
    
    // Build environment with STL variables
    var env = std.process.EnvMap.init(ctx.allocator);
    defer env.deinit();
    
    // Inherit existing environment
    var inherited_env = try std.process.getEnvMap(ctx.allocator);
    defer inherited_env.deinit();
    var env_iter = inherited_env.iterator();
    while (env_iter.next()) |e| {
        try env.put(e.key_ptr.*, e.value_ptr.*);
    }
    
    // Add STL variables
    const app_id_str = try std.fmt.allocPrint(ctx.allocator, "{d}", .{ctx.app_id});
    defer ctx.allocator.free(app_id_str);
    
    try env.put("STL_APP_ID", app_id_str);
    try env.put("STL_GAME_NAME", ctx.game_name);
    try env.put("STL_PREFIX_PATH", ctx.prefix_path);
    try env.put("STL_INSTALL_DIR", ctx.install_dir);
    try env.put("STL_CONFIG_DIR", ctx.config_dir);
    try env.put("STL_SCRATCH_DIR", ctx.scratch_dir);
    if (ctx.proton_path) |p| {
        try env.put("STL_PROTON_PATH", p);
    }
    
    // Build command args: shell -c "command"
    var child = std.process.Child.init(&.{ entry.shell, "-c", entry.command }, ctx.allocator);
    child.env_map = &env;
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    
    // Set working directory
    if (cfg.working_dir) |dir| {
        child.cwd = dir;
    } else {
        child.cwd = ctx.install_dir;
    }
    
    if (entry.background or !entry.wait) {
        // Fire and forget
        _ = try child.spawn();
        try pre_launch_pids.append(child.id);
        std.log.debug("CustomCommands: Started background process PID {d}", .{child.id});
        return true;
    }
    
    // Wait for completion
    _ = try child.spawn();
    
    const timeout = if (entry.timeout_seconds > 0) entry.timeout_seconds else cfg.timeout_seconds;
    
    if (timeout > 0) {
        // Use timeout
        const term = child.wait() catch |err| {
            std.log.warn("CustomCommands: Command wait error: {}", .{err});
            return false;
        };
        
        return switch (term) {
            .Exited => |code| blk: {
                if (code != 0) {
                    std.log.warn("CustomCommands: [{s}] exited with code {d}", .{ entry.name, code });
                }
                break :blk code == 0;
            },
            else => blk: {
                std.log.warn("CustomCommands: [{s}] terminated abnormally", .{entry.name});
                break :blk false;
            },
        };
    } else {
        const term = try child.wait();
        return switch (term) {
            .Exited => |code| code == 0,
            else => false,
        };
    }
}

fn modifyEnv(ctx: *const Context, env: *EnvMap) !void {
    _ = ctx;
    _ = env;
    // Custom commands don't modify environment
}

fn modifyArgs(ctx: *const Context, args: *ArgList) !void {
    _ = ctx;
    _ = args;
    // Custom commands don't modify launch arguments
}

fn cleanup(ctx: *const Context) void {
    const cfg = ctx.game_config.custom_commands;
    
    if (cfg.post_exit.len > 0) {
        std.log.info("CustomCommands: Running {d} post-exit command(s)", .{cfg.post_exit.len});
        
        for (cfg.post_exit) |entry| {
            // Check AppID filter
            if (entry.app_ids.len > 0) {
                var found = false;
                for (entry.app_ids) |id| {
                    if (id == ctx.app_id) {
                        found = true;
                        break;
                    }
                }
                if (!found) continue;
            }
            
            _ = runCommand(ctx, &entry, cfg) catch |err| {
                std.log.warn("CustomCommands: Post-exit command failed: {}", .{err});
                continue;
            };
        }
    }
    
    // Clean up background processes if needed
    if (pre_launch_init) {
        for (pre_launch_pids.items) |pid| {
            std.log.debug("CustomCommands: Cleaning up background PID {d}", .{pid});
            // We don't kill them - they were meant to run in background
        }
        pre_launch_pids.clearAndFree();
    }
}

pub const customcmd_tinker = interface.Tinker{
    .id = "customcmd",
    .name = "Custom Commands",
    .priority = Priority.SETUP, // Run during setup phase
    .isEnabledFn = isEnabled,
    .preparePrefixFn = preparePrefix,
    .modifyEnvFn = modifyEnv,
    .modifyArgsFn = modifyArgs,
    .cleanupFn = cleanup,
};

// ═══════════════════════════════════════════════════════════════════════════════
// COMMON COMMAND TEMPLATES
// ═══════════════════════════════════════════════════════════════════════════════

pub const Templates = struct {
    /// Kill Discord before game (prevents overlay conflicts)
    pub const kill_discord = CommandEntry{
        .name = "Kill Discord",
        .command = "pkill -f discord || true",
        .wait = true,
    };
    
    /// Set CPU governor to performance
    pub const cpu_performance = CommandEntry{
        .name = "CPU Performance Mode",
        .command = "echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor",
        .wait = true,
    };
    
    /// Reset CPU governor after game
    pub const cpu_powersave = CommandEntry{
        .name = "CPU Powersave Mode",
        .command = "echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor",
        .wait = true,
    };
    
    /// Stop syncthing during gaming
    pub const stop_syncthing = CommandEntry{
        .name = "Stop Syncthing",
        .command = "systemctl --user stop syncthing.service || true",
        .wait = true,
    };
    
    /// Restart syncthing after gaming
    pub const start_syncthing = CommandEntry{
        .name = "Start Syncthing",
        .command = "systemctl --user start syncthing.service || true",
        .wait = true,
    };
    
    /// Notify when game starts
    pub const notify_start = CommandEntry{
        .name = "Game Started Notification",
        .command = "notify-send 'STL-Next' \"Starting $STL_GAME_NAME\"",
        .wait = false,
    };
    
    /// Notify when game exits
    pub const notify_exit = CommandEntry{
        .name = "Game Exited Notification",
        .command = "notify-send 'STL-Next' \"$STL_GAME_NAME has exited\"",
        .wait = false,
    };
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "default config disabled" {
    const config = CustomCommandsConfig{};
    try std.testing.expect(!config.enabled);
}

test "templates defined" {
    try std.testing.expect(Templates.kill_discord.wait);
    try std.testing.expect(!Templates.notify_start.wait);
}

