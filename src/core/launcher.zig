const std = @import("std");
const steam = @import("../engine/steam.zig");
const config = @import("config.zig");
const tinkers = @import("../tinkers/mod.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// LAUNCHER (Phase 3.5 - Hardened)
// ═══════════════════════════════════════════════════════════════════════════════

pub const LaunchResult = struct {
    success: bool,
    command: []const []const u8,
    env_count: usize,
    setup_time_ms: f64,
    error_msg: ?[]const u8 = null,
};

pub fn launch(
    allocator: std.mem.Allocator,
    steam_engine: *steam.SteamEngine,
    app_id: u32,
    extra_args: []const []const u8,
    dry_run: bool,
) !LaunchResult {
    var timer = try std.time.Timer.start();

    // Phase 1: Load game configuration
    const game_config = config.loadGameConfig(allocator, app_id) catch config.GameConfig.defaults(app_id);

    // Phase 2: Get game info from Steam
    const game_info = try steam_engine.getGameInfo(app_id);

    // Phase 3: Build paths
    const config_dir = try config.getConfigDir(allocator);
    defer allocator.free(config_dir);

    const prefix_path = try std.fmt.allocPrint(
        allocator,
        "{s}/steamapps/compatdata/{d}/pfx",
        .{ steam_engine.steam_path, app_id },
    );
    defer allocator.free(prefix_path);

    const scratch_dir = try std.fmt.allocPrint(allocator, "/tmp/stl-next/{d}", .{app_id});
    defer allocator.free(scratch_dir);

    std.fs.makeDirAbsolute("/tmp/stl-next") catch {};
    std.fs.makeDirAbsolute(scratch_dir) catch {};

    // Phase 4: Build context
    const ctx = tinkers.Context{
        .allocator = allocator,
        .app_id = app_id,
        .game_name = game_info.name,
        .install_dir = game_info.install_dir,
        .proton_path = game_info.proton_version,
        .prefix_path = prefix_path,
        .config_dir = config_dir,
        .scratch_dir = scratch_dir,
        .game_config = &game_config,
    };

    // Phase 5: Initialize environment
    var env = std.process.EnvMap.init(allocator);
    defer env.deinit();

    var inherited_env = try std.process.getEnvMap(allocator);
    defer inherited_env.deinit();
    var env_iter = inherited_env.iterator();
    while (env_iter.next()) |entry| {
        try env.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    const app_id_str = try std.fmt.allocPrint(allocator, "{d}", .{app_id});
    try env.put("SteamAppId", app_id_str);
    try env.put("SteamGameId", app_id_str);
    try env.put("STEAM_COMPAT_DATA_PATH", prefix_path);

    // Phase 6: Build argument list
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    if (game_config.use_native or game_info.proton_version == null) {
        const executable = game_info.executable orelse {
            return LaunchResult{
                .success = false,
                .command = &.{},
                .env_count = 0,
                .setup_time_ms = 0,
                .error_msg = "No executable found",
            };
        };
        try args.append(executable);
    } else {
        const proton_path = findProtonBinary(allocator, steam_engine, game_info.proton_version) catch |err| {
            return LaunchResult{
                .success = false,
                .command = &.{},
                .env_count = 0,
                .setup_time_ms = 0,
                .error_msg = try std.fmt.allocPrint(allocator, "Proton not found: {}", .{err}),
            };
        };
        try args.append(proton_path);
        try args.append("run");
        if (game_info.executable) |exe| {
            try args.append(exe);
        }
    }

    for (extra_args) |arg| {
        try args.append(arg);
    }

    if (game_config.launch_options) |opts| {
        var iter = std.mem.splitScalar(u8, opts, ' ');
        while (iter.next()) |opt| {
            if (opt.len > 0) try args.append(opt);
        }
    }

    // Phase 7: Run tinker pipeline
    var registry = try tinkers.initBuiltinRegistry(allocator);
    defer registry.deinit();
    try registry.runAll(&ctx, &env, &args);

    const setup_time = timer.read();
    const setup_time_ms = @as(f64, @floatFromInt(setup_time)) / std.time.ns_per_ms;

    // Phase 8: Report
    std.log.info("╔════════════════════════════════════════════════════════════════╗", .{});
    std.log.info("║ STL-Next Launch                                                ║", .{});
    std.log.info("╠════════════════════════════════════════════════════════════════╣", .{});
    std.log.info("║ Game: {s: <58} ║", .{game_info.name[0..@min(58, game_info.name.len)]});
    std.log.info("║ AppID: {d: <57} ║", .{app_id});
    std.log.info("║ Setup: {d:.2}ms                                                   ║", .{setup_time_ms});
    std.log.info("╠════════════════════════════════════════════════════════════════╣", .{});
    std.log.info("║ Command:                                                       ║", .{});
    for (args.items) |arg| {
        const display = if (arg.len > 60) arg[0..60] else arg;
        std.log.info("║   {s: <62} ║", .{display});
    }
    std.log.info("╠════════════════════════════════════════════════════════════════╣", .{});
    std.log.info("║ Environment: {d} variables                                       ║", .{env.count()});
    std.log.info("╚════════════════════════════════════════════════════════════════╝", .{});

    if (dry_run) {
        std.log.info("Dry run - not executing", .{});
        return LaunchResult{
            .success = true,
            .command = try allocator.dupe([]const u8, args.items),
            .env_count = env.count(),
            .setup_time_ms = setup_time_ms,
        };
    }

    // Phase 9: Execute using std.process.Child
    std.log.info("Launching game...", .{});
    
    // Convert to null-terminated slices for Child
    var argv_ptrs = try allocator.alloc([]const u8, args.items.len);
    defer allocator.free(argv_ptrs);
    for (args.items, 0..) |arg, i| {
        argv_ptrs[i] = arg;
    }
    
    var child = std.process.Child.init(argv_ptrs, allocator);
    
    // Set environment
    child.env_map = &env;
    
    // Don't wait, just spawn
    _ = try child.spawn();
    
    std.log.info("Game launched with PID {d}", .{child.id});

    return LaunchResult{
        .success = true,
        .command = try allocator.dupe([]const u8, args.items),
        .env_count = env.count(),
        .setup_time_ms = setup_time_ms,
    };
}

fn findProtonBinary(
    allocator: std.mem.Allocator,
    steam_engine: *steam.SteamEngine,
    version: ?[]const u8,
) ![]const u8 {
    const proton_name = version orelse "Proton Experimental";

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

pub fn dryRun(
    allocator: std.mem.Allocator,
    steam_engine: *steam.SteamEngine,
    app_id: u32,
    extra_args: []const []const u8,
) !LaunchResult {
    return launch(allocator, steam_engine, app_id, extra_args, true);
}
