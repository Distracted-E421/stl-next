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
| Vortex Integration | ✅ | 🚧 Basic | Detection only |
| ReShade | ✅ | ❌ Phase 5 | Planned |
| SpecialK | ✅ | ❌ Phase 5 | Planned |
| GUI | ✅ (yad) | ❌ Phase 5 | Raylib planned |

### ❌ Not Yet Implemented

| Feature | Original STL | Priority | Planned Phase |
|---------|-------------|----------|---------------|
| Winetricks | ✅ | High | Phase 5 |
| Custom Commands | ✅ | High | Phase 5 |
| Non-Steam Games | ✅ | Medium | Phase 5 |
| SteamGridDB | ✅ | Medium | Phase 6 |
| Boxtron/Roberta | ✅ | Low | Phase 6 |
| Vkbasalt | ✅ | Low | Phase 5 |
| OBS Capture | ❌ | Low | Phase 6 |
| DLSS/FSR Tweaks | ❌ | Medium | Phase 5 |

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

1. Winetricks integration
2. Custom commands
3. Non-Steam games
4. Multi-app launch

### Medium-term (Phase 6)

1. DLSS/OptiScaler
2. LatencyFleX
3. VKDeviceChooser
4. Config sharing

### Long-term (Future)

1. Steam Deck mode
2. D-Bus integration
3. Plugin system
4. ProtonDB integration

## Contributing

We welcome contributions! Priority areas:

1. **Tinker modules** - Add new tinkers following `interface.zig`
2. **Tests** - Edge cases in `edge_cases.zig`
3. **Documentation** - Usage guides, examples
4. **Bug reports** - Especially for mod manager issues

See [ARCHITECTURE.md](ARCHITECTURE.md) for code structure.

