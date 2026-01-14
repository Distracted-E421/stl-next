//! Tinker Module System (Phase 3.5 - Hardened)
//!
//! No global state! All tinkers read config from Context.

const std = @import("std");

pub const interface = @import("interface.zig");
pub const Tinker = interface.Tinker;
pub const TinkerRegistry = interface.TinkerRegistry;
pub const Context = interface.Context;
pub const Priority = interface.Priority;

pub const mangohud = @import("mangohud.zig");
pub const gamescope = @import("gamescope.zig");
pub const gamemode = @import("gamemode.zig");

/// Initialize a registry with all built-in tinkers
pub fn initBuiltinRegistry(allocator: std.mem.Allocator) !TinkerRegistry {
    var registry = TinkerRegistry.init(allocator);

    try registry.register(&mangohud.mangohud_tinker);
    try registry.register(&gamescope.gamescope_tinker);
    try registry.register(&gamemode.gamemode_tinker);

    std.log.info("Tinker Registry: {d} tinkers available", .{registry.tinkers.items.len});

    return registry;
}

pub const builtin_tinker_ids = [_][]const u8{
    "mangohud",
    "gamescope",
    "gamemode",
};

test "registry initialization" {
    var registry = try initBuiltinRegistry(std.testing.allocator);
    defer registry.deinit();
    try std.testing.expectEqual(@as(usize, 3), registry.tinkers.items.len);
}
