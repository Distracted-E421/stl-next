# STL-Next Architecture

**Version**: 0.4.0  
**Status**: Phase 4 Complete

## High-Level Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              STL-NEXT                                     │
├──────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌───────────┐ │
│  │    CLI      │    │   Daemon    │    │    TUI      │    │  GUI (P5) │ │
│  │  (main.zig) │    │(daemon.zig) │    │ (tui.zig)   │    │ (raylib)  │ │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘    └─────┬─────┘ │
│         │                  │                  │                  │       │
│         └──────────────────┴────────┬─────────┴──────────────────┘       │
│                                     │                                     │
│  ┌──────────────────────────────────┴──────────────────────────────────┐ │
│  │                           IPC Layer                                  │ │
│  │        Unix Domain Sockets • JSON Protocol • Event-Driven            │ │
│  └──────────────────────────────────┬──────────────────────────────────┘ │
│                                     │                                     │
│  ┌─────────────┬──────────────┬─────┴─────┬──────────────┬─────────────┐ │
│  │   Config    │   Launcher   │  Tinkers  │   Engine     │   Modding   │ │
│  │   System    │   Pipeline   │  System   │   (Steam)    │   Manager   │ │
│  └─────────────┴──────────────┴───────────┴──────────────┴─────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
src/
├── main.zig              # CLI entry point, command dispatch
├── core/
│   ├── config.zig        # JSON configuration loading/saving
│   └── launcher.zig      # Launch pipeline orchestration
├── engine/
│   ├── steam.zig         # Steam installation discovery
│   ├── vdf.zig           # Text VDF parsing (localconfig, etc.)
│   ├── appinfo.zig       # Binary VDF streaming (appinfo.vdf)
│   └── leveldb.zig       # Steam collections via LevelDB
├── tinkers/
│   ├── mod.zig           # Module exports
│   ├── interface.zig     # Tinker trait definition
│   ├── mangohud.zig      # MangoHud overlay
│   ├── gamescope.zig     # Gamescope compositor
│   └── gamemode.zig      # Feral GameMode
├── ipc/
│   ├── mod.zig           # Module exports
│   ├── protocol.zig      # JSON message definitions
│   ├── server.zig        # Daemon-side socket handling
│   └── client.zig        # Client-side with retry logic
├── ui/
│   ├── mod.zig           # Module exports
│   ├── daemon.zig        # Wait requester daemon logic
│   └── tui.zig           # Terminal UI client
├── modding/
│   ├── mod.zig           # Module exports
│   └── manager.zig       # MO2/Vortex + NXM protocol
└── tests/
    └── edge_cases.zig    # Comprehensive edge case tests
