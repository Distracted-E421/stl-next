const std = @import("std");
const interface = @import("interface.zig");
const Context = interface.Context;
const EnvMap = interface.EnvMap;
const ArgList = interface.ArgList;

// ═══════════════════════════════════════════════════════════════════════════════
// OPTISCALER TINKER (Phase 6)
// ═══════════════════════════════════════════════════════════════════════════════
//
// OptiScaler is a universal upscaler that enables FSR 3.1, XeSS, and DLSS
// Frame Generation on any GPU, including AMD and Intel GPUs.
//
// Project: https://github.com/cdozdil/OptiScaler
//
// Features:
//   - FSR 3.1 Frame Generation on any GPU
//   - DLSS-to-FSR replacement
//   - XeSS integration
//   - Anti-lag features
//   - Works with Vulkan and DX11/DX12
//
// ═══════════════════════════════════════════════════════════════════════════════

/// OptiScaler upscaler backend
pub const UpscalerBackend = enum {
    fsr31, // AMD FSR 3.1
    xess, // Intel XeSS
    dlss, // NVIDIA DLSS (passthrough)
    auto, // Auto-detect best option

    pub fn toString(self: UpscalerBackend) []const u8 {
        return switch (self) {
            .fsr31 => "fsr31",
            .xess => "xess",
            .dlss => "dlss",
            .auto => "auto",
        };
    }
};

/// OptiScaler configuration
pub const OptiScalerConfig = struct {
    /// Enable OptiScaler
    enabled: bool = false,
    /// Upscaler backend to use
    backend: UpscalerBackend = .auto,
    /// Enable frame generation
    frame_generation: bool = true,
    /// FSR quality preset
    fsr_quality: FsrQuality = .quality,
    /// Sharpening amount (0.0-1.0)
    sharpening: f32 = 0.5,
    /// Anti-lag mode
    anti_lag: AntiLagMode = .enabled,
    /// Override game's native upscaler
    override_native: bool = true,
    /// Enable debug overlay
    debug_overlay: bool = false,
    /// Custom OptiScaler install path
    install_path: ?[]const u8 = null,
    /// Vulkan mode (for VKD3D games)
    vulkan_mode: bool = false,

    pub const FsrQuality = enum {
        ultra_performance,
        performance,
        balanced,
        quality,
        ultra_quality,

        pub fn toString(self: FsrQuality) []const u8 {
            return switch (self) {
                .ultra_performance => "ultra_performance",
                .performance => "performance",
                .balanced => "balanced",
                .quality => "quality",
                .ultra_quality => "ultra_quality",
            };
        }

        pub fn toScaleFactor(self: FsrQuality) f32 {
            return switch (self) {
                .ultra_performance => 3.0,
                .performance => 2.0,
                .balanced => 1.7,
                .quality => 1.5,
                .ultra_quality => 1.3,
            };
        }
    };

    pub const AntiLagMode = enum {
        disabled,
        enabled,
        enabled_boost,

        pub fn toString(self: AntiLagMode) []const u8 {
            return switch (self) {
                .disabled => "0",
                .enabled => "1",
                .enabled_boost => "2",
            };
        }
    };
};

/// Default OptiScaler paths
const OPTISCALER_PATHS = [_][]const u8{
    "~/.local/share/optiscaler",
    "/opt/optiscaler",
    "/usr/share/optiscaler",
};

/// OptiScaler DLL names
const OPTISCALER_DLLS = [_][]const u8{
    "nvngx.dll", // DLSS replacement
    "dxgi.dll", // DX11/12 hook
    "d3d11.dll", // DX11 hook
    "d3d12.dll", // DX12 hook
    "libxess.dll", // XeSS support
    "amd_fidelityfx_vk.dll", // FSR Vulkan
};

fn isEnabled(ctx: *const Context) bool {
    // Check game config for OptiScaler settings
    _ = ctx;
    return false; // Will be enabled via config
}

fn preparePrefix(ctx: *const Context) anyerror!void {
    // Install OptiScaler DLLs to the Wine prefix
    const prefix_path = ctx.prefix_path;
    const home = std.posix.getenv("HOME") orelse return;

    // Find OptiScaler installation
    var optiscaler_path: ?[]const u8 = null;
    for (OPTISCALER_PATHS) |path_template| {
        var path_buf: [512]u8 = undefined;
        const path = if (path_template[0] == '~')
            std.fmt.bufPrint(&path_buf, "{s}{s}", .{ home, path_template[1..] }) catch continue
        else
            path_template;

        if (std.fs.accessAbsolute(path, .{})) |_| {
            optiscaler_path = path;
            break;
        } else |_| {}
    }

    if (optiscaler_path) |install_path| {
        std.log.info("OptiScaler: Found at {s}", .{install_path});
        try installDlls(ctx.allocator, install_path, prefix_path);
    } else {
        std.log.warn("OptiScaler: Not found, please install from https://github.com/cdozdil/OptiScaler", .{});
    }
}

fn installDlls(allocator: std.mem.Allocator, source_path: []const u8, prefix_path: []const u8) !void {
    const system32 = try std.fmt.allocPrint(
        allocator,
        "{s}/drive_c/windows/system32",
        .{prefix_path},
    );
    defer allocator.free(system32);

    for (OPTISCALER_DLLS) |dll| {
        const src = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ source_path, dll });
        defer allocator.free(src);

        const dst = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ system32, dll });
        defer allocator.free(dst);

        std.fs.copyFileAbsolute(src, dst, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => {}, // DLL not in package, skip
                else => std.log.warn("OptiScaler: Failed to copy {s}: {s}", .{ dll, @errorName(err) }),
            }
            continue;
        };

        std.log.debug("OptiScaler: Installed {s}", .{dll});
    }
}

