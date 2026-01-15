const std = @import("std");
const fs = std.fs;
const json = std.json;

// Import tinker configs
const winetricks = @import("../tinkers/winetricks.zig");
const customcmd = @import("../tinkers/customcmd.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIG: Game Configuration Management (Phase 4.5 - Extended)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Uses proper std.json parsing instead of string searching.
// Configs are passed through Context, not global state.
//
// Phase 4.5 additions:
//   - Winetricks configuration
//   - Custom commands (pre/post launch)
//   - SteamGridDB settings
//
// ═══════════════════════════════════════════════════════════════════════════════

/// MangoHud configuration
pub const MangoHudConfig = struct {
    enabled: bool = false,
    show_fps: bool = true,
    show_frametime: bool = true,
    show_cpu: bool = true,
    show_gpu: bool = true,
    show_vram: bool = false,
    show_ram: bool = false,
    show_cpu_temp: bool = false,
    show_gpu_temp: bool = true,
    position: []const u8 = "top-left",
    font_size: u8 = 24,
};

/// Gamescope configuration
pub const GamescopeConfig = struct {
    enabled: bool = false,
    width: u16 = 0,
    height: u16 = 0,
    internal_width: u16 = 0,
    internal_height: u16 = 0,
    fullscreen: bool = true,
    borderless: bool = false,
    fsr: bool = false,
    fsr_sharpness: u8 = 5,
    fps_limit: u16 = 0,
};

/// GameMode configuration
pub const GameModeConfig = struct {
    enabled: bool = false,
    renice: i8 = 0,
};

/// Winetricks configuration (re-exported from tinker)
pub const WinetricksConfig = winetricks.WinetricksConfig;

/// Custom commands configuration (re-exported from tinker)
pub const CustomCommandsConfig = customcmd.CustomCommandsConfig;

/// SteamGridDB configuration
pub const SteamGridDBConfig = struct {
    /// Enable automatic artwork fetching
    enabled: bool = false,
    /// Prefer animated images
    prefer_animated: bool = false,
    /// Preferred grid style
    grid_style: []const u8 = "alternate",
    /// Preferred hero style
    hero_style: []const u8 = "blurred",
    /// Download on first launch
    auto_download: bool = true,
    /// SteamGridDB game ID (for non-Steam games)
    game_id: ?u32 = null,
};

/// Complete game configuration
pub const GameConfig = struct {
    app_id: u32,
    use_native: bool = false,
    proton_version: ?[]const u8 = null,
    launch_options: ?[]const u8 = null,
    
    // Tinker configurations
    mangohud: MangoHudConfig = .{},
    gamescope: GamescopeConfig = .{},
    gamemode: GameModeConfig = .{},
    winetricks: WinetricksConfig = .{},
    custom_commands: CustomCommandsConfig = .{},
    
    // Artwork configuration
    steamgriddb: SteamGridDBConfig = .{},

    pub fn defaults(app_id: u32) GameConfig {
        return .{ .app_id = app_id };
    }
};

/// Get the config directory path
pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("STL_CONFIG_DIR")) |dir| {
        return allocator.dupe(u8, dir);
    }
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| {
        return std.fmt.allocPrint(allocator, "{s}/stl-next", .{xdg});
    }
    if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.config/stl-next", .{home});
    }
    return error.NoConfigDir;
}

