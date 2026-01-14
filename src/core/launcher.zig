const std = @import("std");
const steam = @import("../engine/steam.zig");
const config = @import("config.zig");
const tinkers = @import("../tinkers/mod.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// LAUNCHER: Game Launch Orchestration
// ═══════════════════════════════════════════════════════════════════════════════
//
// Orchestrates the game launch process:
// 1. Load game configuration
// 2. Initialize tinker registry
// 3. Build launch context
// 4. Execute tinker pipeline (prepare → env → args)
// 5. Launch the game
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
    var timer = try std.time.Timer.start();
    
    // Phase 1: Load game configuration
    const game_config = config.loadGameConfig(allocator, app_id) catch config.GameConfig.defaults(app_id);
    
    // Apply tinker configs to their respective modules
    game_config.applyTinkerConfigs();
    
    // Phase 2: Build launch context
    const game_info = try steam_engine.getGameInfo(app_id);
    const config_dir = try config.getConfigDir(allocator);
    defer allocator.free(config_dir);
    
    const prefix_path = try std.fmt.allocPrint(
        allocator,
        "{s}/steamapps/compatdata/{d}/pfx",
        .{ steam_engine.steam_path, app_id },
    );
    defer allocator.free(prefix_path);
    
    const scratch_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/stl-next/{d}",
        .{app_id},
    );
    defer allocator.free(scratch_dir);
    
    // Ensure scratch dir exists
    std.fs.makeDirAbsolute("/tmp/stl-next") catch {};
    std.fs.makeDirAbsolute(scratch_dir) catch {};
    
    const ctx = tinkers.Context{
        .allocator = allocator,
        .app_id = app_id,
        .game_name = game_info.name,
        .install_dir = game_info.install_dir,
        .proton_path = game_info.proton_version,
        .prefix_path = prefix_path,
        .config_dir = config_dir,
        .scratch_dir = scratch_dir,
    };
    
    // Phase 3: Initialize tinker registry and run pipeline
    var registry = try tinkers.initBuiltinRegistry(allocator);
    defer registry.deinit();
    
    // Build environment
    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();
    
    // Inherit current environment
    var inherited_env = try std.process.getEnvMap(allocator);
    defer inherited_env.deinit();
    var env_iter = inherited_env.iterator();
    while (env_iter.next()) |entry| {
        try env.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    
    // Build argument list
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();
    
    // Get executable path
    const executable = game_info.executable orelse {
        std.log.warn("No executable found for AppID {d}", .{app_id});
        return error.NoExecutable;
    };
    
    // Determine launch method
    if (game_config.use_native or game_info.proton_version == null) {
        // Native Linux game
        try args.append(executable);
    } else {
        // Proton game
        const proton_path = try findProtonBinary(allocator, steam_engine, game_info.proton_version);
        try args.append(proton_path);
        try args.append("run");
        try args.append(executable);
    }
    
    // Add extra args
    for (extra_args) |arg| {
        try args.append(arg);
    }
    
    // Phase 4: Run tinker pipeline
    try registry.runAll(&ctx, &env, &args);
    
    // Phase 5: Report and execute
    const setup_time = timer.read();
    std.log.info("Launch setup completed in {d:.2}ms", .{
        @as(f64, @floatFromInt(setup_time)) / std.time.ns_per_ms,
    });
    
    std.log.info("╔══════════════════════════════════════════╗", .{});
    std.log.info("║ Launch Command                           ║", .{});
    std.log.info("╠══════════════════════════════════════════╣", .{});
    for (args.items, 0..) |arg, i| {
        if (i == 0) {
            std.log.info("║ {s: <40} ║", .{arg[0..@min(40, arg.len)]});
        } else {
            std.log.debug("║   {s: <38} ║", .{arg[0..@min(38, arg.len)]});
        }
    }
    std.log.info("╚══════════════════════════════════════════╝", .{});
    
    std.log.info("Environment variables set: {d}", .{env.count()});
    
    // In a real implementation, we would use std.process.execve
    // For now, just report what we would do
    std.log.info("Phase 3 complete - actual exec() not yet implemented", .{});
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
}
