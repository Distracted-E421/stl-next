# STL-Next: Steam Tinker Launch - Next Generation

A high-performance Steam game wrapper written in Zig, replacing the 21,000-line Bash script with a type-safe, modular architecture.

## 🎯 Project Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ Complete | Core CLI, VDF text parsing, basic Steam discovery |
| Phase 2 | ✅ Complete | Binary VDF streaming, LevelDB collections, fast AppID seeking |
| Phase 3 | ✅ Complete | Tinker module system (MangoHud, Gamescope, GameMode) |
| Phase 4 | 🚧 In Progress | GUI (Raylib), full game launch, mod manager integration |

## 🚀 Performance (Benchmarks)

```
╔══════════════════════════════════════════════════════════════╗
║              STL-NEXT BENCHMARK                              ║
╚══════════════════════════════════════════════════════════════╝

Steam Discovery:         0.10 ms
Game Lookup (413150):    0.09 ms (Stardew Valley)
List All Games:          2.72 ms (42 games)
List Protons:            0.05 ms (12 versions)

Target: All operations < 100ms ✓
```

Compare to original STL: **2-5 seconds** for similar operations.

## 📦 Installation

### NixOS (Recommended)
```bash
git clone https://github.com/e421/stl-next
cd stl-next
nix develop

zig build -Doptimize=ReleaseFast
./zig-out/bin/stl-next help
```

## 🔧 Usage

```bash
# Show help
stl-next help

# Launch a game (shorthand)
stl-next 413150                    # Stardew Valley

# Get game information (JSON)
stl-next info 413150

# List installed games
stl-next list-games | jq '.[]'

# List Proton versions
stl-next list-protons

# Run performance benchmark
stl-next benchmark
```

## 🏗️ Architecture

```
stl-next/
├── src/
│   ├── main.zig              # CLI entry point
│   ├── core/
│   │   ├── config.zig        # Game configuration management
│   │   └── launcher.zig      # Launch orchestration
│   ├── engine/
│   │   ├── steam.zig         # Steam discovery & library management
│   │   ├── vdf.zig           # Text VDF parser
│   │   ├── appinfo.zig       # Binary VDF streaming parser
│   │   └── leveldb.zig       # Steam collections (pure Zig)
│   └── tinkers/              # Phase 3: Module System
│       ├── mod.zig           # Module exports
│       ├── interface.zig     # Tinker trait definition
│       ├── mangohud.zig      # MangoHud overlay
│       ├── gamescope.zig     # Gamescope wrapper
│       └── gamemode.zig      # Feral GameMode
├── build.zig
├── flake.nix
└── justfile
```

## 🎮 Phase 3: Tinker Module System

The Tinker system provides a plugin architecture for game modifications:

### Available Tinkers

| Tinker | Priority | Function |
|--------|----------|----------|
| **GameMode** | 40 (OVERLAY_EARLY) | CPU governor, I/O priority |
| **MangoHud** | 50 (OVERLAY) | Performance overlay HUD |
| **Gamescope** | 80 (WRAPPER) | Micro-compositor, FSR upscaling |

### Tinker Lifecycle

1. **preparePrefix**: Filesystem operations (symlinks, file copies)
2. **modifyEnv**: Environment variable injection
3. **modifyArgs**: Command line modifications

### Per-Game Configuration

```json
// ~/.config/stl-next/games/413150.json
{
  "app_id": 413150,
  "mangohud": {
    "enabled": true,
    "show_fps": true,
    "position": "top_right"
  },
  "gamescope": {
    "enabled": true,
    "width": 1920,
    "height": 1080,
    "fsr": true
  },
  "gamemode": {
    "enabled": true
  }
}
```

## 🔜 Phase 4 Roadmap

- [ ] Raylib-based Wait-Requester GUI
- [ ] IPC daemon/client architecture
- [ ] Full game launch (exec)
- [ ] MO2/Vortex integration
- [ ] ReShade with hash-based updates

## 📜 License

MIT - See LICENSE file

## 🙏 Acknowledgments

- Original [SteamTinkerLaunch](https://github.com/sonic2kk/steamtinkerlaunch) by frostworx
- Valve for Steam on Linux
- The Zig community
