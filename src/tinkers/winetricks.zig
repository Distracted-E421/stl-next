const std = @import("std");
const interface = @import("interface.zig");
const Context = interface.Context;
const EnvMap = interface.EnvMap;
const ArgList = interface.ArgList;
const Priority = interface.Priority;

// ═══════════════════════════════════════════════════════════════════════════════
// WINETRICKS TINKER
// ═══════════════════════════════════════════════════════════════════════════════
//
// Integrates winetricks for installing Windows components, DLLs, fonts, and
// runtime libraries into the Wine prefix.
//
// Common verbs:
//   - vcrun2019: Visual C++ 2019 runtime
//   - dxvk: DirectX to Vulkan translation
//   - dotnet48: .NET Framework 4.8
//   - corefonts: Microsoft core fonts
//   - xact: Microsoft XACT audio
//   - physx: NVIDIA PhysX
//
// ═══════════════════════════════════════════════════════════════════════════════

/// Winetricks configuration
pub const WinetricksConfig = struct {
    enabled: bool = false,
    /// Verbs to install (e.g., "vcrun2019", "dxvk", "dotnet48")
    verbs: []const []const u8 = &.{},
    /// Run silently without GUI
    silent: bool = true,
    /// Force reinstall even if already installed
    force: bool = false,
    /// Use isolate mode (separate prefix for each verb)
    isolate: bool = false,
    /// Custom winetricks binary path (optional, uses PATH by default)
    binary_path: ?[]const u8 = null,
};

/// Known winetricks verb categories
pub const VerbCategory = enum {
    runtime,    // vcrun*, dotnet*, xna*
    dll,        // d3dcompiler*, dxvk, vkd3d
    font,       // corefonts, tahoma, liberation
    audio,      // xact, faudio
    misc,       // physx, gecko, mono
};

/// Common verb presets for easy configuration
pub const VerbPresets = struct {
    /// Basic runtime essentials
    pub const basic = [_][]const u8{ "vcrun2019", "corefonts" };
    
    /// For DirectX 9/10/11 games
    pub const dx_essentials = [_][]const u8{ "d3dcompiler_47", "dxvk" };
    
    /// For older games requiring .NET
    pub const dotnet_legacy = [_][]const u8{ "dotnet40", "dotnet48", "vcrun2019" };
    
    /// For games with XAudio issues
    pub const audio_fix = [_][]const u8{ "xact", "xact_x64", "faudio" };
    
    /// Kitchen sink - install everything common
    pub const full = [_][]const u8{
        "vcrun2019",
        "corefonts",
        "d3dcompiler_47",
        "dxvk",
        "faudio",
    };
};

fn isEnabled(ctx: *const Context) bool {
    return ctx.game_config.winetricks.enabled and 
           ctx.game_config.winetricks.verbs.len > 0;
}

fn preparePrefix(ctx: *const Context) !void {
    const config = ctx.game_config.winetricks;
    
    // Find winetricks binary
    const winetricks_bin = config.binary_path orelse "winetricks";
    
    // Check if winetricks is available
    var check_child = std.process.Child.init(&.{ winetricks_bin, "--version" }, ctx.allocator);
    check_child.stderr_behavior = .Ignore;
    check_child.stdout_behavior = .Ignore;
    _ = check_child.spawnAndWait() catch |err| {
        std.log.err("Winetricks: Binary not found at '{s}': {}", .{ winetricks_bin, err });
        return error.WinetricksNotFound;
    };
    
    std.log.info("Winetricks: Installing {d} verb(s) to prefix", .{config.verbs.len});
    
    for (config.verbs) |verb| {
        try installVerb(ctx, winetricks_bin, verb, config.silent, config.force);
    }
}

