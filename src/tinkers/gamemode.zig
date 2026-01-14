const std = @import("std");
const interface = @import("interface.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// GAMEMODE TINKER: Feral Interactive's GameMode
// ═══════════════════════════════════════════════════════════════════════════════

/// GameMode configuration
pub const GameModeConfig = struct {
    enabled: bool = false,
    custom_ini: ?[]const u8 = null,
    renice: i8 = 0,
    disable_screensaver: bool = true,
    inhibit_sleep: bool = true,
};

var global_config: GameModeConfig = .{ .enabled = false };

pub fn setConfig(config: GameModeConfig) void {
    global_config = config;
}

fn isEnabled(ctx: *const interface.Context) bool {
    _ = ctx; // Context not needed for global config check
    return global_config.enabled;
}

fn modifyEnv(ctx: *const interface.Context, env: *interface.EnvMap) !void {
    const current_preload = env.get("LD_PRELOAD") orelse "";
    
    if (current_preload.len > 0) {
        const new_preload = try std.fmt.allocPrint(
            ctx.allocator,
            "{s}:libgamemodeauto.so.0",
            .{current_preload},
        );
        try env.put("LD_PRELOAD", new_preload);
    } else {
        try env.put("LD_PRELOAD", "libgamemodeauto.so.0");
    }
    
    if (global_config.custom_ini) |ini_path| {
        try env.put("GAMEMODE_INI", ini_path);
    }
    
    if (global_config.renice != 0) {
        const renice_str = try std.fmt.allocPrint(ctx.allocator, "{d}", .{global_config.renice});
        try env.put("GAMEMODE_RENICE", renice_str);
    }
    
    std.log.info("GameMode: Enabled via LD_PRELOAD", .{});
}

pub const gamemode_tinker = interface.Tinker{
    .id = "gamemode",
    .name = "GameMode",
    .priority = interface.Priority.OVERLAY_EARLY,
    .isEnabledFn = isEnabled,
    .preparePrefixFn = null,
    .modifyEnvFn = modifyEnv,
    .modifyArgsFn = null,
    .cleanupFn = null,
};

test "gamemode env setup" {
    try std.testing.expect(gamemode_tinker.priority < interface.Priority.OVERLAY);
}
