const std = @import("std");
const interface = @import("interface.zig");
const Tinker = interface.Tinker;
const Context = interface.Context;
const EnvMap = interface.EnvMap;
const ArgList = interface.ArgList;
const Priority = interface.Priority;
const config = @import("../core/config.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// RESHADE TINKER
// ═══════════════════════════════════════════════════════════════════════════════
//
// ReShade is a generic post-processing injector for games/apps. It works with:
//   - DirectX 9, 10, 11, 12
//   - OpenGL
//   - Vulkan (via layer)
//
// STL-Next approach:
//   1. Detect game renderer (DX9/DX11/DX12/OpenGL/Vulkan)
//   2. Set up Vulkan layer for Vulkan games
//   3. Manage shader presets
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const ReshadeRenderer = enum {
    dx9,
    dx10,
    dx11,
    dx12,
    opengl,
    vulkan,
    unknown,
};

/// Get config directory for ReShade
fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse "/tmp";
    return std.fmt.allocPrint(allocator, "{s}/.config/stl-next/reshade", .{home});
}

/// Get ReShade installation directory
fn getInstallDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse "/tmp";
    return std.fmt.allocPrint(allocator, "{s}/.local/share/stl-next/reshade", .{home});
}

fn isEnabled(ctx: *const Context) bool {
    return ctx.game_config.reshade.enabled;
}

fn preparePrefix(ctx: *const Context) anyerror!void {
    if (!isEnabled(ctx)) return;

    std.log.info("ReShade: Preparing injection for game {d}", .{ctx.app_id});

    // Check if ReShade is installed
    const install_dir = try getInstallDir(ctx.allocator);
    defer ctx.allocator.free(install_dir);

    const reshade_dll = try std.fmt.allocPrint(ctx.allocator, "{s}/ReShade64.dll", .{install_dir});
    defer ctx.allocator.free(reshade_dll);

    std.fs.accessAbsolute(reshade_dll, .{}) catch {
        std.log.warn("ReShade: Not installed at {s}", .{install_dir});
        std.log.warn("ReShade: Download from https://reshade.me/ and extract to {s}", .{install_dir});
        return;
    };

    std.log.info("ReShade: Found installation at {s}", .{install_dir});
}

fn modifyEnv(ctx: *const Context, env: *EnvMap) anyerror!void {
    if (!isEnabled(ctx)) return;

    const reshade_config = ctx.game_config.reshade;

    // For Vulkan games, configure the layer
    const renderer = reshade_config.renderer orelse .dx11;
    if (renderer == .vulkan) {
        const install_dir = try getInstallDir(ctx.allocator);
        defer ctx.allocator.free(install_dir);

        // Append to existing VK_LAYER_PATH or create new
        if (std.posix.getenv("VK_LAYER_PATH")) |existing| {
            const new_path = try std.fmt.allocPrint(
                ctx.allocator,
                "{s}:{s}",
                .{ existing, install_dir },
            );
            try env.put("VK_LAYER_PATH", new_path);
        } else {
            try env.put("VK_LAYER_PATH", install_dir);
        }

        try env.put("VK_INSTANCE_LAYERS", "VK_LAYER_reshade_vkLayer");
        std.log.info("ReShade: Configured Vulkan layer", .{});
    }

    // Set screenshot path if configured
    if (reshade_config.screenshot_path) |path| {
        try env.put("RESHADE_SCREENSHOT_PATH", path);
    }

    std.log.info("ReShade: Applied configuration", .{});
}

fn modifyArgs(ctx: *const Context, args: *ArgList) anyerror!void {
    _ = ctx;
    _ = args;
    // ReShade doesn't modify command line arguments
}

fn cleanup(ctx: *const Context) void {
    _ = ctx;
    std.log.debug("ReShade: Cleanup (no-op)", .{});
}

pub const reshade_tinker = Tinker{
    .id = "reshade",
    .name = "ReShade",
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

pub fn installReshade(allocator: std.mem.Allocator, version: ?[]const u8) !void {
    _ = version;

    const install_dir = try getInstallDir(allocator);
    defer allocator.free(install_dir);

    // Create directory
    std.fs.makeDirAbsolute(install_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    std.log.info("ReShade: Installation directory: {s}", .{install_dir});
    std.log.info("ReShade: Please download from https://reshade.me/", .{});
    std.log.info("ReShade: Extract ReShade64.dll to {s}", .{install_dir});
}

pub fn listPresets(allocator: std.mem.Allocator) !void {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const presets_dir = try std.fmt.allocPrint(allocator, "{s}/presets", .{config_dir});
    defer allocator.free(presets_dir);

    var dir = std.fs.openDirAbsolute(presets_dir, .{ .iterate = true }) catch {
        std.log.info("ReShade: No presets found in {s}", .{presets_dir});
        return;
    };
    defer dir.close();

    std.log.info("ReShade Presets:", .{});
    std.log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", .{});

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".ini")) {
            std.log.info("  {s}", .{entry.name});
        }
    }
}
