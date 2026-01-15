const std = @import("std");
const client = @import("client.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// GPU MANAGER (Phase 8 - D-Bus)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Multi-GPU management via D-Bus and /sys filesystem:
//
//   1. switcheroo-control D-Bus service (net.hadess.SwitcherooControl)
//   2. /sys/class/drm enumeration (fallback)
//   3. PCI device scanning
//
// Solves: "Steam doesn't always pick the right GPU"
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const GpuError = error{
    NoGpuFound,
    SwitcherooNotAvailable,
    InvalidGpuIndex,
    EnvSetupFailed,
};

/// GPU vendor identification
pub const Vendor = enum {
    intel,
    nvidia,
    amd,
    other,

    pub fn fromPciId(vendor_id: u16) Vendor {
        return switch (vendor_id) {
            0x8086 => .intel, // Intel (both integrated AND Arc discrete)
            0x10de => .nvidia, // NVIDIA
            0x1002 => .amd, // AMD/ATI
            else => .other,
        };
    }

    pub fn fromName(name: []const u8) Vendor {
        if (std.mem.indexOf(u8, name, "Intel") != null or std.mem.indexOf(u8, name, "intel") != null) return .intel;
        if (std.mem.indexOf(u8, name, "NVIDIA") != null or std.mem.indexOf(u8, name, "nvidia") != null) return .nvidia;
        if (std.mem.indexOf(u8, name, "AMD") != null or std.mem.indexOf(u8, name, "amd") != null or
            std.mem.indexOf(u8, name, "Radeon") != null or std.mem.indexOf(u8, name, "radeon") != null) return .amd;
        return .other;
    }
};

/// Intel GPU class (integrated vs discrete Arc)
pub const IntelGpuClass = enum {
    integrated, // UHD, Iris, Iris Xe, Iris Plus
    arc, // Arc A-series (A310, A380, A580, A750, A770)
    arc_pro, // Arc Pro series
    unknown,

    /// Classify Intel GPU by device ID
    pub fn fromDeviceId(device_id: u16) IntelGpuClass {
        // Intel Arc A-series device IDs (Alchemist)
        // A770: 0x56A0, 0x56A1
        // A750: 0x56A5, 0x56A6
        // A580: 0x56B0 (estimated)
        // A380: 0x56A1 (mobile), 0x5692
        // A310: 0x5693
        return switch (device_id) {
            // Arc A770 (Limited Edition, Desktop)
            0x56A0, 0x56A1 => .arc,
            // Arc A750
            0x56A5, 0x56A6 => .arc,
            // Arc A580
            0x56B0, 0x56B1 => .arc,
            // Arc A380
            0x5690, 0x5691, 0x5692 => .arc,
            // Arc A310
            0x5693, 0x5694 => .arc,
            // Arc Pro series
            0x56C0, 0x56C1, 0x56C2 => .arc_pro,
            // Mobile Arc
            0x5697, 0x56A3, 0x56A4, 0x56B2, 0x56B3 => .arc,
            // Everything else (UHD, Iris, etc.) is integrated
            else => .integrated,
        };
    }
};

/// GPU preference for game launch
pub const GpuPreference = enum {
    integrated, // Power saving (Intel iGPU, AMD APU)
    discrete, // Performance (dedicated GPU)
    specific, // Specific GPU by index/name
    auto, // Let system decide (no env vars)
    nvidia, // Prefer NVIDIA GPU (for DLSS, RTX, CUDA games)
    intel_arc, // Prefer Intel Arc GPU (for XeSS, QuickSync)
    amd, // Prefer AMD GPU (for FSR native)
    by_monitor, // Match GPU to target monitor (future: compositor query)
};

/// GPU information
pub const GpuInfo = struct {
    name: []const u8,
    vendor: Vendor,
    pci_id: ?[]const u8, // "8086:56a0" format
    device_path: ?[]const u8, // "/dev/dri/card0"
    render_node: ?[]const u8, // "/dev/dri/renderD128"
    is_default: bool,
    is_discrete: bool,
    intel_class: ?IntelGpuClass, // Only set for Intel GPUs

    pub fn deinit(self: *GpuInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.pci_id) |p| allocator.free(p);
        if (self.device_path) |d| allocator.free(d);
        if (self.render_node) |r| allocator.free(r);
    }

    /// Check if this is a discrete (dedicated) GPU
    pub fn isDiscrete(self: *const GpuInfo) bool {
        return switch (self.vendor) {
            .nvidia => true, // All NVIDIA GPUs are discrete
            .amd => self.is_discrete, // AMD can be APU or discrete
            .intel => if (self.intel_class) |ic| (ic == .arc or ic == .arc_pro) else false,
            .other => self.is_discrete,
        };
    }

    /// Get a human-friendly description
    pub fn getDescription(self: *const GpuInfo) []const u8 {
        if (self.vendor == .intel) {
            if (self.intel_class) |ic| {
                return switch (ic) {
                    .integrated => "Integrated (UHD/Iris)",
                    .arc => "Discrete (Arc)",
                    .arc_pro => "Discrete (Arc Pro)",
                    .unknown => "Unknown",
                };
            }
        }
        return if (self.isDiscrete()) "Discrete" else "Integrated";
    }
};

