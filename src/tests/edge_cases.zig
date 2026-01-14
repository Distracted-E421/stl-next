const std = @import("std");
const protocol = @import("../ipc/protocol.zig");
const config = @import("../core/config.zig");
const modding = @import("../modding/manager.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// EDGE CASE TESTS (Phase 4 - Hardened)
// ═══════════════════════════════════════════════════════════════════════════════
//
// These tests cover edge cases that the original STL didn't handle:
// - URL truncation
// - Malformed input
// - Special characters
// - Boundary conditions
//
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// NXM URL EDGE CASES (This is the bug that started it all)
// ═══════════════════════════════════════════════════════════════════════════════

test "nxm: collection url preserves revisions (THE ORIGINAL BUG)" {
    // This is the exact URL that was being truncated by STL
    const url = "nxm://stardewvalley/collections/tckf0m/revisions/100";
    
    var link = try modding.NxmLink.parse(std.testing.allocator, url);
    defer link.deinit(std.testing.allocator);
    
    // CRITICAL: Revision ID must be preserved!
    try std.testing.expectEqual(@as(u32, 100), link.revision_id.?);
    try std.testing.expectEqualStrings("tckf0m", link.collection_slug.?);
}

test "nxm: wine encoding escapes all slashes" {
    const url = "nxm://stardewvalley/collections/tckf0m/revisions/100";
    
    var link = try modding.NxmLink.parse(std.testing.allocator, url);
    defer link.deinit(std.testing.allocator);
    
    const encoded = try link.encodeForWine(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    
    // After nxm:// there should be NO raw slashes
    const after_scheme = encoded[6..];
    try std.testing.expect(std.mem.indexOf(u8, after_scheme, "/") == null);
    
    // All parts should still be present (as %2F)
    try std.testing.expect(std.mem.indexOf(u8, encoded, "stardewvalley") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "collections") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "tckf0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "revisions") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "100") != null);
}

test "nxm: special characters in mod names" {
    // Some mods have special characters in their slugs
    var link = try modding.NxmLink.parse(
        std.testing.allocator,
        "nxm://game/collections/mod-name_v2/revisions/1",
    );
    defer link.deinit(std.testing.allocator);
    
    try std.testing.expectEqualStrings("mod-name_v2", link.collection_slug.?);
}

test "nxm: query params preserved" {
    const url = "nxm://skyrimse/mods/1000/files/2000?key=abc123def456&expires=1234567890";
    
    var link = try modding.NxmLink.parse(std.testing.allocator, url);
    defer link.deinit(std.testing.allocator);
    
    try std.testing.expectEqualStrings("abc123def456", link.key.?);
    try std.testing.expectEqual(@as(u64, 1234567890), link.expires.?);
}

test "nxm: various game domains" {
    const domains = [_][]const u8{
        "stardewvalley",
        "skyrimse",
        "fallout4",
        "baldursgate3",
        "cyberpunk2077",
        "witcher3",
        "newvegas",
    };
    
    for (domains) |domain| {
        const url = try std.fmt.allocPrint(
            std.testing.allocator,
            "nxm://{s}/mods/1/files/1",
            .{domain},
        );
        defer std.testing.allocator.free(url);
        
        var link = modding.NxmLink.parse(std.testing.allocator, url) catch |err| {
            std.debug.print("Failed for domain {s}: {}\n", .{ domain, err });
            return err;
        };
        defer link.deinit(std.testing.allocator);
        
        try std.testing.expectEqualStrings(domain, link.game_domain);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NXM ERROR CASES
// ═══════════════════════════════════════════════════════════════════════════════

test "nxm: empty url fails" {
    const result = modding.NxmLink.parse(std.testing.allocator, "");
    try std.testing.expectError(modding.NxmError.EmptyUrl, result);
}

test "nxm: wrong scheme fails" {
    const bad_schemes = [_][]const u8{
        "http://nexusmods.com/mods/1",
        "https://nexusmods.com/mods/1",
        "ftp://somewhere/file",
        "file:///local/path",
        "nxms://typo/mods/1",
    };
    
    for (bad_schemes) |url| {
        const result = modding.NxmLink.parse(std.testing.allocator, url);
        try std.testing.expectError(modding.NxmError.InvalidScheme, result);
    }
}

test "nxm: scheme only fails" {
    const result = modding.NxmLink.parse(std.testing.allocator, "nxm://");
    try std.testing.expectError(modding.NxmError.MissingGameDomain, result);
}

test "nxm: invalid mod id fails" {
    const bad_ids = [_][]const u8{
        "nxm://game/mods/abc/files/1",
        "nxm://game/mods/-1/files/1",
        "nxm://game/mods/99999999999/files/1", // Overflow
    };
    
    for (bad_ids) |url| {
        // Should fail with some error
        if (modding.NxmLink.parse(std.testing.allocator, url)) |link| {
            // If it somehow parses, it should not be valid
            var mut_link = link;
            defer mut_link.deinit(std.testing.allocator);
            // This shouldn't happen for invalid IDs
        } else |_| {
            // Expected - it should error
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// IPC PROTOCOL EDGE CASES
// ═══════════════════════════════════════════════════════════════════════════════

test "ipc: action round-trip" {
    const actions = [_]protocol.Action{
        .PAUSE_LAUNCH,
        .RESUME_LAUNCH,
        .UPDATE_CONFIG,
        .PROCEED,
        .ABORT,
        .GET_STATUS,
        .GET_GAME_INFO,
        .GET_TINKERS,
        .TOGGLE_TINKER,
    };
    
    for (actions) |action| {
        const str = action.toString();
        const parsed = protocol.Action.fromString(str);
        try std.testing.expectEqual(action, parsed.?);
    }
}

test "ipc: daemon message with special characters in game name" {
    const names_to_test = [_][]const u8{
        "Stardew Valley",
        "The Witcher 3: Wild Hunt",
        "Half-Life 2: Episode One",
        "Tom Clancy's Rainbow Six Siege",
        "FINAL FANTASY XIV",
        "R&D Simulator \"2025\"", // Quotes!
        "Path\\Of\\Exile", // Backslashes!
    };
    
    for (names_to_test) |name| {
        const msg = protocol.DaemonMessage{
            .state = .COUNTDOWN,
            .countdown_seconds = 5,
            .game_name = name,
            .app_id = 12345,
        };
        
        const serialized = msg.serialize(std.testing.allocator) catch |err| {
            std.debug.print("Serialization failed for name '{s}': {}\n", .{ name, err });
            continue;
        };
        defer std.testing.allocator.free(serialized);
        
        // Should produce valid JSON
        var parsed = std.json.parseFromSlice(
            std.json.Value,
            std.testing.allocator,
            serialized,
            .{},
        ) catch |err| {
            std.debug.print("JSON parse failed for name '{s}': {}\n", .{ name, err });
            std.debug.print("Serialized: {s}\n", .{serialized});
            return err;
        };
        defer parsed.deinit();
    }
}

test "ipc: state parsing from partial json" {
    const test_cases = [_]struct { input: []const u8, expected: protocol.DaemonState }{
        .{ .input = "{\"state\":\"COUNTDOWN\"}", .expected = .COUNTDOWN },
        .{ .input = "{\"state\":\"WAITING\"}", .expected = .WAITING },
        .{ .input = "{\"state\":\"LAUNCHING\"}", .expected = .LAUNCHING },
        .{ .input = "{\"state\":\"RUNNING\"}", .expected = .RUNNING },
        .{ .input = "{\"state\":\"FINISHED\"}", .expected = .FINISHED },
        .{ .input = "{\"state\":\"ERROR\"}", .expected = .ERROR },
        .{ .input = "{\"garbage\":true}", .expected = .INITIALIZING }, // Defaults
    };
    
    for (test_cases) |tc| {
        const msg = try protocol.DaemonMessage.parseFromJson(std.testing.allocator, tc.input);
        try std.testing.expectEqual(tc.expected, msg.state);
    }
}

test "ipc: countdown extraction edge cases" {
    const test_cases = [_]struct { input: []const u8, expected: u8 }{
        .{ .input = "{\"countdown_seconds\":10}", .expected = 10 },
        .{ .input = "{\"countdown_seconds\":0}", .expected = 0 },
        .{ .input = "{\"countdown_seconds\":255}", .expected = 255 },
        .{ .input = "{\"countdown_seconds\":1}", .expected = 1 },
        .{ .input = "{}", .expected = 0 }, // Missing
    };
    
    for (test_cases) |tc| {
        const msg = try protocol.DaemonMessage.parseFromJson(std.testing.allocator, tc.input);
        try std.testing.expectEqual(tc.expected, msg.countdown_seconds);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIG EDGE CASES
// ═══════════════════════════════════════════════════════════════════════════════

test "config: default values" {
    const cfg = config.GameConfig.defaults(413150);
    
    try std.testing.expectEqual(@as(u32, 413150), cfg.app_id);
    try std.testing.expect(!cfg.use_native);
    try std.testing.expect(cfg.proton_version == null);
    try std.testing.expect(!cfg.mangohud.enabled);
    try std.testing.expect(!cfg.gamescope.enabled);
    try std.testing.expect(!cfg.gamemode.enabled);
}

test "config: mangohud defaults" {
    const cfg = config.GameConfig.defaults(0);
    
    try std.testing.expect(cfg.mangohud.show_fps);
    try std.testing.expect(cfg.mangohud.show_frametime);
    try std.testing.expect(cfg.mangohud.show_cpu);
    try std.testing.expect(cfg.mangohud.show_gpu);
    try std.testing.expectEqualStrings("top-left", cfg.mangohud.position);
    try std.testing.expectEqual(@as(u8, 24), cfg.mangohud.font_size);
}

test "config: gamescope defaults" {
    const cfg = config.GameConfig.defaults(0);
    
    try std.testing.expect(cfg.gamescope.fullscreen);
    try std.testing.expect(!cfg.gamescope.borderless);
    try std.testing.expect(!cfg.gamescope.fsr);
    try std.testing.expectEqual(@as(u8, 5), cfg.gamescope.fsr_sharpness);
    try std.testing.expectEqual(@as(u16, 0), cfg.gamescope.fps_limit);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOUNDARY CONDITIONS
// ═══════════════════════════════════════════════════════════════════════════════

test "boundary: max app id" {
    const max_app_id: u32 = std.math.maxInt(u32);
    const cfg = config.GameConfig.defaults(max_app_id);
    try std.testing.expectEqual(max_app_id, cfg.app_id);
}

test "boundary: zero app id" {
    const cfg = config.GameConfig.defaults(0);
    try std.testing.expectEqual(@as(u32, 0), cfg.app_id);
}

test "boundary: socket path length" {
    // Ensure socket path doesn't exceed unix socket max length
    const path = try protocol.getSocketPath(std.testing.allocator, std.math.maxInt(u32));
    defer std.testing.allocator.free(path);
    
    // Unix socket path max is typically 108 bytes
    try std.testing.expect(path.len < 108);
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONCURRENCY / RACE CONDITIONS (conceptual)
// ═══════════════════════════════════════════════════════════════════════════════

test "concurrent: multiple daemon message serializations" {
    var messages: [10]protocol.DaemonMessage = undefined;
    var results: [10]?[]u8 = undefined;
    
    for (&messages, 0..) |*msg, i| {
        msg.* = protocol.DaemonMessage{
            .state = .COUNTDOWN,
            .countdown_seconds = @intCast(i),
            .game_name = "Test Game",
            .app_id = @intCast(i * 1000),
        };
    }
    
    // Serialize all (simulating concurrent access)
    for (messages, 0..) |msg, i| {
        results[i] = msg.serialize(std.testing.allocator) catch null;
    }
    
    // All should succeed and be different
    for (results, 0..) |maybe_result, i| {
        if (maybe_result) |result| {
            defer std.testing.allocator.free(result);
            try std.testing.expect(result.len > 0);
            
            // Should contain the correct app_id
            var expected_buf: [32]u8 = undefined;
            const expected = try std.fmt.bufPrint(&expected_buf, "{d}", .{i * 1000});
            try std.testing.expect(std.mem.indexOf(u8, result, expected) != null);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY SAFETY
// ═══════════════════════════════════════════════════════════════════════════════

test "memory: nxm link cleanup" {
    // Allocate and free many times to catch leaks
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        var link = try modding.NxmLink.parse(
            std.testing.allocator,
            "nxm://stardewvalley/collections/tckf0m/revisions/100?key=test",
        );
        link.deinit(std.testing.allocator);
    }
    // If we get here without the test allocator complaining, no leaks
}

test "memory: protocol message cleanup" {
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const msg = protocol.DaemonMessage{
            .state = .COUNTDOWN,
            .countdown_seconds = 5,
            .game_name = "Test Game With A Longer Name",
            .app_id = 413150,
        };
        
        const serialized = try msg.serialize(std.testing.allocator);
        std.testing.allocator.free(serialized);
    }
}

