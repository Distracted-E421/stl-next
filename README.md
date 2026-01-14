# STL-Next: Steam Tinker Launch - Next Generation

A high-performance Steam game wrapper written in Zig, replacing the 21,000-line Bash script.

## 🎯 Project Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ Complete | Core CLI, VDF text parsing, Steam discovery |
| Phase 2 | ✅ Complete | Binary VDF streaming, fast AppID seeking |
| Phase 3 | ✅ Complete | Tinker modules (MangoHud, Gamescope, GameMode) |
| Phase 3.5 | ✅ Complete | Launch Options, JSON parsing, exec(), tests |
| Phase 4 | ✅ Complete | **IPC Daemon**, Wait Requester, NXM Handler, TUI |
| Phase 5 | 🚧 Next | Raylib GUI, Full MO2/Vortex integration |

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
└── modding/              # Phase 4: NEW
    └── manager.zig       # MO2/Vortex + NXM handler
```

## 🎮 New CLI Commands (Phase 4)

| Command | Description |
|---------|-------------|
| `wait <AppID>` | Start wait requester daemon with countdown |
| `tui <AppID>` | Connect TUI client to running daemon |
| `nxm <url>` | Handle NXM protocol link from browser |

## 🔧 Environment Variables

| Variable | Description |
|----------|-------------|
| `STL_SKIP_WAIT` | Skip wait requester (instant launch) |
| `STL_COUNTDOWN` | Countdown seconds (default: 10) |
| `STL_CONFIG_DIR` | Config directory |

## 📝 Known Limitations

| Feature | Status | Notes |
|---------|--------|-------|
| Raylib GUI | ❌ Phase 5 | TUI available now |
| MO2 USVFS | 🔶 Basic | DLL override detection |
| VR Support | ❌ Phase 5+ | UEVR integration planned |

## 🔜 Phase 5 Roadmap

- [ ] Raylib-based graphical Wait-Requester
- [ ] Full MO2 USVFS injection
- [ ] Vortex download integration
- [ ] ReShade with hash-based updates
- [ ] Steam Deck gamepad support

## 📜 License

MIT

---

**Core Principle**: Performance-first. Sub-100ms overhead for any operation.