/// Environment variables for GPU selection
pub const GpuEnvVars = struct {
    vars: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GpuEnvVars {
        return .{
            .vars = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GpuEnvVars) void {
        var it = self.vars.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.vars.deinit();
    }

    pub fn put(self: *GpuEnvVars, key: []const u8, value: []const u8) !void {
        const k = try self.allocator.dupe(u8, key);
        const v = try self.allocator.dupe(u8, value);
        try self.vars.put(k, v);
    }
};

/// GPU Manager
pub const GpuManager = struct {
    allocator: std.mem.Allocator,
    dbus: ?client.DbusClient,
    gpus: std.ArrayList(GpuInfo),
    has_switcheroo: bool,

    const Self = @This();

    // D-Bus service for switcheroo-control
    const SWITCHEROO_SERVICE = "net.hadess.SwitcherooControl";
    const SWITCHEROO_PATH = "/net/hadess/SwitcherooControl";
    const SWITCHEROO_INTERFACE = "net.hadess.SwitcherooControl";

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .dbus = client.DbusClient.init(allocator),
            .gpus = .{},
            .has_switcheroo = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.gpus.items) |*gpu| {
            gpu.deinit(self.allocator);
        }
        self.gpus.deinit(self.allocator);
        if (self.dbus) |*d| d.deinit();
    }

    /// Discover available GPUs
    pub fn discoverGpus(self: *Self) !void {
        // Clear existing
        for (self.gpus.items) |*gpu| {
            gpu.deinit(self.allocator);
        }
        self.gpus.clearRetainingCapacity();

        // Try switcheroo-control first
        if (self.dbus) |*dbus| {
            self.has_switcheroo = dbus.isServiceAvailable(SWITCHEROO_SERVICE);
            if (self.has_switcheroo) {
                try self.discoverViaSwitcheroo(dbus);
                if (self.gpus.items.len > 0) return;
            }
        }

        // Fallback to /sys/class/drm
        try self.discoverViaSysfs();
    }

    fn discoverViaSwitcheroo(self: *Self, dbus_client: *client.DbusClient) !void {
        _ = self;
        // Query HasDualGpu property
        var response = dbus_client.getProperty(
            SWITCHEROO_SERVICE,
            SWITCHEROO_PATH,
            SWITCHEROO_INTERFACE,
            "HasDualGpu",
        ) catch return;
        defer response.deinit();

        const has_dual = response.asBool();
        if (!has_dual) {
            std.log.info("GPU: switcheroo reports single GPU system", .{});
        }

        // Note: Full GPU enumeration would require parsing GetGPUs method
        // For now, we rely on sysfs fallback for detailed info
        std.log.info("GPU: switcheroo-control available, dual GPU: {}", .{has_dual});
    }

    fn discoverViaSysfs(self: *Self) !void {
        const drm_path = "/sys/class/drm";

        var dir = std.fs.openDirAbsolute(drm_path, .{ .iterate = true }) catch |err| {
            std.log.warn("GPU: Cannot open {s}: {s}", .{ drm_path, @errorName(err) });
            return;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            // Look for card* directories (not renderD*)
            if (!std.mem.startsWith(u8, entry.name, "card")) continue;
            if (std.mem.indexOf(u8, entry.name, "-") != null) continue; // Skip card0-DP-1 etc.

            const gpu_info = self.parseGpuFromSysfs(drm_path, entry.name) catch continue;
            try self.gpus.append(self.allocator, gpu_info);
        }

        std.log.info("GPU: Discovered {d} GPUs via sysfs", .{self.gpus.items.len});
    }

    fn parseGpuFromSysfs(self: *Self, drm_path: []const u8, card_name: []const u8) !GpuInfo {
        var buf: [512]u8 = undefined;

        // Read device/vendor
        const vendor_path = try std.fmt.bufPrint(&buf, "{s}/{s}/device/vendor", .{ drm_path, card_name });
        const vendor_id = self.readSysfsHex(vendor_path) catch 0;

        // Read device/device
        const device_path_str = try std.fmt.bufPrint(&buf, "{s}/{s}/device/device", .{ drm_path, card_name });
        const device_id = self.readSysfsHex(device_path_str) catch 0;

        // Determine vendor
        const vendor = Vendor.fromPciId(@intCast(vendor_id));

        // For Intel, classify as integrated or Arc
        const intel_class: ?IntelGpuClass = if (vendor == .intel)
            IntelGpuClass.fromDeviceId(@intCast(device_id))
        else
            null;

        // Build PCI ID string
        const pci_id = try std.fmt.allocPrint(self.allocator, "{x:0>4}:{x:0>4}", .{
            @as(u16, @intCast(vendor_id)),
            @as(u16, @intCast(device_id)),
        });

        // Device path
        const device_path = try std.fmt.allocPrint(self.allocator, "/dev/dri/{s}", .{card_name});

        // GPU name - more descriptive for Intel
        const name = switch (vendor) {
            .intel => if (intel_class) |ic| switch (ic) {
                .arc, .arc_pro => try std.fmt.allocPrint(self.allocator, "Intel Arc ({s})", .{pci_id}),
                .integrated => try std.fmt.allocPrint(self.allocator, "Intel UHD/Iris ({s})", .{pci_id}),
                .unknown => try std.fmt.allocPrint(self.allocator, "Intel GPU ({s})", .{pci_id}),
            } else try std.fmt.allocPrint(self.allocator, "Intel GPU ({s})", .{pci_id}),
            .nvidia => try std.fmt.allocPrint(self.allocator, "NVIDIA GPU ({s})", .{pci_id}),
            .amd => try std.fmt.allocPrint(self.allocator, "AMD GPU ({s})", .{pci_id}),
            .other => try std.fmt.allocPrint(self.allocator, "Unknown GPU ({s})", .{pci_id}),
        };

        // Determine if discrete
        const is_discrete = switch (vendor) {
            .nvidia => true, // All NVIDIA are discrete
            .intel => if (intel_class) |ic| (ic == .arc or ic == .arc_pro) else false,
            .amd => !std.mem.eql(u8, card_name, "card0"), // First AMD is usually APU
            .other => false,
        };

        return GpuInfo{
            .name = name,
            .vendor = vendor,
            .pci_id = pci_id,
            .device_path = device_path,
            .render_node = null,
            .is_default = std.mem.eql(u8, card_name, "card0"),
            .is_discrete = is_discrete,
            .intel_class = intel_class,
        };
    }

    fn readSysfsHex(self: *Self, path: []const u8) !u64 {
        _ = self;
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        var buf: [32]u8 = undefined;
        const bytes_read = try file.readAll(&buf);
        const content = std.mem.trim(u8, buf[0..bytes_read], " \t\n");

        // Remove 0x prefix if present
        const hex_str = if (std.mem.startsWith(u8, content, "0x"))
            content[2..]
        else
            content;

        return std.fmt.parseInt(u64, hex_str, 16);
    }

    /// Get environment variables for the specified GPU preference
    pub fn getEnvVars(self: *Self, preference: GpuPreference, specific_index: ?usize) !GpuEnvVars {
        var env = GpuEnvVars.init(self.allocator);
        errdefer env.deinit();

        switch (preference) {
            .auto => {
                // No env vars - let system decide
                return env;
            },
            .integrated => {
                // Find integrated GPU (usually card0, Intel/AMD APU)
                for (self.gpus.items) |gpu| {
                    if (!gpu.is_discrete) {
                        try self.setEnvForGpu(&env, gpu);
                        return env;
                    }
                }
            },
            .discrete => {
                // Find discrete GPU (NVIDIA, AMD dGPU, Intel Arc)
                for (self.gpus.items) |gpu| {
                    if (gpu.is_discrete) {
                        try self.setEnvForGpu(&env, gpu);
                        return env;
                    }
                }
            },
            .nvidia => {
                // Find NVIDIA GPU specifically (for DLSS, RTX, CUDA)
                for (self.gpus.items) |gpu| {
                    if (gpu.vendor == .nvidia) {
                        try self.setEnvForGpu(&env, gpu);
                        return env;
                    }
                }
                std.log.warn("GPU: No NVIDIA GPU found, using default", .{});
            },
            .intel_arc => {
                // Find Intel Arc GPU specifically (for XeSS, QuickSync)
                for (self.gpus.items) |gpu| {
                    if (gpu.vendor == .intel) {
                        if (gpu.intel_class) |ic| {
                            if (ic == .arc or ic == .arc_pro) {
                                try self.setEnvForGpu(&env, gpu);
                                return env;
                            }
                        }
                    }
                }
                std.log.warn("GPU: No Intel Arc GPU found, using default", .{});
            },
            .amd => {
                // Find AMD GPU specifically (for FSR native)
                for (self.gpus.items) |gpu| {
                    if (gpu.vendor == .amd) {
                        try self.setEnvForGpu(&env, gpu);
                        return env;
                    }
                }
                std.log.warn("GPU: No AMD GPU found, using default", .{});
            },
            .by_monitor => {
                // Future: Query compositor for GPU connected to target monitor
                // For now, log a message and fall back to auto
                std.log.info("GPU: Monitor-based GPU selection not yet implemented", .{});
                std.log.info("GPU: This would require querying KDE/Wayland compositor", .{});
                // TODO: Implement via D-Bus to KWin or wlr-randr
            },
            .specific => {
                if (specific_index) |idx| {
                    if (idx < self.gpus.items.len) {
                        try self.setEnvForGpu(&env, self.gpus.items[idx]);
                        return env;
                    }
                }
                return error.InvalidGpuIndex;
            },
        }

        return env;
    }

    fn setEnvForGpu(self: *Self, env: *GpuEnvVars, gpu: GpuInfo) !void {
        _ = self;

        switch (gpu.vendor) {
            .nvidia => {
                // NVIDIA PRIME render offload
                try env.put("__NV_PRIME_RENDER_OFFLOAD", "1");
                try env.put("__VK_LAYER_NV_optimus", "NVIDIA_only");
                try env.put("__GLX_VENDOR_LIBRARY_NAME", "nvidia");
            },
            .intel, .amd => {
                // Mesa device selection
                if (gpu.pci_id) |pci| {
                    try env.put("MESA_VK_DEVICE_SELECT", pci);
                }
                // DRI PRIME (for AMD/Intel)
                if (gpu.device_path) |path| {
                    // Extract card number for DRI_PRIME
                    if (std.mem.lastIndexOf(u8, path, "card")) |idx| {
                        const card_num = path[idx + 4 ..];
                        try env.put("DRI_PRIME", card_num);
                    }
                }
            },
            .other => {},
        }
    }

    /// List discovered GPUs
    pub fn listGpus(self: *Self) []const GpuInfo {
        return self.gpus.items;
    }

    /// Get GPU by vendor (returns first match)
    pub fn getGpuByVendor(self: *Self, vendor: Vendor) ?*const GpuInfo {
        for (self.gpus.items) |*gpu| {
            if (gpu.vendor == vendor) return gpu;
        }
        return null;
    }

    /// Get the best GPU for a specific game feature
    pub fn getGpuForFeature(self: *Self, feature: GameFeature) ?*const GpuInfo {
        return switch (feature) {
            .dlss, .rtx, .nvenc, .cuda => self.getGpuByVendor(.nvidia),
            .xess, .quicksync => blk: {
                // Need Intel Arc for XeSS, any Intel for QuickSync
                for (self.gpus.items) |*gpu| {
                    if (gpu.vendor == .intel) {
                        if (feature == .xess) {
                            if (gpu.intel_class) |ic| {
                                if (ic == .arc or ic == .arc_pro) break :blk gpu;
                            }
                        } else {
                            break :blk gpu; // QuickSync works on any Intel
                        }
                    }
                }
                break :blk null;
            },
            .fsr_native, .amf => self.getGpuByVendor(.amd),
            .fsr_generic, .vulkan => blk: {
                // FSR generic and Vulkan work on any GPU, prefer discrete
                for (self.gpus.items) |*gpu| {
                    if (gpu.is_discrete) break :blk gpu;
                }
                break :blk if (self.gpus.items.len > 0) &self.gpus.items[0] else null;
            },
        };
    }
};

