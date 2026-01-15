//! Tinker Module System (Phase 4.5 - Extended)
//!
//! No global state! All tinkers read config from Context.
//!
//! Phase 4.5 additions:
//!   - Winetricks tinker (install Windows components)
//!   - Custom commands tinker (pre/post launch scripts)

const std = @import("std");

pub const interface = @import("interface.zig");
pub const Tinker = interface.Tinker;
pub const TinkerRegistry = interface.TinkerRegistry;
pub const Context = interface.Context;
pub const Priority = interface.Priority;

// Built-in tinkers
pub const mangohud = @import("mangohud.zig");
pub const gamescope = @import("gamescope.zig");
pub const gamemode = @import("gamemode.zig");
pub const winetricks = @import("winetricks.zig");
pub const customcmd = @import("customcmd.zig");

/// Initialize a registry with all built-in tinkers
pub fn initBuiltinRegistry(allocator: std.mem.Allocator) !TinkerRegistry {
    var registry = TinkerRegistry.init(allocator);

    // Core tinkers
    try registry.register(&mangohud.mangohud_tinker);
    try registry.register(&gamescope.gamescope_tinker);
    try registry.register(&gamemode.gamemode_tinker);
    
    // Phase 4.5 tinkers
    try registry.register(&winetricks.winetricks_tinker);
    try registry.register(&customcmd.customcmd_tinker);

    std.log.info("Tinker Registry: {d} tinkers available", .{registry.tinkers.items.len});

    return registry;
}

pub const builtin_tinker_ids = [_][]const u8{
    "mangohud",
    "gamescope",
    "gamemode",
    "winetricks",
    "customcmd",
};

/// Re-export commonly used types
pub const WinetricksConfig = winetricks.WinetricksConfig;
pub const VerbPresets = winetricks.VerbPresets;
pub const CustomCommandsConfig = customcmd.CustomCommandsConfig;
pub const CommandEntry = customcmd.CommandEntry;
pub const CommandTemplates = customcmd.Templates;

test "registry initialization" {
    var registry = try initBuiltinRegistry(std.testing.allocator);
    defer registry.deinit();
    try std.testing.expectEqual(@as(usize, 5), registry.tinkers.items.len);
}
