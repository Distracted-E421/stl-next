# STL-Next: Steam Tinker Launch - Next Generation

A high-performance Steam game wrapper written in Zig, replacing the 21,000-line Bash script with a type-safe, modular architecture.

## 🎯 Design Pillars

1. **PERFORMANCE**: Sub-100ms launch overhead (vs 2-5s in Bash STL)
2. **MODULARITY**: Strict separation of "Tinker" modules from core engine
3. **NIXOS NATIVE**: No hardcoded paths, proper PATH resolution
4. **TYPE SAFETY**: Catch errors at compile time, not runtime

## 🏗️ Architecture

```
stl-next/
├── src/
│   ├── main.zig           # Entry point, CLI handling
│   ├── core/
│   │   ├── config.zig     # Configuration system (JSON)
│   │   └── launcher.zig   # Launch orchestration
│   ├── engine/
│   │   ├── steam.zig      # Steam installation discovery
│   │   └── vdf.zig        # Valve Data Format parser
│   └── tinkers/           # Modular tinker implementations
│       ├── mangohud.zig
│       ├── gamescope.zig
│       ├── reshade.zig
│       └── mod_organizer.zig
├── build.zig              # Zig build system
├── flake.nix              # NixOS packaging
└── benches/               # Performance benchmarks
```

## 📦 Installation

### NixOS (Recommended)

```nix
# flake.nix
{
  inputs.stl-next.url = "github:e421/stl-next";
  
  outputs = { self, nixpkgs, stl-next }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            stl-next.packages.x86_64-linux.default
          ];
        })
      ];
    };
  };
}
```

### Build from Source

```bash
# Enter development shell
nix develop

# Build debug version
zig build

# Build optimized release
zig build release

# Run tests
zig build test
```

## 🚀 Usage

```bash
# Launch a game by AppID
stl-next 413150                    # Stardew Valley

# Show game information
stl-next info 489830               # Skyrim SE

# List installed games
stl-next list-games | jq '.[]'

# List Proton versions
stl-next list-protons

# Configure (TUI)
stl-next configure
```

## ⚙️ Configuration

Configuration files are stored in `~/.config/stl-next/`:

```
~/.config/stl-next/
├── config.json           # Global settings
└── games/
    ├── 413150.json       # Stardew Valley config
    └── 489830.json       # Skyrim SE config
```

### Example Game Config

```json
{
  "app_id": 413150,
  "mangohud": {
    "enabled": true,
    "show_fps": true,
    "show_gpu": true
  },
  "gamescope": {
    "enabled": false,
    "width": 1920,
    "height": 1080,
    "fsr": true
  },
  "gamemode": true,
  "proton_version": "GE-Proton8-25"
}
```

## 🧩 Tinker Modules

STL-Next uses a modular "Tinker" system. Each tinker is a self-contained module that can:

- Modify the Wine prefix before launch
- Set environment variables
- Wrap the launch command
- Hook into post-launch events

### Built-in Tinkers

| Tinker | Description | Priority |
|--------|-------------|----------|
| `gamemode` | CPU governor optimization | 60 |
| `mangohud` | Performance overlay | 75 |
| `gamescope` | Wayland compositor wrapper | 100 |
| `reshade` | Visual enhancement injection | 120 |
| `vkbasalt` | Vulkan post-processing | 125 |
| `mod_organizer` | MO2 integration | 150 |
| `vortex` | Vortex integration | 150 |

### Custom Tinkers

```zig
pub const my_tinker = launcher.Tinker{
    .id = "my_custom_tinker",
    .priority = 80,
    .isEnabled = struct {
        fn f(gc: *const config.GameConfig) bool {
            return gc.custom_setting;
        }
    }.f,
    .modifyEnv = struct {
        fn f(allocator: std.mem.Allocator, env: *std.process.EnvMap) !void {
            try env.put("MY_VAR", "value");
        }
    }.f,
};
```

## 🔧 Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `STL_CONFIG_DIR` | Configuration directory | `~/.config/stl-next` |
| `STL_LOG_LEVEL` | Log verbosity: debug, info, warn, error | `info` |
| `STL_JSON_OUTPUT` | Force JSON output for scripts | `false` |

## 📊 Performance Targets

| Operation | Target | Bash STL |
|-----------|--------|----------|
| Startup overhead | <100ms | 2-5s |
| Config load | <5ms | 200-500ms |
| VDF parse (text) | <10ms | 500ms+ |
| VDF seek (binary) | <1ms | N/A |

## 🗺️ Roadmap

### Phase 1: Core Engine ✅
- [x] Steam installation discovery
- [x] VDF parser (text)
- [x] Configuration system
- [x] Basic launch flow

### Phase 2: VDF Binary Parser
- [ ] Binary VDF streaming parser
- [ ] AppInfo.vdf fast seeking
- [ ] Collections (LevelDB)

### Phase 3: Tinker Modules
- [ ] MangoHud integration
- [ ] GameMode integration
- [ ] Gamescope wrapper
- [ ] ReShade installer

### Phase 4: Mod Manager Integration
- [ ] Mod Organizer 2
- [ ] Vortex
- [ ] NXM link handler

### Phase 5: GUI
- [ ] Raylib-based TUI/GUI
- [ ] Pre-launch requester
- [ ] Configuration editor

## 📜 License

GPL-3.0 - Same as original SteamTinkerLaunch

## 🙏 Acknowledgments

- [SteamTinkerLaunch](https://github.com/sonic2kk/steamtinkerlaunch) - Original Bash implementation
- [Proton-GE](https://github.com/GloriousEggroll/proton-ge-custom) - Custom Proton builds
- [MangoHud](https://github.com/flightlessmango/MangoHud) - Performance overlay

