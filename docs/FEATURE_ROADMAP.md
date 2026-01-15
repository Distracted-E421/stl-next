# STL-Next Feature Roadmap & Comparison

This document tracks feature parity with the original SteamTinkerLaunch and planned enhancements.

## Feature Comparison: STL vs STL-Next

### ✅ Implemented in STL-Next

| Feature | Original STL | STL-Next | Notes |
|---------|-------------|----------|-------|
| Game Launch | ✅ | ✅ | `std.process.Child.spawn()` |
| Steam Discovery | ✅ | ✅ | Multi-library support |
| VDF Parsing | ✅ | ✅ | Both text and binary |
| Launch Options | ✅ | ✅ | From `localconfig.vdf` |
| MangoHud | ✅ | ✅ | Tinker module |
| Gamescope | ✅ | ✅ | Tinker module |
| GameMode | ✅ | ✅ | Tinker module |
| Per-Game Config | ✅ | ✅ | JSON format |
| Proton Selection | ✅ | ✅ | Auto-discovery |
| NXM Handler | ✅ (buggy) | ✅ (fixed!) | **URL truncation fixed** |
| Wait Requester | ✅ (yad) | ✅ (TUI/daemon) | IPC-based |
| Collections | ✅ (partial) | ✅ (LevelDB) | Read-only |

### 🚧 In Progress / Partial

| Feature | Original STL | STL-Next | Notes |
|---------|-------------|----------|-------|
| MO2 Integration | ✅ | 🚧 Basic | Detection only |
| Vortex Integration | ✅ | ✅ Basic | Auto-discovery, NXM forwarding |
| ReShade | ✅ | ✅ Phase 6 | Complete |
| SpecialK | ✅ | ✅ Phase 6 | Complete |
| vkBasalt | ✅ | ✅ Phase 6 | Complete |
| LatencyFleX | ❌ | ✅ Phase 6 | Complete |
| MultiApp | ❌ | ✅ Phase 6 | Complete |
| GUI | ✅ (yad) | ✅ Raylib | Wait Requester complete |
| Nexus Mods API | ❌ | ✅ Full | Premium downloads, tracking |

### ✅ Phase 5: Nix Packaging (Complete)

| Feature | Description | Status |
|---------|-------------|--------|
| Nix Flake | Build system with nixpkgs zig | ✅ |
| NixOS Module | System-wide installation | ✅ |
| Home Manager Module | User-level installation | ✅ |
| NXM Handler Registration | Desktop entry for nxm:// | ✅ |
| Zig 0.15.2 | Latest stable (upgraded from 0.14.0) | ✅ |

### ✅ Phase 5.5: GUI & API Integration (Complete)

| Feature | Description | Status |
|---------|-------------|--------|
| Raylib GUI | Wait Requester with visual countdown | ✅ |
| IPC Integration | GUI ↔ Daemon communication | ✅ |
| Wayland Support | HiDPI workarounds documented | ✅ |
| Vortex Integration | Auto-discovery, NXM forwarding | ✅ |
| Nexus Mods API | Full v1 API client | ✅ |
| API Key Management | Env, config, sops-nix, agenix | ✅ |
| CLI Parity | Full CLI/GUI feature parity | ✅ |

### ✅ Now Implemented (Phase 4.5)

| Feature | Original STL | STL-Next | Notes |
|---------|-------------|----------|-------|
| Winetricks | ✅ | ✅ | Full tinker with verb presets |
| Custom Commands | ✅ | ✅ | Pre/post launch, env vars |
| Non-Steam Games | ✅ | ✅ | Native, Windows, imports |
| SteamGridDB | ✅ | ✅ | Search, download, cache |

### ✅ Phase 6: Advanced Features (Complete)

| Feature | Original STL | STL-Next | Notes |
|---------|-------------|----------|-------|
| Boxtron/Roberta | ✅ | ✅ | DOSBox/ScummVM for classic games |
| OBS Capture | ❌ | ✅ | Recording/streaming integration |
| DLSS Tweaks | ❌ | ✅ | Quality presets, Frame Gen, Reflex |
| OptiScaler | ❌ | ✅ | Universal upscaler (FSR 3.1, XeSS) |

### ✅ Phase 7: Stardrop & Collections (Complete)

| Feature | Original STL | STL-Next | Notes |
|---------|-------------|----------|-------|
| Stardrop Integration | ❌ | ✅ | Native Linux mod manager |
| Nexus Collections Import | ❌ | ✅ | **KILLER FEATURE** |
| Profile Management | ❌ | ✅ | Import/export Stardrop profiles |
| Collections API | ❌ | ✅ | GraphQL v2 client |

### CLI Commands (Phase 7)

```bash
# Stardrop integration
stl-next stardrop              # Show Stardrop help
stl-next stardrop-discover     # Find Stardrop installation
stl-next stardrop-profiles     # List profiles
stl-next stardrop-create       # Create new profile
stl-next stardrop-export       # Export profile to JSON

# Nexus Collections (KILLER FEATURE!)
stl-next collection            # Show collection help
stl-next collection-info       # Show collection metadata
stl-next collection-import     # Import collection to Stardrop
stl-next collection-list       # List popular collections
```

