# D-Bus Integration Design (Phase 8)

## 🎯 Why D-Bus?

D-Bus integration solves several pain points, especially for multi-GPU systems:

1. **GPU Selection & Switching** - Proper PRIME offload and `switcheroo-control`
2. **Power Profile Management** - Auto-switch to performance mode during gaming
3. **Session Management** - Prevent accidental logout, inhibit screen lock
4. **Desktop Notifications** - Game launch status, mod events, errors
5. **GameMode Integration** - Native D-Bus API instead of library wrapper

## 🖥️ Target D-Bus Services

### 1. GPU Switching (`net.hadess.SwitcherooControl`)

For hybrid graphics systems (Intel/NVIDIA, Intel/AMD):

```xml
<!-- org.freedesktop.switcheroo-control -->
<interface name="net.hadess.SwitcherooControl">
  <property name="HasDualGpu" type="b" access="read"/>
  <property name="NumGPUs" type="u" access="read"/>
  <method name="GetGPUs">
    <arg name="gpus" type="a(sss)" direction="out"/>
    <!-- Returns: (name, device_path, environment_variable) -->
  </method>
</interface>
```

**STL-Next Usage**:
```zig
// Query available GPUs
const gpus = try dbus.call("net.hadess.SwitcherooControl", "/net/hadess/SwitcherooControl", "GetGPUs");
// Returns: [("Intel Arc A770", "/dev/dri/card0", "DRI_PRIME=pci-0000_03_00_0"),
//           ("NVIDIA RTX 2080", "/dev/dri/card1", "__NV_PRIME_RENDER_OFFLOAD=1")]

// Set per-game GPU
if (game_config.gpu.prefer_discrete) {
    try env.put("DRI_PRIME", "1");
    try env.put("__NV_PRIME_RENDER_OFFLOAD", "1");
    try env.put("__VK_LAYER_NV_optimus", "NVIDIA_only");
    try env.put("__GLX_VENDOR_LIBRARY_NAME", "nvidia");
}
```

### 2. Power Profiles (`net.hadess.PowerProfiles`)

Auto-switch to performance mode when gaming:

```xml
<interface name="net.hadess.PowerProfiles">
  <property name="ActiveProfile" type="s" access="readwrite"/>
  <!-- Values: "power-saver", "balanced", "performance" -->
  <property name="PerformanceInhibited" type="s" access="read"/>
  <property name="PerformanceDegraded" type="s" access="read"/>
</interface>
```

**STL-Next Usage**:
```zig
pub const PowerProfileManager = struct {
    original_profile: []const u8,
    
    pub fn setPerformanceMode(self: *Self) !void {
        // Save current profile
        self.original_profile = try dbus.getProperty(
            "net.hadess.PowerProfiles",
            "/net/hadess/PowerProfiles",
            "ActiveProfile"
        );
        
        // Switch to performance
        try dbus.setProperty(
            "net.hadess.PowerProfiles",
            "/net/hadess/PowerProfiles",
            "ActiveProfile",
            "performance"
        );
    }
    
    pub fn restoreProfile(self: *Self) !void {
        try dbus.setProperty(..., self.original_profile);
    }
};
```

### 3. Screen Saver Inhibit (`org.freedesktop.ScreenSaver`)

Prevent screen lock during gaming:

```xml
<interface name="org.freedesktop.ScreenSaver">
  <method name="Inhibit">
    <arg name="application_name" type="s" direction="in"/>
    <arg name="reason_for_inhibit" type="s" direction="in"/>
    <arg name="cookie" type="u" direction="out"/>
  </method>
  <method name="UnInhibit">
    <arg name="cookie" type="u" direction="in"/>
  </method>
</interface>
```

**STL-Next Usage**:
```zig
// On game launch
const cookie = try dbus.call(
    "org.freedesktop.ScreenSaver",
    "/org/freedesktop/ScreenSaver",
    "Inhibit",
    .{ "STL-Next", "Gaming session active" }
);

// On game exit
try dbus.call(..., "UnInhibit", .{cookie});
```

### 4. Desktop Notifications (`org.freedesktop.Notifications`)

Rich notifications for game events:

```xml
<interface name="org.freedesktop.Notifications">
  <method name="Notify">
    <arg name="app_name" type="s" direction="in"/>
    <arg name="replaces_id" type="u" direction="in"/>
    <arg name="app_icon" type="s" direction="in"/>
    <arg name="summary" type="s" direction="in"/>
    <arg name="body" type="s" direction="in"/>
    <arg name="actions" type="as" direction="in"/>
    <arg name="hints" type="a{sv}" direction="in"/>
    <arg name="expire_timeout" type="i" direction="in"/>
    <arg name="id" type="u" direction="out"/>
  </method>
</interface>
```

**STL-Next Usage**:
```zig
pub fn notifyGameLaunch(game_name: []const u8, app_id: u32) !void {
    _ = try dbus.call(
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        "Notify",
        .{
            "STL-Next",                    // app_name
            @as(u32, 0),                   // replaces_id
            "steam",                       // app_icon
            "Game Launching",              // summary
            std.fmt.allocPrint(allocator, 
                "Starting {s} (AppID: {d})", .{game_name, app_id}),
            &[_][]const u8{},              // actions
            .{},                           // hints
            @as(i32, 5000),                // timeout (ms)
        }
    );
}
```

