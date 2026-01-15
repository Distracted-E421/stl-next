const std = @import("std");
const interface = @import("interface.zig");
const Tinker = interface.Tinker;
const Context = interface.Context;
const EnvMap = interface.EnvMap;
const ArgList = interface.ArgList;
const Priority = interface.Priority;
const config = @import("../core/config.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// LATENCYFLEX TINKER
// ═══════════════════════════════════════════════════════════════════════════════
//
// LatencyFleX is an open-source alternative to NVIDIA Reflex for reducing
// system latency in games. It works with:
//
//   - Vulkan (native Linux games and Proton)
//   - DXVK (Direct3D to Vulkan translation)
//
// ═══════════════════════════════════════════════════════════════════════════════

// Re-export from config
pub const LatencyflexMode = config.LatencyflexMode;

/// Check if LatencyFleX v1 layer is installed
fn isV1Installed() bool {
    const layer_paths = [_][]const u8{
        "/usr/share/vulkan/implicit_layer.d/latencyflex.json",
        "/usr/local/share/vulkan/implicit_layer.d/latencyflex.json",
    };

    for (layer_paths) |path| {
        std.fs.accessAbsolute(path, .{}) catch continue;
        return true;
    }

    // Check XDG data dirs
    if (std.posix.getenv("HOME")) |home| {
        var buf: [512]u8 = undefined;
        const local_path = std.fmt.bufPrint(&buf, "{s}/.local/share/vulkan/implicit_layer.d/latencyflex.json", .{home}) catch return false;
        std.fs.accessAbsolute(local_path, .{}) catch return false;
        return true;
    }

    return false;
}

/// Check if LFX2 DXVK is available
fn isV2Installed() bool {
    const dxvk_paths = [_][]const u8{
        "/usr/share/dxvk/x64/d3d11.dll",
    };

    for (dxvk_paths) |path| {
        std.fs.accessAbsolute(path, .{}) catch continue;
        return true;
    }

    return false;
}

fn isEnabled(ctx: *const Context) bool {
    return ctx.game_config.latencyflex.enabled;
}

fn preparePrefix(ctx: *const Context) anyerror!void {
    if (!isEnabled(ctx)) return;

    std.log.info("LatencyFleX: Preparing low-latency injection", .{});

    // Check installation status
    const v1_installed = isV1Installed();
    const v2_installed = isV2Installed();

    if (!v1_installed and !v2_installed) {
        std.log.warn("LatencyFleX: Not installed!", .{});
        std.log.warn("LatencyFleX: Install options:", .{});
        std.log.warn("  NixOS: nix-shell -p latencyflex", .{});
        std.log.warn("  AUR: yay -S latencyflex-git", .{});
        return;
    }

    if (v1_installed) {
        std.log.info("LatencyFleX: Found v1 Vulkan layer", .{});
    }
    if (v2_installed) {
        std.log.info("LatencyFleX: Found v2 (LFX2) support", .{});
    }
}

fn modifyEnv(ctx: *const Context, env: *EnvMap) anyerror!void {
    if (!isEnabled(ctx)) return;

    const lfx_config = ctx.game_config.latencyflex;

    // Determine which mode to use
    var effective_mode: LatencyflexMode = lfx_config.mode;
    if (effective_mode == .auto) {
        if (isV2Installed()) {
            effective_mode = .v2;
        } else if (isV1Installed()) {
            effective_mode = .v1;
        } else {
            std.log.warn("LatencyFleX: No installation found, skipping", .{});
            return;
        }
    }

    switch (effective_mode) {
        .v1 => {
            // Enable the Vulkan layer
            try env.put("LFX", "1");

            // Set wait target if specified
            if (lfx_config.wait_target_us > 0) {
                var buf: [32]u8 = undefined;
                const target_str = std.fmt.bufPrint(&buf, "{d}", .{lfx_config.wait_target_us}) catch "0";
                try env.put("LFX_WAIT_TARGET_US", target_str);
            }

            std.log.info("LatencyFleX: Enabled v1 Vulkan layer", .{});
        },
        .v2 => {
            // LFX2 is enabled via DXVK environment
            try env.put("DXVK_LFX", "1");

            // Frame cap for optimal latency
            if (lfx_config.max_fps) |fps| {
                var buf: [32]u8 = undefined;
                const fps_str = std.fmt.bufPrint(&buf, "{d}", .{fps}) catch "0";
                try env.put("DXVK_FRAME_RATE", fps_str);
            }

            std.log.info("LatencyFleX: Enabled v2 (LFX2) via DXVK", .{});
        },
        .auto => unreachable,
    }

    // Common settings
    if (lfx_config.max_fps) |fps| {
        std.log.info("LatencyFleX: Frame cap: {d} FPS", .{fps});
    }
}

fn modifyArgs(ctx: *const Context, args: *ArgList) anyerror!void {
    _ = ctx;
    _ = args;
    // LatencyFleX doesn't modify command line arguments
}

fn cleanup(ctx: *const Context) void {
    _ = ctx;
    std.log.debug("LatencyFleX: Cleanup (no-op)", .{});
}

pub const latencyflex_tinker = Tinker{
    .id = "latencyflex",
    .name = "LatencyFleX",
    .priority = Priority.OVERLAY,
    .isEnabledFn = isEnabled,
    .preparePrefixFn = preparePrefix,
    .modifyEnvFn = modifyEnv,
    .modifyArgsFn = modifyArgs,
    .cleanupFn = cleanup,
};

// ═══════════════════════════════════════════════════════════════════════════════
// CLI COMMANDS
// ═══════════════════════════════════════════════════════════════════════════════

pub fn showInfo() void {
    const compat = @import("../compat.zig");

    compat.print(
        \\LatencyFleX Integration
        \\━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        \\
        \\LatencyFleX is an open-source NVIDIA Reflex alternative for
        \\reducing system latency in games.
        \\
        \\Versions:
        \\  v1 (LFX)  - Vulkan layer, works with any Vulkan game
        \\  v2 (LFX2) - DXVK integration, better for Proton games
        \\
        \\Installation (NixOS):
        \\  environment.systemPackages = [ pkgs.latencyflex ];
        \\
        \\Installation (Arch):
        \\  yay -S latencyflex-git
        \\
        \\Usage:
        \\  STL-Next automatically detects and uses the best version.
        \\
        \\━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        \\
    , .{});
}

pub fn checkInstallation() void {
    const compat = @import("../compat.zig");

    compat.print("LatencyFleX Installation Status\n", .{});
    compat.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    if (isV1Installed()) {
        compat.print("  [✓] v1 (Vulkan layer) - INSTALLED\n", .{});
    } else {
        compat.print("  [✗] v1 (Vulkan layer) - NOT FOUND\n", .{});
    }

    if (isV2Installed()) {
        compat.print("  [✓] v2 (LFX2/DXVK) - INSTALLED\n", .{});
    } else {
        compat.print("  [✗] v2 (LFX2/DXVK) - NOT FOUND\n", .{});
    }

    compat.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
}
