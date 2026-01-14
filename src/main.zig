const std = @import("std");
const builtin = @import("builtin");

// ═══════════════════════════════════════════════════════════════════════════════
// STL-NEXT: Steam Tinker Launch - Next Generation
// ═══════════════════════════════════════════════════════════════════════════════
//
// A high-performance Steam game wrapper written in Zig.
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
const config = @import("core/config.zig");
const launcher = @import("core/launcher.zig");

pub const std_options = std.Options{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
};

const VERSION = "0.1.0-alpha";

const Command = enum {
    run,
    info,
    list_games,
    list_protons,
    configure,
    install,
    version,
    help,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments (Zig 0.13 API)
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse command
    if (args.len < 2) {
        printUsage();
        return;
    }

    const cmd_str = args[1];
    const cmd = std.meta.stringToEnum(Command, cmd_str) orelse {
        // Check if it's an AppID (numeric) - shorthand for 'run'
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
        .configure => {
            std.log.info("Configuration UI not yet implemented", .{});
            std.log.info("Use environment variables or config files for now", .{});
        },
        .install => {
            std.log.info("Tool installation not yet implemented", .{});
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

    // Phase 1: Locate Steam installation
    var steam_engine = try steam.SteamEngine.init(allocator);
    defer steam_engine.deinit();

    std.log.info("║ Steam: {s: <34} ║", .{steam_engine.steam_path[0..@min(34, steam_engine.steam_path.len)]});

    // Phase 2: Load game metadata from appinfo.vdf
    const game_info = steam_engine.getGameInfo(app_id) catch |err| {
        std.log.err("Failed to load game info: {}", .{err});
        return err;
    };

    std.log.info("║ Game:  {s: <34} ║", .{game_info.name[0..@min(34, game_info.name.len)]});
    std.log.info("╚══════════════════════════════════════════╝", .{});

    // Phase 3: Load STL configuration for this game
    const game_config = config.loadGameConfig(allocator, app_id) catch |err| blk: {
        std.log.warn("No custom config for AppID {d}, using defaults: {}", .{ app_id, err });
        break :blk config.GameConfig.defaults(app_id);
    };
    _ = game_config;

    // Phase 4: Build environment and launch
    const setup_time = timer.read();
    std.log.info("Setup completed in {d:.2}ms", .{@as(f64, @floatFromInt(setup_time)) / std.time.ns_per_ms});

    // For now, just pass through to Proton/the game
    
    try launcher.launch(allocator, &steam_engine, app_id, extra_args);
}

fn showGameInfo(allocator: std.mem.Allocator, app_id: u32) !void {
    var steam_engine = try steam.SteamEngine.init(allocator);
    defer steam_engine.deinit();

    const game_info = try steam_engine.getGameInfo(app_id);

    // Check for --json flag (TODO: proper arg parsing)
    const stdout = std.io.getStdOut().writer();

    try stdout.print(
        \\{{
        \\  "app_id": {d},
        \\  "name": "{s}",
        \\  "install_dir": "{s}",
        \\  "executable": "{s}",
        \\  "proton_version": "{s}",
        \\  "playtime_minutes": {d}
        \\}}
        \\
    , .{
        game_info.app_id,
        game_info.name,
        game_info.install_dir,
        game_info.executable,
        game_info.proton_version orelse "native",
        game_info.playtime_minutes,
    });
}

fn listGames(allocator: std.mem.Allocator) !void {
    var steam_engine = try steam.SteamEngine.init(allocator);
    defer steam_engine.deinit();

    const games = try steam_engine.listInstalledGames();

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("[\n");

    for (games, 0..) |game, i| {
        try stdout.print(
            \\  {{"app_id": {d}, "name": "{s}"}}{s}
        , .{
            game.app_id,
            game.name,
            if (i < games.len - 1) "," else "",
        });
        try stdout.writeAll("\n");
    }

    try stdout.writeAll("]\n");
}

fn listProtons(allocator: std.mem.Allocator) !void {
    var steam_engine = try steam.SteamEngine.init(allocator);
    defer steam_engine.deinit();

    const protons = try steam_engine.listProtonVersions();

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("[\n");

    for (protons, 0..) |proton, i| {
        try stdout.print(
            \\  {{"name": "{s}", "path": "{s}"}}{s}
        , .{
            proton.name,
            proton.path,
            if (i < protons.len - 1) "," else "",
        });
        try stdout.writeAll("\n");
    }

    try stdout.writeAll("]\n");
}

fn printVersion() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(
        \\STL-Next v{s}
        \\Steam Tinker Launch - Next Generation
        \\
        \\A high-performance Steam game wrapper written in Zig.
        \\https://github.com/e421/stl-next
        \\
    , .{VERSION}) catch {};
}

fn printUsage() void {
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll(
        \\Usage: stl-next <command> [options]
        \\
        \\Commands:
        \\  run <AppID>       Launch a game with STL-Next configuration
        \\  info <AppID>      Show game information (JSON)
        \\  list-games        List installed Steam games (JSON)
        \\  list-protons      List available Proton versions (JSON)
        \\  configure         Open configuration UI (WIP)
        \\  install <tool>    Install a tool (ReShade, MO2, etc.) (WIP)
        \\  version           Show version information
        \\  help              Show this help message
        \\
        \\Shorthand:
        \\  stl-next <AppID>  Same as 'stl-next run <AppID>'
        \\
        \\Environment Variables:
        \\  STL_CONFIG_DIR    Config directory (default: ~/.config/stl-next)
        \\  STL_LOG_LEVEL     Log level: debug, info, warn, error
        \\  STL_JSON_OUTPUT   Force JSON output for all commands
        \\
        \\Examples:
        \\  stl-next 413150                    # Launch Stardew Valley
        \\  stl-next info 489830               # Show Skyrim SE info
        \\  stl-next list-games | jq '.[]'     # List games with jq
        \\
    ) catch {};
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