/// Load game configuration from disk using proper JSON parsing
pub fn loadGameConfig(allocator: std.mem.Allocator, app_id: u32) !GameConfig {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const config_path = try std.fmt.allocPrint(
        allocator,
        "{s}/games/{d}.json",
        .{ config_dir, app_id },
    );
    defer allocator.free(config_path);

    const file = fs.openFileAbsolute(config_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.log.debug("Config: No config for AppID {d}, using defaults", .{app_id});
            return GameConfig.defaults(app_id);
        }
        return err;
    };
    defer file.close();

    const stat = try file.stat();
    if (stat.size > 1024 * 1024) {
        return error.ConfigFileTooLarge;
    }

    const content = try allocator.alloc(u8, stat.size);
    defer allocator.free(content);
    _ = try file.readAll(content);

    // Parse JSON properly
    var config = GameConfig.defaults(app_id);
    
    var parsed = json.parseFromSlice(json.Value, allocator, content, .{}) catch |err| {
        std.log.warn("Config: Failed to parse JSON for AppID {d}: {}", .{ app_id, err });
        return config;
    };
    defer parsed.deinit();
    
    const root = parsed.value;
    if (root != .object) {
        std.log.warn("Config: Root is not an object for AppID {d}", .{app_id});
        return config;
    }

    const obj = root.object;

    // Parse top-level fields
    if (obj.get("use_native")) |v| {
        if (v == .bool) config.use_native = v.bool;
    }
    if (obj.get("proton_version")) |v| {
        if (v == .string) config.proton_version = try allocator.dupe(u8, v.string);
    }
    if (obj.get("launch_options")) |v| {
        if (v == .string) config.launch_options = try allocator.dupe(u8, v.string);
    }

    // Parse MangoHud config
    if (obj.get("mangohud")) |mh| {
        if (mh == .object) {
            const mh_obj = mh.object;
            if (mh_obj.get("enabled")) |v| {
                if (v == .bool) config.mangohud.enabled = v.bool;
            }
            if (mh_obj.get("show_fps")) |v| {
                if (v == .bool) config.mangohud.show_fps = v.bool;
            }
            if (mh_obj.get("show_frametime")) |v| {
                if (v == .bool) config.mangohud.show_frametime = v.bool;
            }
            if (mh_obj.get("show_cpu")) |v| {
                if (v == .bool) config.mangohud.show_cpu = v.bool;
            }
            if (mh_obj.get("show_gpu")) |v| {
                if (v == .bool) config.mangohud.show_gpu = v.bool;
            }
            if (mh_obj.get("position")) |v| {
                if (v == .string) config.mangohud.position = try allocator.dupe(u8, v.string);
            }
            if (mh_obj.get("font_size")) |v| {
                if (v == .integer) config.mangohud.font_size = @intCast(v.integer);
            }
        }
    }

    // Parse Gamescope config
    if (obj.get("gamescope")) |gs| {
        if (gs == .object) {
            const gs_obj = gs.object;
            if (gs_obj.get("enabled")) |v| {
                if (v == .bool) config.gamescope.enabled = v.bool;
            }
            if (gs_obj.get("width")) |v| {
                if (v == .integer) config.gamescope.width = @intCast(v.integer);
            }
            if (gs_obj.get("height")) |v| {
                if (v == .integer) config.gamescope.height = @intCast(v.integer);
            }
            if (gs_obj.get("fullscreen")) |v| {
                if (v == .bool) config.gamescope.fullscreen = v.bool;
            }
            if (gs_obj.get("fsr")) |v| {
                if (v == .bool) config.gamescope.fsr = v.bool;
            }
            if (gs_obj.get("fps_limit")) |v| {
                if (v == .integer) config.gamescope.fps_limit = @intCast(v.integer);
            }
        }
    }

    // Parse GameMode config
    if (obj.get("gamemode")) |gm| {
        if (gm == .object) {
            const gm_obj = gm.object;
            if (gm_obj.get("enabled")) |v| {
                if (v == .bool) config.gamemode.enabled = v.bool;
            }
            if (gm_obj.get("renice")) |v| {
                if (v == .integer) config.gamemode.renice = @intCast(v.integer);
            }
        }
    }

    std.log.info("Config: Loaded for AppID {d}", .{app_id});
    return config;
}

/// Save game configuration to disk
pub fn saveGameConfig(allocator: std.mem.Allocator, config: *const GameConfig) !void {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const games_dir = try std.fmt.allocPrint(allocator, "{s}/games", .{config_dir});
    defer allocator.free(games_dir);

    // Ensure directories exist
    fs.makeDirAbsolute(config_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    fs.makeDirAbsolute(games_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const config_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{d}.json",
        .{ games_dir, config.app_id },
    );
    defer allocator.free(config_path);

    const file = try fs.createFileAbsolute(config_path, .{});
    defer file.close();

    var writer = file.writer();
    try writer.writeAll("{\n");
    try writer.print("  \"app_id\": {d},\n", .{config.app_id});
    try writer.print("  \"use_native\": {s},\n", .{if (config.use_native) "true" else "false"});

    // MangoHud
    try writer.writeAll("  \"mangohud\": {\n");
    try writer.print("    \"enabled\": {s},\n", .{if (config.mangohud.enabled) "true" else "false"});
    try writer.print("    \"show_fps\": {s},\n", .{if (config.mangohud.show_fps) "true" else "false"});
    try writer.print("    \"position\": \"{s}\",\n", .{config.mangohud.position});
    try writer.print("    \"font_size\": {d}\n", .{config.mangohud.font_size});
    try writer.writeAll("  },\n");

    // Gamescope
    try writer.writeAll("  \"gamescope\": {\n");
    try writer.print("    \"enabled\": {s},\n", .{if (config.gamescope.enabled) "true" else "false"});
    try writer.print("    \"width\": {d},\n", .{config.gamescope.width});
    try writer.print("    \"height\": {d},\n", .{config.gamescope.height});
    try writer.print("    \"fullscreen\": {s},\n", .{if (config.gamescope.fullscreen) "true" else "false"});
    try writer.print("    \"fsr\": {s},\n", .{if (config.gamescope.fsr) "true" else "false"});
    try writer.print("    \"fps_limit\": {d}\n", .{config.gamescope.fps_limit});
    try writer.writeAll("  },\n");

    // GameMode
    try writer.writeAll("  \"gamemode\": {\n");
    try writer.print("    \"enabled\": {s},\n", .{if (config.gamemode.enabled) "true" else "false"});
    try writer.print("    \"renice\": {d}\n", .{config.gamemode.renice});
    try writer.writeAll("  }\n");

    try writer.writeAll("}\n");

    std.log.info("Config: Saved to {s}", .{config_path});
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "default config" {
    const config = GameConfig.defaults(413150);
    try std.testing.expectEqual(@as(u32, 413150), config.app_id);
    try std.testing.expect(!config.use_native);
    try std.testing.expect(!config.mangohud.enabled);
}

test "json parsing" {
    const test_json =
        \\{
        \\  "app_id": 413150,
        \\  "use_native": false,
        \\  "mangohud": {
        \\    "enabled": true,
        \\    "show_fps": true
        \\  }
        \\}
    ;

    var parsed = try json.parseFromSlice(json.Value, std.testing.allocator, test_json, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .object);
    const obj = parsed.value.object;
    try std.testing.expectEqual(@as(i64, 413150), obj.get("app_id").?.integer);
}
