const std = @import("std");
const interface = @import("interface.zig");
const Context = interface.Context;
const EnvMap = interface.EnvMap;
const ArgList = interface.ArgList;

// ═══════════════════════════════════════════════════════════════════════════════
// BOXTRON/ROBERTA TINKER (Phase 6)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Boxtron: Steam Play compatibility tool for DOS games (DOSBox)
// Roberta: Steam Play compatibility tool for ScummVM games
//
// These are Proton alternatives specifically for classic games that run better
// under DOSBox or ScummVM than under Wine/Proton.
//
// Installation:
//   - Boxtron: https://github.com/dreamer/boxtron
//   - Roberta: https://github.com/dreamer/roberta
//
// ═══════════════════════════════════════════════════════════════════════════════

/// Boxtron/Roberta configuration
pub const BoxtronConfig = struct {
    /// Use Boxtron for DOS games
    boxtron_enabled: bool = false,
    /// Use Roberta for ScummVM games
    roberta_enabled: bool = false,
    /// Custom DOSBox config file
    dosbox_config: ?[]const u8 = null,
    /// Custom ScummVM config file
    scummvm_config: ?[]const u8 = null,
    /// DOSBox cycles (CPU speed)
    cycles: ?u32 = null,
    /// DOSBox fullscreen mode
    fullscreen: bool = true,
    /// DOSBox aspect correction
    aspect_correction: bool = true,
    /// DOSBox scaler
    scaler: Scaler = .normal2x,
    /// DOSBox renderer
    renderer: Renderer = .opengl,

    pub const Scaler = enum {
        none,
        normal2x,
        normal3x,
        advmame2x,
        advmame3x,
        hq2x,
        hq3x,
        tv2x,
        tv3x,
        scan2x,
        scan3x,

        pub fn toString(self: Scaler) []const u8 {
            return switch (self) {
                .none => "none",
                .normal2x => "normal2x",
                .normal3x => "normal3x",
                .advmame2x => "advmame2x",
                .advmame3x => "advmame3x",
                .hq2x => "hq2x",
                .hq3x => "hq3x",
                .tv2x => "tv2x",
                .tv3x => "tv3x",
                .scan2x => "scan2x",
                .scan3x => "scan3x",
            };
        }
    };

    pub const Renderer = enum {
        surface,
        texture,
        opengl,
        openglnb,

        pub fn toString(self: Renderer) []const u8 {
            return switch (self) {
                .surface => "surface",
                .texture => "texture",
                .opengl => "opengl",
                .openglnb => "openglnb",
            };
        }
    };
};

/// Paths to Boxtron/Roberta installations
const BOXTRON_PATHS = [_][]const u8{
    "/usr/share/steam/compatibilitytools.d/boxtron",
    "~/.local/share/Steam/compatibilitytools.d/boxtron",
    "~/.steam/steam/compatibilitytools.d/boxtron",
};

const ROBERTA_PATHS = [_][]const u8{
    "/usr/share/steam/compatibilitytools.d/roberta",
    "~/.local/share/Steam/compatibilitytools.d/roberta",
    "~/.steam/steam/compatibilitytools.d/roberta",
};

fn isEnabled(ctx: *const Context) bool {
    // Check if boxtron or roberta is enabled in game config
    // For now, check if there's a boxtron/roberta field in game config
    // This requires extending GameConfig with BoxtronConfig
    _ = ctx;
    return false; // Will be enabled via config
}

