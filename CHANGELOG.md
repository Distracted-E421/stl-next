# Changelog

All notable changes to STL-Next are documented in this file.

## [0.5.0-alpha] - Extended Features

### Added

#### Winetricks Integration (`src/tinkers/winetricks.zig`)
- Automatic winetricks integration during prefix preparation
- Per-game verb configuration
- Preset verb collections (basic, dx_essentials, dotnet_legacy, audio_fix, full)
- Silent mode support for unattended installation
- Force reinstall option
- Integration with Proton's Wine binary

#### Custom Commands (`src/tinkers/customcmd.zig`)
- Pre-launch commands (run before game starts)
- Post-exit commands (run after game exits)
- On-error commands (run if launch fails)
- Environment variables available to commands ($STL_APP_ID, $STL_GAME_NAME, etc.)
- Per-command timeouts
- Background command support
- AppID filtering for game-specific commands
- Built-in command templates (kill discord, CPU governor, syncthing, notifications)

#### Non-Steam Games (`src/engine/nonsteam.zig`)
- Full support for non-Steam games
- Platform types: native, windows, flatpak, appimage, snap, web
- Game sources: manual, gog, epic, amazon, ea, ubisoft, itch, humble, gamejolt
- CLI commands: add-game, remove-game, list-nonsteam, import-heroic
- Heroic Games Launcher import (Epic/GOG/Amazon)
- All STL-Next features work with non-Steam games

#### SteamGridDB Integration (`src/engine/steamgriddb.zig`)
- Game artwork fetching from SteamGridDB
- Image types: grid (600x900), hero (1920x620), logo, icon
- Style preferences (alternate, blurred, material, etc.)
- CLI commands: artwork, search-game
- Image caching to ~/.cache/stl-next/steamgriddb/
- Works with both Steam AppIDs and SteamGridDB game IDs

#### Documentation
- `docs/WINETRICKS_GUIDE.md` - Complete winetricks integration guide
- `docs/CUSTOM_COMMANDS.md` - Custom commands configuration guide
- `docs/NONSTEAM_GAMES.md` - Non-Steam games management guide
- `docs/STEAMGRIDDB_GUIDE.md` - SteamGridDB artwork integration guide

### Changed

- Version bumped to 0.5.0-alpha
- Extended GameConfig with winetricks, custom_commands, and steamgriddb options
- TinkerRegistry now includes winetricks and customcmd tinkers (5 total)
- Updated help text with new commands

---

## [0.4.5-alpha] - Bug Verification & Documentation

### Added

#### Bug Verification
- **BUG_VERIFICATION_MATRIX.md** - Comprehensive tracking of all 24 original STL bugs
  - 5 confirmed fixed in STL-Next
  - 2 mitigated by architecture
  - 11 pending testing
  - 6 not applicable (different architecture)

#### Platform Documentation
- **NIXOS_INSTALLATION.md** - Dedicated guide for NixOS users
  - Flake-based installation
  - Home Manager integration
  - NixOS-specific troubleshooting
  - GPU driver configuration

#### Testing Infrastructure
- **GAME_TESTING_GUIDE.md** - Test procedures for target games:
  - Stardew Valley (413150) - SMAPI, NXM mods
  - Skyrim SE (489830) - MO2/Vortex, SKSE
  - Fallout 4 (377160) - F4SE, plugins.txt
  - Cyberpunk 2077 (1091500) - ReShade, performance

#### Stardrop Integration Research
- **STARDROP_INTEGRATION.md** - First-class Stardrop support plan
  - Detection strategy for Linux native mod manager
  - NXM link forwarding architecture
  - Nexus Collections API integration
  - NixOS packaging approach

### Research

- Analyzed 24 open bugs from original SteamTinkerLaunch
- Researched Stardrop mod manager (600+ stars, active development)
- Documented Nexus Collections API for future integration
- Identified critical path for pre-release testing

### Fixed Bug Categories

| Category | Fixed | Mitigated | Pending | N/A |
|----------|-------|-----------|---------|-----|
| Critical (NXM) | 1 | 0 | 0 | 0 |
| Vortex | 0 | 1 | 2 | 2 |
| Custom Commands | 1 | 1 | 1 | 0 |
| Game Detection | 2 | 0 | 1 | 1 |
| **Total** | **5** | **2** | **11** | **6** |

---

## [0.4.0-alpha] - Phase 4 Complete

### Added

#### IPC System
- **Unix Domain Socket server** for daemon/client communication
- **JSON protocol** with typed actions and responses
- **Non-blocking polling** for responsive countdown
- **Retry logic** in client with configurable timeout
- **Comprehensive error types**: `DaemonNotRunning`, `ConnectionTimeout`, `InvalidResponse`

#### Wait Requester Daemon
- **Configurable countdown** (default 10s, `STL_COUNTDOWN` env var)
- **Skip option** via `STL_SKIP_WAIT`
- **Pause/resume** during countdown
- **Tinker toggling** from TUI client
- **Config save** on launch with updated tinker states

