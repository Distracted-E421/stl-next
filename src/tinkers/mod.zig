//! Tinker Module System (Phase 6 - Full Featured)
//!
//! No global state! All tinkers read config from Context.
//!
//! Phase 4.5 additions:
//!   - Winetricks tinker (install Windows components)
//!   - Custom commands tinker (pre/post launch scripts)
//!
//! Phase 6 additions:
//!   - ReShade (shader injection)
//!   - vkBasalt (Vulkan post-processing)
//!   - SpecialK (HDR, frame pacing)
//!   - LatencyFleX (low-latency gaming)
//!   - MultiApp (helper app launcher)

const std = @import("std");

pub const interface = @import("interface.zig");
pub const Tinker = interface.Tinker;
pub const TinkerRegistry = interface.TinkerRegistry;
pub const Context = interface.Context;
pub const Priority = interface.Priority;

// Core tinkers (Phase 3)
pub const mangohud = @import("mangohud.zig");
pub const gamescope = @import("gamescope.zig");
pub const gamemode = @import("gamemode.zig");

// Extended tinkers (Phase 4.5)
pub const winetricks = @import("winetricks.zig");
pub const customcmd = @import("customcmd.zig");

// Advanced tinkers (Phase 6)
pub const reshade = @import("reshade.zig");
pub const vkbasalt = @import("vkbasalt.zig");
pub const specialk = @import("specialk.zig");
pub const latencyflex = @import("latencyflex.zig");
pub const multiapp = @import("multiapp.zig");

/// Initialize a registry with all built-in tinkers
pub fn initBuiltinRegistry(allocator: std.mem.Allocator) !TinkerRegistry {
    var registry = TinkerRegistry.init(allocator);

    // Core tinkers (Phase 3)
    try registry.register(&mangohud.mangohud_tinker);
    try registry.register(&gamescope.gamescope_tinker);
    try registry.register(&gamemode.gamemode_tinker);

    // Extended tinkers (Phase 4.5)
    try registry.register(&winetricks.winetricks_tinker);
    try registry.register(&customcmd.customcmd_tinker);

    // Advanced tinkers (Phase 6)
    try registry.register(&reshade.reshade_tinker);
    try registry.register(&vkbasalt.vkbasalt_tinker);
    try registry.register(&specialk.specialk_tinker);
    try registry.register(&latencyflex.latencyflex_tinker);
    try registry.register(&multiapp.multiapp_tinker);

    std.log.info("Tinker Registry: {d} tinkers available", .{registry.tinkers.items.len});

    return registry;
}

pub const builtin_tinker_ids = [_][]const u8{
    // Core
    "mangohud",
    "gamescope",
    "gamemode",
    // Extended
    "winetricks",
    "customcmd",
    // Advanced
    "reshade",
    "vkbasalt",
    "specialk",
    "latencyflex",
    "multiapp",
};

/// Re-export commonly used types
// Phase 4.5
pub const WinetricksConfig = winetricks.WinetricksConfig;
pub const VerbPresets = winetricks.VerbPresets;
pub const CustomCommandsConfig = customcmd.CustomCommandsConfig;
pub const CommandEntry = customcmd.CommandEntry;
pub const CommandTemplates = customcmd.Templates;

// Phase 6
pub const ReshadeConfig = reshade.ReshadeConfig;
pub const ReshadeRenderer = reshade.ReshadeRenderer;
pub const VkbasaltConfig = vkbasalt.VkbasaltConfig;
pub const VkbasaltEffect = vkbasalt.VkbasaltEffect;
pub const SpecialkConfig = specialk.SpecialkConfig;
pub const SpecialkFeature = specialk.SpecialkFeature;
pub const LatencyflexConfig = latencyflex.LatencyflexConfig;
pub const LatencyflexMode = latencyflex.LatencyflexMode;
pub const MultiappConfig = multiapp.MultiappConfig;
pub const HelperApp = multiapp.HelperApp;
pub const MultiappPresets = multiapp.Presets;

test "registry initialization" {
    var registry = try initBuiltinRegistry(std.testing.allocator);
    defer registry.deinit();
    try std.testing.expectEqual(@as(usize, 10), registry.tinkers.items.len);
}
