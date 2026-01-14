# STL-Next: Steam Tinker Launch - Next Generation

A high-performance Steam game wrapper written in Zig, replacing the 21,000-line Bash script with a type-safe, modular architecture.

## 🎯 Project Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ Complete | Core CLI, VDF text parsing, basic Steam discovery |
| Phase 2 | ✅ Complete | Binary VDF streaming, LevelDB collections, fast AppID seeking |
| Phase 3 | 🚧 In Progress | Tinker module system, Wine prefix orchestration |
| Phase 4 | ⏳ Planned | GUI (Raylib), full game launch, ReShade/MO2 integration |

## 🚀 Performance (Phase 2 Benchmarks)

```
╔══════════════════════════════════════════════════════════════╗
║              STL-NEXT PHASE 2 BENCHMARK                      ║
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
# Clone and enter dev shell
git clone https://github.com/e421/stl-next
cd stl-next
nix develop

# Build
zig build -Doptimize=ReleaseFast

# Run
./zig-out/bin/stl-next help
```

### Other Linux
```bash
# Requires Zig 0.13.0
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
│   └── engine/
│       ├── steam.zig         # Steam discovery & library management
│       ├── vdf.zig           # Text VDF parser
│       ├── appinfo.zig       # Binary VDF streaming parser
│       └── leveldb.zig       # Steam collections (pure Zig)
├── build.zig                 # Zig build system
├── flake.nix                 # NixOS development environment
└── justfile                  # Task runner commands
```

## 🎮 Phase 2 Features

- **Binary VDF Streaming Parser**: Parses Steam's 200MB+ appinfo.vdf in <10ms
- **Fast AppID Seeking**: O(1) jumps to specific games without parsing entire file
- **LevelDB Collections**: Pure Zig reader for Steam's hidden games & categories
- **Proton Detection**: Finds all installed Proton versions across libraries

## 🔜 Phase 3 Roadmap

- [ ] Tinker module system (Gamescope, MangoHud, GameMode)
- [ ] Wine prefix orchestration
- [ ] Per-game configuration files
- [ ] Environment variable injection
- [ ] Proton launch wrapper

## 📜 License

MIT - See LICENSE file

## 🙏 Acknowledgments

- Original [SteamTinkerLaunch](https://github.com/sonic2kk/steamtinkerlaunch) by frostworx
- Valve for Steam on Linux
- The Zig community
