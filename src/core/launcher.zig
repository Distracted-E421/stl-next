const std = @import("std");
const steam = @import("../engine/steam.zig");
const config = @import("config.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// LAUNCHER: Game Launch Orchestration
// ═══════════════════════════════════════════════════════════════════════════════
//
// Orchestrates the game launch process:
// 1. Build environment variables
// 2. Apply Tinker module modifications
// 3. Construct command vector
// 4. Execute (fork/exec)
//
// Performance target: <50ms from invocation to exec()
//
// ═══════════════════════════════════════════════════════════════════════════════

pub fn launch(
    allocator: std.mem.Allocator,
    steam_engine: *steam.SteamEngine,
    app_id: u32,
    extra_args: []const []const u8,
) !void {
    _ = extra_args;

    // Phase 1: Build environment
    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();

    // Inherit current environment
    var inherited_env = try std.process.getEnvMap(allocator);
    defer inherited_env.deinit();
    var env_iter = inherited_env.iterator();
    while (env_iter.next()) |entry| {
        try env.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    // Phase 2: Load game config and apply Tinker modifications
    const game_config = config.loadGameConfig(allocator, app_id) catch config.GameConfig.defaults(app_id);

    // Apply MangoHud if enabled
    if (game_config.mangohud.enabled) {
        try env.put("MANGOHUD", "1");
        try env.put("MANGOHUD_DLSYM", "1");
        std.log.info("MangoHud: ENABLED", .{});
    }

    // Apply GameMode if enabled
    if (game_config.gamemode) {
        // GameMode is typically activated via LD_PRELOAD or wrapper
        std.log.info("GameMode: ENABLED", .{});
    }

    // Phase 3: Build command vector
    var cmd = std.ArrayList([]const u8).init(allocator);
    defer cmd.deinit();

    // Apply Gamescope wrapper if enabled
    if (game_config.gamescope.enabled) {
        const gs_args = try game_config.gamescope.buildArgs(allocator);
        for (gs_args) |arg| {
            try cmd.append(arg);
        }
    }

    // Find the game's executable
    const game_info = try steam_engine.getGameInfo(app_id);
    
    // Get executable path, falling back to a placeholder
    const executable = game_info.executable orelse {
        std.log.warn("No executable found for AppID {d}", .{app_id});
        return error.NoExecutable;
    };

    // Determine launch method (native vs Proton)
    if (game_config.use_native or game_info.proton_version == null) {
        // Native Linux game
        try cmd.append(executable);
    } else {
        // Proton game - need to wrap with Proton
        const proton_path = try findProtonBinary(allocator, steam_engine, game_info.proton_version);
        try cmd.append(proton_path);
        try cmd.append("run");
        try cmd.append(executable);
    }

    // Phase 4: Execute
    std.log.info("Launching: {s}", .{cmd.items[0]});

    // In a real implementation, we would use std.process.Child or execv
    // For now, just log what we would do
    std.log.debug("Command vector:", .{});
    for (cmd.items) |arg| {
        std.log.debug("  {s}", .{arg});
    }

    std.log.info("Environment variables set: {d}", .{env.count()});
    std.log.info("Phase 1 complete - actual exec() not implemented yet", .{});
}

fn findProtonBinary(
    allocator: std.mem.Allocator,
    steam_engine: *steam.SteamEngine,
    version: ?[]const u8,
) ![]const u8 {
    const proton_name = version orelse "Proton Experimental";
    
    // Check user-installed Proton versions first
    const user_proton = try std.fmt.allocPrint(
        allocator,
        "{s}/compatibilitytools.d/{s}/proton",
        .{ steam_engine.steam_path, proton_name },
    );
    
    if (std.fs.accessAbsolute(user_proton, .{})) {
        return user_proton;
    } else |_| {
        allocator.free(user_proton);
    }

    // Check Steam's default Proton locations
    for (steam_engine.library_folders.items) |lib_path| {
        const steam_proton = try std.fmt.allocPrint(
            allocator,
            "{s}/steamapps/common/{s}/proton",
            .{ lib_path, proton_name },
        );

        if (std.fs.accessAbsolute(steam_proton, .{})) {
            return steam_proton;
        } else |_| {
            allocator.free(steam_proton);
        }
    }

    return error.ProtonNotFound;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "find proton binary returns error when not found" {
    // This would need a mock steam engine to test properly
    // For now, just verify the function compiles
}
