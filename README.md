# STL-Next: Steam Tinker Launch - Next Generation

A high-performance Steam game wrapper written in Zig, replacing the 21,000-line Bash script.

## 🎯 Why This Fork Exists

The original SteamTinkerLaunch has a **critical bug unfixed for 6+ months**:

```bash
# The Bug: Wine interprets "/" as command switches!
# What STL sends to Vortex:
nxm://stardewvalley/collections/tckf0m/revisions/100

# What Vortex actually receives (TRUNCATED!):
nxm://stardewvalley/collections/tckf0m
# Error: "Invalid URL: invalid nxm url"
```

**STL-Next fixes this** with proper URL encoding:
```bash
$ ./stl-next nxm "nxm://stardewvalley/collections/tckf0m/revisions/100"
  Parsed: Collection: stardewvalley/collections/tckf0m/revisions/100
  Wine-safe: nxm://stardewvalley%2Fcollections%2Ftckf0m%2Frevisions%2F100
  # /revisions/100 PRESERVED! ✅
```

See: [STL_URL_TRUNCATION_BUG_REPORT.md](../stardew-modding-nix/STL_URL_TRUNCATION_BUG_REPORT.md)

## 📊 Project Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ Complete | Core CLI, VDF text parsing, Steam discovery |
| Phase 2 | ✅ Complete | Binary VDF streaming, fast AppID seeking |
| Phase 3 | ✅ Complete | Tinker modules (MangoHud, Gamescope, GameMode) |
| Phase 3.5 | ✅ Complete | Launch Options, JSON parsing, exec(), tests |
| Phase 4 | ✅ Complete | **IPC Daemon**, Wait Requester, NXM Handler, TUI |
| Phase 4.5 | ✅ Complete | **Winetricks**, Custom Commands, Non-Steam Games, SteamGridDB |
| Phase 5 | ✅ Complete | **Nix Flake Packaging**, NixOS/Home Manager Modules |
| Phase 5.5 | ✅ Complete | **Raylib GUI** - Modern Wait Requester |
| Phase 5.6 | ✅ Complete | **Vortex Integration** - Auto-discovery, NXM forwarding |
| Phase 5.7 | ✅ Complete | **Nexus Mods API** - Full v1 client, tracking, Premium downloads |
| Phase 6 | ✅ Complete | **14 Tinkers**: ReShade, vkBasalt, SpecialK, LatencyFleX, MultiApp, Boxtron, OBS, DLSS, OptiScaler |
| Phase 7 | 📋 Planned | Full MO2 USVFS, Stardrop integration, VR support |

### Zig Version

STL-Next is built with **Zig 0.15.2** (latest stable). The Raylib GUI is next in the roadmap.

## ✨ Phase 4 Features

### IPC Daemon/Client Architecture

```bash
# Terminal 1: Start the wait requester daemon
$ ./stl-next wait 413150
╔════════════════════════════════════════════╗
║      STL-NEXT WAIT REQUESTER v0.4.0-alpha  ║
╚════════════════════════════════════════════╝
Game: Stardew Valley
IPC Server: Listening on /run/user/1000/stl-next-413150.sock
Wait Requester: 10s remaining...

# Terminal 2: Connect with TUI client
$ ./stl-next tui 413150
```

### NXM Protocol Handler

```bash
$ ./stl-next nxm "nxm://stardewvalley/mods/12345/files/67890"
NXM Handler: nxm://stardewvalley/mods/12345/files/67890
  Game: stardewvalley
  Mod ID: 12345
  File ID: 67890
```

### TUI (Terminal User Interface)

```
╔════════════════════════════════════════════════════════════════════╗
║                    STL-NEXT WAIT REQUESTER                         ║
╠════════════════════════════════════════════════════════════════════╣
║ Game: Stardew Valley                                               ║
║ AppID: 413150                                                      ║
╠════════════════════════════════════════════════════════════════════╣
║ Commands:                                                          ║
║   [P] Pause countdown    [R] Resume countdown                      ║
║   [L] Launch now         [Q] Quit/Abort                            ║
║   [M] Toggle MangoHud    [G] Toggle Gamescope                      ║
╚════════════════════════════════════════════════════════════════════╝

⏱️  Launching in... 8s [████████░░]
```