fn installVerb(
    ctx: *const Context,
    winetricks_bin: []const u8,
    verb: []const u8,
    silent: bool,
    force: bool,
) !void {
    var args: std.ArrayList([]const u8) = .{};
    defer args.deinit(ctx.allocator);
    
    try args.append(ctx.allocator, winetricks_bin);
    
    // Set prefix
    try args.append(ctx.allocator, "--prefix");
    try args.append(ctx.allocator, ctx.prefix_path);
    
    // Silent mode
    if (silent) {
        try args.append(ctx.allocator, "-q");
    }
    
    // Force reinstall
    if (force) {
        try args.append(ctx.allocator, "--force");
    }
    
    // The verb to install
    try args.append(ctx.allocator, verb);
    
    std.log.info("Winetricks: Installing '{s}'...", .{verb});
    
    var child = std.process.Child.init(args.items, ctx.allocator);
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    
    // Set WINEPREFIX
    var env = std.process.EnvMap.init(ctx.allocator);
    defer env.deinit();
    
    var inherited_env = try std.process.getEnvMap(ctx.allocator);
    defer inherited_env.deinit();
    var env_iter = inherited_env.iterator();
    while (env_iter.next()) |entry| {
        try env.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    try env.put("WINEPREFIX", ctx.prefix_path);
    
    // If proton is set, point to its Wine
    if (ctx.proton_path) |proton| {
        const wine_path = try std.fmt.allocPrint(ctx.allocator, "{s}/dist/bin/wine64", .{proton});
        defer ctx.allocator.free(wine_path);
        if (std.fs.accessAbsolute(wine_path, .{})) {
            try env.put("WINE", wine_path);
        } else |_| {}
    }
    
    child.env_map = &env;
    
    const term = try child.spawnAndWait();
    
    switch (term) {
        .Exited => |code| {
            if (code == 0) {
                std.log.info("Winetricks: '{s}' installed successfully", .{verb});
            } else {
                std.log.warn("Winetricks: '{s}' failed with code {d}", .{ verb, code });
            }
        },
        else => {
            std.log.warn("Winetricks: '{s}' terminated abnormally", .{verb});
        },
    }
}

fn modifyEnv(ctx: *const Context, env: *EnvMap) !void {
    _ = ctx;
    _ = env;
    // Winetricks typically doesn't need runtime env changes
    // It modifies the prefix during preparePrefix
}

fn modifyArgs(ctx: *const Context, args: *ArgList) !void {
    _ = ctx;
    _ = args;
    // Winetricks doesn't modify launch arguments
}

pub const winetricks_tinker = interface.Tinker{
    .id = "winetricks",
    .name = "Winetricks",
    .priority = Priority.SETUP_EARLY, // Run first to install dependencies
    .isEnabledFn = isEnabled,
    .preparePrefixFn = preparePrefix,
    .modifyEnvFn = modifyEnv,
    .modifyArgsFn = modifyArgs,
    .cleanupFn = null,
};

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Check if a verb is already installed in the prefix
pub fn isVerbInstalled(allocator: std.mem.Allocator, prefix_path: []const u8, verb: []const u8) !bool {
    // winetricks stores installed verbs in .verbs file
    const verbs_file = try std.fmt.allocPrint(allocator, "{s}/.verbs", .{prefix_path});
    defer allocator.free(verbs_file);
    
    const file = std.fs.openFileAbsolute(verbs_file, .{}) catch {
        return false;
    };
    defer file.close();
    
    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);
    
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, verb)) {
            return true;
        }
    }
    
    return false;
}

/// List all available winetricks verbs (requires winetricks installed)
pub fn listAvailableVerbs(allocator: std.mem.Allocator) ![]const []const u8 {
    var child = std.process.Child.init(&.{ "winetricks", "list-all" }, allocator);
    child.stderr_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    
    _ = try child.spawn();
    
    const stdout = child.stdout orelse return error.NoStdout;
    const output = try stdout.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(output);
    
    _ = try child.wait();
    
    var verbs: std.ArrayList([]const u8) = .{};
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len > 0 and line[0] != '#' and line[0] != ' ') {
            // Extract verb name (first word)
            var parts = std.mem.splitScalar(u8, line, ' ');
            if (parts.next()) |verb| {
                try verbs.append(allocator, try allocator.dupe(u8, verb));
            }
        }
    }
    
    return verbs.toOwnedSlice(allocator);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "verb presets" {
    try std.testing.expectEqual(@as(usize, 2), VerbPresets.basic.len);
    try std.testing.expectEqual(@as(usize, 5), VerbPresets.full.len);
}

test "default config disabled" {
    const config = WinetricksConfig{};
    try std.testing.expect(!config.enabled);
    try std.testing.expectEqual(@as(usize, 0), config.verbs.len);
}

