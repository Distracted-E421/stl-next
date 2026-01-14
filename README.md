# STL-Next: Steam Tinker Launch - Next Generation

A high-performance Steam game wrapper written in Zig, replacing the 21,000-line Bash script with a type-safe, modular architecture.

## 🎯 Project Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ Complete | Core CLI, VDF text parsing, basic Steam discovery |
| Phase 2 | ✅ Complete | Binary VDF streaming, fast AppID seeking |
| Phase 3 | ✅ Complete | Tinker module system (MangoHud, Gamescope, GameMode) |
| Phase 3.5 | ✅ Complete | **Hardening**: Proper JSON, no global state, actual exec |
| Phase 4 | 🚧 Next | GUI (Raylib), mod manager integration |

## 🔧 Phase 3.5 Hardening

Phase 3.5 focused on production-readiness:

| Issue | Before | After |
|-------|--------|-------|
| **JSON Parsing** | String searching (`indexOf`) | Proper `std.json` parsing |
| **Global State** | Tinkers used global vars | Configs passed via `Context` |
| **Game Launch** | Stub (`"not implemented"`) | Real `std.process.Child.spawn()` |
| **Memory Safety** | Some leaks in debug | Proper defers and cleanup |

## 🚀 Performance

```
╔══════════════════════════════════════════════════════════════╗
║              STL-NEXT BENCHMARK                              ║
╚══════════════════════════════════════════════════════════════╝

Steam Discovery:         0.13 ms
Game Lookup (413150):    0.12 ms (Stardew Valley)
List All Games:         10.26 ms (42 games)
List Protons:            0.23 ms (12 versions)

All operations < 100ms ✓
```

## 📦 Installation

```bash
# NixOS
git clone https://github.com/e421/stl-next
cd stl-next
nix develop
zig build -Doptimize=ReleaseFast

# Usage
./zig-out/bin/stl-next help
./zig-out/bin/stl-next 413150        # Launch Stardew Valley
./zig-out/bin/stl-next info 413150   # Get game info (JSON)
./zig-out/bin/stl-next benchmark     # Run performance test
```

## 🏗️ Architecture

```
src/
├── main.zig              # CLI entry
├── core/
│   ├── config.zig        # JSON configs (std.json parsing)
│   └── launcher.zig      # Launch pipeline (real exec!)
├── engine/
│   ├── steam.zig         # Steam discovery
│   ├── vdf.zig           # VDF parsing
│   └── appinfo.zig       # Binary VDF streaming
└── tinkers/
    ├── interface.zig     # Tinker trait (no global state)
    ├── mangohud.zig      # MangoHud overlay
    ├── gamescope.zig     # Compositor wrapper
    └── gamemode.zig      # System optimizations
```

## 🎮 Tinker System

### Config via Context (No Global State)

```zig
// Old (bad): Global variables
var global_config: Config = .{};
pub fn setConfig(c: Config) void { global_config = c; }

// New (good): Config passed through Context
fn isEnabled(ctx: *const Context) bool {
    return ctx.game_config.mangohud.enabled;
}
```

### Per-Game JSON Config

```json
// ~/.config/stl-next/games/413150.json
{
  "app_id": 413150,
  "mangohud": { "enabled": true, "show_fps": true },
  "gamescope": { "enabled": true, "width": 1920 },
  "gamemode": { "enabled": true }
}
```

## 🚨 Known Limitations

| Feature | Status | Notes |
|---------|--------|-------|
| LevelDB Parsing | ❌ Stub | Returns empty data (needs real implementation) |
| Executable Detection | ❌ Basic | Doesn't parse launch options from Steam |
| VR Support | ❌ Not started | UEVR, SideQuest planned for Phase 4 |
| GUI | ❌ Not started | Raylib-based, planned for Phase 4 |

## 🔜 Phase 4 Roadmap

- [ ] Raylib-based Wait-Requester GUI
- [ ] IPC daemon/client architecture
- [ ] MO2/Vortex integration (USVFS)
- [ ] Real LevelDB parsing
- [ ] Steam launch options parsing
- [ ] ReShade with hash-based updates

## 📜 License

MIT

## 🙏 Acknowledgments

- Original [SteamTinkerLaunch](https://github.com/sonic2kk/steamtinkerlaunch)
- Valve for Steam on Linux
- The Zig community
