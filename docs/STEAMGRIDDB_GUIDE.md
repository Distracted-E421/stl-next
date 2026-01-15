# SteamGridDB Integration Guide

STL-Next integrates with [SteamGridDB](https://www.steamgriddb.com/) to provide beautiful artwork for your games, including non-Steam games.

## Overview

SteamGridDB provides:
- **Grid images** (600x900) - Library covers
- **Hero images** (1920x620) - Library backgrounds
- **Logo images** - Transparent game logos
- **Icon images** - Application icons

---

## Getting Started

### 1. Get an API Key

1. Go to [SteamGridDB](https://www.steamgriddb.com/)
2. Create an account / log in
3. Go to [Profile → Preferences → API](https://www.steamgriddb.com/profile/preferences/api)
4. Generate a new API key

### 2. Set the API Key

**Option A: Environment Variable (Recommended)**

```bash
# Add to ~/.bashrc, ~/.zshrc, or NixOS config
export STEAMGRIDDB_API_KEY="your-api-key-here"
```

**NixOS:**

```nix
# configuration.nix or home.nix
environment.sessionVariables = {
  STEAMGRIDDB_API_KEY = "your-api-key-here";
};
```

**Option B: Per-Command**

```bash
STEAMGRIDDB_API_KEY="your-key" stl-next artwork 413150
```

---

## Commands

### Search for a Game

```bash
stl-next search-game "Stardew Valley"
```

Output:
```
Found 3 game(s) matching 'Stardew Valley':

  ID: 3793     Stardew Valley ✓
  ID: 36912    Stardew Valley: Original Soundtrack
  ID: 45123    Stardew Valley TITS

Use the ID to fetch artwork:
  stl-next artwork <id>
```

The ✓ indicates a verified entry.

### Fetch Artwork by Steam AppID

```bash
stl-next artwork 413150
```

Output:
```
Fetching artwork for Steam AppID 413150...
Found 15 grid image(s):
  - https://cdn2.steamgriddb.com/file/sgdb-cdn/grid/... (600x900, score: 5)
  - https://cdn2.steamgriddb.com/file/sgdb-cdn/grid/... (600x900, score: 3)
  ...

Downloaded to: /home/user/.cache/stl-next/steamgriddb/grids/413150_12345.png
```

### Fetch Artwork by SteamGridDB ID

For non-Steam games, use the SteamGridDB game ID:

```bash
stl-next artwork 3793
```

---

## Image Types

### Grid (600x900)
Vertical cover art for library view.

### Hero (1920x620)
Horizontal banner for library backgrounds.

### Logo
Transparent game logo for overlays.

### Icon
Square icon for shortcuts.

---

## Cache Location

Downloaded images are cached at:
```
~/.cache/stl-next/steamgriddb/
├── grids/
│   └── <app_id>_<image_id>.png
├── heroes/
│   └── <app_id>_<image_id>.png
├── logos/
│   └── <app_id>_<image_id>.png
└── icons/
    └── <app_id>_<image_id>.png
```

---

## Per-Game Configuration

Store artwork preferences in game configs:

```json
{
  "app_id": 413150,
  "steamgriddb": {
    "enabled": true,
    "prefer_animated": false,
    "grid_style": "alternate",
    "hero_style": "blurred",
    "auto_download": true,
    "game_id": 3793
  }
}
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable auto artwork fetching |
| `prefer_animated` | bool | `false` | Prefer animated images |
| `grid_style` | string | `"alternate"` | Preferred grid style |
| `hero_style` | string | `"blurred"` | Preferred hero style |
| `auto_download` | bool | `true` | Download on first launch |
| `game_id` | u32 | `null` | SteamGridDB game ID (for non-Steam) |

---

## Image Styles

### Grid Styles
- `alternate` - Alternative design
- `blurred` - Blurred background
- `white_logo` - White logo variant
- `material` - Material design
- `no_logo` - No logo overlay

### Hero Styles
- `alternate`
- `blurred`
- `material`

---

## Non-Steam Games

For non-Steam games, first search for the game:

```bash
stl-next search-game "Celeste"
# ID: 36983    Celeste ✓
```

Then save the ID in your game config:

```json
{
  "app_id": -1001,
  "steamgriddb": {
    "enabled": true,
    "game_id": 36983
  }
}
```

---

## API Reference

### Programmatic Usage

```zig
const steamgriddb = @import("engine/steamgriddb.zig");

// Initialize client
var client = try steamgriddb.SteamGridDBClient.init(allocator, null);
defer client.deinit();

// Search for a game
const results = try client.searchGame("Stardew Valley");
defer {
    for (results) |*r| r.deinit(allocator);
    allocator.free(results);
}

// Get images by Steam AppID
const grids = try client.getImagesByAppId(413150, .grid);

// Get images by SteamGridDB ID with filters
const heroes = try client.getImages(
    3793,          // SteamGridDB game ID
    .hero,         // Image type
    .blurred,      // Style preference
    .dim_1920x620, // Dimensions
);

// Download an image
const path = try client.downloadImage(&grids[0], .grid, 413150);
```

---

## Troubleshooting

### "No API key provided"

Set the `STEAMGRIDDB_API_KEY` environment variable.

### "No games found"

- Check spelling
- Try different search terms
- Game may not be in SteamGridDB yet

### "API returned 401"

Your API key is invalid. Generate a new one.

### "API returned 429"

Rate limited. The free tier allows 1000 requests/day.

---

## Rate Limits

| Tier | Daily Requests |
|------|----------------|
| Free | 1,000 |
| Supporter | 10,000 |
| Patron | Unlimited |

STL-Next caches downloaded images to minimize API calls.

---

## Contributing Artwork

SteamGridDB is community-driven! You can:

1. Upload your own artwork
2. Vote on existing artwork
3. Report inappropriate content

Visit [SteamGridDB](https://www.steamgriddb.com/) to contribute.

---

## Related Documentation

- [Non-Steam Games Guide](./NONSTEAM_GAMES.md)
- [Architecture Overview](./ARCHITECTURE.md)
- [Feature Roadmap](./FEATURE_ROADMAP.md)