## Bugs Fixed vs Original STL

### 🐛 Critical: NXM URL Truncation (Issue #1242)

**Original Bug**: Wine interprets `/` as command switches, truncating NXM URLs:

```bash
# Sent to Vortex:
nxm://stardewvalley/collections/tckf0m/revisions/100
# Received by Vortex:
nxm://stardewvalley/collections/tckf0m
# Result: "Invalid URL: invalid nxm url"
```

**STL-Next Fix**: URL-encode slashes before passing to Wine:

```zig
pub fn encodeForWine(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
    for (rest) |c| {
        switch (c) {
            '/' => try result.appendSlice("%2F"),
            ' ' => try result.appendSlice("%20"),
            '"' => try result.appendSlice("%22"),
            else => try result.append(c),
        }
    }
}
```

**Test Coverage**: `src/tests/edge_cases.zig`

### 🐛 Performance: Startup Time

**Original**: 2-5 seconds of bash parsing

**STL-Next**: Sub-100ms for all operations

| Operation | Original STL | STL-Next | Improvement |
|-----------|-------------|----------|-------------|
| Steam Discovery | ~500ms | 0.14ms | 3500x |
| Game Lookup | ~1000ms | 0.35ms | 2850x |
| Config Load | ~200ms | 0.5ms | 400x |

### 🐛 Reliability: JSON Parsing

**Original**: String searching in config files

**STL-Next**: `std.json.parseFromSlice()` with validation

## Enhancement Requests from Original STL

Based on GitHub issues from `sonic2kk/steamtinkerlaunch`:

### High Priority

| Issue | Description | STL-Next Status |
|-------|-------------|-----------------|
| #1259 | Proton Wayland toggle | ✅ Can add to config |
| #1274 | Multiple app launch | 🔄 Possible via daemon |
| #1276 | LSFG-VK support | ❌ Research needed |
| #1247 | Don't keep default configs | ✅ Easy to implement |
| #1187 | Skip GE-Proton download | N/A (no auto-download) |

### Medium Priority

| Issue | Description | STL-Next Status |
|-------|-------------|-----------------|
| #1244 | Keep MO2 open after game | 🔄 IPC supports this |
| #1225 | Multiple fork commands | 🔄 Tinker system |
| #1201 | VKDeviceChooser | ❌ New tinker needed |
| #1196 | DLSSTweaks | ❌ Research needed |
| #1188 | OptiScaler | ❌ Research needed |
| #1184 | Persistent REGEDIT | ❌ New feature |

### Low Priority

| Issue | Description | STL-Next Status |
|-------|-------------|-----------------|
| #1192 | UUU script path | ❌ Config option |
| #1185 | Reopen addnonsteamgame | N/A |
| #1182 | ReShade shader sources | ❌ Phase 5 |
| #1169 | Manual dependency paths | ❌ Config option |
| #1110 | Update MO2 to 2.5.0 | N/A (no installer) |

### Feature Requests (New)

| Issue | Description | Priority | Notes |
|-------|-------------|----------|-------|
| #1248 | DLSS Swapper | Medium | DLL management |
| #794 | LatencyFleX 1&2 | Medium | Low-latency gaming |
| #872 | Custom DXVK versions | Medium | Symlink approach |
| #860 | Winetricks + SLR | High | Compatibility |
| #992 | v14.0 Roadmap | Reference | Official roadmap |

## Phase 5 Roadmap

### Core Features

1. **Raylib GUI**
   - Wait requester with visual countdown
   - Config editor
   - Tinker toggles
   - Game art display

2. **Full Mod Manager Integration**
   - MO2 USVFS injection
   - Vortex download handling
   - Virtual filesystem setup
   - Profile management

3. **Additional Tinkers**
   - ReShade installer/manager
   - vkBasalt filter config
   - OBS Game Capture
   - LatencyFleX

### New Features (Beyond Original STL)

