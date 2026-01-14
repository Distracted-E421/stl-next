//! Tinker Module System
//! 
//! This module exports all available tinkers and provides
//! a registry initialization function.

const std = @import("std");

pub const interface = @import("interface.zig");
pub const Tinker = interface.Tinker;
pub const TinkerRegistry = interface.TinkerRegistry;
pub const Context = interface.Context;
pub const Priority = interface.Priority;

// Individual tinkers
pub const mangohud = @import("mangohud.zig");
pub const gamescope = @import("gamescope.zig");
pub const gamemode = @import("gamemode.zig");

/// Initialize a registry with all built-in tinkers
pub fn initBuiltinRegistry(allocator: std.mem.Allocator) !TinkerRegistry {
    var registry = TinkerRegistry.init(allocator);
    
    // Register all built-in tinkers
    try registry.register(&mangohud.mangohud_tinker);
    try registry.register(&gamescope.gamescope_tinker);
    try registry.register(&gamemode.gamemode_tinker);
    
    std.log.info("Tinker Registry: {d} tinkers registered", .{registry.tinkers.items.len});
    
    return registry;
}

/// List of all built-in tinker IDs
pub const builtin_tinker_ids = [_][]const u8{
    "mangohud",
    "gamescope", 
    "gamemode",
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "registry initialization" {
    var registry = try initBuiltinRegistry(std.testing.allocator);
    defer registry.deinit();
    
    try std.testing.expectEqual(@as(usize, 3), registry.tinkers.items.len);
}

test "tinkers sorted by priority" {
    var registry = try initBuiltinRegistry(std.testing.allocator);
    defer registry.deinit();
    
    // GameMode (OVERLAY_EARLY=40) should be first
    // MangoHud (OVERLAY=50) should be second
    // Gamescope (WRAPPER=80) should be last
    
    try std.testing.expect(registry.tinkers.items[0].priority <= registry.tinkers.items[1].priority);
    try std.testing.expect(registry.tinkers.items[1].priority <= registry.tinkers.items[2].priority);
}