### 5. GameMode D-Bus (`com.feralinteractive.GameMode`)

Native GameMode integration without libgamemode:

```xml
<interface name="com.feralinteractive.GameMode">
  <method name="RegisterGame">
    <arg name="pid" type="i" direction="in"/>
    <arg name="status" type="i" direction="out"/>
  </method>
  <method name="UnregisterGame">
    <arg name="pid" type="i" direction="in"/>
    <arg name="status" type="i" direction="out"/>
  </method>
  <method name="QueryStatus">
    <arg name="pid" type="i" direction="in"/>
    <arg name="status" type="i" direction="out"/>
  </method>
</interface>
```

### 6. Session Management (`org.gnome.SessionManager` / `org.kde.Shutdown`)

Prevent accidental logout during gaming:

```zig
// GNOME
try dbus.call(
    "org.gnome.SessionManager",
    "/org/gnome/SessionManager",
    "Inhibit",
    .{
        "STL-Next",           // app_id
        @as(u32, 0),          // toplevel_xid (0 for none)
        "Gaming session",     // reason
        @as(u32, 8),          // flags: INHIBIT_LOGOUT | INHIBIT_SWITCH
    }
);

// KDE
try dbus.call(
    "org.kde.Shutdown",
    "/Shutdown",
    "interactiveLogoutConfirm"
);
```

## 🔧 Implementation Plan

### Phase 8.1: D-Bus Foundation

```zig
// src/dbus/client.zig
pub const DbusClient = struct {
    connection: *sd_bus,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        // Connect to session bus
    }
    
    pub fn call(
        self: *Self,
        destination: []const u8,
        path: []const u8,
        interface: []const u8,
        method: []const u8,
        args: anytype,
    ) !DbusResponse {
        // Generic D-Bus method call
    }
    
    pub fn getProperty(self: *Self, ...) ![]const u8 {}
    pub fn setProperty(self: *Self, ...) !void {}
};
```

### Phase 8.2: GPU Manager

```zig
// src/dbus/gpu.zig
pub const GpuManager = struct {
    dbus: *DbusClient,
    gpus: []GpuInfo,
    
    pub const GpuInfo = struct {
        name: []const u8,
        vendor: Vendor,
        device_path: []const u8,
        env_vars: std.StringHashMap([]const u8),
    };
    
    pub const Vendor = enum { intel, nvidia, amd, other };
    
    pub fn discoverGpus(self: *Self) !void {
        // Query switcheroo-control or fallback to /sys/class/drm
    }
    
    pub fn selectGpu(self: *Self, preference: GpuPreference) ![]EnvVar {
        // Returns environment variables to set
    }
    
    pub const GpuPreference = enum {
        integrated,   // Power saving
        discrete,     // Performance
        specific,     // By name/index
        auto,         // Let system decide
    };
};
```

### Phase 8.3: Session Manager

```zig
// src/dbus/session.zig
pub const SessionManager = struct {
    dbus: *DbusClient,
    inhibit_cookies: std.ArrayList(u32),
    original_power_profile: ?[]const u8,
    
    pub fn beginGamingSession(self: *Self, game_name: []const u8) !void {
        // 1. Switch to performance profile
        // 2. Inhibit screen saver
        // 3. Inhibit logout
        // 4. Register with GameMode
        // 5. Send notification
    }
    
    pub fn endGamingSession(self: *Self) !void {
        // Reverse all of the above
    }
};
```

## 📋 Configuration

```json
{
  "app_id": 413150,
  "dbus": {
    "enabled": true,
    "gpu_selection": {
      "enabled": true,
      "preference": "discrete",
      "specific_gpu": null
    },
    "power_profile": {
      "enabled": true,
      "gaming_profile": "performance",
      "restore_on_exit": true
    },
    "session": {
      "inhibit_screensaver": true,
      "inhibit_logout": true,
      "gamemode_dbus": true
    },
    "notifications": {
      "on_launch": true,
      "on_exit": true,
      "on_error": true,
      "on_mod_update": false
    }
  }
}
```

## 🎮 Multi-GPU Use Cases

### Use Case 1: Intel + NVIDIA (Your Setup)

```bash
# Problem: Steam sometimes picks wrong GPU
# Solution: STL-Next D-Bus integration

# Arc A770 (iGPU-like, display + compute)
# RTX 2080 (dGPU, gaming)

# Per-game config:
{
  "dbus": {
    "gpu_selection": {
      "preference": "discrete",  // Use RTX 2080 for this game
    }
  }
}
```

**Environment set automatically**:
```bash
__NV_PRIME_RENDER_OFFLOAD=1
__VK_LAYER_NV_optimus=NVIDIA_only
__GLX_VENDOR_LIBRARY_NAME=nvidia
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
```

### Use Case 2: Prefer Intel Arc (OpenCL, AV1)

For games that benefit from Arc features:

