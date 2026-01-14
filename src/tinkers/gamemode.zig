const std = @import("std");
const interface = @import("interface.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// GAMEMODE TINKER (Phase 3.5 - Hardened)
// ═══════════════════════════════════════════════════════════════════════════════
//
// No global state! Reads config from ctx.game_config.gamemode
//
// ═══════════════════════════════════════════════════════════════════════════════

fn isEnabled(ctx: *const interface.Context) bool {
    return ctx.game_config.gamemode.enabled;
}

fn modifyEnv(ctx: *const interface.Context, env: *interface.EnvMap) !void {
    const cfg = &ctx.game_config.gamemode;

    // Get current LD_PRELOAD
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

    // Renice value
    if (cfg.renice != 0) {
        const renice_str = try std.fmt.allocPrint(ctx.allocator, "{d}", .{cfg.renice});
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
