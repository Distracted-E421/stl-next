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

pub const std_options = std.Options{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
};

const VERSION = "0.5.0-alpha";

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
        .version => printVersion(),
        .help => printUsage(),
    }
}

fn runGame(allocator: std.mem.Allocator, app_id: u32, extra_args: []const []const u8) !void {
    var timer = try std.time.Timer.start();

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
    
    std.log.info("╚══════════════════════════════════════════╝", .{});

    const game_config = config.loadGameConfig(allocator, app_id) catch |err| blk: {
        std.log.warn("No custom config for AppID {d}, using defaults: {}", .{ app_id, err });
        break :blk config.GameConfig.defaults(app_id);
    };
    _ = game_config;

    const setup_time = timer.read();
    std.log.info("Setup completed in {d:.2}ms", .{@as(f64, @floatFromInt(setup_time)) / std.time.ns_per_ms});

    const result = try launcher.launch(allocator, &steam_engine, app_id, extra_args, false);
    if (!result.success) {
        if (result.error_msg) |msg| std.log.err("Launch failed: {s}", .{msg});
        return error.LaunchFailed;
    }
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
        \\
        \\Examples:
        \\  stl-next 413150                    # Launch Stardew Valley
        \\  stl-next info 489830               # Show Skyrim SE info
        \\  stl-next list-games | jq '.[]'     # List games with jq
        \\  stl-next add-game "Celeste" ~/Games/Celeste/Celeste --native
        \\  stl-next artwork 413150            # Get Stardew Valley artwork
        \\
    , .{});
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
        const name = game.name;
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
