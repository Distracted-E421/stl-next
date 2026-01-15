# Non-Steam Games Guide

STL-Next fully supports non-Steam games, including:
- Native Linux games (binaries, AppImages)
- Windows games via Wine/Proton
- Games from GOG, Epic, Amazon, and other stores
- Flatpak and Snap applications

Non-Steam games get all the same features as Steam games: MangoHud, Gamescope, GameMode, winetricks, custom commands, and SteamGridDB artwork.

---

## Quick Start

### Add a Native Linux Game

```bash
stl-next add-game "Celeste" ~/Games/Celeste/Celeste --native
```

### Add a Windows Game

```bash
stl-next add-game "Hades" ~/Games/Hades/Hades.exe --windows
```

### List All Non-Steam Games

```bash
stl-next list-nonsteam
```

### Import from Heroic (Epic/GOG/Amazon)

```bash
stl-next import-heroic
```

---

## Command Reference

### `add-game <name> <executable> [flags]`

Add a non-Steam game to STL-Next.

**Flags:**
- `--native` - Native Linux game (default)
- `--windows` - Windows game requiring Wine/Proton
- `--flatpak` - Flatpak application
- `--appimage` - AppImage file

**Examples:**

```bash
# Native Linux game
stl-next add-game "Cave Story" ~/Games/CaveStory/CaveStory --native

# Windows game
stl-next add-game "Disco Elysium" ~/Games/DiscoElysium/disco.exe --windows

# AppImage
stl-next add-game "Pixelorama" ~/Applications/Pixelorama.AppImage --appimage
```

### `remove-game <id>`

Remove a non-Steam game by its ID.

```bash
stl-next remove-game -1001
```

**Note:** Non-Steam games use negative IDs to avoid collision with Steam AppIDs.

### `list-nonsteam`

List all non-Steam games in JSON format.

```bash
stl-next list-nonsteam
```

Output:
```json
[
  {
    "id": -1000,
    "name": "Celeste",
    "platform": "native",
    "executable": "/home/user/Games/Celeste/Celeste",
    "source": "manual"
  },
  {
    "id": -1001,
    "name": "Hades",
    "platform": "windows",
    "executable": "/home/user/Games/Hades/Hades.exe",
    "source": "manual"
  }
]
```

### `import-heroic`

Import games from [Heroic Games Launcher](https://heroicgameslauncher.com/).

Heroic supports:
- Epic Games Store
- GOG Galaxy
- Amazon Prime Gaming

```bash
stl-next import-heroic
# Output: Imported 12 game(s) from Heroic
```

---

## Platform Types

| Platform | Description |
|----------|-------------|
| `native` | Native Linux binary |
| `windows` | Windows game requiring Wine/Proton |
| `flatpak` | Flatpak application |
| `appimage` | AppImage file |
| `snap` | Snap package |
| `web` | Browser-based game |

---

## Game Sources

STL-Next tracks where games came from:

| Source | Description |
|--------|-------------|
| `manual` | Manually added |
| `gog` | GOG Galaxy |
| `epic` | Epic Games Store |
| `amazon` | Amazon Prime Gaming |
| `ea` | EA Origin/EA App |
| `ubisoft` | Ubisoft Connect |
| `itch` | itch.io |
| `humble` | Humble Bundle |
| `gamejolt` | Game Jolt |

---

## Configuration

Non-Steam games are stored in `~/.config/stl-next/nonsteam.json`:

```json
{
  "next_id": -1003,
  "games": [
    {
      "id": -1000,
      "name": "Celeste",
      "platform": "native",
      "source": "manual",
      "executable": "/home/user/Games/Celeste/Celeste",
      "working_dir": null,
      "arguments": "",
      "playtime_minutes": 120,
      "hidden": false,
      "notes": "Great platformer!"
    }
  ]
}
```

### Game Configuration

Each non-Steam game can have its own per-game configuration at:
`~/.config/stl-next/games/<id>.json`

```json
{
  "app_id": -1001,
  "proton_version": "GE-Proton8-25",
  "mangohud": {
    "enabled": true,
    "show_fps": true
  },
  "gamescope": {
    "enabled": true,
    "width": 1920,
    "height": 1080,
    "fsr": true
  },
  "winetricks": {
    "enabled": true,
    "verbs": ["vcrun2019", "dxvk"]
  }
}
```

---

## Windows Games with Wine/Proton

For Windows games, STL-Next handles:

### 1. Wine Prefix Creation

If no prefix exists, STL-Next creates one at:
```
~/.config/stl-next/prefixes/<game-id>/
```

### 2. Proton/Wine Selection

Specify a Proton version in the game config:

```json
{
  "app_id": -1001,
  "proton_version": "GE-Proton8-25"
}
```

Or use system Wine:
```json
{
  "app_id": -1001,
  "proton_version": null
}
```

### 3. Winetricks Integration

Install Windows dependencies:

```json
{
  "winetricks": {
    "enabled": true,
    "verbs": ["vcrun2019", "dxvk", "corefonts"]
  }
}
```

---

## Running Non-Steam Games

Non-Steam games can be launched with:

```bash
# By ID (note: negative number)
stl-next run -- -1001

# Or using the stl-next launcher with the game ID
stl-next -1001
```

---

## SteamGridDB Integration

Fetch artwork for non-Steam games:

```bash
# Search for a game
stl-next search-game "Celeste"
# Found 3 game(s) matching 'Celeste':
#   ID: 36983    Celeste ✓
#   ID: 12345    Celeste Classic
#   ...

# Download artwork using SteamGridDB ID
stl-next artwork 36983
```

Store the SteamGridDB ID in the game config:

```json
{
  "steamgriddb_id": 36983
}
```

---

## Advanced: Game Entry Structure

```zig
pub const NonSteamGame = struct {
    id: i32,                          // Negative ID
    name: []const u8,                 // Display name
    platform: Platform,               // native, windows, etc.
    source: GameSource,               // manual, gog, epic, etc.
    executable: []const u8,           // Path to executable
    working_dir: ?[]const u8,         // Working directory
    arguments: []const u8,            // Launch arguments
    prefix_path: ?[]const u8,         // Wine prefix (Windows games)
    proton_version: ?[]const u8,      // Proton/Wine version
    icon_path: ?[]const u8,           // Path to icon
    steamgriddb_id: ?u32,             // SteamGridDB game ID
    igdb_id: ?u32,                    // IGDB game ID
    tags: []const []const u8,         // Categories/tags
    playtime_minutes: u32,            // Total playtime
    last_played: ?i64,                // Unix timestamp
    hidden: bool,                     // Hidden from main list
    env_vars: []const EnvVar,         // Custom environment
    notes: []const u8,                // User notes
};
```

---

## Future Enhancements

### Planned Imports
- [x] Heroic (Epic/GOG/Amazon)
- [ ] Lutris
- [ ] GOG Galaxy (native)
- [ ] itch.io
- [ ] Legendary CLI

### Planned Features
- [ ] Automatic prefix creation
- [ ] Wine version management
- [ ] Game metadata from IGDB
- [ ] Launch history tracking
- [ ] Backup/restore game configs

---

## Related Documentation

- [Winetricks Guide](./WINETRICKS_GUIDE.md)
- [SteamGridDB Guide](./STEAMGRIDDB_GUIDE.md)
- [Custom Commands Guide](./CUSTOM_COMMANDS.md)

