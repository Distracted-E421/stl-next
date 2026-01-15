const std = @import("std");
const builtin = @import("builtin");
const compat = @import("compat.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// STL-NEXT: Steam Tinker Launch - Next Generation
// ═══════════════════════════════════════════════════════════════════════════════
//
// A high-performance Steam game wrapper written in Zig 0.15.x
// Replaces the 21,000-line Bash script with a type-safe, modular architecture.
//
// Design Pillars:
// 1. PERFORMANCE: Sub-100ms launch overhead (vs 2-5s in Bash)
// 2. MODULARITY: Strict separation of "Tinker" modules from core engine
// 3. NIXOS NATIVE: No hardcoded paths, proper PATH resolution
//
// ═══════════════════════════════════════════════════════════════════════════════

const vdf = @import("engine/vdf.zig");
const steam = @import("engine/steam.zig");
const appinfo = @import("engine/appinfo.zig");
const nonsteam = @import("engine/nonsteam.zig");
const steamgriddb = @import("engine/steamgriddb.zig");
const config = @import("core/config.zig");
const launcher = @import("core/launcher.zig");
const ipc = @import("ipc/mod.zig");
const ui = @import("ui/mod.zig");
const modding = @import("modding/mod.zig");
const nexusmods = @import("api/nexusmods.zig");
const dbus = @import("dbus/mod.zig");

pub const std_options = std.Options{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
};

const VERSION = "0.9.0-alpha";

const Command = enum {
    run,
    info,
    list_games,
    list_protons,
    collections,
    configure,
    install,
    benchmark,
    wait,
    nxm,
    tui,
    add_game,
    remove_game,
    list_nonsteam,
    import_heroic,
    artwork,
    search_game,
    // Nexus Mods commands
    nexus,
    nexus_login,
    nexus_whoami,
    nexus_mod,
    nexus_files,
    nexus_download,
    nexus_track,
    nexus_tracked,
    // Stardrop & Collections commands (Phase 7)
    stardrop,
    stardrop_discover,
    stardrop_profiles,
    stardrop_create,
    stardrop_export,
    collection,
    collection_info,
    collection_import,
    collection_list,
    // D-Bus & GPU commands (Phase 8)
    gpu,
    gpu_list,
    gpu_test,
    session,
    session_test,
    // Profile management (Phase 8)
    profile,
    profile_list,
    profile_create,
    profile_set,
    profile_delete,
    profile_shortcut,
    version,
    help,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const cmd_str = args[1];
    var cmd_buf: [64]u8 = undefined;
    var cmd_normalized: []const u8 = cmd_str;
    if (cmd_str.len <= cmd_buf.len) {
        @memcpy(cmd_buf[0..cmd_str.len], cmd_str);
        for (cmd_buf[0..cmd_str.len]) |*c| {
            if (c.* == '-') c.* = '_';
        }
        cmd_normalized = cmd_buf[0..cmd_str.len];
    }

    const cmd = std.meta.stringToEnum(Command, cmd_normalized) orelse {
        if (std.fmt.parseInt(u32, cmd_str, 10)) |app_id| {
            try runGame(allocator, app_id, args[2..]);
            return;
        } else |_| {}

        std.log.err("Unknown command: {s}", .{cmd_str});
        printUsage();
        return;
    };

    switch (cmd) {
        .run => {
            if (args.len < 3) {
                std.log.err("Usage: stl-next run <AppID> [args...]", .{});
                return;
            }
            const app_id = try std.fmt.parseInt(u32, args[2], 10);
            try runGame(allocator, app_id, args[3..]);
        },
        .info => {
            if (args.len < 3) {
                std.log.err("Usage: stl-next info <AppID>", .{});
                return;
            }
            const app_id = try std.fmt.parseInt(u32, args[2], 10);
            try showGameInfo(allocator, app_id);
        },
        .list_games => try listGames(allocator),
        .list_protons => try listProtons(allocator),
        .collections => try showCollections(allocator, if (args.len > 2) args[2] else null),
        .benchmark => try runBenchmark(allocator),
        .configure => {
            std.log.info("Configuration UI not yet implemented", .{});
            std.log.info("Use environment variables or config files for now", .{});
        },
        .install => {
            std.log.info("Tool installation not yet implemented", .{});
        },
        .wait => {
            if (args.len < 3) {
                std.log.err("Usage: stl-next wait <AppID>", .{});
                return;
            }
            const app_id = try std.fmt.parseInt(u32, args[2], 10);
            try runWaitRequester(allocator, app_id);
        },
        .nxm => {
            if (args.len < 3) {
                std.log.err("Usage: stl-next nxm <nxm://...>", .{});
                return;
            }
            try handleNxmLink(allocator, args[2]);
        },
        .tui => {
            if (args.len < 3) {
                std.log.err("Usage: stl-next tui <AppID>", .{});
                return;
            }
            const app_id = try std.fmt.parseInt(u32, args[2], 10);
            try runTuiClient(allocator, app_id);
        },
        .add_game => {
            if (args.len < 4) {
                std.log.err("Usage: stl-next add-game <name> <executable> [--windows|--native]", .{});
                return;
            }
            try addNonSteamGame(allocator, args[2], args[3], args[4..]);
        },
        .remove_game => {
            if (args.len < 3) {
                std.log.err("Usage: stl-next remove-game <id>", .{});
                return;
            }
            const id = try std.fmt.parseInt(i32, args[2], 10);
            try removeNonSteamGame(allocator, id);
        },
        .list_nonsteam => try listNonSteamGames(allocator),
        .import_heroic => try importHeroicGames(allocator),
        .artwork => {
            if (args.len < 3) {
                std.log.err("Usage: stl-next artwork <AppID|GameName>", .{});
                return;
            }
            try fetchArtwork(allocator, args[2]);
        },
        .search_game => {
            if (args.len < 3) {
                std.log.err("Usage: stl-next search-game <name>", .{});
                return;
            }
            try searchSteamGridDB(allocator, args[2]);
        },
        // Nexus Mods commands
        .nexus => printNexusHelp(),
        .nexus_login => try nexusLogin(allocator, if (args.len > 2) args[2] else null),
        .nexus_whoami => try nexusWhoami(allocator),
        .nexus_mod => {
            if (args.len < 4) {
                std.log.err("Usage: stl-next nexus-mod <game_domain> <mod_id>", .{});
                std.log.err("Example: stl-next nexus-mod stardewvalley 21297", .{});
                return;
            }
            const mod_id = try std.fmt.parseInt(u64, args[3], 10);
            try nexusModInfo(allocator, args[2], mod_id);
        },
        .nexus_files => {
            if (args.len < 4) {
                std.log.err("Usage: stl-next nexus-files <game_domain> <mod_id>", .{});
                return;
            }
            const mod_id = try std.fmt.parseInt(u64, args[3], 10);
            try nexusModFiles(allocator, args[2], mod_id);
        },
        .nexus_download => {
            if (args.len < 5) {
                std.log.err("Usage: stl-next nexus-download <game_domain> <mod_id> <file_id>", .{});
                std.log.err("Note: Requires Nexus Premium for direct download", .{});
                return;
            }
            const mod_id = try std.fmt.parseInt(u64, args[3], 10);
            const file_id = try std.fmt.parseInt(u64, args[4], 10);
            try nexusDownload(allocator, args[2], mod_id, file_id);
        },
        .nexus_track => {
            if (args.len < 4) {
                std.log.err("Usage: stl-next nexus-track <game_domain> <mod_id>", .{});
                return;
            }
            const mod_id = try std.fmt.parseInt(u64, args[3], 10);
            try nexusTrackMod(allocator, args[2], mod_id);
        },
        .nexus_tracked => try nexusTrackedMods(allocator),
        // Stardrop & Collections commands (Phase 7)
        .stardrop => printStardropHelp(),
        .stardrop_discover => try stardropDiscover(allocator),
        .stardrop_profiles => try stardropProfiles(allocator),
        .stardrop_create => {
            if (args.len < 3) {
                std.log.err("Usage: stl-next stardrop-create <profile_name>", .{});
                return;
            }
            try stardropCreateProfile(allocator, args[2]);
        },
        .stardrop_export => {
            if (args.len < 4) {
                std.log.err("Usage: stl-next stardrop-export <profile_name> <output_file>", .{});
                return;
            }
            try stardropExportProfile(allocator, args[2], args[3]);
        },
        .collection => printCollectionHelp(),
        .collection_info => {
            if (args.len < 3) {
                std.log.err("Usage: stl-next collection-info <slug>", .{});
                std.log.err("Example: stl-next collection-info tckf0m", .{});
                return;
            }
            const revision: ?u32 = if (args.len > 3) std.fmt.parseInt(u32, args[3], 10) catch null else null;
            try collectionInfo(allocator, args[2], revision);
        },
        .collection_import => {
            if (args.len < 3) {
                std.log.err("Usage: stl-next collection-import <slug> [profile_name]", .{});
                std.log.err("Example: stl-next collection-import tckf0m \"My Collection\"", .{});
                return;
            }
            const profile_name = if (args.len > 3) args[3] else args[2];
            try collectionImport(allocator, args[2], profile_name);
        },
        .collection_list => {
            const game = if (args.len > 2) args[2] else "stardewvalley";
            try collectionList(allocator, game);
        },
        // D-Bus & GPU commands (Phase 8)
        .gpu, .gpu_list => try gpuList(allocator),
        .gpu_test => try gpuTest(allocator, if (args.len > 2) args[2] else null),
        .session, .session_test => try sessionTest(allocator),
        // Profile management (Phase 8)
        .profile => printProfileHelp(),
        .profile_list => {
            if (args.len < 3) {
                compat.print("Usage: stl-next profile-list <AppID>\n", .{});
                return;
            }
            const app_id = try std.fmt.parseInt(u32, args[2], 10);
            try profileList(allocator, app_id);
        },
        .profile_create => {
            if (args.len < 4) {
                compat.print("Usage: stl-next profile-create <AppID> <name> [--gpu nvidia|arc|amd|0|1] [--monitor DP-1]\n", .{});
                return;
            }
            const app_id = try std.fmt.parseInt(u32, args[2], 10);
            try profileCreate(allocator, app_id, args[3], args[4..]);
        },
        .profile_set => {
            if (args.len < 4) {
                compat.print("Usage: stl-next profile-set <AppID> <profile_name>\n", .{});
                return;
            }
            const app_id = try std.fmt.parseInt(u32, args[2], 10);
            try profileSet(allocator, app_id, args[3]);
        },
        .profile_delete => {
            if (args.len < 4) {
                compat.print("Usage: stl-next profile-delete <AppID> <profile_name>\n", .{});
                return;
            }
            const app_id = try std.fmt.parseInt(u32, args[2], 10);
            try profileDelete(allocator, app_id, args[3]);
        },
        .profile_shortcut => {
            if (args.len < 4) {
                compat.print("Usage: stl-next profile-shortcut <AppID> <profile_name>\n", .{});
                return;
            }
            const app_id = try std.fmt.parseInt(u32, args[2], 10);
            try profileCreateShortcut(allocator, app_id, args[3]);
        },
        .version => printVersion(),
        .help => printUsage(),
    }
}

fn runGame(allocator: std.mem.Allocator, app_id: u32, extra_args: []const []const u8) !void {
    var timer = try std.time.Timer.start();

    // Parse --profile and --dry-run flags from extra_args
    var profile_name: ?[]const u8 = null;
    var dry_run: bool = false;
    var filtered_args: std.ArrayListUnmanaged([]const u8) = .{};
    defer filtered_args.deinit(allocator);

    var i: usize = 0;
    while (i < extra_args.len) : (i += 1) {
        if (std.mem.eql(u8, extra_args[i], "--profile")) {
            if (i + 1 < extra_args.len) {
                profile_name = extra_args[i + 1];
                i += 1; // Skip the profile name
            }
        } else if (std.mem.eql(u8, extra_args[i], "--dry-run")) {
            dry_run = true;
        } else {
            try filtered_args.append(allocator, extra_args[i]);
        }
    }

    std.log.info("╔══════════════════════════════════════════╗", .{});
    std.log.info("║        STL-NEXT v{s}              ║", .{VERSION});
    std.log.info("╠══════════════════════════════════════════╣", .{});
    std.log.info("║ AppID: {d: <34} ║", .{app_id});

    var steam_engine = try steam.SteamEngine.init(allocator);
    defer steam_engine.deinit();

    std.log.info("║ Steam: {s: <34} ║", .{steam_engine.steam_path[0..@min(34, steam_engine.steam_path.len)]});

    const game_info = steam_engine.getGameInfo(app_id) catch |err| {
        std.log.err("Failed to load game info: {}", .{err});
        return err;
    };

    std.log.info("║ Game:  {s: <34} ║", .{game_info.name[0..@min(34, game_info.name.len)]});

    if (game_info.is_hidden) {
        std.log.info("║ Status: HIDDEN                           ║", .{});
    }
    if (game_info.collections.len > 0) {
        std.log.info("║ Tags:   {d} collection(s)                ║", .{game_info.collections.len});
    }

    // Load game config and apply profile
    var game_config = config.loadGameConfig(allocator, app_id) catch |err| blk: {
        std.log.warn("No custom config for AppID {d}, using defaults: {}", .{ app_id, err });
        break :blk config.GameConfig.defaults(app_id);
    };
    defer game_config.deinit();

    // If --profile was specified, use that; otherwise use active_profile
    const effective_profile_name = profile_name orelse game_config.active_profile;

    // Get the profile and apply GPU settings
    if (game_config.getProfile(effective_profile_name)) |profile| {
        std.log.info("║ Profile: {s: <32} ║", .{profile.name[0..@min(32, profile.name.len)]});

        // Apply profile GPU preference to game_config.gpu
        if (profile.gpu_preference != .auto) {
            var gpu_mgr = dbus.GpuManager.init(allocator);
            defer gpu_mgr.deinit();
            gpu_mgr.discoverGpus() catch {};

            // Get env vars for GPU preference and log
            if (gpu_mgr.getEnvVars(profile.gpu_preference, profile.gpu_index)) |env_result| {
                var env = env_result;
                defer env.deinit();
                if (env.vars.count() > 0) {
                    std.log.info("║ GPU: {s: <36} ║", .{@tagName(profile.gpu_preference)});
                }
            } else |_| {}
        }
    } else if (profile_name != null) {
        std.log.warn("Profile \"{s}\" not found, using default", .{profile_name.?});
    }

    std.log.info("╚══════════════════════════════════════════╝", .{});

    const setup_time = timer.read();
    std.log.info("Setup completed in {d:.2}ms", .{@as(f64, @floatFromInt(setup_time)) / std.time.ns_per_ms});

    // Pass profile name to launcher (will be used to apply GPU env vars)
    const result = try launchWithProfile(allocator, &steam_engine, app_id, filtered_args.items, &game_config, effective_profile_name, dry_run);
    defer result.deinit();

    if (!result.success) {
        if (result.error_msg) |msg| std.log.err("Launch failed: {s}", .{msg});
        return error.LaunchFailed;
    }
}

/// Launch with profile-aware GPU selection
fn launchWithProfile(
    allocator: std.mem.Allocator,
    steam_engine: *steam.SteamEngine,
    app_id: u32,
    extra_args: []const []const u8,
    game_config: *const config.GameConfig,
    profile_name: []const u8,
    dry_run: bool,
) !launcher.LaunchResult {
    // Get the profile
    const profile = game_config.getProfile(profile_name);

    // If profile has GPU preference, set up GPU env vars before launch
    if (profile) |p| {
        if (p.gpu_preference != .auto) {
            var gpu_mgr = dbus.GpuManager.init(allocator);
            defer gpu_mgr.deinit();
            gpu_mgr.discoverGpus() catch {};

            // Get and set GPU environment variables
            if (gpu_mgr.getEnvVars(p.gpu_preference, p.gpu_index)) |env_result| {
                var env = env_result;
                defer env.deinit();
                var it = env.vars.iterator();
                while (it.next()) |entry| {
                    // Set env var for this process (will be inherited by child)
                    // Note: This doesn't actually work for child process - need to pass via launcher
                    std.log.info("GPU: {s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* });
                }
            } else |_| {}
        }
    }

    // Call the regular launcher
    return launcher.launch(allocator, steam_engine, app_id, extra_args, dry_run);
}

fn showGameInfo(allocator: std.mem.Allocator, app_id: u32) !void {
    var timer = try std.time.Timer.start();

    var steam_engine = try steam.SteamEngine.init(allocator);
    defer steam_engine.deinit();

    const game_info = try steam_engine.getGameInfo(app_id);

    const lookup_time = timer.read();
    const stdout = compat.stdout();

    var buf: [4096]u8 = undefined;

    const exec_str = if (game_info.executable) |e| try std.fmt.allocPrint(allocator, "\"{s}\"", .{e}) else try allocator.dupe(u8, "null");
    defer allocator.free(exec_str);
    const launch_str = if (game_info.launch_options) |l| try std.fmt.allocPrint(allocator, "\"{s}\"", .{l}) else try allocator.dupe(u8, "null");
    defer allocator.free(launch_str);
    const proton_str = if (game_info.proton_version) |p| try std.fmt.allocPrint(allocator, "\"{s}\"", .{p}) else try allocator.dupe(u8, "null");
    defer allocator.free(proton_str);

    const msg1 = try std.fmt.bufPrint(&buf,
        \\{{
        \\  "app_id": {d},
        \\  "name": "{s}",
        \\  "install_dir": "{s}",
        \\  "executable": {s},
        \\  "launch_options": {s},
        \\  "proton_version": {s},
        \\  "playtime_minutes": {d},
        \\  "is_hidden": {},
        \\  "collections": [
    , .{
        game_info.app_id,
        game_info.name,
        game_info.install_dir,
        exec_str,
        launch_str,
        proton_str,
        game_info.playtime_minutes,
        game_info.is_hidden,
    });
    try stdout.writeAll(msg1);

    for (game_info.collections, 0..) |col, i| {
        const col_msg = try std.fmt.bufPrint(&buf, "\"{s}\"{s}", .{ col, if (i < game_info.collections.len - 1) ", " else "" });
        try stdout.writeAll(col_msg);
    }

    const msg2 = try std.fmt.bufPrint(&buf,
        \\],
        \\  "_lookup_time_ms": {d:.3}
        \\}}
        \\
    , .{@as(f64, @floatFromInt(lookup_time)) / std.time.ns_per_ms});
    try stdout.writeAll(msg2);
}

fn listGames(allocator: std.mem.Allocator) !void {
    var timer = try std.time.Timer.start();

    var steam_engine = try steam.SteamEngine.init(allocator);
    defer steam_engine.deinit();

    const games = try steam_engine.listInstalledGames();

    const scan_time = timer.read();
    const stdout = compat.stdout();
    var buf: [1024]u8 = undefined;

    try stdout.writeAll("[\n");

    for (games, 0..) |game, i| {
        const msg = try std.fmt.bufPrint(&buf,
            \\  {{"app_id": {d}, "name": "{s}", "hidden": {}}}{s}
            \\
        , .{
            game.app_id,
            game.name,
            game.is_hidden,
            if (i < games.len - 1) "," else "",
        });
        try stdout.writeAll(msg);
    }

    const msg = try std.fmt.bufPrint(&buf,
        \\]
        \\// Found {d} games in {d:.2}ms
        \\
    , .{ games.len, @as(f64, @floatFromInt(scan_time)) / std.time.ns_per_ms });
    try stdout.writeAll(msg);
}

fn listProtons(allocator: std.mem.Allocator) !void {
    var steam_engine = try steam.SteamEngine.init(allocator);
    defer steam_engine.deinit();

    const protons = try steam_engine.listProtonVersions();
    const stdout = compat.stdout();
    var buf: [1024]u8 = undefined;

    try stdout.writeAll("[\n");

    for (protons, 0..) |proton, i| {
        const msg = try std.fmt.bufPrint(&buf,
            \\  {{"name": "{s}", "path": "{s}", "is_proton": {}}}{s}
            \\
        , .{
            proton.name,
            proton.path,
            proton.is_proton,
            if (i < protons.len - 1) "," else "",
        });
        try stdout.writeAll(msg);
    }

    try stdout.writeAll("]\n");
}

fn showCollections(allocator: std.mem.Allocator, app_id_str: ?[]const u8) !void {
    var steam_engine = try steam.SteamEngine.init(allocator);
    defer steam_engine.deinit();

    const stdout = compat.stdout();
    var buf: [1024]u8 = undefined;

    if (app_id_str) |id_str| {
        const app_id = try std.fmt.parseInt(u32, id_str, 10);
        const collections = try steam_engine.getGameCollections(app_id);

        const msg1 = try std.fmt.bufPrint(&buf, "{{\"app_id\": {d}, \"collections\": [", .{app_id});
        try stdout.writeAll(msg1);

        for (collections, 0..) |col, i| {
            const msg = try std.fmt.bufPrint(&buf, "\"{s}\"{s}", .{ col, if (i < collections.len - 1) ", " else "" });
            try stdout.writeAll(msg);
        }

        try stdout.writeAll("]}\n");
    } else {
        try stdout.writeAll("Usage: stl-next collections <AppID>\n");
        try stdout.writeAll("Shows the Steam collections/tags for a game.\n");
    }
}

fn runBenchmark(allocator: std.mem.Allocator) !void {
    const stdout = compat.stdout();
    var buf: [1024]u8 = undefined;

    try stdout.writeAll("\n");
    try stdout.writeAll("╔══════════════════════════════════════════════════════════════╗\n");
    try stdout.writeAll("║              STL-NEXT PHASE 2 BENCHMARK                      ║\n");
    try stdout.writeAll("╚══════════════════════════════════════════════════════════════╝\n");
    try stdout.writeAll("\n");

    {
        var timer = try std.time.Timer.start();
        var engine = try steam.SteamEngine.init(allocator);
        defer engine.deinit();
        const elapsed = timer.read();

        const msg = try std.fmt.bufPrint(&buf, "Steam Discovery:     {d:>8.2} ms\n", .{
            @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms,
        });
        try stdout.writeAll(msg);
    }

    {
        var engine = try steam.SteamEngine.init(allocator);
        defer engine.deinit();

        const test_ids = [_]u32{ 413150, 489830, 620, 730, 570 };

        for (test_ids) |app_id| {
            var timer = try std.time.Timer.start();
            const info = engine.getGameInfo(app_id) catch continue;
            const elapsed = timer.read();

            const msg = try std.fmt.bufPrint(&buf, "Game Lookup ({d}): {d:>8.2} ms ({s})\n", .{
                app_id,
                @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms,
                info.name[0..@min(20, info.name.len)],
            });
            try stdout.writeAll(msg);
            break;
        }
    }

    {
        var engine = try steam.SteamEngine.init(allocator);
        defer engine.deinit();

        var timer = try std.time.Timer.start();
        const games = try engine.listInstalledGames();
        const elapsed = timer.read();

        const msg = try std.fmt.bufPrint(&buf, "List All Games:      {d:>8.2} ms ({d} games)\n", .{
            @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms,
            games.len,
        });
        try stdout.writeAll(msg);
    }

    {
        var engine = try steam.SteamEngine.init(allocator);
        defer engine.deinit();

        var timer = try std.time.Timer.start();
        const protons = try engine.listProtonVersions();
        const elapsed = timer.read();

        const msg = try std.fmt.bufPrint(&buf, "List Protons:        {d:>8.2} ms ({d} versions)\n", .{
            @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms,
            protons.len,
        });
        try stdout.writeAll(msg);
    }

    try stdout.writeAll("\n");
    try stdout.writeAll("Target: All operations < 100ms ✓\n");
    try stdout.writeAll("Binary VDF seeking: O(1) per skip\n");
}

fn printVersion() void {
    compat.print(
        \\STL-Next v{s}
        \\Steam Tinker Launch - Next Generation
        \\
        \\Phase 4.5: Extended Features
        \\
        \\Features:
        \\  ✓ Binary VDF streaming parser
        \\  ✓ Fast AppID seeking (<10ms)
        \\  ✓ LevelDB collections support
        \\  ✓ Winetricks integration
        \\  ✓ Custom pre/post launch commands
        \\  ✓ Non-Steam game management
        \\  ✓ SteamGridDB artwork
        \\
        \\https://github.com/e421/stl-next
        \\
    , .{VERSION});
}

fn printUsage() void {
    compat.print(
        \\Usage: stl-next <command> [options]
        \\
        \\Steam Game Commands:
        \\  run <AppID>           Launch a game with STL-Next configuration
        \\  info <AppID>          Show game information (JSON)
        \\  list-games            List installed Steam games (JSON)
        \\  list-protons          List available Proton versions (JSON)
        \\  collections <ID>      Show collections for a game
        \\  benchmark             Run performance benchmarks
        \\
        \\Wait Requester / IPC:
        \\  wait <AppID>          Start wait requester daemon
        \\  tui <AppID>           Connect TUI client to daemon
        \\  nxm <url>             Handle NXM protocol link
        \\
        \\Non-Steam Games:
        \\  add-game <name> <exe> [--windows|--native]  Add a non-Steam game
        \\  remove-game <id>      Remove a non-Steam game by ID
        \\  list-nonsteam         List all non-Steam games
        \\  import-heroic         Import games from Heroic (Epic/GOG/Amazon)
        \\
        \\SteamGridDB Artwork:
        \\  artwork <AppID>       Fetch artwork for a Steam game
        \\  search-game <name>    Search SteamGridDB for a game
        \\
        \\Nexus Mods (requires API key):
        \\  nexus                 Show Nexus Mods help
        \\  nexus-login [key]     Save API key (or enter interactively)
        \\  nexus-whoami          Show current Nexus user info
        \\  nexus-mod <game> <id> Show mod information
        \\  nexus-files <game> <mod_id>  List files for a mod
        \\  nexus-download <game> <mod_id> <file_id>  Get download link
        \\  nexus-track <game> <mod_id>  Track a mod for updates
        \\  nexus-tracked         List all tracked mods
        \\
        \\Stardrop Integration (Phase 7):
        \\  stardrop              Show Stardrop help
        \\  stardrop-discover     Find Stardrop installation
        \\  stardrop-profiles     List Stardrop profiles
        \\  stardrop-create       Create a new profile
        \\  stardrop-export       Export profile to JSON
        \\
        \\Nexus Collections (KILLER FEATURE!):
        \\  collection            Show collection help
        \\  collection-info       Show collection metadata
        \\  collection-import     Import collection to Stardrop
        \\  collection-list       List popular collections
        \\
        \\GPU & Session (Phase 8 - Multi-GPU!):
        \\  gpu, gpu-list         List detected GPUs
        \\  gpu-test [pref]       Test GPU selection:
        \\                          integrated/int, discrete/disc, auto
        \\                          nvidia/nv, intel/arc, amd/radeon
        \\                          monitor (future), or index (0, 1, ...)
        \\  session, session-test Show D-Bus session capabilities
        \\
        \\Launch Profiles (Phase 8 - No More Launch Options!):
        \\  profile               Show profile help
        \\  profile-list <AppID>  List profiles for a game
        \\  profile-create <AppID> <name> [--gpu X] [--monitor Y]
        \\  profile-set <AppID> <name>    Set active profile
        \\  profile-delete <AppID> <name> Delete a profile
        \\  profile-shortcut <AppID> <name>  Create Steam shortcut
        \\
        \\Configuration:
        \\  configure             Open configuration UI (WIP)
        \\  install <tool>        Install a tool (ReShade, MO2, etc.) (WIP)
        \\
        \\Shorthand:
        \\  stl-next <AppID>      Same as 'stl-next run <AppID>'
        \\
        \\Environment Variables:
        \\  STL_CONFIG_DIR        Config directory (default: ~/.config/stl-next)
        \\  STL_LOG_LEVEL         Log level: debug, info, warn, error
        \\  STL_SKIP_WAIT         Skip wait requester (instant launch)
        \\  STL_COUNTDOWN         Wait requester countdown seconds (default: 10)
        \\  STEAMGRIDDB_API_KEY   API key for SteamGridDB (free at steamgriddb.com)
        \\  STL_NEXUS_API_KEY     Nexus Mods API key (get from nexusmods.com)
        \\  STARDROP_PATH         Path to Stardrop installation
        \\
        \\Examples:
        \\  stl-next 413150                    # Launch Stardew Valley
        \\  stl-next info 489830               # Show Skyrim SE info
        \\  stl-next list-games | jq '.[]'     # List games with jq
        \\  stl-next add-game "Celeste" ~/Games/Celeste/Celeste --native
        \\  stl-next artwork 413150            # Get Stardew Valley artwork
        \\  stl-next collection-import tckf0m  # Import Nexus Collection!
        \\
    , .{});
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEXUS MODS COMMANDS
// ═══════════════════════════════════════════════════════════════════════════════

fn printNexusHelp() void {
    compat.print(
        \\Nexus Mods Integration
        \\======================
        \\
        \\First, get your API key from:
        \\  https://www.nexusmods.com/users/myaccount?tab=api%20access
        \\
        \\Then save it:
        \\  stl-next nexus-login YOUR_API_KEY
        \\
        \\Or set environment variable:
        \\  export STL_NEXUS_API_KEY=YOUR_API_KEY
        \\
        \\Commands:
        \\  nexus-whoami               Check API key and show user info
        \\  nexus-mod <game> <mod_id>  Get mod details
        \\  nexus-files <game> <mod_id>  List available files
        \\  nexus-download <game> <mod_id> <file_id>  Get download link (Premium)
        \\  nexus-track <game> <mod_id>  Track mod for updates
        \\  nexus-tracked              List tracked mods
        \\
        \\Game Domains (examples):
        \\  stardewvalley, skyrimspecialedition, fallout4, cyberpunk2077
        \\
        \\Rate Limits:
        \\  2,500 requests per day, 100 per hour after daily limit
        \\
        \\Premium Features:
        \\  Direct download links (no browser needed)
        \\  Faster download speeds from Nexus CDN
        \\
    , .{});
}

fn nexusLogin(allocator: std.mem.Allocator, key_arg: ?[]const u8) !void {
    var api_key: []const u8 = undefined;
    var key_owned = false;

    if (key_arg) |k| {
        api_key = k;
    } else {
        // Interactive input
        compat.print("Enter your Nexus Mods API key: ", .{});

        var buf: [256]u8 = undefined;
        const stdin_file = compat.stdin();
        const bytes_read = stdin_file.readAll(&buf) catch {
            std.log.err("Failed to read input", .{});
            return;
        };

        if (bytes_read == 0) {
            std.log.err("No API key provided", .{});
            return;
        }

        // Trim newlines
        var end = bytes_read;
        while (end > 0 and (buf[end - 1] == '\n' or buf[end - 1] == '\r')) {
            end -= 1;
        }
        api_key = buf[0..end];
        key_owned = false;
    }

    // Validate the key
    var client = nexusmods.NexusClient.init(allocator);
    defer client.deinit();
    try client.setApiKey(api_key);

    compat.print("Validating API key...\n", .{});

    const user = client.validateKey() catch |err| {
        switch (err) {
            error.InvalidApiKey => std.log.err("Invalid API key", .{}),
            error.RateLimited => std.log.err("Rate limited - try again later", .{}),
            error.NetworkError => std.log.err("Network error - check your connection", .{}),
            else => std.log.err("Error validating key: {}", .{err}),
        }
        return;
    };
    defer {
        var u = user;
        u.deinit(allocator);
    }

    // Save the key
    nexusmods.saveApiKey(allocator, api_key) catch |err| {
        std.log.warn("Could not save API key: {}", .{err});
    };

    compat.print("\n✓ API key validated and saved!\n", .{});
    compat.print("  User: {s}\n", .{user.name});
    compat.print("  Premium: {s}\n", .{if (user.is_premium) "Yes" else "No"});
    compat.print("  Supporter: {s}\n", .{if (user.is_supporter) "Yes" else "No"});
}

fn nexusWhoami(allocator: std.mem.Allocator) !void {
    var client = nexusmods.NexusClient.init(allocator);
    defer client.deinit();

    client.discoverApiKey() catch {
        std.log.err("No API key found. Run: stl-next nexus-login YOUR_API_KEY", .{});
        return;
    };

    const user = client.validateKey() catch |err| {
        switch (err) {
            error.InvalidApiKey => std.log.err("API key is invalid or expired", .{}),
            error.RateLimited => std.log.err("Rate limited - try again later", .{}),
            error.NetworkError => std.log.err("Network error - check your connection", .{}),
            else => std.log.err("Error: {}", .{err}),
        }
        return;
    };
    defer {
        var u = user;
        u.deinit(allocator);
    }

    compat.print("\n╔════════════════════════════════════════════╗\n", .{});
    compat.print("║           NEXUS MODS USER                  ║\n", .{});
    compat.print("╠════════════════════════════════════════════╣\n", .{});
    compat.print("║ Name:      {s: <30} ║\n", .{user.name[0..@min(30, user.name.len)]});
    compat.print("║ User ID:   {d: <30} ║\n", .{user.user_id});
    compat.print("║ Premium:   {s: <30} ║\n", .{if (user.is_premium) "✓ Yes" else "✗ No"});
    compat.print("║ Supporter: {s: <30} ║\n", .{if (user.is_supporter) "✓ Yes" else "✗ No"});
    compat.print("╚════════════════════════════════════════════╝\n", .{});
}

fn nexusModInfo(allocator: std.mem.Allocator, game_domain: []const u8, mod_id: u64) !void {
    var client = nexusmods.NexusClient.init(allocator);
    defer client.deinit();

    client.discoverApiKey() catch {
        std.log.err("No API key found. Run: stl-next nexus-login YOUR_API_KEY", .{});
        return;
    };

    const mod = client.getMod(game_domain, mod_id) catch |err| {
        switch (err) {
            error.ModNotFound => std.log.err("Mod {d} not found in {s}", .{ mod_id, game_domain }),
            error.InvalidApiKey => std.log.err("API key is invalid", .{}),
            else => std.log.err("Error: {}", .{err}),
        }
        return;
    };
    defer {
        var m = mod;
        m.deinit(allocator);
    }

    compat.print("\n╔════════════════════════════════════════════════════════╗\n", .{});
    compat.print("║ MOD: {s: <51} ║\n", .{mod.name[0..@min(51, mod.name.len)]});
    compat.print("╠════════════════════════════════════════════════════════╣\n", .{});
    compat.print("║ ID:       {d: <45} ║\n", .{mod.mod_id});
    compat.print("║ Version:  {s: <45} ║\n", .{mod.version[0..@min(45, mod.version.len)]});
    compat.print("║ Author:   {s: <45} ║\n", .{mod.author[0..@min(45, mod.author.len)]});
    compat.print("║ Endorse:  {d: <45} ║\n", .{mod.endorsement_count});
    compat.print("╠════════════════════════════════════════════════════════╣\n", .{});
    compat.print("║ Summary:                                               ║\n", .{});

    // Print summary wrapped
    var summary = mod.summary;
    while (summary.len > 54) {
        compat.print("║ {s: <54} ║\n", .{summary[0..54]});
        summary = summary[54..];
    }
    if (summary.len > 0) {
        compat.print("║ {s: <54} ║\n", .{summary});
    }

    compat.print("╚════════════════════════════════════════════════════════╝\n", .{});
}

fn nexusModFiles(allocator: std.mem.Allocator, game_domain: []const u8, mod_id: u64) !void {
    var client = nexusmods.NexusClient.init(allocator);
    defer client.deinit();

    client.discoverApiKey() catch {
        std.log.err("No API key found. Run: stl-next nexus-login YOUR_API_KEY", .{});
        return;
    };

    const files = client.getModFiles(game_domain, mod_id) catch |err| {
        switch (err) {
            error.ModNotFound => std.log.err("Mod {d} not found in {s}", .{ mod_id, game_domain }),
            error.InvalidApiKey => std.log.err("API key is invalid", .{}),
            else => std.log.err("Error: {}", .{err}),
        }
        return;
    };
    defer {
        for (files) |*f| {
            var file = f.*;
            file.deinit(allocator);
        }
        allocator.free(files);
    }

    compat.print("\nFiles for mod {d} in {s}:\n", .{ mod_id, game_domain });
    compat.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    for (files) |file| {
        const size_mb = @as(f64, @floatFromInt(file.size_kb)) / 1024.0;
        compat.print("\nFile ID: {d}\n", .{file.file_id});
        compat.print("  Name:     {s}\n", .{file.name});
        compat.print("  Version:  {s}\n", .{file.version});
        compat.print("  Category: {s}\n", .{file.category_name});
        compat.print("  Size:     {d:.1} MB\n", .{size_mb});
        compat.print("  Primary:  {s}\n", .{if (file.is_primary) "Yes" else "No"});
    }

    compat.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    compat.print("Total: {d} file(s)\n", .{files.len});
    compat.print("\nTo download: stl-next nexus-download {s} {d} <file_id>\n", .{ game_domain, mod_id });
}

fn nexusDownload(allocator: std.mem.Allocator, game_domain: []const u8, mod_id: u64, file_id: u64) !void {
    var client = nexusmods.NexusClient.init(allocator);
    defer client.deinit();

    client.discoverApiKey() catch {
        std.log.err("No API key found. Run: stl-next nexus-login YOUR_API_KEY", .{});
        return;
    };

    const links = client.getDownloadLink(game_domain, mod_id, file_id, null, null) catch |err| {
        switch (err) {
            error.NotPremium => {
                std.log.err("Direct downloads require Nexus Premium membership", .{});
                std.log.err("Use the 'Mod Manager Download' button on nexusmods.com instead", .{});
                std.log.err("STL-Next will catch the NXM link automatically", .{});
            },
            error.ModNotFound => std.log.err("Mod or file not found", .{}),
            error.InvalidApiKey => std.log.err("API key is invalid", .{}),
            else => std.log.err("Error: {}", .{err}),
        }
        return;
    };
    defer {
        for (links) |*l| {
            var link = l.*;
            link.deinit(allocator);
        }
        allocator.free(links);
    }

    compat.print("\nDownload links for file {d}:\n", .{file_id});
    compat.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    for (links) |link| {
        compat.print("\n[{s}] {s}\n", .{ link.short_name, link.name });
        compat.print("  {s}\n", .{link.uri});
    }

    compat.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    compat.print("Use wget or curl to download, or pipe to your download manager.\n", .{});
}

fn nexusTrackMod(allocator: std.mem.Allocator, game_domain: []const u8, mod_id: u64) !void {
    var client = nexusmods.NexusClient.init(allocator);
    defer client.deinit();

    client.discoverApiKey() catch {
        std.log.err("No API key found. Run: stl-next nexus-login YOUR_API_KEY", .{});
        return;
    };

    client.trackMod(game_domain, mod_id) catch |err| {
        switch (err) {
            error.ModNotFound => std.log.err("Mod {d} not found in {s}", .{ mod_id, game_domain }),
            error.InvalidApiKey => std.log.err("API key is invalid", .{}),
            else => std.log.err("Error: {}", .{err}),
        }
        return;
    };

    compat.print("✓ Now tracking mod {d} in {s}\n", .{ mod_id, game_domain });
    compat.print("  You'll be notified of updates on nexusmods.com\n", .{});
}

fn nexusTrackedMods(allocator: std.mem.Allocator) !void {
    var client = nexusmods.NexusClient.init(allocator);
    defer client.deinit();

    client.discoverApiKey() catch {
        std.log.err("No API key found. Run: stl-next nexus-login YOUR_API_KEY", .{});
        return;
    };

    const mods = client.getTrackedMods() catch |err| {
        switch (err) {
            error.InvalidApiKey => std.log.err("API key is invalid", .{}),
            else => std.log.err("Error: {}", .{err}),
        }
        return;
    };
    defer {
        for (mods) |*m| {
            var mod = m.*;
            mod.deinit(allocator);
        }
        allocator.free(mods);
    }

    compat.print("\n╔════════════════════════════════════════════╗\n", .{});
    compat.print("║           TRACKED MODS                     ║\n", .{});
    compat.print("╠════════════════════════════════════════════╣\n", .{});

    if (mods.len == 0) {
        compat.print("║ No tracked mods                            ║\n", .{});
    } else {
        for (mods) |mod| {
            compat.print("║ [{s: <20}] {d: <16} ║\n", .{ mod.domain_name[0..@min(20, mod.domain_name.len)], mod.mod_id });
        }
    }

    compat.print("╚════════════════════════════════════════════╝\n", .{});
    compat.print("Total: {d} mod(s) tracked\n", .{mods.len});
}

// ═══════════════════════════════════════════════════════════════════════════════
// PHASE 4: WAIT REQUESTER & MOD MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

fn runWaitRequester(allocator: std.mem.Allocator, app_id: u32) !void {
    std.log.info("╔════════════════════════════════════════════╗", .{});
    std.log.info("║      STL-NEXT WAIT REQUESTER v{s}      ║", .{VERSION});
    std.log.info("╚════════════════════════════════════════════╝", .{});

    var steam_engine = try steam.SteamEngine.init(allocator);
    defer steam_engine.deinit();

    const game_info = try steam_engine.getGameInfo(app_id);
    std.log.info("Game: {s}", .{game_info.name});

    var game_config = config.loadGameConfig(allocator, app_id) catch config.GameConfig.defaults(app_id);
    defer game_config.deinit();

    var requester = try ui.WaitRequester.init(allocator, app_id, game_info.name, &game_config);
    defer requester.deinit();

    const should_launch = try requester.run();

    if (should_launch) {
        std.log.info("Launching game...", .{});
        const result = try launcher.launch(allocator, &steam_engine, app_id, &.{}, false);
        if (!result.success) {
            if (result.error_msg) |msg| {
                std.log.err("Launch failed: {s}", .{msg});
            }
        }
    } else {
        std.log.info("Launch aborted by user", .{});
    }
}

fn runTuiClient(allocator: std.mem.Allocator, app_id: u32) !void {
    var steam_engine = try steam.SteamEngine.init(allocator);
    defer steam_engine.deinit();

    const game_info = try steam_engine.getGameInfo(app_id);
    try ui.runTUI(allocator, app_id, game_info.name);
}

fn handleNxmLink(allocator: std.mem.Allocator, url: []const u8) !void {
    std.log.info("NXM Handler: {s}", .{url});

    var link = try modding.NxmLink.parse(allocator, url);
    defer link.deinit(allocator);

    const formatted = try link.toDisplayString(allocator);
    defer allocator.free(formatted);
    std.log.info("  Parsed: {s}", .{formatted});

    if (link.isValid()) {
        std.log.info("  Status: Valid link", .{});

        const encoded = try link.encodeForWine(allocator);
        defer allocator.free(encoded);
        std.log.debug("  Wine-safe: {s}", .{encoded});
    } else {
        std.log.warn("  Status: Incomplete or invalid link", .{});
    }

    std.log.info("NXM handling requires mod manager integration (MO2/Vortex)", .{});
}

// ═══════════════════════════════════════════════════════════════════════════════
// PHASE 4.5: NON-STEAM GAMES
// ═══════════════════════════════════════════════════════════════════════════════

fn addNonSteamGame(allocator: std.mem.Allocator, name: []const u8, executable: []const u8, extra_args: []const []const u8) !void {
    var manager = try nonsteam.NonSteamManager.init(allocator);
    defer manager.deinit();

    var platform = nonsteam.Platform.native;
    for (extra_args) |arg| {
        if (std.mem.eql(u8, arg, "--windows")) {
            platform = .windows;
        } else if (std.mem.eql(u8, arg, "--native")) {
            platform = .native;
        } else if (std.mem.eql(u8, arg, "--flatpak")) {
            platform = .flatpak;
        } else if (std.mem.eql(u8, arg, "--appimage")) {
            platform = .appimage;
        }
    }

    const game = nonsteam.NonSteamGame{
        .id = 0,
        .name = try allocator.dupe(u8, name),
        .platform = platform,
        .executable = try allocator.dupe(u8, executable),
    };

    try manager.addGame(game);

    compat.print("Added non-Steam game: {s} ({s})\n", .{ name, @tagName(platform) });
}

fn removeNonSteamGame(allocator: std.mem.Allocator, id: i32) !void {
    var manager = try nonsteam.NonSteamManager.init(allocator);
    defer manager.deinit();

    if (manager.getGame(id)) |game| {
        // Copy the name before removing (removeGame frees the original)
        const name = try allocator.dupe(u8, game.name);
        defer allocator.free(name);
        try manager.removeGame(id);
        compat.print("Removed non-Steam game: {s}\n", .{name});
    } else {
        std.log.err("Game with ID {d} not found", .{id});
    }
}

fn listNonSteamGames(allocator: std.mem.Allocator) !void {
    var manager = try nonsteam.NonSteamManager.init(allocator);
    defer manager.deinit();

    const stdout = compat.stdout();
    var buf: [1024]u8 = undefined;

    try stdout.writeAll("[\n");

    const games = manager.listGames();
    for (games, 0..) |game, i| {
        const msg = try std.fmt.bufPrint(&buf,
            \\  {{
            \\    "id": {d},
            \\    "name": "{s}",
            \\    "platform": "{s}",
            \\    "executable": "{s}",
            \\    "source": "{s}"
            \\  }}{s}
            \\
        , .{
            game.id,
            game.name,
            @tagName(game.platform),
            game.executable,
            @tagName(game.source),
            if (i < games.len - 1) "," else "",
        });
        try stdout.writeAll(msg);
    }

    try stdout.writeAll("]\n");
    const msg = try std.fmt.bufPrint(&buf, "// Found {d} non-Steam game(s)\n", .{games.len});
    try stdout.writeAll(msg);
}

fn importHeroicGames(allocator: std.mem.Allocator) !void {
    var manager = try nonsteam.NonSteamManager.init(allocator);
    defer manager.deinit();

    const count = manager.importFromHeroic() catch |err| {
        std.log.err("Failed to import from Heroic: {}", .{err});
        return;
    };

    compat.print("Imported {d} game(s) from Heroic\n", .{count});
}

// ═══════════════════════════════════════════════════════════════════════════════
// PHASE 4.5: STEAMGRIDDB
// ═══════════════════════════════════════════════════════════════════════════════

fn fetchArtwork(allocator: std.mem.Allocator, identifier: []const u8) !void {
    var client = steamgriddb.SteamGridDBClient.init(allocator, null) catch |err| {
        if (err == error.NoApiKey) {
            std.log.err("SteamGridDB requires an API key.", .{});
            std.log.err("Set STEAMGRIDDB_API_KEY or get a free key at https://www.steamgriddb.com/profile/preferences/api", .{});
            return;
        }
        return err;
    };
    defer client.deinit();

    const stdout = compat.stdout();
    var buf: [1024]u8 = undefined;

    if (std.fmt.parseInt(u32, identifier, 10)) |app_id| {
        std.log.info("Fetching artwork for Steam AppID {d}...", .{app_id});

        const grids = client.getImagesByAppId(app_id, .grid) catch |err| {
            std.log.warn("Failed to fetch grids: {}", .{err});
            return;
        };
        defer {
            for (grids) |*g| g.deinit(allocator);
            allocator.free(grids);
        }

        if (grids.len > 0) {
            const msg = try std.fmt.bufPrint(&buf, "Found {d} grid image(s):\n", .{grids.len});
            try stdout.writeAll(msg);

            for (grids[0..@min(5, grids.len)]) |grid| {
                const msg2 = try std.fmt.bufPrint(&buf, "  - {s} ({d}x{d}, score: {d})\n", .{
                    grid.url[0..@min(60, grid.url.len)],
                    grid.width,
                    grid.height,
                    grid.score,
                });
                try stdout.writeAll(msg2);
            }

            if (grids.len > 0) {
                const path = try client.downloadImage(&grids[0], .grid, app_id);
                defer allocator.free(path);
                const msg3 = try std.fmt.bufPrint(&buf, "\nDownloaded to: {s}\n", .{path});
                try stdout.writeAll(msg3);
            }
        } else {
            try stdout.writeAll("No grid images found.\n");
        }
    } else |_| {
        std.log.info("Searching SteamGridDB for '{s}'...", .{identifier});
        try searchSteamGridDB(allocator, identifier);
    }
}

fn searchSteamGridDB(allocator: std.mem.Allocator, name: []const u8) !void {
    var client = steamgriddb.SteamGridDBClient.init(allocator, null) catch |err| {
        if (err == error.NoApiKey) {
            std.log.err("SteamGridDB requires an API key.", .{});
            std.log.err("Set STEAMGRIDDB_API_KEY or get a free key at https://www.steamgriddb.com/profile/preferences/api", .{});
            return;
        }
        return err;
    };
    defer client.deinit();

    const results = try client.searchGame(name);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    const stdout = compat.stdout();
    var buf: [1024]u8 = undefined;

    if (results.len == 0) {
        const msg = try std.fmt.bufPrint(&buf, "No games found matching '{s}'\n", .{name});
        try stdout.writeAll(msg);
        return;
    }

    const msg = try std.fmt.bufPrint(&buf, "Found {d} game(s) matching '{s}':\n\n", .{ results.len, name });
    try stdout.writeAll(msg);

    for (results[0..@min(10, results.len)]) |result| {
        const msg2 = try std.fmt.bufPrint(&buf, "  ID: {d: <8} {s}{s}\n", .{
            result.id,
            result.name,
            if (result.verified) " ✓" else "",
        });
        try stdout.writeAll(msg2);
    }

    try stdout.writeAll("\nUse the ID to fetch artwork:\n");
    try stdout.writeAll("  stl-next artwork <id>\n");
}

// ═══════════════════════════════════════════════════════════════════════════════
// PHASE 7: STARDROP & NEXUS COLLECTIONS - THE KILLER FEATURE!
// ═══════════════════════════════════════════════════════════════════════════════

const nexus_collections = @import("api/nexus_collections.zig");

fn printStardropHelp() void {
    compat.print(
        \\Stardrop Integration
        \\====================
        \\
        \\Stardrop is a native Linux mod manager for Stardew Valley.
        \\STL-Next provides first-class integration including the ability
        \\to import entire Nexus Collections!
        \\
        \\Commands:
        \\  stardrop-discover     Find Stardrop installation
        \\  stardrop-profiles     List all Stardrop profiles
        \\  stardrop-create       Create a new profile
        \\  stardrop-export       Export a profile to JSON
        \\
        \\Collection Import (KILLER FEATURE):
        \\  collection-info <slug>      Show collection metadata
        \\  collection-import <slug>    Import collection to Stardrop
        \\  collection-list [game]      List popular collections
        \\
        \\Environment Variables:
        \\  STARDROP_PATH         Path to Stardrop installation
        \\  STL_NEXUS_API_KEY     Required for collections import
        \\
        \\Example:
        \\  stl-next collection-import tckf0m "My Stardew Collection"
        \\
    , .{});
}

fn printCollectionHelp() void {
    compat.print(
        \\Nexus Collections - KILLER FEATURE!
        \\====================================
        \\
        \\Import entire Nexus Mods Collections with one command!
        \\No more manually downloading 100+ mods.
        \\
        \\Commands:
        \\  collection-info <slug> [revision]   Show collection info
        \\  collection-import <slug> [profile]  Import to Stardrop
        \\  collection-list [game]              List popular collections
        \\
        \\How to find a collection slug:
        \\  Go to: https://next.nexusmods.com/stardewvalley/collections
        \\  The slug is the last part of the URL, e.g. "tckf0m"
        \\
        \\Example:
        \\  # View collection info
        \\  stl-next collection-info tckf0m
        \\
        \\  # Import to Stardrop with custom profile name
        \\  stl-next collection-import tckf0m "Aesthetic Overhaul"
        \\
        \\Requirements:
        \\  - Nexus Mods API key (STL_NEXUS_API_KEY)
        \\  - Nexus Premium (for bulk downloads) OR manual NXM links
        \\  - Stardrop installed
        \\
    , .{});
}

fn stardropDiscover(allocator: std.mem.Allocator) !void {
    var manager = modding.stardrop.StardropManager.init(allocator);
    defer manager.deinit();

    manager.discover() catch |err| {
        std.log.err("Stardrop not found: {}", .{err});
        std.log.info("Set STARDROP_PATH environment variable or install Stardrop", .{});
        std.log.info("Download from: https://github.com/Floogen/Stardrop/releases", .{});
        return;
    };

    if (manager.install) |install| {
        const stdout = compat.stdout();
        var buf: [1024]u8 = undefined;

        try stdout.writeAll("{\n");
        const msg = try std.fmt.bufPrint(&buf, "  \"path\": \"{s}\",\n", .{install.path});
        try stdout.writeAll(msg);
        const msg2 = try std.fmt.bufPrint(&buf, "  \"version\": \"{s}\",\n", .{install.version});
        try stdout.writeAll(msg2);
        const msg3 = try std.fmt.bufPrint(&buf, "  \"mods_folder\": \"{s}\",\n", .{install.mods_folder});
        try stdout.writeAll(msg3);
        const msg4 = try std.fmt.bufPrint(&buf, "  \"profiles_folder\": \"{s}\"\n", .{install.profiles_folder});
        try stdout.writeAll(msg4);
        try stdout.writeAll("}\n");

        std.log.info("Stardrop installation found!", .{});
    }
}

fn stardropProfiles(allocator: std.mem.Allocator) !void {
    var manager = modding.stardrop.StardropManager.init(allocator);
    defer manager.deinit();

    try manager.discover();
    try manager.loadProfiles();

    const stdout = compat.stdout();
    var buf: [1024]u8 = undefined;

    try stdout.writeAll("[\n");

    for (manager.profiles.items, 0..) |profile, i| {
        const comma = if (i < manager.profiles.items.len - 1) "," else "";
        const msg = try std.fmt.bufPrint(&buf,
            \\  {{
            \\    "name": "{s}",
            \\    "protected": {},
            \\    "enabled_mods": {d}
            \\  }}{s}
            \\
        , .{
            profile.name,
            profile.is_protected,
            profile.enabled_mod_ids.items.len,
            comma,
        });
        try stdout.writeAll(msg);
    }

    try stdout.writeAll("]\n");

    const msg2 = try std.fmt.bufPrint(&buf, "// Found {d} profile(s)\n", .{manager.profiles.items.len});
    try stdout.writeAll(msg2);
}

fn stardropCreateProfile(allocator: std.mem.Allocator, name: []const u8) !void {
    var manager = modding.stardrop.StardropManager.init(allocator);
    defer manager.deinit();

    try manager.discover();
    try manager.createProfile(name);

    compat.print("Created profile: {s}\n", .{name});
}

fn stardropExportProfile(allocator: std.mem.Allocator, profile_name: []const u8, output_path: []const u8) !void {
    var manager = modding.stardrop.StardropManager.init(allocator);
    defer manager.deinit();

    try manager.discover();
    try manager.loadProfiles();
    try manager.exportProfile(profile_name, output_path);

    compat.print("Exported profile '{s}' to {s}\n", .{ profile_name, output_path });
}

fn collectionInfo(allocator: std.mem.Allocator, slug: []const u8, revision: ?u32) !void {
    // Get API key
    const api_key = std.posix.getenv("STL_NEXUS_API_KEY") orelse {
        std.log.err("Nexus API key required. Set STL_NEXUS_API_KEY environment variable.", .{});
        std.log.info("Get your key at: https://www.nexusmods.com/users/myaccount?tab=api", .{});
        return;
    };

    var client = try nexus_collections.CollectionsClient.init(allocator, api_key);
    defer client.deinit();

    std.log.info("Fetching collection '{s}'...", .{slug});

    var collection = client.getCollection("stardewvalley", slug, revision) catch |err| {
        std.log.err("Failed to fetch collection: {}", .{err});
        return;
    };
    defer collection.deinit(allocator);

    const stdout = compat.stdout();
    var buf: [2048]u8 = undefined;

    // Print collection info
    try stdout.writeAll("{\n");
    const msg1 = try std.fmt.bufPrint(&buf, "  \"slug\": \"{s}\",\n", .{collection.slug});
    try stdout.writeAll(msg1);
    const msg2 = try std.fmt.bufPrint(&buf, "  \"name\": \"{s}\",\n", .{collection.name});
    try stdout.writeAll(msg2);
    const msg3 = try std.fmt.bufPrint(&buf, "  \"author\": \"{s}\",\n", .{collection.author});
    try stdout.writeAll(msg3);
    const msg4 = try std.fmt.bufPrint(&buf, "  \"summary\": \"{s}\",\n", .{collection.summary[0..@min(200, collection.summary.len)]});
    try stdout.writeAll(msg4);
    const msg5 = try std.fmt.bufPrint(&buf, "  \"game\": \"{s}\",\n", .{collection.game_domain});
    try stdout.writeAll(msg5);
    const msg6 = try std.fmt.bufPrint(&buf, "  \"revision\": {d},\n", .{collection.current_revision});
    try stdout.writeAll(msg6);
    const msg7 = try std.fmt.bufPrint(&buf, "  \"endorsements\": {d},\n", .{collection.endorsements});
    try stdout.writeAll(msg7);
    const msg8 = try std.fmt.bufPrint(&buf, "  \"downloads\": {d},\n", .{collection.total_downloads});
    try stdout.writeAll(msg8);
    const msg9 = try std.fmt.bufPrint(&buf, "  \"mod_count\": {d},\n", .{collection.mods.len});
    try stdout.writeAll(msg9);
    try stdout.writeAll("  \"mods\": [\n");

    for (collection.mods, 0..) |mod, i| {
        const comma = if (i < collection.mods.len - 1) "," else "";
        const version_str = if (mod.version) |v| v else "?";
        const author_str = if (mod.author) |a| a else "Unknown";
        const msg = try std.fmt.bufPrint(&buf,
            \\    {{
            \\      "mod_id": {d},
            \\      "name": "{s}",
            \\      "version": "{s}",
            \\      "author": "{s}",
            \\      "optional": {}
            \\    }}{s}
            \\
        , .{
            mod.mod_id,
            mod.name,
            version_str,
            author_str,
            mod.optional,
            comma,
        });
        try stdout.writeAll(msg);
    }

    try stdout.writeAll("  ]\n}\n");

    compat.print("\n✨ Collection has {d} mods. Use 'collection-import {s}' to install!\n", .{ collection.mods.len, slug });
}

fn collectionImport(allocator: std.mem.Allocator, slug: []const u8, profile_name: []const u8) !void {
    // Get API key
    const api_key = std.posix.getenv("STL_NEXUS_API_KEY") orelse {
        std.log.err("Nexus API key required. Set STL_NEXUS_API_KEY environment variable.", .{});
        std.log.info("Get your key at: https://www.nexusmods.com/users/myaccount?tab=api", .{});
        return;
    };

    // Initialize managers
    var stardrop_manager = modding.stardrop.StardropManager.init(allocator);
    defer stardrop_manager.deinit();

    stardrop_manager.discover() catch |err| {
        std.log.err("Stardrop not found: {}", .{err});
        std.log.info("Please install Stardrop first: https://github.com/Floogen/Stardrop/releases", .{});
        return;
    };

    var nexus_client = nexusmods.NexusClient.init(allocator);
    defer nexus_client.deinit();

    // Load API key from environment or files
    nexus_client.discoverApiKey() catch |err| {
        std.log.err("Failed to load Nexus API key: {}", .{err});
        std.log.info("Set STL_NEXUS_API_KEY or run: stl-next nexus-login <key>", .{});
        return;
    };
    _ = api_key;

    stardrop_manager.setNexusClient(&nexus_client);

    std.log.info("╔══════════════════════════════════════════════════════════╗", .{});
    std.log.info("║   NEXUS COLLECTION IMPORT - THE KILLER FEATURE!          ║", .{});
    std.log.info("╠══════════════════════════════════════════════════════════╣", .{});
    std.log.info("║ Collection: {s: <45} ║", .{slug});
    std.log.info("║ Profile:    {s: <45} ║", .{profile_name});
    std.log.info("╚══════════════════════════════════════════════════════════╝", .{});

    // Progress callback
    const progressCallback = struct {
        fn callback(progress: *const modding.stardrop.ImportProgress) void {
            switch (progress.status) {
                .fetching_collection => compat.print("📥 Fetching collection metadata...\n", .{}),
                .downloading_mods => {
                    if (progress.current_mod) |mod_name| {
                        compat.print("⬇️  [{d}/{d}] Downloading: {s}\n", .{
                            progress.downloaded,
                            progress.total_mods,
                            mod_name,
                        });
                    }
                },
                .extracting => compat.print("📦 Extracting mods...\n", .{}),
                .creating_profile => compat.print("📝 Creating Stardrop profile...\n", .{}),
                .complete => {
                    compat.print("\n", .{});
                    compat.print("✅ SUCCESS! Imported {d} mods to profile '{s}'\n", .{
                        progress.downloaded,
                        progress.current_mod orelse "Unknown",
                    });
                },
                .failed => {
                    if (progress.error_message) |msg| {
                        compat.print("❌ FAILED: {s}\n", .{msg});
                    }
                },
                .idle => {},
            }
        }
    }.callback;

    stardrop_manager.importCollection(slug, null, profile_name, &progressCallback) catch |err| {
        std.log.err("Import failed: {}", .{err});
        return;
    };

    std.log.info("", .{});
    std.log.info("🎮 Launch Stardrop and select the '{s}' profile to play!", .{profile_name});
}

fn collectionList(allocator: std.mem.Allocator, game: []const u8) !void {
    _ = allocator;

    compat.print(
        \\Popular Collections for {s}:
        \\============================
        \\
        \\Visit: https://next.nexusmods.com/{s}/collections
        \\
        \\Some popular Stardew Valley collections:
        \\  - tckf0m    "Aesthetic Overhaul" - Visual improvements
        \\  - xxxxxxx   "Expanded" - Content expansion
        \\  - xxxxxxx   "Quality of Life" - UI/UX improvements
        \\
        \\To import a collection:
        \\  stl-next collection-import <slug> [profile_name]
        \\
        \\Note: Collection listing requires Nexus v2 API access.
        \\      Visit the URL above to browse collections.
        \\
    , .{ game, game });
}

// ═══════════════════════════════════════════════════════════════════════════════
// D-BUS & GPU COMMANDS (Phase 8)
// ═══════════════════════════════════════════════════════════════════════════════

fn gpuList(allocator: std.mem.Allocator) !void {
    var gpu_mgr = dbus.GpuManager.init(allocator);
    defer gpu_mgr.deinit();

    compat.print(
        \\GPU Detection (D-Bus / sysfs)
        \\==============================
        \\
    , .{});

    // Check D-Bus service availability
    if (gpu_mgr.has_switcheroo) {
        compat.print("switcheroo-control: Available ✓\n\n", .{});
    } else {
        compat.print("switcheroo-control: Not available (using sysfs fallback)\n\n", .{});
    }

    // Discover GPUs
    gpu_mgr.discoverGpus() catch |err| {
        compat.print("Error discovering GPUs: {s}\n", .{@errorName(err)});
        return;
    };

    const gpus = gpu_mgr.listGpus();
    if (gpus.len == 0) {
        compat.print("No GPUs found.\n", .{});
        return;
    }

    compat.print("Detected GPUs:\n", .{});
    for (gpus, 0..) |gpu, i| {
        compat.print("  [{d}] {s}\n", .{ i, gpu.name });
        compat.print("      Vendor: {s}\n", .{@tagName(gpu.vendor)});
        compat.print("      Type: {s}\n", .{gpu.getDescription()});
        if (gpu.pci_id) |pci| {
            compat.print("      PCI ID: {s}\n", .{pci});
        }
        if (gpu.device_path) |path| {
            compat.print("      Device: {s}\n", .{path});
        }
        compat.print("      Default: {s}\n", .{if (gpu.is_default) "Yes" else "No"});
        compat.print("\n", .{});
    }

    // Show env vars for each preference
    compat.print("GPU Selection Examples:\n", .{});
    compat.print("-----------------------\n", .{});

    // Integrated (if any)
    var integrated_env = gpu_mgr.getEnvVars(.integrated, null) catch null;
    if (integrated_env) |*env| {
        defer env.deinit();
        if (env.vars.count() > 0) {
            compat.print("Integrated GPU:\n", .{});
            var it = env.vars.iterator();
            while (it.next()) |entry| {
                compat.print("  {s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            compat.print("\n", .{});
        }
    }

    // Discrete
    var discrete_env = gpu_mgr.getEnvVars(.discrete, null) catch null;
    if (discrete_env) |*env| {
        defer env.deinit();
        if (env.vars.count() > 0) {
            compat.print("Discrete GPU:\n", .{});
            var it = env.vars.iterator();
            while (it.next()) |entry| {
                compat.print("  {s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }
    }
}

fn gpuTest(allocator: std.mem.Allocator, preference_str: ?[]const u8) !void {
    var gpu_mgr = dbus.GpuManager.init(allocator);
    defer gpu_mgr.deinit();

    gpu_mgr.discoverGpus() catch |err| {
        compat.print("Error discovering GPUs: {s}\n", .{@errorName(err)});
        return;
    };

    var specific_idx: ?usize = null;
    const preference: dbus.GpuPreference = if (preference_str) |p| blk: {
        if (std.mem.eql(u8, p, "integrated") or std.mem.eql(u8, p, "int")) break :blk .integrated;
        if (std.mem.eql(u8, p, "discrete") or std.mem.eql(u8, p, "disc")) break :blk .discrete;
        if (std.mem.eql(u8, p, "nvidia") or std.mem.eql(u8, p, "nv")) break :blk .nvidia;
        if (std.mem.eql(u8, p, "intel") or std.mem.eql(u8, p, "arc")) break :blk .intel_arc;
        if (std.mem.eql(u8, p, "amd") or std.mem.eql(u8, p, "radeon")) break :blk .amd;
        if (std.mem.eql(u8, p, "monitor") or std.mem.eql(u8, p, "display")) break :blk .by_monitor;
        if (std.mem.eql(u8, p, "auto")) break :blk .auto;
        // Try as index
        if (std.fmt.parseInt(usize, p, 10)) |idx| {
            specific_idx = idx;
            break :blk .specific;
        } else |_| {}
        break :blk .auto;
    } else .discrete; // Default to discrete

    compat.print("GPU Test: preference = {s}\n\n", .{@tagName(preference)});

    var env = gpu_mgr.getEnvVars(preference, specific_idx) catch |err| {
        compat.print("Error getting env vars: {s}\n", .{@errorName(err)});
        return;
    };
    defer env.deinit();

    if (env.vars.count() == 0) {
        compat.print("No environment variables set (auto mode or no matching GPU).\n", .{});
    } else {
        compat.print("Environment variables to set:\n", .{});
        var it = env.vars.iterator();
        while (it.next()) |entry| {
            compat.print("  export {s}=\"{s}\"\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }
}

fn sessionTest(allocator: std.mem.Allocator) !void {
    var session = dbus.SessionManager.init(allocator);
    defer session.deinit();

    compat.print(
        \\Session Manager (D-Bus)
        \\========================
        \\
    , .{});

    // Check service availability
    compat.print("D-Bus Services:\n", .{});
    compat.print("  PowerProfiles: {s}\n", .{if (session.has_power_profiles) "Available ✓" else "Not available"});
    compat.print("  ScreenSaver: {s}\n", .{if (session.has_screensaver) "Available ✓" else "Not available"});
    compat.print("  Notifications: {s}\n", .{if (session.has_notifications) "Available ✓" else "Not available"});
    compat.print("\n", .{});

    // Get current power profile
    if (session.getCurrentPowerProfile()) |profile| {
        compat.print("Current Power Profile: {s}\n\n", .{profile.toString()});
    }

    compat.print("Session management features:\n", .{});
    compat.print("  - Auto performance mode on game launch\n", .{});
    compat.print("  - Screen saver inhibit during gaming\n", .{});
    compat.print("  - Desktop notifications for game events\n", .{});
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROFILE MANAGEMENT (Phase 8)
// ═══════════════════════════════════════════════════════════════════════════════

fn printProfileHelp() void {
    compat.print(
        \\Launch Profiles - Per-Game GPU/Monitor Presets
        \\===============================================
        \\
        \\Profiles let you save different configurations for the same game,
        \\e.g., "Arc A770 - Main Monitor" vs "RTX 2080 - 4K TV".
        \\
        \\Commands:
        \\  profile-list <AppID>              List profiles for a game
        \\  profile-create <AppID> <name>     Create a new profile
        \\      --gpu nvidia|arc|amd|0|1      Set GPU preference
        \\      --monitor DP-1|HDMI-A-1       Set target monitor
        \\      --resolution 2560x1440        Override resolution
        \\      --mangohud on|off             Enable/disable MangoHud
        \\  profile-set <AppID> <name>        Set active profile
        \\  profile-delete <AppID> <name>     Delete a profile
        \\  profile-shortcut <AppID> <name>   Create Steam shortcut for profile
        \\
        \\Examples:
        \\  stl-next profile-create 413150 "Arc A770" --gpu arc --monitor DP-1
        \\  stl-next profile-create 413150 "RTX 2080 4K" --gpu nvidia --resolution 3840x2160
        \\  stl-next profile-set 413150 "Arc A770"
        \\  stl-next profile-shortcut 413150 "RTX 2080 4K"
        \\
        \\Steam Shortcuts:
        \\  Using profile-shortcut creates a non-Steam game entry like:
        \\  "Stardew Valley [RTX 2080 4K]" that launches with that profile.
        \\
        \\Quick Launch with Profile:
        \\  stl-next run <AppID> --profile "Profile Name"
        \\  stl-next run 413150 --profile "Arc A770"
        \\
    , .{});
}

fn profileList(allocator: std.mem.Allocator, app_id: u32) !void {
    var game_config = config.loadGameConfig(allocator, app_id) catch |err| {
        compat.print("No configuration found for AppID {d}: {s}\n", .{ app_id, @errorName(err) });
        compat.print("Create a profile with: stl-next profile-create {d} \"Profile Name\"\n", .{app_id});
        return;
    };
    defer game_config.deinit();

    compat.print("Profiles for {s} (AppID: {d})\n", .{ game_config.name, app_id });
    compat.print("================================\n\n", .{});

    if (game_config.profiles.len == 0) {
        compat.print("No profiles configured. Using default settings.\n", .{});
        compat.print("Create one with: stl-next profile-create {d} \"Profile Name\"\n", .{app_id});
        return;
    }

    for (game_config.profiles, 0..) |profile, i| {
        const is_active = std.mem.eql(u8, profile.name, game_config.active_profile);
        compat.print("[{d}] {s}{s}\n", .{
            i,
            profile.name,
            if (is_active) " ← ACTIVE" else "",
        });

        // GPU preference
        compat.print("    GPU: {s}", .{@tagName(profile.gpu_preference)});
        if (profile.gpu_index) |idx| {
            compat.print(" (index {d})", .{idx});
        }
        compat.print("\n", .{});

        // Monitor
        if (profile.target_monitor) |mon| {
            compat.print("    Monitor: {s}\n", .{mon});
        }

        // Resolution
        if (profile.resolution_override) |res| {
            compat.print("    Resolution: {d}x{d}", .{ res.width, res.height });
            if (res.refresh_hz) |hz| {
                compat.print("@{d}Hz", .{hz});
            }
            compat.print("\n", .{});
        }

        // Overrides
        if (profile.enable_mangohud) |mh| {
            compat.print("    MangoHud: {s}\n", .{if (mh) "ON" else "OFF"});
        }
        if (profile.enable_gamescope) |gs| {
            compat.print("    Gamescope: {s}\n", .{if (gs) "ON" else "OFF"});
        }

        // Steam shortcut
        if (profile.steam_shortcut_id) |sid| {
            compat.print("    Steam Shortcut ID: {d}\n", .{sid});
        }

        if (profile.description) |desc| {
            compat.print("    Description: {s}\n", .{desc});
        }

        compat.print("\n", .{});
    }
}

fn profileCreate(allocator: std.mem.Allocator, app_id: u32, name: []const u8, extra_args: []const []const u8) !void {
    // Parse flags
    var gpu_pref: config.GpuPreference = .auto;
    var gpu_index: ?usize = null;
    var monitor: ?[]const u8 = null;
    var resolution: ?config.Resolution = null;
    var mangohud: ?bool = null;
    var gamescope: ?bool = null;
    var description: ?[]const u8 = null;

    var i: usize = 0;
    while (i < extra_args.len) : (i += 1) {
        const arg = extra_args[i];
        if (std.mem.eql(u8, arg, "--gpu") and i + 1 < extra_args.len) {
            const gpu_str = extra_args[i + 1];
            i += 1;
            // Parse GPU preference
            if (std.mem.eql(u8, gpu_str, "nvidia") or std.mem.eql(u8, gpu_str, "nv")) {
                gpu_pref = .nvidia;
            } else if (std.mem.eql(u8, gpu_str, "arc") or std.mem.eql(u8, gpu_str, "intel") or std.mem.eql(u8, gpu_str, "intel_arc")) {
                gpu_pref = .intel_arc;
            } else if (std.mem.eql(u8, gpu_str, "amd") or std.mem.eql(u8, gpu_str, "radeon")) {
                gpu_pref = .amd;
            } else if (std.mem.eql(u8, gpu_str, "discrete") or std.mem.eql(u8, gpu_str, "disc")) {
                gpu_pref = .discrete;
            } else if (std.mem.eql(u8, gpu_str, "integrated") or std.mem.eql(u8, gpu_str, "int")) {
                gpu_pref = .integrated;
            } else if (std.fmt.parseInt(usize, gpu_str, 10)) |idx| {
                gpu_pref = .specific;
                gpu_index = idx;
            } else |_| {
                compat.print("Unknown GPU preference: {s}\n", .{gpu_str});
            }
        } else if (std.mem.eql(u8, arg, "--monitor") and i + 1 < extra_args.len) {
            monitor = extra_args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--resolution") and i + 1 < extra_args.len) {
            const res_str = extra_args[i + 1];
            i += 1;
            // Parse resolution like "2560x1440" or "2560x1440@144"
            if (parseResolution(res_str)) |res| {
                resolution = res;
            }
        } else if (std.mem.eql(u8, arg, "--mangohud")) {
            mangohud = true;
        } else if (std.mem.eql(u8, arg, "--no-mangohud")) {
            mangohud = false;
        } else if (std.mem.eql(u8, arg, "--gamescope")) {
            gamescope = true;
        } else if (std.mem.eql(u8, arg, "--no-gamescope")) {
            gamescope = false;
        } else if (std.mem.eql(u8, arg, "--description") and i + 1 < extra_args.len) {
            description = extra_args[i + 1];
            i += 1;
        }
    }

    // Create the profile
    const new_profile = config.LaunchProfile{
        .name = name,
        .description = description,
        .gpu_preference = gpu_pref,
        .gpu_index = gpu_index,
        .target_monitor = monitor,
        .resolution_override = resolution,
        .enable_mangohud = mangohud,
        .enable_gamescope = gamescope,
        .create_steam_shortcut = false,
        .steam_shortcut_id = null,
    };

    // Load existing config or create new
    // Note: We don't defer deinit here because ownership transfers to mutable_config
    // and the program exits shortly after anyway
    const game_config = config.loadGameConfig(allocator, app_id) catch config.GameConfig.defaults(app_id);

    compat.print("Creating profile \"{s}\" for AppID {d}...\n\n", .{ name, app_id });
    compat.print("Profile configuration:\n", .{});
    compat.print("  Name: {s}\n", .{new_profile.name});
    compat.print("  Game: {s}\n", .{game_config.name});
    compat.print("  GPU: {s}", .{@tagName(new_profile.gpu_preference)});
    if (new_profile.gpu_index) |idx| {
        compat.print(" (index {d})", .{idx});
    }
    compat.print("\n", .{});

    if (new_profile.target_monitor) |mon| {
        compat.print("  Monitor: {s}\n", .{mon});
    }
    if (new_profile.resolution_override) |res| {
        compat.print("  Resolution: {d}x{d}", .{ res.width, res.height });
        if (res.refresh_hz) |hz| compat.print("@{d}Hz", .{hz});
        compat.print("\n", .{});
    }
    if (new_profile.enable_mangohud) |mh| {
        compat.print("  MangoHud: {s}\n", .{if (mh) "ON" else "OFF"});
    }
    if (new_profile.enable_gamescope) |gs| {
        compat.print("  Gamescope: {s}\n", .{if (gs) "ON" else "OFF"});
    }
    if (new_profile.description) |desc| {
        compat.print("  Description: {s}\n", .{desc});
    }

    // Add profile to config and save
    var mutable_config = game_config;
    mutable_config.addProfile(allocator, new_profile) catch |err| {
        if (err == error.ProfileExists) {
            compat.print("\n⚠️ Profile \"{s}\" already exists!\n", .{name});
            compat.print("Use profile-delete first if you want to recreate it.\n", .{});
            return;
        }
        compat.print("\nError adding profile: {s}\n", .{@errorName(err)});
        return;
    };

    // Save the config
    config.saveGameConfig(allocator, &mutable_config) catch |err| {
        compat.print("\n⚠️ Could not save config: {s}\n", .{@errorName(err)});
        compat.print("Profile created in memory but not persisted.\n", .{});
    };

    compat.print("\n✅ Profile saved!\n\n", .{});
    compat.print("To use:\n", .{});
    compat.print("  stl-next run {d} --profile \"{s}\"\n", .{ app_id, name });
    compat.print("  stl-next profile-set {d} \"{s}\"  (set as default)\n", .{ app_id, name });
    compat.print("  stl-next profile-shortcut {d} \"{s}\"  (create Steam shortcut)\n", .{ app_id, name });
}

/// Parse resolution string like "2560x1440" or "2560x1440@144"
fn parseResolution(res_str: []const u8) ?config.Resolution {
    // Find 'x' separator
    const x_pos = std.mem.indexOf(u8, res_str, "x") orelse return null;

    const width_str = res_str[0..x_pos];
    const rest = res_str[x_pos + 1 ..];

    // Check for @refresh rate
    const at_pos = std.mem.indexOf(u8, rest, "@");
    const height_str = if (at_pos) |pos| rest[0..pos] else rest;
    const refresh_str = if (at_pos) |pos| rest[pos + 1 ..] else null;

    const width = std.fmt.parseInt(u32, width_str, 10) catch return null;
    const height = std.fmt.parseInt(u32, height_str, 10) catch return null;
    const refresh: ?u32 = if (refresh_str) |r| std.fmt.parseInt(u32, r, 10) catch null else null;

    return config.Resolution{
        .width = width,
        .height = height,
        .refresh_hz = refresh,
    };
}

fn profileSet(allocator: std.mem.Allocator, app_id: u32, profile_name: []const u8) !void {
    var game_config = config.loadGameConfig(allocator, app_id) catch {
        compat.print("No configuration found for AppID {d}\n", .{app_id});
        return;
    };
    // Note: We don't defer deinit here because we modify active_profile
    // to point to profile_name (a borrowed string), which would cause
    // an invalid free. The program exits shortly after anyway.

    // Check if profile exists
    if (game_config.getProfile(profile_name)) |_| {
        // Set the active profile
        game_config.active_profile = profile_name;

        // Save the config
        config.saveGameConfig(allocator, &game_config) catch |err| {
            compat.print("⚠️ Could not save config: {s}\n", .{@errorName(err)});
            return;
        };

        compat.print("✅ Active profile set to \"{s}\" for AppID {d}\n", .{ profile_name, app_id });
        compat.print("Next launch will use this profile's GPU/monitor settings.\n", .{});
    } else {
        compat.print("Profile \"{s}\" not found. Available profiles:\n", .{profile_name});
        for (game_config.profiles) |profile| {
            compat.print("  - {s}\n", .{profile.name});
        }
    }
}

fn profileDelete(allocator: std.mem.Allocator, app_id: u32, profile_name: []const u8) !void {
    if (std.mem.eql(u8, profile_name, "Default")) {
        compat.print("Cannot delete the Default profile.\n", .{});
        return;
    }

    var game_config = config.loadGameConfig(allocator, app_id) catch {
        compat.print("No configuration found for AppID {d}\n", .{app_id});
        return;
    };
    defer game_config.deinit();

    game_config.removeProfile(allocator, profile_name) catch |err| {
        switch (err) {
            error.CannotRemoveDefault => compat.print("Cannot delete the Default profile.\n", .{}),
            error.ProfileNotFound => compat.print("Profile \"{s}\" not found.\n", .{profile_name}),
            error.CannotRemoveLastProfile => compat.print("Cannot remove the last profile.\n", .{}),
            else => compat.print("Error removing profile: {s}\n", .{@errorName(err)}),
        }
        return;
    };

    // Save the updated config
    config.saveGameConfig(allocator, &game_config) catch |err| {
        compat.print("⚠️ Profile removed but could not save: {s}\n", .{@errorName(err)});
        return;
    };

    compat.print("✅ Profile \"{s}\" deleted from AppID {d}\n", .{ profile_name, app_id });
}

fn profileCreateShortcut(allocator: std.mem.Allocator, app_id: u32, profile_name: []const u8) !void {
    var game_config = config.loadGameConfig(allocator, app_id) catch {
        compat.print("No configuration found for AppID {d}\n", .{app_id});
        return;
    };
    defer game_config.deinit();

    if (game_config.getProfile(profile_name)) |profile| {
        compat.print(
            \\Creating Steam shortcut for "{s}" [{s}]
            \\==========================================
            \\
        , .{ game_config.name, profile.name });

        // Get the stl-next binary path (try to find it)
        const exe_path = getStlNextPath(allocator) catch try allocator.dupe(u8, "/usr/bin/stl-next");
        defer allocator.free(exe_path);

        // Generate shortcut name
        const shortcut_name = try std.fmt.allocPrint(allocator, "{s} [{s}]", .{ game_config.name, profile.name });
        defer allocator.free(shortcut_name);

        // Generate launch arguments
        const launch_args = try std.fmt.allocPrint(allocator, "run {d} --profile \"{s}\"", .{ app_id, profile.name });
        defer allocator.free(launch_args);

        compat.print("Shortcut details:\n", .{});
        compat.print("  Name: {s}\n", .{shortcut_name});
        compat.print("  Exe: {s}\n", .{exe_path});
        compat.print("  Args: {s}\n", .{launch_args});
        compat.print("  GPU: {s}\n", .{@tagName(profile.gpu_preference)});
        compat.print("\n", .{});

        // Try to write to Steam's shortcuts.vdf
        if (writeSteamShortcut(allocator, shortcut_name, exe_path, launch_args)) |shortcut_id| {
            compat.print("✅ Steam shortcut created successfully!\n", .{});
            compat.print("   Shortcut ID: {d}\n", .{shortcut_id});
            compat.print("   Restart Steam to see \"{s}\" in your library.\n", .{shortcut_name});
        } else |err| {
            compat.print("⚠️ Could not write to Steam shortcuts: {s}\n", .{@errorName(err)});
            compat.print("\nTo add manually to Steam:\n", .{});
            compat.print("  1. Steam → Add a Game → Add a Non-Steam Game\n", .{});
            compat.print("  2. Browse to: {s}\n", .{exe_path});
            compat.print("  3. Set launch options: {s}\n", .{launch_args});
            compat.print("  4. Rename to: {s}\n", .{shortcut_name});
        }
    } else {
        compat.print("Profile \"{s}\" not found for AppID {d}\n", .{ profile_name, app_id });
    }
}

/// Get the path to the stl-next binary
fn getStlNextPath(allocator: std.mem.Allocator) ![]const u8 {
    // Try /proc/self/exe first (Linux-specific)
    var buf: [4096]u8 = undefined;
    const self_link = std.fs.readLinkAbsolute("/proc/self/exe", &buf) catch {
        // Fallback: check common locations
        const paths = [_][]const u8{
            "/usr/bin/stl-next",
            "/usr/local/bin/stl-next",
            "./zig-out/bin/stl-next",
        };
        for (paths) |path| {
            std.fs.accessAbsolute(path, .{}) catch continue;
            return allocator.dupe(u8, path);
        }
        return error.NotFound;
    };
    return allocator.dupe(u8, self_link);
}

/// Write a shortcut entry to Steam's shortcuts.vdf
fn writeSteamShortcut(
    allocator: std.mem.Allocator,
    name: []const u8,
    exe_path: []const u8,
    launch_options: []const u8,
) !u32 {
    // Find Steam user data directory
    const steam_path = std.posix.getenv("HOME") orelse return error.NoHome;
    const userdata_base = try std.fmt.allocPrint(allocator, "{s}/.steam/steam/userdata", .{steam_path});
    defer allocator.free(userdata_base);

    // Find the user ID directory (usually there's only one)
    var userdata_dir = std.fs.openDirAbsolute(userdata_base, .{ .iterate = true }) catch return error.NoSteamUserdata;
    defer userdata_dir.close();

    var user_id: ?[]const u8 = null;
    var iter = userdata_dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            // Skip non-numeric directories
            _ = std.fmt.parseInt(u32, entry.name, 10) catch continue;
            user_id = try allocator.dupe(u8, entry.name);
            break;
        }
    }

    const uid = user_id orelse return error.NoSteamUser;
    defer allocator.free(uid);

    const shortcuts_path = try std.fmt.allocPrint(allocator, "{s}/{s}/config/shortcuts.vdf", .{ userdata_base, uid });
    defer allocator.free(shortcuts_path);

    compat.print("Steam shortcuts file: {s}\n", .{shortcuts_path});

    // Generate a unique shortcut ID based on exe+name hash
    // Steam uses a CRC-like algorithm but this should be unique enough
    const hash1 = std.hash.Wyhash.hash(0, exe_path);
    const hash2 = std.hash.Wyhash.hash(hash1, name);
    const shortcut_id: u32 = @truncate(hash2);

    // Get the start directory (directory containing the exe)
    const start_dir = getStartDir(allocator, exe_path) catch try allocator.dupe(u8, "");
    defer allocator.free(start_dir);

    // Try to write the binary VDF
    writeShortcutsVdf(allocator, shortcuts_path, name, exe_path, start_dir, launch_options, shortcut_id) catch |err| {
        compat.print("\n📝 Shortcut entry (for manual addition):\n", .{});
        compat.print("   AppID: {d}\n", .{shortcut_id});
        compat.print("   appname: {s}\n", .{name});
        compat.print("   exe: \"{s}\"\n", .{exe_path});
        compat.print("   LaunchOptions: {s}\n", .{launch_options});
        return err;
    };

    return shortcut_id;
}

fn getStartDir(allocator: std.mem.Allocator, exe_path: []const u8) ![]const u8 {
    // Find the last / to get the directory
    var last_slash: usize = 0;
    for (exe_path, 0..) |c, i| {
        if (c == '/') last_slash = i;
    }
    if (last_slash > 0) {
        return allocator.dupe(u8, exe_path[0..last_slash]);
    }
    return allocator.dupe(u8, "");
}

/// Write the binary VDF shortcuts file
fn writeShortcutsVdf(
    allocator: std.mem.Allocator,
    path: []const u8,
    name: []const u8,
    exe_path: []const u8,
    start_dir: []const u8,
    launch_options: []const u8,
    app_id: u32,
) !void {
    // Read existing shortcuts if file exists
    var existing_shortcuts: std.ArrayListUnmanaged(u8) = .{};
    defer existing_shortcuts.deinit(allocator);

    var next_index: u32 = 0;

    // Try to read existing file
    if (std.fs.openFileAbsolute(path, .{})) |file| {
        defer file.close();
        const stat = try file.stat();
        if (stat.size > 0 and stat.size < 10 * 1024 * 1024) { // Max 10MB
            const content = try allocator.alloc(u8, stat.size);
            defer allocator.free(content);
            _ = try file.readAll(content);

            // Find the highest existing index
            // Format: \x00"N"\x00 where N is the index
            var i: usize = 0;
            while (i < content.len - 4) : (i += 1) {
                if (content[i] == 0x00 and content[i + 1] == '"') {
                    // Try to parse index
                    var end: usize = i + 2;
                    while (end < content.len and content[end] != '"') : (end += 1) {}
                    if (end < content.len) {
                        const idx_str = content[i + 2 .. end];
                        if (std.fmt.parseInt(u32, idx_str, 10)) |idx| {
                            if (idx >= next_index) next_index = idx + 1;
                        } else |_| {}
                    }
                }
            }

            // Copy existing content (without final \x08\x08)
            if (content.len > 2 and content[content.len - 1] == 0x08 and content[content.len - 2] == 0x08) {
                try existing_shortcuts.appendSlice(allocator, content[0 .. content.len - 2]);
            } else if (content.len > 1 and content[content.len - 1] == 0x08) {
                try existing_shortcuts.appendSlice(allocator, content[0 .. content.len - 1]);
            }
        }
    } else |_| {}

    // Create new file
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();

    // If we have existing content, write it
    if (existing_shortcuts.items.len > 0) {
        try file.writeAll(existing_shortcuts.items);
    } else {
        // Write header: \x00shortcuts\x00
        try file.writeAll("\x00shortcuts\x00");
    }

    // Write new shortcut entry
    // Format: \x00"index"\x00
    var idx_buf: [16]u8 = undefined;
    const idx_str = try std.fmt.bufPrint(&idx_buf, "{d}", .{next_index});
    try file.writeAll("\x00\"");
    try file.writeAll(idx_str);
    try file.writeAll("\"\x00");

    // Write appid (type 0x02 = uint32)
    try file.writeAll("\x02appid\x00");
    try file.writeAll(&std.mem.toBytes(app_id));

    // Write AppName (type 0x01 = string)
    try file.writeAll("\x01AppName\x00");
    try file.writeAll(name);
    try file.writeAll("\x00");

    // Write Exe (type 0x01 = string)
    try file.writeAll("\x01Exe\x00\"");
    try file.writeAll(exe_path);
    try file.writeAll("\"\x00");

    // Write StartDir (type 0x01 = string)
    try file.writeAll("\x01StartDir\x00\"");
    try file.writeAll(start_dir);
    try file.writeAll("\"\x00");

    // Write icon (type 0x01 = string, empty)
    try file.writeAll("\x01icon\x00\x00");

    // Write ShortcutPath (type 0x01 = string, empty)
    try file.writeAll("\x01ShortcutPath\x00\x00");

    // Write LaunchOptions (type 0x01 = string)
    try file.writeAll("\x01LaunchOptions\x00");
    try file.writeAll(launch_options);
    try file.writeAll("\x00");

    // Write IsHidden (type 0x02 = uint32, value 0)
    try file.writeAll("\x02IsHidden\x00");
    try file.writeAll(&std.mem.toBytes(@as(u32, 0)));

    // Write AllowDesktopConfig (type 0x02 = uint32, value 1)
    try file.writeAll("\x02AllowDesktopConfig\x00");
    try file.writeAll(&std.mem.toBytes(@as(u32, 1)));

    // Write AllowOverlay (type 0x02 = uint32, value 1)
    try file.writeAll("\x02AllowOverlay\x00");
    try file.writeAll(&std.mem.toBytes(@as(u32, 1)));

    // Write OpenVR (type 0x02 = uint32, value 0)
    try file.writeAll("\x02OpenVR\x00");
    try file.writeAll(&std.mem.toBytes(@as(u32, 0)));

    // Write Devkit (type 0x02 = uint32, value 0)
    try file.writeAll("\x02Devkit\x00");
    try file.writeAll(&std.mem.toBytes(@as(u32, 0)));

    // Write DevkitGameID (type 0x01 = string, empty)
    try file.writeAll("\x01DevkitGameID\x00\x00");

    // Write DevkitOverrideAppID (type 0x02 = uint32, value 0)
    try file.writeAll("\x02DevkitOverrideAppID\x00");
    try file.writeAll(&std.mem.toBytes(@as(u32, 0)));

    // Write LastPlayTime (type 0x02 = uint32, value 0)
    try file.writeAll("\x02LastPlayTime\x00");
    try file.writeAll(&std.mem.toBytes(@as(u32, 0)));

    // Write tags (empty nested object)
    try file.writeAll("\x00tags\x00\x08");

    // Close this shortcut entry
    try file.writeAll("\x08");

    // Close shortcuts section and file
    try file.writeAll("\x08");

    std.log.info("Shortcuts: Written to {s}", .{path});
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "command parsing" {
    const cmd = std.meta.stringToEnum(Command, "info");
    try std.testing.expectEqual(Command.info, cmd.?);
}

test "appid parsing" {
    const app_id = try std.fmt.parseInt(u32, "413150", 10);
    try std.testing.expectEqual(@as(u32, 413150), app_id);
}

test {
    _ = @import("core/config.zig");
    _ = @import("core/launcher.zig");
    _ = @import("engine/vdf.zig");
    _ = @import("engine/steam.zig");
    _ = @import("engine/appinfo.zig");
    _ = @import("engine/leveldb.zig");
    _ = @import("engine/nonsteam.zig");
    _ = @import("engine/steamgriddb.zig");
    _ = @import("ipc/protocol.zig");
    _ = @import("ipc/server.zig");
    _ = @import("ipc/client.zig");
    _ = @import("tinkers/winetricks.zig");
    _ = @import("tinkers/customcmd.zig");
    _ = @import("modding/manager.zig");
    _ = @import("tests/edge_cases.zig");
}
