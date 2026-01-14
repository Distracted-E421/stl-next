const std = @import("std");
const interface = @import("interface.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// GAMESCOPE TINKER (Phase 3.5 - Hardened)
// ═══════════════════════════════════════════════════════════════════════════════
//
// No global state! Reads config from ctx.game_config.gamescope
//
// ═══════════════════════════════════════════════════════════════════════════════

fn isEnabled(ctx: *const interface.Context) bool {
    return ctx.game_config.gamescope.enabled;
}

fn modifyArgs(ctx: *const interface.Context, args: *interface.ArgList) !void {
    const cfg = &ctx.game_config.gamescope;

    // Build gamescope command prefix
    var gs_args = std.ArrayList([]const u8).init(ctx.allocator);
    defer gs_args.deinit();

    try gs_args.append("gamescope");

    // Output resolution
    if (cfg.width > 0 and cfg.height > 0) {
        try gs_args.append("-W");
        try gs_args.append(try std.fmt.allocPrint(ctx.allocator, "{d}", .{cfg.width}));
        try gs_args.append("-H");
        try gs_args.append(try std.fmt.allocPrint(ctx.allocator, "{d}", .{cfg.height}));
    }

    // Internal resolution
    if (cfg.internal_width > 0 and cfg.internal_height > 0) {
        try gs_args.append("-w");
        try gs_args.append(try std.fmt.allocPrint(ctx.allocator, "{d}", .{cfg.internal_width}));
        try gs_args.append("-h");
        try gs_args.append(try std.fmt.allocPrint(ctx.allocator, "{d}", .{cfg.internal_height}));
    }

    // Display mode
    if (cfg.fullscreen) try gs_args.append("-f");
    if (cfg.borderless) try gs_args.append("-b");

    // Upscaling
    if (cfg.fsr) {
        try gs_args.append("-F");
        try gs_args.append("fsr");
        try gs_args.append("--fsr-sharpness");
        try gs_args.append(try std.fmt.allocPrint(ctx.allocator, "{d}", .{cfg.fsr_sharpness}));
    }

    // FPS limit
    if (cfg.fps_limit > 0) {
        try gs_args.append("-r");
        try gs_args.append(try std.fmt.allocPrint(ctx.allocator, "{d}", .{cfg.fps_limit}));
    }

    // Separator
    try gs_args.append("--");

    // Prepend gamescope args to existing command
    // We need to insert at the beginning, so we rebuild the list
    const original_items = try ctx.allocator.dupe([]const u8, args.items);
    defer ctx.allocator.free(original_items);

    args.clearRetainingCapacity();

    for (gs_args.items) |arg| {
        try args.append(arg);
    }
    for (original_items) |arg| {
        try args.append(arg);
    }

    std.log.info("Gamescope: Wrapping with {d}x{d} @ {d}fps", .{
        cfg.width,
        cfg.height,
        cfg.fps_limit,
    });
}

pub const gamescope_tinker = interface.Tinker{
    .id = "gamescope",
    .name = "Gamescope",
    .priority = interface.Priority.WRAPPER,
    .isEnabledFn = isEnabled,
    .preparePrefixFn = null,
    .modifyEnvFn = null,
    .modifyArgsFn = modifyArgs,
    .cleanupFn = null,
};