fn modifyEnv(ctx: *const Context, env: *EnvMap) anyerror!void {
    _ = ctx;

    // OptiScaler configuration via environment
    try env.put("OPTISCALER_ENABLED", "1");

    // Enable DXVK for better compatibility
    try env.put("DXVK_ASYNC", "1");

    // VKD3D-Proton settings for better frame generation
    try env.put("VKD3D_FEATURE_LEVEL", "12_2");
}

fn modifyArgs(ctx: *const Context, args: *ArgList) anyerror!void {
    // OptiScaler doesn't modify command-line arguments
    _ = ctx;
    _ = args;
}

/// Generate OptiScaler configuration INI
pub fn generateConfig(allocator: std.mem.Allocator, config: OptiScalerConfig, game_name: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const w = result.writer();

    try w.print("; OptiScaler Configuration for {s}\n", .{game_name});
    try w.print("; Generated by STL-Next\n\n", .{});

    try w.writeAll("[OptiScaler]\n");
    try w.print("Enabled=true\n", .{});
    try w.print("Backend={s}\n", .{config.backend.toString()});
    try w.print("OverrideNative={s}\n", .{if (config.override_native) "true" else "false"});
    try w.print("DebugOverlay={s}\n", .{if (config.debug_overlay) "true" else "false"});

    try w.writeAll("\n[FrameGeneration]\n");
    try w.print("Enabled={s}\n", .{if (config.frame_generation) "true" else "false"});
    try w.print("AntiLag={s}\n", .{config.anti_lag.toString()});

    try w.writeAll("\n[FSR]\n");
    try w.print("Quality={s}\n", .{config.fsr_quality.toString()});
    try w.print("Sharpening={d:.2}\n", .{config.sharpening});

    try w.writeAll("\n[Vulkan]\n");
    try w.print("Enabled={s}\n", .{if (config.vulkan_mode) "true" else "false"});

    return result.toOwnedSlice();
}

/// Write OptiScaler config to the game directory
pub fn writeConfigToGame(allocator: std.mem.Allocator, config: OptiScalerConfig, game_name: []const u8, game_dir: []const u8) !void {
    const config_content = try generateConfig(allocator, config, game_name);
    defer allocator.free(config_content);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/optiscaler.ini", .{game_dir});
    defer allocator.free(config_path);

    const file = try std.fs.createFileAbsolute(config_path, .{});
    defer file.close();

    try file.writeAll(config_content);

    std.log.info("OptiScaler: Wrote config to {s}", .{config_path});
}

/// Check GPU vendor for optimal backend selection
pub fn detectOptimalBackend() UpscalerBackend {
    // Check for NVIDIA
    if (std.fs.accessAbsolute("/dev/nvidia0", .{})) |_| {
        return .dlss;
    } else |_| {}

    // Check for AMD
    const amd_paths = [_][]const u8{
        "/sys/class/drm/card0/device/vendor",
        "/sys/class/drm/card1/device/vendor",
    };

    for (amd_paths) |path| {
        const file = std.fs.openFileAbsolute(path, .{}) catch continue;
        defer file.close();

        var buf: [16]u8 = undefined;
        const len = file.read(&buf) catch continue;
        if (len > 0 and std.mem.startsWith(u8, buf[0..len], "0x1002")) {
            return .fsr31; // AMD vendor ID
        }
    }

    // Check for Intel
    for (amd_paths) |path| {
        const file = std.fs.openFileAbsolute(path, .{}) catch continue;
        defer file.close();

        var buf: [16]u8 = undefined;
        const len = file.read(&buf) catch continue;
        if (len > 0 and std.mem.startsWith(u8, buf[0..len], "0x8086")) {
            return .xess; // Intel vendor ID
        }
    }

    return .fsr31; // Default to FSR
}

pub const tinker = interface.Tinker{
    .id = "optiscaler",
    .name = "OptiScaler",
    .priority = interface.Priority.SETUP,
    .isEnabledFn = isEnabled,
    .preparePrefixFn = preparePrefix,
    .modifyEnvFn = modifyEnv,
    .modifyArgsFn = modifyArgs,
    .cleanupFn = null,
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "default config" {
    const config = OptiScalerConfig{};
    try std.testing.expect(!config.enabled);
    try std.testing.expectEqual(UpscalerBackend.auto, config.backend);
    try std.testing.expect(config.frame_generation);
}

test "fsr quality scale factors" {
    const Quality = OptiScalerConfig.FsrQuality;
    try std.testing.expectEqual(@as(f32, 3.0), Quality.ultra_performance.toScaleFactor());
    try std.testing.expectEqual(@as(f32, 2.0), Quality.performance.toScaleFactor());
    try std.testing.expectEqual(@as(f32, 1.5), Quality.quality.toScaleFactor());
}

test "config generation" {
    const allocator = std.testing.allocator;

    const config = OptiScalerConfig{
        .backend = .fsr31,
        .frame_generation = true,
        .fsr_quality = .balanced,
        .sharpening = 0.6,
    };

    const result = try generateConfig(allocator, config, "Test Game");
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "Backend=fsr31") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Quality=balanced") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[FrameGeneration]") != null);
}