## 🚀 Performance

```
╔══════════════════════════════════════════════════════════════╗
║              STL-NEXT BENCHMARK                              ║
╚══════════════════════════════════════════════════════════════╝

Steam Discovery:         0.14 ms
Game Lookup (413150):    0.35 ms (with launch options!)
List All Games:         12.25 ms (42 games)
List Protons:            0.07 ms (6 versions)

All operations < 100ms ✓
```

## 📦 Installation

### NixOS / Home Manager (Recommended)

Add to your flake inputs:

```nix
inputs.stl-next.url = "github:e421/stl-next";
# Or local: inputs.stl-next.url = "path:/path/to/stl-next";
```

**NixOS Module:**
```nix
{ stl-next, ... }: {
  imports = [ stl-next.nixosModules.default ];
  programs.stl-next = {
    enable = true;
    registerNxmHandler = true;
  };
}
```

**Home Manager Module:**
```nix
{ stl-next, ... }: {
  imports = [ stl-next.homeManagerModules.default ];
  programs.stl-next = {
    enable = true;
    countdownSeconds = 10;
    defaultTinkers.gamemode = true;
  };
}
```

### Development / Manual Build

```bash
git clone https://github.com/e421/stl-next
cd stl-next
nix develop
zig build -Doptimize=ReleaseFast

# Usage
./zig-out/bin/stl-next help
./zig-out/bin/stl-next 413150          # Launch Stardew Valley
./zig-out/bin/stl-next info 413150     # Get game info (JSON)
./zig-out/bin/stl-next wait 413150     # Start wait requester
./zig-out/bin/stl-next tui 413150      # Connect TUI client
./zig-out/bin/stl-next nxm "nxm://..." # Handle NXM link
```

## 🏗️ Architecture

```
src/
├── main.zig              # CLI entry point
├── core/
│   ├── config.zig        # JSON configs (std.json)
│   └── launcher.zig      # Launch pipeline (real exec!)
├── engine/
│   ├── steam.zig         # Steam discovery + launch options
│   ├── vdf.zig           # VDF parsing
│   ├── appinfo.zig       # Binary VDF streaming
│   └── leveldb.zig       # Collections (best-effort)
├── tinkers/
│   ├── interface.zig     # Tinker trait (no global state!)
│   ├── mangohud.zig      # MangoHud overlay
│   ├── gamescope.zig     # Compositor wrapper
│   └── gamemode.zig      # System optimizations
├── ipc/                  # Phase 4: NEW
│   ├── protocol.zig      # JSON over Unix sockets
│   ├── server.zig        # Daemon side
│   └── client.zig        # Client side
├── ui/                   # Phase 4: NEW
│   ├── daemon.zig        # Wait requester daemon
│   └── tui.zig           # Terminal UI client
└── modding/              # Phase 4+: Mod Manager Integration
    ├── manager.zig       # MO2/Vortex coordinator + NXM handler
    └── vortex.zig        # Vortex auto-discovery + NXM forwarding
```

## 🎮 New CLI Commands (Phase 4+)

| Command | Description |
|---------|-------------|
| `wait <AppID>` | Start wait requester daemon with countdown |
| `tui <AppID>` | Connect TUI client to running daemon |
| `nxm <url>` | Handle NXM protocol link from browser |

### Nexus Mods Commands (Phase 5.5)

```bash
# Setup (get key from nexusmods.com/users/myaccount?tab=api%20access)
stl-next nexus-login YOUR_API_KEY   # Save API key
stl-next nexus-whoami               # Verify key + show user info

# Mod information
stl-next nexus-mod stardewvalley 21297        # Get mod details
stl-next nexus-files stardewvalley 21297      # List downloadable files

# Downloads (Premium Nexus members only)
stl-next nexus-download stardewvalley 21297 12345  # Get download link

# Update tracking
stl-next nexus-track stardewvalley 21297      # Track mod for updates
stl-next nexus-tracked                         # List all tracked mods
```

See: [NEXUS_API_SECRETS.md](docs/NEXUS_API_SECRETS.md) for NixOS secret management.

## 🔧 Environment Variables

