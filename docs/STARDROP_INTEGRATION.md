# Stardrop Integration Plan

This document outlines the research and implementation plan for first-class Stardrop mod manager support in STL-Next.

## What is Stardrop?

[Stardrop](https://github.com/Floogen/Stardrop) is a **cross-platform, open-source mod manager** specifically designed for Stardew Valley. Unlike Vortex (which is Windows-only and requires Wine), Stardrop runs natively on Linux.

### Key Features

- **Native Linux support** - No Wine required
- **Avalonia UI framework** - Cross-platform .NET
- **SMAPI integration** - Automatic SMAPI detection and updates
- **NexusMods integration** - API key support for downloads
- **Profile management** - Multiple mod configurations
- **Dependency resolution** - Automatic mod dependency handling
- **Open source** - GPLv3 licensed

### GitHub Repository

- URL: https://github.com/Floogen/Stardrop
- Stars: ~600+
- Last activity: Active development
- License: GPLv3

---

## Why Integrate Stardrop?

### Advantages Over Vortex/MO2 for Stardew Valley

| Feature | Stardrop | Vortex (Wine) | MO2 (Wine) |
|---------|----------|---------------|------------|
| Linux Native | ✅ Yes | ❌ No | ❌ No |
| Performance | ✅ Fast | ⚠️ Slow | ⚠️ Slow |
| Complexity | ✅ Simple | ❌ High | ❌ High |
| Stardew-specific | ✅ Yes | ❌ Generic | ❌ Generic |
| SMAPI support | ✅ First-class | ⚠️ Manual | ⚠️ Manual |
| Collections | ✅ Planned | ✅ Yes | ❌ No |

### User Benefits

1. **No Wine overhead** - Faster mod management
2. **Better SMAPI integration** - Auto-updates, compatibility checks
3. **Simpler setup** - No Wine prefix configuration needed
4. **Active development** - Features being added regularly

---

## Current Stardrop Status

Based on the GitHub repository analysis:

### Implemented Features

- ✅ Mod browsing and installation
- ✅ SMAPI detection and installation
- ✅ Profile management
- ✅ Dependency resolution
- ✅ NexusMods API integration
- ✅ Mod updates checking
- ✅ Native Linux builds

### Open Issues (as of Jan 2026)

| Issue | Description | Relevant to STL-Next |
|-------|-------------|---------------------|
| #290 | Linux ZIP extraction issues | May need workaround |
| #306 | Linux UI scaling on HiDPI | User education |
| #284 | Flatpak game detection | Path handling needed |
| #282 | NixOS .NET runtime | **Critical for our users** |

### NixOS Specific Concerns

Issue #282 highlights .NET runtime issues on NixOS. Solutions:

1. **Bundled runtime**: Stardrop could bundle .NET
2. **Nix package**: Package Stardrop properly for NixOS
3. **FHS wrapper**: Use `buildFHSEnv` for compatibility

---

## Integration Architecture

### Detection Strategy

```zig
// Proposed addition to src/modding/stardrop.zig

pub const StardropConfig = struct {
    executable_path: []const u8,
    data_directory: []const u8,
    smapi_path: ?[]const u8,
    active_profile: ?[]const u8,
};

pub fn detectStardrop(allocator: std.mem.Allocator) !?StardropConfig {
    // Check common installation locations
    const paths = [_][]const u8{
        // Flatpak
        "~/.var/app/io.github.floogen.Stardrop/",
        // AppImage (common location)
        "~/.local/share/Stardrop/",
        "~/.local/bin/Stardrop",
        // System install
        "/usr/share/stardrop/",
        "/opt/stardrop/",
        // NixOS
        // (Will be in nix store, need to check PATH)
    };
    
    for (paths) |path| {
        if (try fileExists(path)) {
            return StardropConfig{
                .executable_path = path,
                // ...
            };
        }
    }
    
    // Check if 'stardrop' is in PATH
    if (try findInPath("stardrop")) |exe_path| {
        return StardropConfig{
            .executable_path = exe_path,
            // ...
        };
    }
    
    return null;
}
```

### NXM Link Forwarding

When STL-Next receives an NXM link for Stardew Valley:

```
1. User clicks NXM link on Nexus
2. Browser triggers: nxm://stardewvalley/mods/123/files/456
3. STL-Next intercepts (registered as nxm:// handler)
4. STL-Next checks if Stardrop is installed
5. If yes: Forward link to Stardrop
6. If no: Show dialog suggesting Stardrop installation
```

### Launch Integration

```zig
pub fn launchWithStardrop(
    allocator: std.mem.Allocator,
    stardrop_config: StardropConfig,
    game_config: GameConfig,
) !void {
    // Option 1: Launch Stardrop to manage mods, then game
    // Option 2: Let Stardrop handle the entire launch
    // Option 3: STL-Next applies tinkers, Stardrop applies mods
    
    // Recommended: Option 3 for maximum flexibility
    // STL-Next handles: MangoHud, GameMode, Gamescope
    // Stardrop handles: SMAPI, mod load order
}
```

---

## Implementation Phases

### Phase 1: Detection & Configuration (2 days)

- [ ] Create `src/modding/stardrop.zig`
- [ ] Implement Stardrop detection
- [ ] Add Stardrop to CLI output
- [ ] Store Stardrop path in game config

### Phase 2: NXM Forwarding (2 days)

- [ ] Check game domain in NXM link
- [ ] If `stardewvalley`, offer Stardrop forwarding
- [ ] Launch Stardrop with NXM URL as argument
- [ ] Handle Stardrop not installed gracefully

### Phase 3: Launch Integration (3 days)

- [ ] Detect if game uses SMAPI
- [ ] Integrate Stardrop launch mode
- [ ] Pass tinker environment to Stardrop-launched games
- [ ] Handle exit cleanup

### Phase 4: Collections Support (Future)

- [ ] Research Nexus Collections API
- [ ] Implement collection import
- [ ] Batch mod installation
- [ ] Profile creation from collection

---

## Nexus Collections Integration

### What Are Nexus Collections?

Nexus Collections are curated mod lists that include:
- Mod IDs and versions
- Installation order
- Configuration files
- Compatibility patches
- (Optionally) INI tweaks and load orders

### Collection URL Format

```
nxm://stardewvalley/collections/tckf0m/revisions/100
```

Components:
- `stardewvalley`: Game domain
- `collections`: Type indicator
- `tckf0m`: Collection slug (unique identifier)
- `revisions/100`: Specific revision number

### API Endpoint

```
https://api.nexusmods.com/v1/games/stardewvalley/collections/{slug}/revisions/{revision}
```

Returns JSON with:
- Mod list
- File IDs
- Installation instructions
- Dependencies

### Integration Plan

```zig
pub const NexusCollection = struct {
    slug: []const u8,
    revision: u32,
    name: []const u8,
    mod_count: u32,
    mods: []CollectionMod,
};

pub const CollectionMod = struct {
    mod_id: u32,
    file_id: u32,
    name: []const u8,
    version: []const u8,
    optional: bool,
};

pub fn fetchCollection(
    allocator: std.mem.Allocator,
    api_key: []const u8,
    game_domain: []const u8,
    slug: []const u8,
    revision: u32,
) !NexusCollection {
    // API call to Nexus
    // Parse response
    // Return structured data
}

pub fn installCollection(
    allocator: std.mem.Allocator,
    collection: NexusCollection,
    stardrop: StardropConfig,
) !void {
    // For each mod in collection:
    //   1. Check if already installed
    //   2. Download if needed
    //   3. Install via Stardrop
    //   4. Configure settings
}
```

---

## NixOS Packaging

For NixOS users, Stardrop needs proper packaging:

```nix
# stardrop.nix
{ lib
, buildDotnetModule
, fetchFromGitHub
, dotnetCorePackages
, libX11
, libICE
, libSM
, fontconfig
, ... }:

buildDotnetModule rec {
  pname = "stardrop";
  version = "2.5.0";  # Check latest

  src = fetchFromGitHub {
    owner = "Floogen";
    repo = "Stardrop";
    rev = "v${version}";
    sha256 = "...";
  };

  projectFile = "Stardrop.Desktop/Stardrop.Desktop.csproj";
  nugetDeps = ./deps.nix;

  dotnet-sdk = dotnetCorePackages.sdk_8_0;
  dotnet-runtime = dotnetCorePackages.runtime_8_0;

  buildInputs = [
    libX11
    libICE
    libSM
    fontconfig
  ];

  meta = with lib; {
    description = "Cross-platform Stardew Valley mod manager";
    homepage = "https://github.com/Floogen/Stardrop";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
```

---

## Testing Plan

### Manual Testing

1. **Install Stardrop** (AppImage or build from source)
2. **Configure STL-Next** to detect Stardrop
3. **Test NXM link** forwarding
4. **Launch game** through STL-Next with Stardrop mods
5. **Verify mods load** correctly in game

### Automated Testing

```zig
test "detect stardrop - appimage" {
    // Mock filesystem with Stardrop AppImage
    // Call detectStardrop()
    // Verify config returned
}

test "nxm forward to stardrop" {
    // Parse NXM link
    // Check game domain is stardewvalley
    // Verify Stardrop launch command built correctly
}
```

---

## User Documentation

### Setting Up Stardrop with STL-Next

```markdown
## Quick Start

1. Download Stardrop from GitHub releases
2. Extract AppImage to ~/.local/bin/Stardrop
3. Make executable: chmod +x ~/.local/bin/Stardrop
4. Run STL-Next detection: stl-next detect-modmanager 413150
5. Should show: "Detected: Stardrop at ~/.local/bin/Stardrop"

## Using NXM Links

1. In Stardrop settings, enable "Register as NXM handler"
2. STL-Next will forward Stardew Valley NXM links to Stardrop
3. For other games, STL-Next handles links directly

## Launching with Mods

1. Manage mods in Stardrop
2. Launch game from Steam (with STL-Next)
3. STL-Next applies tinkers (MangoHud, etc.)
4. SMAPI loads mods configured in Stardrop
```

---

## Resources

- [Stardrop GitHub](https://github.com/Floogen/Stardrop)
- [SMAPI Documentation](https://stardewvalleywiki.com/Modding:Player_Guide)
- [Nexus Mods API](https://app.swaggerhub.com/apis-docs/NexusMods/nexus-mods_public_api_params_in_form_data/1.0)
- [Avalonia UI](https://avaloniaui.net/) (Stardrop's UI framework)

---

## Timeline

| Phase | Est. Duration | Dependencies |
|-------|---------------|--------------|
| Research (this doc) | ✅ Complete | None |
| Detection | 2 days | None |
| NXM Forwarding | 2 days | Detection |
| Launch Integration | 3 days | Forwarding |
| NixOS Packaging | 2 days | Can parallel |
| Collections | 5 days | All above |
| **Total** | **~14 days** | |

---

## Open Questions

1. **Should Stardrop handle all SMAPI games?**
   - Currently Stardrop is Stardew-specific
   - May expand to other SMAPI-supported games

2. **How to handle Stardrop updates?**
   - Auto-update check?
   - Nix flake input?

3. **Collection caching strategy?**
   - Download all mods upfront?
   - Lazy download on demand?

4. **Profile sync between STL-Next and Stardrop?**
   - Who is source of truth?
   - How to handle conflicts?

