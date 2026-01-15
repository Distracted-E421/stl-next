// ═══════════════════════════════════════════════════════════════════════════════
// D-BUS MODULE (Phase 8)
// ═══════════════════════════════════════════════════════════════════════════════
//
// D-Bus integration for desktop session management:
//
//   client.zig   - Low-level D-Bus client (busctl wrapper)
//   gpu.zig      - GPU selection via switcheroo-control
//   session.zig  - Power profiles, screen saver, notifications
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const client = @import("client.zig");
pub const gpu = @import("gpu.zig");
pub const session = @import("session.zig");

// Re-export main types
pub const DbusClient = client.DbusClient;
pub const DbusResponse = client.DbusResponse;
pub const DbusError = client.DbusError;

pub const GpuManager = gpu.GpuManager;
pub const GpuInfo = gpu.GpuInfo;
pub const GpuPreference = gpu.GpuPreference;
pub const Vendor = gpu.Vendor;

pub const SessionManager = session.SessionManager;
pub const PowerProfile = session.PowerProfile;

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test {
    @import("std").testing.refAllDecls(@This());
}

