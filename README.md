# STL-Next: Steam Tinker Launch - Next Generation

A high-performance Steam game wrapper written in Zig, replacing the 21,000-line Bash script.

## 🎯 Project Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ Complete | Core CLI, VDF text parsing, Steam discovery |
| Phase 2 | ✅ Complete | Binary VDF streaming, fast AppID seeking |
| Phase 3 | ✅ Complete | Tinker modules (MangoHud, Gamescope, GameMode) |
| Phase 3.5 | ✅ Complete | **Launch Options**, JSON parsing, exec(), tests |
| Phase 4 | 🚧 Next | GUI (Raylib), mod manager integration |

## ✨ Phase 3.5 Features

### Steam Launch Options Parsing

```bash
$ ./stl-next info 413150
{
  "name": "Stardew Valley",
  "launch_options": "~/.local/share/Steam/.../StardewModdingAPI %command%",
  "executable": ".../Stardew Valley-original.exe"
}
```

Launch options from `localconfig.vdf` are now properly parsed, including:
- SMAPI command prefixes
- Environment variables (`MANGOHUD=1 %command%`)
- Custom launcher scripts

### Proper JSON Config Parsing

Uses `std.json` instead of string searching:

```json
// ~/.config/stl-next/games/413150.json
{
  "mangohud": { "enabled": true, "show_fps": true },
  "gamescope": { "enabled": true, "width": 1920 },
  "gamemode": { "enabled": true }
}
```

### Real Game Execution

```zig
// Before (Phase 3)
return error.NotYetImplemented;

// After (Phase 3.5)
var child = std.process.Child.init(argv_ptrs, allocator);
child.env_map = &env;
_ = try child.spawn();
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
./zig-out/bin/stl-next 413150        # Launch Stardew Valley
./zig-out/bin/stl-next info 413150   # Get game info (JSON)
./zig-out/bin/stl-next benchmark     # Performance test
```

## 🏗️ Architecture

```
src/
├── main.zig              # CLI entry
├── core/
│   ├── config.zig        # JSON configs (std.json)
│   └── launcher.zig      # Launch pipeline (real exec!)
├── engine/
│   ├── steam.zig         # Steam discovery + launch options
│   ├── vdf.zig           # VDF parsing
│   ├── appinfo.zig       # Binary VDF streaming
│   └── leveldb.zig       # Collections (best-effort)
└── tinkers/
    ├── interface.zig     # Tinker trait (no global state!)
    ├── mangohud.zig      # MangoHud overlay
    ├── gamescope.zig     # Compositor wrapper
    └── gamemode.zig      # System optimizations
```

## 🎮 Tinker Config Via Context

```zig
// No more global state! Config passed through Context
fn isEnabled(ctx: *const Context) bool {
    return ctx.game_config.mangohud.enabled;
}
```

## 🧪 Test Coverage

- VDF string extraction (quotes, escapes, special chars)
- Launch options parsing from localconfig.vdf
- JSON tag/hidden parsing
- Installation type detection (native, flatpak, snap)
- Config system defaults

## 📝 Known Limitations

| Feature | Status | Notes |
|---------|--------|-------|
| LevelDB Parsing | 🔶 Best-effort | Returns empty if DB not found |
| Proton Args | 🔶 Basic | Manual proton path selection |
| VR Support | ❌ Not started | Planned for Phase 4 |
| GUI | ❌ Not started | Raylib-based, Phase 4 |

## 🔜 Phase 4 Roadmap

- [ ] Raylib-based Wait-Requester GUI
- [ ] IPC daemon/client architecture
- [ ] MO2/Vortex mod manager integration
- [ ] NXM protocol handler
- [ ] ReShade with hash-based updates

## 📜 License

MIT

---

**Core Principle**: Performance-first. Sub-100ms overhead for any operation.
