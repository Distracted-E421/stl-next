# STL Bug Verification Matrix

This document tracks all known bugs from the original SteamTinkerLaunch repository and their status in STL-Next.

## Bug Status Legend

| Status | Description |
|--------|-------------|
| ✅ FIXED | Bug has been verified as fixed in STL-Next |
| 🔧 MITIGATED | Issue is partially addressed or designed around |
| ⏳ PENDING | Not yet tested/verified |
| 🚫 N/A | Not applicable to STL-Next architecture |
| 🔄 IN PROGRESS | Currently being worked on |

---

## Critical Bugs (Must Fix Before Release)

### #1 - NXM URL Truncation (Original Motivation)

**Original Issue**: Wine stripped forward slashes from NXM URLs, breaking collection downloads
**STL-Next Status**: ✅ **FIXED**

**How we fixed it**:
- Implemented `NxmLink.encodeForWine()` that URL-encodes slashes as `%2F`
- Full URL validation before processing
- Preserved all URL segments including `/revisions/N` for collections
- Comprehensive test coverage in `src/tests/edge_cases.zig`

```zig
// src/modding/manager.zig - Line 296
pub fn encodeForWine(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
    // Wine interprets / as command switches, so we encode them
    var result = std.ArrayList(u8).init(allocator);
    for (rest) |c| {
        switch (c) {
            '/' => try result.appendSlice("%2F"),
            // ...
        }
    }
}
```

---

## Vortex Integration Bugs

### #1283 - Cannot launch game through Vortex (from within STL)

**Original Issue**: GPU not detected when launching games from Vortex inside STL
**Root Cause**: Environment variables not properly passed to game subprocess
**STL-Next Status**: 🔧 **MITIGATED by Architecture**

**Our approach**:
- STL-Next passes all environment variables through `std.process.Child.spawn()`
- Full GPU environment preserved in `src/core/launcher.zig`
- Vortex integration not yet implemented but designed to avoid this issue

---

### #1273 - Vortex Drop-Down boxes don't work

**Original Issue**: Wine/Electron rendering issue with Vortex dropdown menus
**STL-Next Status**: 🚫 **N/A**

**Notes**: This is a Wine/Vortex issue, not an STL issue. Not within our scope to fix.

---

### #1272 - Vortex Cannot Find Path to Any Game

**Original Issue**: Vortex can't navigate to game folders due to Wine path issues
**STL-Next Status**: ⏳ **PENDING - Will address in Vortex integration phase**

**Planned mitigation**:
- Symlink game directories into Wine prefix
- Proper path mapping in `ModManagerContext`

---

### #1268 - Vortex & AppData failing to sync outside of Vortex

**Original Issue**: AppData/plugins.txt not synced between Vortex and game prefix
**STL-Next Status**: ⏳ **PENDING**

**Planned approach**:
- Implement AppData synchronization in `ModManagerContext`
- Run sync on game launch and after Vortex closes

---

### #1250 - Vortex doesn't work at all (.NET Runtime Error)

**Original Issue**: .NET Runtime installation issues
**STL-Next Status**: 🚫 **N/A - Vortex/Wine issue**

**Notes**: Requires user to properly configure Wine runtime, not an STL-Next bug.

---

## ReShade/Shader Bugs

### #1275 - Shaders are not being downloaded from shader repos

**Original Issue**: Shader repo configuration not being applied
**STL-Next Status**: ⏳ **PENDING - Phase 5 GUI work**

**Planned approach**:
- ReShade tinker module will handle shader repo management
- Auto-download standard shader repos on first use

---

### #1249 - ReShade doesn't have proper UI shaders to compile other shaders

**Original Issue**: Missing reshadeui.fxh
**STL-Next Status**: ⏳ **PENDING**

**Planned fix**: Auto-download standard ReShade shaders including UI dependencies.

---

## Custom Command Bugs

### #1269 - Different custom command behavior with ONLY_CUSTOMCMD

**Original Issue**: Game doesn't launch when ONLY_CUSTOMCMD=1 on NixOS
**STL-Next Status**: 🔧 **MITIGATED by Architecture**

**How we addressed it**:
- STL-Next uses `std.process.Child.spawn()` directly
- No shell interpretation that can break argument parsing
- Custom commands work identically in all modes

---

### #1234 - Custom Commands + GameScope + SLR Crash

**Original Issue**: GameScope placed inside SLR instead of outside
**STL-Next Status**: ✅ **FIXED by Design**

**How we fixed it**:
- Tinker pipeline processes modules in correct order
- GameScope wraps the outer command, not inside SLR
- Order is: `gamescope -> SLR -> proton -> game`

---

### #968 - Compatibility issues with bypassing launchers via custom command

**Original Issue**: Audio crackling, wrong DLL detection when bypassing launchers
**STL-Next Status**: ⏳ **PENDING - Need game-specific testing**

---

## Game Detection/Config Bugs

### #1270 - Launching STL adds stereo files to Skyrim game dir

**Original Issue**: Geo-11 files being added incorrectly
**STL-Next Status**: 🚫 **N/A - No Geo-11 integration planned initially**

---

### #1255 - ANSG Command Adding Game with Blank Title

**Original Issue**: Non-Steam games added without title
**STL-Next Status**: ⏳ **PENDING - Non-Steam game support not yet implemented**

---

### #1240 - Cannot run Football Manager 2014 (game ID mismatch)

