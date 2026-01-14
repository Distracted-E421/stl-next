const std = @import("std");
const fs = std.fs;
const json = std.json;
const tinkers = @import("../tinkers/mod.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIG: Game Configuration Management
// ═══════════════════════════════════════════════════════════════════════════════
//
// STL-Next uses JSON configuration files for per-game settings.
// Location: $XDG_CONFIG_HOME/stl-next/games/<AppID>.json
//
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete game configuration
pub const GameConfig = struct {
    app_id: u32,
    
    // Launch settings
    use_native: bool = false,  // Force native launch (no Proton)
    proton_version: ?[]const u8 = null,  // Specific Proton version
    launch_options: ?[]const u8 = null,  // Extra command line args
    
    // Tinker settings
    mangohud: tinkers.mangohud.MangoHudConfig = .{},
    gamescope: tinkers.gamescope.GamescopeConfig = .{},
    gamemode: tinkers.gamemode.GameModeConfig = .{},
    
    pub fn defaults(app_id: u32) GameConfig {
        return .{ .app_id = app_id };
    }
    
    /// Apply tinker configs to their respective modules
    pub fn applyTinkerConfigs(self: *const GameConfig) void {
        tinkers.mangohud.setConfig(self.mangohud);
        tinkers.gamescope.setConfig(self.gamescope);
        tinkers.gamemode.setConfig(self.gamemode);
    }
};

/// Get the config directory path
pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    // Check STL_CONFIG_DIR first
    if (std.posix.getenv("STL_CONFIG_DIR")) |dir| {
        return allocator.dupe(u8, dir);
    }
    
    // Fall back to XDG_CONFIG_HOME/stl-next
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| {
        return std.fmt.allocPrint(allocator, "{s}/stl-next", .{xdg});
    }
    
    // Fall back to ~/.config/stl-next
    if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.config/stl-next", .{home});
    }
    
    return error.NoConfigDir;
}

/// Load game configuration from disk
pub fn loadGameConfig(allocator: std.mem.Allocator, app_id: u32) !GameConfig {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);
    
    const config_path = try std.fmt.allocPrint(
        allocator,
        "{s}/games/{d}.json",
        .{ config_dir, app_id },
    );
    defer allocator.free(config_path);
    
    // Try to open the config file
    const file = fs.openFileAbsolute(config_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
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
    
    // Parse JSON
    var config = GameConfig.defaults(app_id);
    
    // Simple JSON parsing for key fields
    if (std.mem.indexOf(u8, content, "\"use_native\":true")) |_| {
        config.use_native = true;
    }
    
    // MangoHud
    if (std.mem.indexOf(u8, content, "\"mangohud\"")) |_| {
        if (std.mem.indexOf(u8, content, "\"enabled\":true")) |_| {
            config.mangohud.enabled = true;
        }
    }
    
    // Gamescope
    if (std.mem.indexOf(u8, content, "\"gamescope\"")) |_| {
        if (std.mem.indexOf(u8, content, "\"enabled\":true")) |_| {
            config.gamescope.enabled = true;
        }
    }
    
    // GameMode
    if (std.mem.indexOf(u8, content, "\"gamemode\"")) |_| {
        if (std.mem.indexOf(u8, content, "\"enabled\":true")) |_| {
            config.gamemode.enabled = true;
        }
    }
    
    return config;
}

/// Save game configuration to disk
pub fn saveGameConfig(allocator: std.mem.Allocator, config: *const GameConfig) !void {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);
    
    const games_dir = try std.fmt.allocPrint(allocator, "{s}/games", .{config_dir});
    defer allocator.free(games_dir);
    
    // Ensure directory exists
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
    
    // Write JSON
    var writer = file.writer();
    try writer.writeAll("{\n");
    try writer.print("  \"app_id\": {d},\n", .{config.app_id});
    try writer.print("  \"use_native\": {s},\n", .{if (config.use_native) "true" else "false"});
    
    // MangoHud
    try writer.writeAll("  \"mangohud\": {\n");
    try writer.print("    \"enabled\": {s}\n", .{if (config.mangohud.enabled) "true" else "false"});
    try writer.writeAll("  },\n");
    
    // Gamescope
    try writer.writeAll("  \"gamescope\": {\n");
    try writer.print("    \"enabled\": {s}\n", .{if (config.gamescope.enabled) "true" else "false"});
    try writer.writeAll("  },\n");
    
    // GameMode
    try writer.writeAll("  \"gamemode\": {\n");
    try writer.print("    \"enabled\": {s}\n", .{if (config.gamemode.enabled) "true" else "false"});
    try writer.writeAll("  }\n");
    
    try writer.writeAll("}\n");
    
    std.log.info("Config: Saved to {s}", .{config_path});
}

/// Create a default config file for a game
pub fn createDefaultConfig(allocator: std.mem.Allocator, app_id: u32) !void {
    const config = GameConfig.defaults(app_id);
    try saveGameConfig(allocator, &config);
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
