# Changelog

All notable changes to STL-Next are documented in this file.

## [0.6.1-alpha] - Phase 6 Complete: All Advanced Tinkers

### Added

#### Remaining Phase 6 Tinker Modules

**Boxtron/Roberta Tinker** (`src/tinkers/boxtron.zig`)
- DOSBox integration via Boxtron Steam Play tool
- ScummVM integration via Roberta Steam Play tool
- DOSBox configuration generation (cycles, scaler, renderer)
- Automatic DOS/ScummVM game detection heuristics
- Scaler options: normal2x/3x, hq2x/3x, advmame, tv, scan
- Renderer options: surface, texture, opengl

**OBS Capture Tinker** (`src/tinkers/obs.zig`)
- OBS Studio integration for streaming/recording
- Auto-start recording when game launches
- Auto-start streaming when game launches
- Scene switching per-game
- OBS websocket support (port 4455)
- Replay buffer support
- Cleanup: auto-stop on game exit
- OBS detection via process check

**DLSS Tweaks Tinker** (`src/tinkers/dlss.zig`)
- NVIDIA DLSS quality presets (Ultra Performance → DLAA)
- DLSS Frame Generation toggle (RTX 40+ series)
- NVIDIA Reflex modes (off/on/on+boost)
- DLSS sharpening control (0.0-1.0)
- Ray Reconstruction toggle (RTX 40+ series)
- Custom DLSS DLL swapping
- DXVK-NVAPI environment configuration
- DLSS version database for DLL swapping

**OptiScaler Tinker** (`src/tinkers/optiscaler.zig`)
- Universal upscaler (FSR 3.1, XeSS, DLSS) on any GPU
- Frame Generation on AMD/Intel GPUs
- Backend auto-detection based on GPU vendor
- FSR quality presets (Ultra Performance → Ultra Quality)
- Anti-lag mode configuration
- DLL installation to Wine prefix
- INI configuration generation
- Debug overlay option

#### Configuration Extensions (`src/core/config.zig`)

- `BoxtronConfig` - DOSBox/ScummVM settings
- `ObsConfig` - OBS Studio integration settings
- `DlssConfig` - DLSS quality and frame generation
- `OptiScalerConfig` - Universal upscaler settings

### Changed

- Tinker registry now has **14 built-in tinkers** (was 10)
- Phase 6 is now complete with all planned features
- Updated feature roadmap to reflect Phase 6 completion

### Technical

- Added GPU vendor detection for optimal backend selection
- OBS integration uses obs-cmd CLI as fallback
- DLSS support checks for /dev/nvidia0 presence
- OptiScaler DLL installation to system32

---

## [0.6.0-alpha] - Phase 6: Advanced Tinkers + Configuration

### Added

#### New Tinker Modules (Phase 6)

**ReShade Tinker** (`src/tinkers/reshade.zig`)
- Shader injection for DX9/10/11/12/OpenGL/Vulkan
- Vulkan layer configuration
- Preset management
- Screenshot path configuration

**vkBasalt Tinker** (`src/tinkers/vkbasalt.zig`)
- Vulkan post-processing layer
- Contrast Adaptive Sharpening (CAS - AMD FidelityFX)
- Fast Approximate Anti-Aliasing (FXAA)
- Subpixel Morphological Anti-Aliasing (SMAA)
- Deband and LUT support
- Configuration file generation

**SpecialK Tinker** (`src/tinkers/specialk.zig`)
- Game modification framework for Wine/Proton
- HDR injection and tonemapping
- Low-latency frame limiting
- Texture modding support
- Input latency reduction
- DLL override configuration

**LatencyFleX Tinker** (`src/tinkers/latencyflex.zig`)
- NVIDIA Reflex alternative for Linux
- Auto-detection of v1 (Vulkan layer) and v2 (DXVK)
- Frame cap integration
- Wait target configuration

**MultiApp Tinker** (`src/tinkers/multiapp.zig`)
- Launch helper apps with games
- Support for before/with/after game timing
- Auto-close on game exit policy
- Presets: OBS, Discord, GPU monitor
- Configurable delays between launches

#### Advanced Configuration (`src/core/config.zig`)