```json
{
  "dbus": {
    "gpu_selection": {
      "preference": "integrated",
      "specific_gpu": "Intel Arc A770"
    }
  }
}
```

**Environment set**:
```bash
MESA_VK_DEVICE_SELECT=8086:56a0  # Intel Arc A770 PCI ID
DRI_PRIME=pci-0000_03_00_0
```

### Use Case 3: Let Game Decide

Some games handle multi-GPU well:

```json
{
  "dbus": {
    "gpu_selection": {
      "preference": "auto"
    }
  }
}
```

## 🔗 Dependencies

### Option A: systemd sd-bus (Recommended for NixOS)

```zig
// Pure Zig bindings to sd-bus
const c = @cImport({
    @cInclude("systemd/sd-bus.h");
});
```

NixOS already has systemd, so no additional deps.

### Option B: libdbus-1

```zig
const c = @cImport({
    @cInclude("dbus/dbus.h");
});
```

### Option C: Subprocess (Fallback)

```zig
// Use dbus-send / busctl for simple cases
const result = try std.process.Child.run(.{
    .allocator = allocator,
    .argv = &.{
        "busctl", "get-property",
        "net.hadess.PowerProfiles",
        "/net/hadess/PowerProfiles",
        "net.hadess.PowerProfiles",
        "ActiveProfile",
    },
});
```

## 🚀 Benefits Summary

| Feature | Without D-Bus | With D-Bus |
|---------|--------------|------------|
| GPU Selection | Manual env vars | Auto-detect + per-game |
| Power Profile | Manual tuned | Auto performance mode |
| Screen Lock | Still activates | Properly inhibited |
| Notifications | None | Rich desktop notifications |
| GameMode | Library wrapper | Native D-Bus API |
| Session Safety | Can logout during game | Properly inhibited |

## 📊 Priority for Multi-GPU Users

1. **HIGH**: GPU selection via switcheroo-control
2. **HIGH**: Power profile switching
3. **MEDIUM**: Screen saver inhibit
4. **MEDIUM**: Desktop notifications
5. **LOW**: GameMode D-Bus (already works via library)
6. **LOW**: Session inhibit (rare use case)

---

## 🖥️ Monitor-Based GPU Selection (Advanced)

### The Dream: Runtime GPU Hotswapping

**Ideal scenario**: Game window moves from Monitor A (Arc A770) to Monitor B (RTX 2080), and the game automatically switches which GPU renders it.

**Reality**: This is **not technically possible** without restarting the game.

### Why Runtime Hotswapping Doesn't Work

1. **GPU Context Binding**: Vulkan `VkDevice` / OpenGL contexts are bound to a specific GPU at creation
2. **VRAM Resources**: Textures, buffers, shaders live in specific GPU memory
3. **Pipeline State**: All graphics pipelines would need reconstruction
4. **Shader Recompilation**: Driver-compiled shaders are GPU-specific

Switching mid-game would essentially require a "restart the graphics engine" operation that most games don't support.

### What IS Possible

#### 1. Smart Launch-Time Selection

```bash
# STL-Next can detect which GPU drives which monitor
stl-next gpu-test monitor  # Future: Query compositor

# Then set correct GPU at launch
stl-next run 413150 --gpu nvidia    # Force RTX 2080
stl-next run 413150 --gpu arc       # Force Arc A770
```

#### 2. Feature-Based GPU Selection

```bash
# Automatically pick best GPU for game features
stl-next run 413150 --gpu-for dlss   # → NVIDIA
stl-next run 413150 --gpu-for xess   # → Intel Arc
stl-next run 413150 --gpu-for fsr    # → AMD (or any)
```

#### 3. Compositor-Level Multi-GPU (KDE Plasma 6 / Wayland)

With Wayland compositors that support multi-GPU:
- Each monitor can be assigned to a GPU
- Games render on one GPU
- Compositor copies frames to other monitor (~1-2ms latency)

This happens at the **compositor level**, not the game level.

#### 4. Restart-Based Switching (Future)

STL-Next could detect when a game window moves to a different monitor and offer:
- Notification: "Game is on Monitor B (RTX 2080). Restart on that GPU?"
- Auto-restart option with correct GPU environment

### Implementation Plan

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Detect GPUs | ✅ Done |
| 2 | Vendor-specific selection | ✅ Done |
| 3 | Feature-based selection | 🚧 Design done |
| 4 | Query compositor for monitor→GPU mapping | 📋 Planned |
| 5 | Smart launch suggestion | 📋 Planned |
| 6 | Restart-on-move detection | 📋 Future |

### Technical Notes for Monitor Detection

#### KDE Plasma (via D-Bus)

```bash
# Query KWin for output configuration
busctl --user call org.kde.KWin \
    /KWin \
    org.kde.KWin \
    supportInformation
```

#### wlr-randr (wlroots compositors)

```bash
wlr-randr --json | jq '.[] | {name, make, model}'
```

#### DRM/sysfs

```bash
# List outputs per GPU
ls /sys/class/drm/card*/card*-*/
# card0-DP-1, card0-HDMI-A-1, card1-DP-2, etc.
```

---

**This feature directly addresses the "2 GPUs + Steam" pain point!**