/// Game features that may influence GPU selection
pub const GameFeature = enum {
    dlss, // NVIDIA DLSS upscaling
    xess, // Intel XeSS upscaling
    fsr_native, // AMD FSR (native, best on AMD)
    fsr_generic, // FSR via DXVK/vkBasalt (works on any GPU)
    rtx, // Ray tracing (NVIDIA RTX)
    nvenc, // NVIDIA hardware encoding
    quicksync, // Intel Quick Sync Video
    amf, // AMD Advanced Media Framework
    cuda, // NVIDIA CUDA compute
    vulkan, // Generic Vulkan (any GPU)
};

/// Monitor information (for future per-monitor GPU assignment)
pub const MonitorInfo = struct {
    name: []const u8, // e.g., "DP-1", "HDMI-A-1"
    make: ?[]const u8, // e.g., "Dell"
    model: ?[]const u8, // e.g., "U2720Q"
    serial: ?[]const u8,
    width: u32,
    height: u32,
    refresh_hz: u32,
    gpu_card: ?[]const u8, // e.g., "/dev/dri/card0" - which GPU drives this output
    is_primary: bool,
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "gpu manager init" {
    const allocator = std.testing.allocator;
    var mgr = GpuManager.init(allocator);
    defer mgr.deinit();

    try std.testing.expect(mgr.gpus.items.len == 0);
}

test "vendor from pci id" {
    try std.testing.expectEqual(Vendor.intel, Vendor.fromPciId(0x8086));
    try std.testing.expectEqual(Vendor.nvidia, Vendor.fromPciId(0x10de));
    try std.testing.expectEqual(Vendor.amd, Vendor.fromPciId(0x1002));
    try std.testing.expectEqual(Vendor.other, Vendor.fromPciId(0x0000));
}