fn modifyEnv(ctx: *const Context, env: *EnvMap) anyerror!void {
    // Boxtron/Roberta use Steam Play's compatibility layer
    // They modify STEAM_COMPAT_TOOL_PATH to point to themselves

    // Find Boxtron/Roberta installation
    const home = std.posix.getenv("HOME") orelse return;

    // For Boxtron (DOS games)
    for (BOXTRON_PATHS) |path_template| {
        var path_buf: [512]u8 = undefined;
        const path = if (path_template[0] == '~')
            std.fmt.bufPrint(&path_buf, "{s}{s}", .{ home, path_template[1..] }) catch continue
        else
            path_template;

        if (std.fs.accessAbsolute(path, .{})) |_| {
            std.log.info("Boxtron: Found at {s}", .{path});
            try env.put("STEAM_COMPAT_TOOL_PATH", path);
            break;
        } else |_| {}
    }

    // Set DOSBox-specific environment
    if (ctx.game_config.*.use_native) {
        // Native mode - let DOSBox handle everything
        try env.put("SDL_VIDEODRIVER", "x11");
    }
}

fn modifyArgs(ctx: *const Context, args: *ArgList) anyerror!void {
    // Boxtron/Roberta handle argument modification themselves
    // We just need to ensure the compatibility tool is set
    _ = ctx;
    _ = args;
}

/// Generate a DOSBox configuration file
pub fn generateDosboxConfig(allocator: std.mem.Allocator, config: BoxtronConfig) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const w = result.writer();

    try w.writeAll("[sdl]\n");
    try w.print("fullscreen={s}\n", .{if (config.fullscreen) "true" else "false"});
    try w.print("output={s}\n", .{config.renderer.toString()});

    try w.writeAll("\n[render]\n");
    try w.print("aspect={s}\n", .{if (config.aspect_correction) "true" else "false"});
    try w.print("scaler={s}\n", .{config.scaler.toString()});

    if (config.cycles) |cycles| {
        try w.writeAll("\n[cpu]\n");
        try w.print("cycles={d}\n", .{cycles});
    }

    return result.toOwnedSlice();
}

/// Check if a game is a DOS game (heuristic)
pub fn isDosGame(install_dir: []const u8) bool {
    // Check for common DOS game indicators
    const dos_indicators = [_][]const u8{
        "dosbox.conf",
        "DOSBOX.CONF",
        "game.exe", // Many DOS games
        "GAME.EXE",
        ".bat",
        ".BAT",
    };

    var dir = std.fs.openDirAbsolute(install_dir, .{ .iterate = true }) catch return false;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        for (dos_indicators) |indicator| {
            if (std.mem.indexOf(u8, entry.name, indicator) != null) {
                return true;
            }
        }
    }

    return false;
}

/// Check if a game is a ScummVM game (heuristic)
pub fn isScummvmGame(install_dir: []const u8) bool {
    // Check for common ScummVM game indicators
    const scummvm_indicators = [_][]const u8{
        ".sou", // Sound file
        ".lfl", // LucasArts
        ".001", // Data files
        "monkey.000", // Monkey Island
        "tentacle.001", // Day of the Tentacle
    };

    var dir = std.fs.openDirAbsolute(install_dir, .{ .iterate = true }) catch return false;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        const lower_name = entry.name;
        for (scummvm_indicators) |indicator| {
            if (std.mem.endsWith(u8, lower_name, indicator)) {
                return true;
            }
        }
    }

    return false;
}

pub const tinker = interface.Tinker{
    .id = "boxtron",
    .name = "Boxtron/Roberta",
    .priority = interface.Priority.WRAPPER_EARLY,
    .isEnabledFn = isEnabled,
    .preparePrefixFn = null,
    .modifyEnvFn = modifyEnv,
    .modifyArgsFn = modifyArgs,
    .cleanupFn = null,
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "dosbox config generation" {
    const allocator = std.testing.allocator;

    const config = BoxtronConfig{
        .fullscreen = true,
        .cycles = 20000,
        .scaler = .hq2x,
        .renderer = .opengl,
    };

    const result = try generateDosboxConfig(allocator, config);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "fullscreen=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "cycles=20000") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "scaler=hq2x") != null);
}

test "scaler names" {
    try std.testing.expectEqualStrings("hq2x", BoxtronConfig.Scaler.hq2x.toString());
    try std.testing.expectEqualStrings("normal3x", BoxtronConfig.Scaler.normal3x.toString());
}