```

## Core Components

### 1. CLI (`main.zig`)

Entry point for all STL-Next operations.

**Commands**:
- `run <AppID>` / `<AppID>` - Launch game
- `info <AppID>` - Show game info (JSON)
- `list-games` - List installed games
- `list-protons` - List Proton versions
- `collections <AppID>` - Show Steam collections
- `benchmark` - Performance benchmark
- `wait <AppID>` - Start daemon
- `tui <AppID>` - Connect TUI client
- `nxm <url>` - Handle NXM link

**Design Decisions**:
- Hyphen-to-underscore conversion for CLI friendliness (`list-games` → `list_games`)
- Numeric-only argument interpreted as AppID shorthand

### 2. Configuration System (`core/config.zig`)

JSON-based per-game configuration.

**Location**: `$XDG_CONFIG_HOME/stl-next/games/{AppID}.json`

**Structure**:
```json
{
  "app_id": 413150,
  "use_native": false,
  "proton_version": "Proton Experimental",
  "launch_options": "-windowed",
  "mangohud": {
    "enabled": true,
    "show_fps": true,
    "position": "top-left",
    "font_size": 24
  },
  "gamescope": {
    "enabled": false,
    "width": 1920,
    "height": 1080,
    "fsr": false
  },
  "gamemode": {
    "enabled": true,
    "renice": -4
  }
}
```

**Key Features**:
- Uses `std.json.parseFromSlice()` for robust parsing
- Graceful defaults for missing fields
- Size limit (1MB) to prevent DoS

### 3. Launch Pipeline (`core/launcher.zig`)

Orchestrates game launching with tinker application.

**Pipeline Stages**:
1. Load game configuration
2. Query Steam for game info
3. Build paths (prefix, scratch, config)
4. Create execution context
5. Initialize environment variables
6. Build argument list
7. Run tinker pipeline
8. Execute via `std.process.Child.spawn()`

**Context Struct**:
```zig
pub const Context = struct {
    allocator: std.mem.Allocator,
    app_id: u32,
    game_name: []const u8,
    install_dir: []const u8,
    proton_path: ?[]const u8,
    prefix_path: []const u8,
    config_dir: []const u8,
    scratch_dir: []const u8,
    game_config: *const GameConfig,
};
```

### 4. Steam Engine (`engine/steam.zig`)

Discovers Steam installation and parses game data.

**Capabilities**:
- Find Steam root path (`~/.steam/steam`, `~/.local/share/Steam`, etc.)
- Parse library folders from `libraryfolders.vdf`
- List installed games via `appmanifest_*.acf`
- Get game info including launch options from `localconfig.vdf`
- List Proton versions

**Launch Options Parsing**:
```
localconfig.vdf
└── UserLocalConfigStore
    └── Software
        └── Valve
            └── Steam
                └── Apps
                    └── {AppID}
                        └── LaunchOptions = "-windowed"
```

### 5. Tinker System (`tinkers/`)

Modular system for launch-time modifications.

**Interface**:
```zig
pub const Tinker = struct {
    id: []const u8,
    name: []const u8,
    priority: Priority,
    
    // Function pointers
    isEnabledFn: *const fn (ctx: *const Context) bool,
    applyFn: *const fn (ctx: *const Context, env: *EnvMap, args: *ArrayList) anyerror!void,
};
```

**Available Tinkers**:
| ID | Priority | Effect |
|----|----------|--------|
| `mangohud` | ENV_SETUP (1000) | Sets `MANGOHUD=1`, `MANGOHUD_CONFIG` |
| `gamemode` | ENV_SETUP (1000) | Wraps with `gamemoderun` |
| `gamescope` | WRAPPER (500) | Wraps with `gamescope -- ` |

**Priority Order**:
1. CRITICAL (0) - Must run first
2. WRAPPER (500) - Command wrappers
3. ENV_SETUP (1000) - Environment setup
4. POST_LAUNCH (2000) - After launch hooks

### 6. IPC Layer (`ipc/`)

Communication between daemon and clients.

**Protocol**: JSON over Unix Domain Sockets

**Components**:
- `protocol.zig` - Message types, serialization
- `server.zig` - Non-blocking socket server
- `client.zig` - Retry-enabled client

See [IPC_PROTOCOL.md](IPC_PROTOCOL.md) for full specification.

### 7. Wait Requester Daemon (`ui/daemon.zig`)

Countdown-based launch manager.

**State Machine**:
```
INITIALIZING → COUNTDOWN → LAUNCHING → (game runs)
                   ↓
               WAITING (paused)
                   ↓
               COUNTDOWN (resumed)
                   
COUNTDOWN → FINISHED (aborted)
```

**Features**:
- Configurable countdown (`STL_COUNTDOWN` env var)
- Skip option (`STL_SKIP_WAIT`)
- Tinker toggling during countdown
- Config save on launch

### 8. NXM Handler (`modding/manager.zig`)

Nexus Mods protocol link parser.

**URL Formats Supported**:
```
# Mod download
nxm://{game}/mods/{mod_id}/files/{file_id}?key={key}&expires={time}

