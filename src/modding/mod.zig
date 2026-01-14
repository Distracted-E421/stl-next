//! Modding Module - Mod Manager Integration
//!
//! Support for:
//! - Mod Organizer 2 (MO2)
//! - Vortex
//! - NXM Protocol Handler

pub const manager = @import("manager.zig");

pub const ModManager = manager.ModManager;
pub const ModManagerConfig = manager.ModManagerConfig;
pub const ModManagerContext = manager.ModManagerContext;
pub const NxmLink = manager.NxmLink;
pub const handleNxmLink = manager.handleNxmLink;

test {
    _ = manager;
}

