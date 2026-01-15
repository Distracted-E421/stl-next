//! Modding Module - Mod Manager Integration
//!
//! Support for:
//! - Mod Organizer 2 (MO2)
//! - Vortex
//! - Stardrop (native Linux)
//! - NXM Protocol Handler
//! - Nexus Collections Import (KILLER FEATURE!)

pub const manager = @import("manager.zig");
pub const stardrop = @import("stardrop.zig");
pub const vortex = @import("vortex.zig");

pub const ModManager = manager.ModManager;
pub const ModManagerConfig = manager.ModManagerConfig;
pub const ModManagerContext = manager.ModManagerContext;
pub const NxmLink = manager.NxmLink;
pub const handleNxmLink = manager.handleNxmLink;

// Stardrop exports
pub const StardropManager = stardrop.StardropManager;
pub const StardropProfile = stardrop.StardropProfile;
pub const StardropMod = stardrop.StardropMod;
pub const NexusCollection = stardrop.NexusCollection;
pub const ImportProgress = stardrop.ImportProgress;

test {
    _ = manager;
    _ = stardrop;
}