#### TUI Client
- **Terminal-based UI** connecting to daemon
- **Real-time countdown display**
- **Keyboard controls**: P (pause), R (resume), L (launch), Q (quit)
- **Tinker toggles**: M (MangoHud), G (Gamescope)
- **Status display** with game info

#### NXM Protocol Handler
- **Full URL parsing** for mods and collections
- **🐛 BUG FIX**: URL encoding for Wine compatibility
- **Revision preservation** - the critical collection bug fix
- **Query parameter extraction** (key, expires)
- **Validation** with specific error types

#### Mod Manager Detection
- **MO2 path detection** in common Wine locations
- **Vortex detection** 
- **USVFS DLL override** configuration
- **Context integration** for launch pipeline

### Changed

- **Config system** now uses `std.json.parseFromSlice()` instead of string searching
- **Launch pipeline** uses `std.process.Child.spawn()` instead of `execvpe`
- **Error handling** is now comprehensive with specific error types
- **Memory management** improved with proper allocator handling

### Fixed

- **NXM URL truncation** - Wine was interpreting `/` as command switches
- **VDF directory handling** - Correct mutable pointer usage
- **Launch options extraction** - Proper navigation of localconfig.vdf
- **LevelDB path** - Corrected to `config/htmlcache/Default/Local Storage/leveldb`
- **Optional formatting** - Fixed `{?}` specifiers for optional types

### Documentation

- **IPC_PROTOCOL.md** - Full protocol specification
- **ARCHITECTURE.md** - Code structure overview
- **FEATURE_ROADMAP.md** - Comparison with original STL
- **NXM_HANDLING.md** - Detailed guide on the bug fix

## [0.3.5-alpha] - Phase 3.5 Hardening

### Added

- **Actual game execution** - replaced stub with `std.process.Child.spawn()`
- **Steam launch options** parsing from `localconfig.vdf`
- **Comprehensive test suite** in `src/tests/edge_cases.zig`
- **JSON config parsing** with proper validation

### Changed

- **Config loading** hardened against malformed JSON
- **VDF parser** handles edge cases better
- **Tinker system** passes config through Context (no global state)

### Fixed

- **execvpe type errors** - Simplified to Child.spawn()
- **Directory pointer mutability** in steam.zig
- **JSON escape handling** in config serialization

## [0.3.0-alpha] - Phase 3 Tinkers

### Added

- **Tinker interface** (`src/tinkers/interface.zig`)
- **MangoHud tinker** with configurable options
- **Gamescope tinker** with resolution/FSR settings
- **GameMode tinker** with renice support
- **Tinker registry** with priority-based execution
- **Per-game JSON configuration**

### Changed

- **Launch pipeline** integrates tinker system
- **Environment building** is now modular

## [0.2.0-alpha] - Phase 2 Performance

### Added

- **Binary VDF streaming parser** for appinfo.vdf
- **Fast AppID seeking** - O(1) block skipping
- **LevelDB reader** for Steam collections
- **Hidden games detection**
- **Collection membership** tracking

### Performance

| Operation | Time |
|-----------|------|
| Steam Discovery | 0.14ms |
| Game Lookup | 0.35ms |
| List All Games | 12ms |
| Binary VDF Parse | <10ms |

## [0.1.0-alpha] - Phase 1 Foundation

### Added

- **CLI framework** with command parsing
- **Text VDF parser** for localconfig.vdf, libraryfolders.vdf
- **Steam discovery** - finds Steam installation
- **Library folders** enumeration
- **Installed games** listing
- **Proton versions** listing
- **Basic game info** retrieval

### Infrastructure

- **Nix flake** for reproducible builds
- **Zig 0.13.0** pinned for stability
- **justfile** for common commands
- **README** with usage examples

## Comparison with Original SteamTinkerLaunch

### Performance Improvements

| Operation | Original STL | STL-Next | Improvement |
|-----------|-------------|----------|-------------|
| Startup | 2-5s | <100ms | 20-50x |
| Game lookup | ~1s | 0.35ms | ~3000x |
| Config load | ~200ms | 0.5ms | 400x |

### Bug Fixes

| Bug | Original | STL-Next |
|-----|----------|----------|
| NXM URL truncation | 6+ months unfixed | ✅ Fixed |
| JSON parsing | String search | ✅ Proper parser |
| Type safety | Bash | ✅ Zig types |
| Memory leaks | Bash (N/A) | ✅ Test allocator |

### Missing Features (Planned)

| Feature | Phase |
|---------|-------|
| Raylib GUI | 5 |
| Full MO2/Vortex | 5 |
| ReShade | 5 |
| Winetricks | 5 |
| Non-Steam Games | 5 |
| SteamGridDB | 6 |

---

## Version Numbering

- **0.x.y-alpha**: Pre-release development
- **Major (0.x)**: Phase completion
- **Minor (0.0.y)**: Feature additions
- **Suffix**: Development stage

## Links

- [GitHub Issues](https://github.com/e421/stl-next/issues)
- [Original STL Issues](https://github.com/sonic2kk/steamtinkerlaunch/issues)
- [Architecture Guide](docs/ARCHITECTURE.md)