**Proton Advanced Settings** (`ProtonAdvancedConfig`)
- `enable_wayland` - Proton native Wayland support (STL issue #1259)
- `enable_nvapi` - NVIDIA DLSS/NVAPI support
- `enable_rtx` - Ray Tracing (DXR) support
- `wine_prefix` - Custom Wine prefix override
- `dxvk_async` - DXVK async shader compilation
- `vkd3d_rt` - VKD3D Ray Tracing config

**GPU Configuration** (`GpuConfig`)
- `vk_device` - Vulkan device selection (multi-GPU systems)
- `mesa_device_index` - Mesa device index (STL issue #1201)
- `prime_offload` - NVIDIA PRIME render offload
- `dri_device` - DRI device path override

### Changed

- Tinker registry now has 10 built-in tinkers (was 5)
- Config file now supports Phase 6 tinker configurations
- Launcher applies Proton and GPU settings before game launch

### Technical

- Fixed ArrayList API for Zig 0.15.x (ArrayListUnmanaged)
- Fixed std.time.sleep → std.Thread.sleep for Zig 0.15.x
- Config types defined centrally to avoid circular imports
- Buffer-based config generation for better memory management

---

## [0.5.5-alpha] - Nexus Mods API + GUI Wayland Fix

### Added

#### Nexus Mods API Client (`src/api/nexusmods.zig`)

Full Nexus Mods API v1 integration with Premium download support:

- **API Key Discovery** - Auto-loads from:
  1. `STL_NEXUS_API_KEY` environment variable
  2. `~/.config/stl-next/nexus_api_key` file
  3. `/run/secrets/nexus_api_key` (sops-nix)
  4. `/run/agenix/nexus_api_key` (agenix)

- **CLI Commands**:
  - `nexus` - Show Nexus Mods help
  - `nexus-login [key]` - Save and validate API key
  - `nexus-whoami` - Show current user info (name, premium status)
  - `nexus-mod <game> <mod_id>` - Get mod details
  - `nexus-files <game> <mod_id>` - List available files
  - `nexus-download <game> <mod_id> <file_id>` - Get download links (Premium)
  - `nexus-track <game> <mod_id>` - Track mod for updates
  - `nexus-tracked` - List tracked mods

- **API Endpoints**:
  - `GET /v1/users/validate.json` - Validate API key
  - `GET /v1/games/{domain}/mods/{id}.json` - Get mod info
  - `GET /v1/games/{domain}/mods/{id}/files.json` - List files
  - `GET /v1/games/{domain}/mods/{id}/files/{file_id}/download_link.json` - Download links
  - `POST /v1/user/tracked_mods.json` - Track mod
  - `GET /v1/user/tracked_mods.json` - List tracked mods
  - `POST /v1/games/{domain}/mods/{id}/endorse.json` - Endorse mod

#### NixOS Secret Management Documentation (`docs/NEXUS_API_SECRETS.md`)

Comprehensive guide for managing Nexus API keys on NixOS:

- sops-nix integration with example configuration
- agenix integration with example configuration
- Home Manager module for declarative setup
- Security best practices (chmod 600, .gitignore)
- Rate limiting information (2500/day, 100/hour after limit)

### Fixed

#### GUI Wayland Improvements

- Added warning for Wayland HiDPI mouse coordinate issues
- Recommend `GDK_BACKEND=x11` workaround for affected systems
- Reference to upstream raylib issue #3872

### Changed

- HTTP requests now use curl subprocess for better reliability
- Handles gzip compression and TLS automatically

### Security

- Added `*.env`, `.env*`, `nexus_api_key` to `.gitignore`
- Never hardcode API keys in source code
- API keys read from environment/files only

---

## [0.5.4-alpha] - GUI Fixes + Vortex Integration

### Fixed

#### GUI Improvements

- **Mouse tracking crash** - Fixed infinite recursion in `getScaledMousePos()` that caused immediate segfault
- **Resizable window** - Window is now resizable with 640x480 minimum size
- **Dynamic layout** - UI elements scale with window size using `getWidth()`/`getHeight()` helpers
- **HiDPI support** - Added scale factor detection for proper mouse coordinates on high-DPI displays

### Added

#### Vortex Mod Manager Integration (`src/modding/vortex.zig`)

- **Auto-discovery** in common Wine prefix locations:
  - Steam Proton prefixes (`~/.local/share/Steam/steamapps/compatdata/`)
  - Lutris Wine prefixes (`~/.local/share/lutris/runners/wine/`)
  - Standard Wine prefix (`~/.wine`)
- **VortexInfo struct** - Installation path, Wine prefix, staging dir, AppData path
- **VortexGameConfig** - Per-game mod paths and staging folders
- **NXM link forwarding** - Forward links to running Vortex instance
- **AppData sync** - rsync-based sync between Wine and host
- **Process detection** - Check if Vortex is currently running
- **URL encoding** - Proper encoding for Wine command-line compatibility

### Usage

```zig
const vortex = @import("modding/manager.zig").vortex;

var v = vortex.Vortex.init(allocator);
defer v.deinit();

// Discover Vortex
const info = try v.discover();

// Forward NXM link
try v.forwardNxmLink("nxm://stardewvalley/mods/123/files/456");
```

---

## [0.5.3-alpha] - Phase 5.5: Raylib GUI

### Added

#### Raylib-based Wait Requester GUI

- **Modern dark-themed UI** using Catppuccin Mocha color scheme
- **Visual countdown timer** with animated progress bar
- **Tinker toggles** with hover effects and color-coded indicators
  - MangoHud, Gamescope, GameMode, Winetricks, Custom Commands, SteamGridDB
- **Interactive buttons** - Launch Now, Pause/Resume, Cancel
- **Keyboard shortcuts** - Enter (launch), Space (pause), Tab (skip), Esc (cancel)
- **Window dragging** via title bar (Wayland/X11 compatible)
- **Daemon output** - Prints LAUNCH/CANCELLED and enabled tinkers to stdout

#### Build System Updates

- **Optional GUI build** - Use `zig build -Dgui` to include GUI
- **Separate binary** - `stl-next-gui` built alongside CLI
- **Raylib integration** via system libraries and @cImport

### Technical Details

- Uses Raylib 5.5 via @cImport for clean C interop
- 640x440 undecorated window with MSAA 4x
- 60 FPS target with smooth countdown animation
- Compatible with Wayland (GLFW backend) and X11
- OpenGL 4.6 rendering on Intel Arc A770 tested

### Usage

```bash
# Build with GUI support
zig build -Dgui

# Run GUI
./zig-out/bin/stl-next-gui <AppID> "<Game Name>" [countdown_seconds]
./zig-out/bin/stl-next-gui 413150 "Stardew Valley" 15
```

---

## [0.5.2-alpha] - Zig 0.15.2 Migration

### Changed

#### Zig 0.15.x Migration

- **Upgraded from Zig 0.14.0 to 0.15.2** - Major API migration
- **ArrayList API changes** - Unmanaged ArrayList now uses `.{}` initialization
  - `ArrayList(T).init(allocator)` → `ArrayList(T) = .{}`
  - `list.append(item)` → `list.append(allocator, item)`
  - `list.appendSlice(items)` → `list.appendSlice(allocator, items)`
  - `list.deinit()` → `list.deinit(allocator)`
  - `list.toOwnedSlice()` → `list.toOwnedSlice(allocator)`
- **HTTP Client API changes** - New request/response pattern
  - `client.open()` → `client.request(method, uri, options)`
  - `request.send()/wait()` → `request.sendBodiless()` + `request.receiveHead()`
  - `response.reader()` now takes a buffer and returns a different Reader type
  - Body reading via `reader.allocRemaining(allocator, limit)`
- **File writing changes** - Direct file operations
  - `file.writer()` no longer available for formatted output
  - Use `file.writeAll()` with `std.fmt.allocPrint()` for JSON serialization
- **std.Io.Limit** is now an enum, use `std.Io.Limit.limited(n)` instead of struct

### Files Updated for 0.15.x

- `build.zig` - Added required `.name` field to `addExecutable()`
- `src/engine/nonsteam.zig` - File writing and ArrayList updates
- `src/engine/steamgriddb.zig` - HTTP client and ArrayList updates
- All files using `std.ArrayList` - Updated init/append/deinit patterns

### Fixed

- Build compatibility with Zig 0.15.2
- All existing tests pass with new Zig version
- HTTP requests properly handle new API

---

## [0.5.1-alpha] - Phase 5: Nix Packaging

### Added

#### Nix Flake Packaging

- **Full Nix flake** with proper build system
- **NixOS module** (`nixosModules.default`) for system-wide installation
- **Home Manager module** (`homeManagerModules.default`) for user-level installation
- **NXM protocol handler registration** via desktop entries
- **Configurable defaults** for countdown, tinkers

#### Zig Upgrade

- **Upgraded from Zig 0.13.0 to 0.14.0** for better compatibility
- All tests pass with new Zig version
- No breaking API changes required (code compatible)

#### NixOS Module Features

```nix
programs.stl-next = {
  enable = true;
  registerNxmHandler = true;  # Auto-register NXM protocol handler
};
```

#### Home Manager Module Features

```nix
programs.stl-next = {
  enable = true;
  countdownSeconds = 10;
  defaultTinkers = {
    mangohud = false;
    gamescope = false;
    gamemode = true;
  };
};
```

### Changed

- **flake.nix** completely rewritten for proper NixOS/HM integration
- **NIXOS_INSTALLATION.md** updated with actual flake usage
- **README.md** updated with installation instructions

### Pending (Phase 5.5)

- **Raylib GUI** - Requires Zig 0.15.1 (awaiting zig-overlay support)
- GUI source prepared at `src/gui/` but not yet buildable

---

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