# Collection (THE BUG FIX!)
nxm://{game}/collections/{slug}/revisions/{revision}?key={key}
```

**Key Fix** - URL encoding for Wine:
```zig
pub fn encodeForWine(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
    // Wine interprets / as command switches
    // We encode them as %2F
    for (rest) |c| {
        switch (c) {
            '/' => try result.appendSlice("%2F"),
            ' ' => try result.appendSlice("%20"),
            '"' => try result.appendSlice("%22"),
            else => try result.append(c),
        }
    }
}
```

## Data Flow

### Game Launch Flow

```
User: stl-next 413150
         │
         ▼
    ┌─────────────────┐
    │   Parse CLI     │
    │   (main.zig)    │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │  Load Config    │
    │  (config.zig)   │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │  Steam Engine   │  ← Find game, Proton, launch options
    │  (steam.zig)    │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │ Build Context   │
    │ (launcher.zig)  │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │  Tinker Loop    │  ← MangoHud, Gamescope, GameMode
    │   (foreach)     │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │  Child.spawn()  │  → Game Process
    │   (launcher)    │
    └─────────────────┘
```

### Wait Requester Flow

```
User: stl-next wait 413150
         │
         ▼
    ┌─────────────────┐
    │  Init Daemon    │
    │  (daemon.zig)   │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │  Start Server   │  → Socket created
    │  (server.zig)   │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │  Countdown Loop │
    │    ┌───────┐    │
    │    │ Poll  │←───┼── TUI Client
    │    │  +    │    │
    │    │ Timer │    │
    │    └───────┘    │
    └────────┬────────┘
             │
      [countdown=0 or PROCEED]
             │
             ▼
    ┌─────────────────┐
    │  Save Config    │
    │  Launch Game    │
    └─────────────────┘
```

## Memory Management

STL-Next uses Zig's allocator-based memory model:

1. **General Purpose Allocator** in main for CLI
2. **Test Allocator** for tests (leak detection)
3. **Arena Allocator** for temporary parsing (not yet used)

**Patterns**:
```zig
// Allocate with errdefer cleanup
const path = try allocator.dupe(u8, input);
errdefer allocator.free(path);

// Resource cleanup in deinit
pub fn deinit(self: *Self) void {
    allocator.free(self.socket_path);
}
```

## Error Handling

All errors are explicit via Zig's error unions.

**Categories**:
- `NxmError` - NXM URL parsing failures
- `ClientError` - IPC client failures
- Standard errors (FileNotFound, etc.)

**Pattern**:
```zig
const result = operation() catch |err| {
    switch (err) {
        error.FileNotFound => return defaults(),
        else => return err,
    }
};
```

## Testing Strategy

### Unit Tests

Located within each module:
```zig
test "socket path generation" {
    const path = try getSocketPath(std.testing.allocator, 413150);
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, "413150.sock"));
}
```

### Edge Case Tests

`src/tests/edge_cases.zig` covers:
- NXM URL edge cases (the bug fix!)
- IPC protocol robustness
- Config defaults
- Boundary conditions
- Memory safety

### Running Tests

```bash
zig build test
# Or with development shell
nix develop --command zig build test
```

## Performance Targets

| Operation | Target | Actual |
|-----------|--------|--------|
| Steam Discovery | < 10ms | ~0.14ms |
| Game Lookup | < 50ms | ~0.35ms |
| List Games | < 100ms | ~12ms |
| Config Load | < 10ms | ~0.5ms |
| Total Launch Overhead | < 100ms | ~15ms |

## Future Architecture (Phase 5+)

### Planned Additions

```
src/
├── gui/
│   ├── main.zig          # Raylib entry
│   ├── wait_requester.zig
│   └── config_editor.zig
├── tinkers/
│   ├── reshade.zig       # NEW
│   ├── vkbasalt.zig      # NEW
│   └── obs.zig           # NEW
└── modding/
    ├── vortex.zig        # NEW: Full Vortex integration
    └── mo2.zig           # NEW: Full MO2 integration
```

### Potential Refactors

1. **Event System** - Replace polling with async events
2. **Plugin System** - External tinker loading
3. **Multi-Client IPC** - Broadcast state changes
4. **D-Bus Integration** - Desktop notifications