1. **Proton Wayland Toggle** (#1259)
   ```zig
   if (config.proton_wayland) {
       try env.put("PROTON_ENABLE_WAYLAND", "1");
   }
   ```

2. **VKDeviceChooser Integration** (#1201)
   ```zig
   if (config.vk_device_index) |idx| {
       try env.put("MESA_VK_DEVICE_SELECT", idx);
   }
   ```

3. **Multi-App Launch** (#1274)
   - Launch helper apps before game
   - Auto-close on game exit
   - Sequenced startup

4. **OptiScaler Support** (#1188)
   - DLL injection for upscaling
   - Config file generation
   - Per-game profiles

## Phase 6+ Ideas

### Platform Enhancements

1. **Steam Deck Mode**
   - Gamepad-friendly TUI
   - Quick switch overlay
   - Performance presets

2. **D-Bus Integration**
   - Desktop notifications
   - Session management
   - Power management

3. **Plugin System**
   - External tinker loading
   - Lua/Wren scripting
   - Community modules

### Community Features

1. **Config Sharing**
   - Export/import JSON
   - Per-game templates
   - Community presets

2. **ProtonDB Integration**
   - Auto-fetch configs
   - Report status
   - Suggestion engine

## Implementation Priority

### Immediate (Phase 5)

1. Raylib GUI basics
2. Proton Wayland toggle
3. ReShade tinker
4. Full MO2/Vortex

### Short-term (Phase 5.5)

1. ~~Winetricks integration~~ ✅ Done
2. ~~Custom commands~~ ✅ Done
3. ~~Non-Steam games~~ ✅ Done
4. Multi-app launch

### Medium-term (Phase 6)

1. DLSS/OptiScaler
2. LatencyFleX
3. VKDeviceChooser
4. ~~SteamGridDB~~ ✅ Done
5. Config sharing

### Long-term (Future)

1. Steam Deck mode
2. D-Bus integration
3. Plugin system
4. ProtonDB integration

## ✅ Phase 8: D-Bus Integration + GPU Selection (COMPLETE)

**KILLER FEATURE for multi-GPU systems!**

| Feature | Description | Status |
|---------|-------------|--------|
| **GPU Detection** | Auto-detect GPUs via switcheroo-control or /sys/class/drm | ✅ |
| **GPU Selection** | Per-game GPU preference (NVIDIA, Arc, AMD, discrete, etc.) | ✅ |
| **Power Profiles** | Auto-switch to performance mode via D-Bus | ✅ |
| **Screen Saver Inhibit** | Prevent lock during gaming | ✅ |
| **Desktop Notifications** | Rich game launch/exit notifications | ✅ |
| **Session Inhibit** | Prevent accidental logout | ✅ |

### CLI Commands (Phase 8)

```bash
stl-next gpu             # Alias for gpu-list
stl-next gpu-list        # List detected GPUs with details
stl-next gpu-test [pref] # Test GPU env var generation
stl-next session-test    # Show D-Bus session capabilities
```

## ✅ Phase 8.5: Launch Profiles (COMPLETE)

**No more remembering launch options!**

| Feature | Description | Status |
|---------|-------------|--------|
| **Profile Creation** | Save GPU, monitor, resolution, tinker settings | ✅ |
| **Profile Persistence** | JSON config in ~/.config/stl-next/games/ | ✅ |
| **--profile Flag** | Launch with specific profile | ✅ |
| **Active Profile** | Set default profile per game | ✅ |
| **Steam Shortcuts** | Binary VDF writing to shortcuts.vdf | ✅ |
| **Flag Parsing** | --gpu, --monitor, --resolution, --mangohud | ✅ |

### CLI Commands (Phase 8.5)

```bash
stl-next profile-create <AppID> <name> [--gpu X] [--monitor Y] [--resolution WxH@Hz]
stl-next profile-list <AppID>           # List all profiles
stl-next profile-set <AppID> <name>     # Set active profile
stl-next profile-delete <AppID> <name>  # Remove a profile
stl-next profile-shortcut <AppID> <name> # Create Steam library shortcut
stl-next run <AppID> --profile <name>   # Launch with specific profile
```

### Example Workflow

```bash
# 1. Create profiles for different setups
stl-next profile-create 413150 "Arc-1440p" --gpu arc --resolution 2560x1440@144 --mangohud
stl-next profile-create 413150 "NVIDIA-4K" --gpu nvidia --resolution 3840x2160@60

# 2. Set your preferred default
stl-next profile-set 413150 "Arc-1440p"

# 3. Create Steam shortcuts (appear in library!)
stl-next profile-shortcut 413150 "Arc-1440p"
stl-next profile-shortcut 413150 "NVIDIA-4K"

# 4. Launch (uses default or specify profile)
stl-next run 413150                       # Uses Arc-1440p (default)
stl-next run 413150 --profile "NVIDIA-4K" # Uses NVIDIA-4K
```

### Why D-Bus?

Steam doesn't always handle multi-GPU gracefully. D-Bus integration allows:

1. **Per-game GPU selection** - Force discrete GPU for demanding games
2. **Automatic power profile** - Performance mode during gaming
3. **Proper session handling** - No screen lock mid-boss-fight
4. **Desktop integration** - Notifications when games launch/crash

### Multi-GPU Environment Variables (Auto-set)

```bash
# For NVIDIA discrete:
__NV_PRIME_RENDER_OFFLOAD=1
__VK_LAYER_NV_optimus=NVIDIA_only
__GLX_VENDOR_LIBRARY_NAME=nvidia

# For Intel Arc:
MESA_VK_DEVICE_SELECT=8086:56a0
DRI_PRIME=pci-0000_03_00_0
```

See: [DBUS_INTEGRATION.md](DBUS_INTEGRATION.md)

---

## Contributing

We welcome contributions! Priority areas:

1. **Tinker modules** - Add new tinkers following `interface.zig`
2. **Tests** - Edge cases in `edge_cases.zig`
3. **Documentation** - Usage guides, examples
4. **Bug reports** - Especially for mod manager issues

See [ARCHITECTURE.md](ARCHITECTURE.md) for code structure.