| Variable | Description |
|----------|-------------|
| `STL_SKIP_WAIT` | Skip wait requester (instant launch) |
| `STL_COUNTDOWN` | Countdown seconds (default: 10) |
| `STL_CONFIG_DIR` | Config directory |
| `STL_NEXUS_API_KEY` | Nexus Mods API key (get from nexusmods.com) |
| `STEAMGRIDDB_API_KEY` | SteamGridDB API key (free at steamgriddb.com) |

## 🛡️ Error Handling (Hardened)

Unlike the original Bash script, STL-Next has **comprehensive error handling**:

| Category | Hardening |
|----------|-----------|
| **NXM URLs** | Validates scheme, domain, IDs; URL-encodes for Wine |
| **IPC** | Retry logic, timeouts, connection recovery |
| **Config** | JSON validation, size limits, graceful defaults |
| **VDF** | Handles malformed files, missing fields |
| **Memory** | Test allocator catches all leaks |

Edge case tests in `src/tests/edge_cases.zig`:
- Collection URL revision preservation (THE BUG FIX)
- Special characters in mod names
- Boundary conditions (max AppID, etc.)
- Memory safety (allocation/deallocation loops)

## 📝 Known Limitations

| Feature | Status | Notes |
|---------|--------|-------|
| Raylib GUI | ❌ Phase 5 | TUI available now |
| MO2 USVFS | 🔶 Basic | DLL override detection |
| VR Support | ❌ Phase 5+ | UEVR integration planned |

## 🔜 Phase 5 Roadmap

- [x] Raylib-based graphical Wait-Requester
- [x] Vortex auto-discovery and NXM forwarding
- [ ] Full MO2 USVFS injection
- [ ] Vortex download queue integration
- [ ] ReShade with hash-based updates
- [ ] Steam Deck gamepad support

## 📚 Documentation

### Core Documentation

| Document | Description |
|----------|-------------|
| [IPC Protocol](docs/IPC_PROTOCOL.md) | Full specification of the daemon/client protocol |
| [Architecture](docs/ARCHITECTURE.md) | Code structure and component overview |
| [Feature Roadmap](docs/FEATURE_ROADMAP.md) | Comparison with original STL + future plans |
| [NXM Handling](docs/NXM_HANDLING.md) | NXM protocol parsing and the bug fix |

### Quality Assurance

| Document | Description |
|----------|-------------|
| [Bug Verification Matrix](docs/BUG_VERIFICATION_MATRIX.md) | All original STL bugs and their status in STL-Next |
| [Game Testing Guide](docs/GAME_TESTING_GUIDE.md) | Test procedures for target games (Stardew, Skyrim, FO4, CP77) |

### Platform-Specific

| Document | Description |
|----------|-------------|
| [NixOS Installation](docs/NIXOS_INSTALLATION.md) | Dedicated guide for NixOS users |
| [Stardrop Integration](docs/STARDROP_INTEGRATION.md) | Stardrop mod manager research and plan |

### Feature Guides

| Document | Description |
|----------|-------------|
| [Winetricks Guide](docs/WINETRICKS_GUIDE.md) | Windows components & DLL installation |
| [Custom Commands](docs/CUSTOM_COMMANDS.md) | Pre/post launch shell commands |
| [Non-Steam Games](docs/NONSTEAM_GAMES.md) | Adding GOG, Epic, and other games |
| [SteamGridDB Guide](docs/STEAMGRIDDB_GUIDE.md) | Game artwork integration |
| [Nexus API Secrets](docs/NEXUS_API_SECRETS.md) | API key management (sops-nix, agenix) |

## 🔧 Development

```bash
# Enter development shell
nix develop

# Build debug
zig build

# Build release
zig build -Doptimize=ReleaseFast

# Run tests
zig build test

# Run specific test
zig build test -- "nxm: collection url"
```

## 🤝 Contributing

We welcome contributions! Priority areas:

1. **Tinker modules** - Add tools like ReShade, vkBasalt
2. **Tests** - Edge cases in `src/tests/edge_cases.zig`
3. **Documentation** - Usage guides and examples
4. **Bug reports** - Especially for mod manager issues

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for code structure.

## 📜 License

MIT

---

**Core Principle**: Performance-first. Sub-100ms overhead for any operation.

**Why STL-Next?** Because bugs like [the NXM URL truncation](docs/NXM_HANDLING.md) shouldn't sit unfixed for 6+ months.
