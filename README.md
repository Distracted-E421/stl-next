# STL-Next: Steam Tinker Launch - Next Generation

A high-performance Steam game wrapper written in Zig, designed as a modern replacement for the 21,000-line Bash script that is SteamTinkerLaunch.

## 🚀 Performance

STL-Next achieves sub-millisecond performance for most operations:

| Operation | Time | vs. Original STL |
|-----------|------|------------------|
| Steam Discovery | **0.10 ms** | ~100x faster |
| Game Lookup | **0.09 ms** | ~1000x faster |
| List All Games | **2.72 ms** | ~500x faster |
| List Protons | **0.05 ms** | ~200x faster |

All operations complete in under 100ms. Compare to 2-5 seconds for the original Bash STL.

## 📦 Installation (NixOS)

```bash
# Enter development shell
cd stl-next
nix develop

# Build release binary
zig build -Doptimize=ReleaseFast

# Binary is at ./zig-out/bin/stl-next
```

## 🔧 Usage

```bash
# Show help
stl-next help

# Get game info (JSON)
stl-next info 413150

# List installed games
stl-next list-games | jq '.[]'

# List available Proton versions
stl-next list-protons

# Launch a game (shorthand)
stl-next 413150

# Run benchmark
stl-next benchmark
```

## 🏗️ Architecture

STL-Next is built with three guiding principles:

1. **Performance**: Sub-100ms launch overhead (vs 2-5s in Bash)
2. **Modularity**: Strict separation of "Tinker" modules from core engine
3. **NixOS Native**: No hardcoded paths, proper PATH resolution

### Phase Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ Complete | Core scaffolding, CLI, basic Steam discovery |
| Phase 2 | ✅ Complete | Binary VDF parser, fast AppID seeking, LevelDB collections |
| Phase 3 | 🚧 Next | Prefix orchestration, Wine/Proton management |
| Phase 4 | 📋 Planned | Tinker module system (Gamescope, MangoHud, etc.) |
| Phase 5 | 📋 Planned | GUI with Raylib |

### Core Components

```
src/
├── main.zig          # CLI entry point
├── core/
│   ├── config.zig    # Game config management
│   └── launcher.zig  # Game launch orchestration
└── engine/
    ├── steam.zig     # Steam installation discovery
    ├── appinfo.zig   # Binary VDF parser (appinfo.vdf)
    ├── vdf.zig       # VDF format utilities
    └── leveldb.zig   # Steam collections (hidden games, categories)
```

## 🎯 Design Goals

### Binary VDF Streaming Parser

The `appinfo.vdf` file can be 200MB+. STL-Next parses it in under 10ms using:
- Memory-mapped file I/O
- O(1) seeking to specific AppIDs
- Lazy parsing (only decode what's needed)

### LevelDB Collections Support

Steam stores user collections (categories, hidden status) in LevelDB. STL-Next includes:
- Pure Zig LevelDB reader (no C dependencies)
- Game hidden status detection
- Collection/tag retrieval

### NixOS-First Design

- No hardcoded paths (uses `$HOME`, `$XDG_*`)
- Works with both native Steam and Flatpak
- Proper Nix flake with reproducible builds

## 📊 Example Output

```bash
$ ./zig-out/bin/stl-next info 413150
{
  "app_id": 413150,
  "name": "Stardew Valley",
  "install_dir": "/home/user/.steam/steam/steamapps/common/Stardew Valley",
  "executable": null,
  "proton_version": null,
  "playtime_minutes": 0,
  "is_hidden": false,
  "collections": [],
  "_lookup_time_ms": 0.187
}

$ ./zig-out/bin/stl-next benchmark

╔══════════════════════════════════════════════════════════════╗
║              STL-NEXT PHASE 2 BENCHMARK                      ║
╚══════════════════════════════════════════════════════════════╝

Steam Discovery:         0.10 ms
Game Lookup (413150):     0.09 ms (Stardew Valley)
List All Games:          2.72 ms (42 games)
List Protons:            0.05 ms (12 versions)

Target: All operations < 100ms ✓
Binary VDF seeking: O(1) per skip
```

## 🛠️ Development

```bash
# Build debug
zig build

# Build release
zig build -Doptimize=ReleaseFast

# Run tests
zig build test

# Run with arguments
zig build run -- benchmark
```

## 📜 License

MIT

## 🙏 Credits

Inspired by the incredible work of [SteamTinkerLaunch](https://github.com/sonic2kk/steamtinkerlaunch) by sonic2kk.