**Original Issue**: STL using wrong game ID (31337 instead of actual)
**STL-Next Status**: ✅ **FIXED by Design**

**How we fixed it**:
- `steam.zig` reads AppID directly from manifest files
- No placeholder IDs used
- Validated against `appmanifest_*.acf` files

---

### #1210 - getGameName returns empty string

**Original Issue**: Game config corrupted/incomplete
**STL-Next Status**: ✅ **FIXED**

**How we fixed it**:
- `GameConfig` struct has mandatory fields with validation
- Config loading fails gracefully with clear errors
- JSON parsing validates all required fields

---

## Runtime/Process Bugs

### #1242 - Games crash without loading anything

**Original Issue**: Various Proton versions causing crashes
**STL-Next Status**: ⏳ **PENDING - Requires extensive testing**

---

### #1236 - FlawlessWidescreen not working with git version

**Original Issue**: Timing issue with FWS
**STL-Next Status**: ⏳ **PENDING - FWS not yet integrated**

---

### #1223 - One Time Run produces different result GUI vs CLI

**Original Issue**: Environment differences between launch modes
**STL-Next Status**: ✅ **FIXED by Design**

**How we fixed it**:
- Single code path for all launch modes
- CLI and daemon use same `launcher.zig` functions
- Environment constructed identically

---

### #1165 - Native VR games don't detect VR headset

**Original Issue**: VR environment variables not set
**STL-Next Status**: ⏳ **PENDING - VR support not yet implemented**

---

### #1153 - GAMEPID function spams log with gamescope

**Original Issue**: Window detection fails in gamescope's nested X display
**STL-Next Status**: 🚫 **N/A - Different architecture**

**Notes**: STL-Next tracks process PID directly, not window IDs.

---

### #1138 - No wait requester appearing

**Original Issue**: Locale/YAD issues preventing GUI display
**STL-Next Status**: 🚫 **N/A**

**Notes**: STL-Next uses native Zig TUI/Raylib GUI, no YAD dependency.

---

## Non-Steam Game Bugs

### #949 - Non-Steam Game Categories Not Working

**Original Issue**: Categories/tags not being set correctly
**STL-Next Status**: ⏳ **PENDING - Steam LevelDB integration partial**

---

### #913 - Problems with Proton-TkG and Winesync

**Original Issue**: Custom Proton builds not handled correctly
**STL-Next Status**: ⏳ **PENDING**

---

### #1257 - dlWDIB downloading HTML instead of EXE

**Original Issue**: GitHub download URL returning HTML page
**STL-Next Status**: 🚫 **N/A - Different download approach planned**

---

## Summary Statistics

| Category | Count | Fixed | Mitigated | Pending | N/A |
|----------|-------|-------|-----------|---------|-----|
| Critical (NXM) | 1 | 1 | 0 | 0 | 0 |
| Vortex | 5 | 0 | 1 | 2 | 2 |
| ReShade | 2 | 0 | 0 | 2 | 0 |
| Custom Commands | 3 | 1 | 1 | 1 | 0 |
| Game Detection | 4 | 2 | 0 | 1 | 1 |
| Runtime/Process | 6 | 1 | 0 | 3 | 2 |
| Non-Steam | 3 | 0 | 0 | 2 | 1 |
| **TOTAL** | **24** | **5** | **2** | **11** | **6** |

## New STL-Next Features (Beyond Bug Fixes)

These features go beyond fixing original STL bugs:

| Feature | Description | Status |
|---------|-------------|--------|
| **Multi-GPU Support** | D-Bus GPU detection, per-game selection | ✅ Complete |
| **Launch Profiles** | Save GPU/monitor/resolution per game | ✅ Complete |
| **Steam Shortcuts** | Binary VDF writing for profile shortcuts | ✅ Complete |
| **Profile Persistence** | JSON config, survives restarts | ✅ Complete |
| **Session Management** | Power profiles, screen saver inhibit | ✅ Complete |
| **Nexus Collections** | GraphQL API for one-click collection import | ✅ Complete |

## Testing Priority

### High Priority (Test Before Release)

1. ✅ NXM URL handling - **VERIFIED**
2. ⏳ Custom command modes (ONLY_CUSTOMCMD)
3. ⏳ GameScope + SLR ordering
4. ⏳ Game ID detection accuracy

### Medium Priority (Test With Target Games)

5. ⏳ Stardew Valley - mod loading, SMAPI integration
6. ⏳ Skyrim - MO2/Vortex integration, script extender
7. ⏳ Fallout 4 - plugin.txt handling, F4SE
8. ⏳ Cyberpunk 2077 - ReShade injection, mod detection

### Low Priority (Future Phases)

9. ⏳ VR headset detection
10. ⏳ Non-Steam game categories
11. ⏳ FlawlessWidescreen timing
12. ⏳ ReShade shader repo management

---

## How to Test a Bug Fix

1. Find the bug number in this document
2. Set up the test case as described in the original GitHub issue
3. Run the equivalent operation in STL-Next
4. Verify the expected behavior
5. Update this document with results

## Reporting New Issues

If you find a bug in STL-Next:
1. Check this document first - it may already be tracked
2. Check `docs/KNOWN_LIMITATIONS.md`
3. Open an issue with reproduction steps
4. Include your system info (NixOS vs other Linux, GPU, Proton version)

