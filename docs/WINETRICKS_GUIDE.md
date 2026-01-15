# Winetricks Integration Guide

STL-Next provides first-class integration with [Winetricks](https://wiki.winehq.org/Winetricks) for installing Windows components, DLLs, fonts, and runtime libraries into Wine prefixes.

## Overview

Winetricks is essential for many Windows games that require:
- Visual C++ runtime libraries (vcrun2019, vcrun2022)
- DirectX components (d3dcompiler_47, dxvk)
- .NET Framework (dotnet48, dotnet40)
- Audio libraries (xact, faudio)
- Fonts (corefonts, tahoma)

STL-Next runs winetricks **automatically** during the prefix preparation phase, before game launch.

---

## Configuration

### Per-Game Configuration

Edit `~/.config/stl-next/games/<AppID>.json`:

```json
{
  "app_id": 413150,
  "winetricks": {
    "enabled": true,
    "verbs": ["vcrun2019", "dxvk", "corefonts"],
    "silent": true,
    "force": false
  }
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable winetricks integration |
| `verbs` | array | `[]` | List of verbs to install |
| `silent` | bool | `true` | Run without GUI prompts |
| `force` | bool | `false` | Reinstall even if already installed |
| `isolate` | bool | `false` | Use isolated prefix per verb |
| `binary_path` | string | `null` | Custom winetricks binary path |

---

## Common Verb Presets

STL-Next includes preset verb collections for common use cases:

### Basic Runtime (`VerbPresets.basic`)
```
vcrun2019, corefonts
```
Minimal runtime for most games.

### DirectX Essentials (`VerbPresets.dx_essentials`)
```
d3dcompiler_47, dxvk
```
For DirectX 9/10/11 games.

### .NET Legacy (`VerbPresets.dotnet_legacy`)
```
dotnet40, dotnet48, vcrun2019
```
For older games requiring .NET Framework.

### Audio Fix (`VerbPresets.audio_fix`)
```
xact, xact_x64, faudio
```
For games with XAudio issues.

### Full (`VerbPresets.full`)
```
vcrun2019, corefonts, d3dcompiler_47, dxvk, faudio
```
Comprehensive package for maximum compatibility.

---

## Common Verbs Reference

### Runtime Libraries

| Verb | Description |
|------|-------------|
| `vcrun2019` | Visual C++ 2015-2019 runtime |
| `vcrun2022` | Visual C++ 2015-2022 runtime |
| `vcrun6` | Visual C++ 6 runtime |
| `vcrun2010` | Visual C++ 2010 runtime |

### DirectX Components

| Verb | Description |
|------|-------------|
| `dxvk` | DirectX 9/10/11 to Vulkan |
| `vkd3d` | DirectX 12 to Vulkan |
| `d3dcompiler_47` | DirectX shader compiler |
| `d3dx9` | DirectX 9 extensions |
| `d3dx10` | DirectX 10 extensions |
| `d3dx11_43` | DirectX 11 extensions |

### .NET Framework

| Verb | Description |
|------|-------------|
| `dotnet40` | .NET Framework 4.0 |
| `dotnet48` | .NET Framework 4.8 |
| `dotnetdesktop6` | .NET Desktop 6.0 |

### Audio

| Verb | Description |
|------|-------------|
| `xact` | Microsoft XACT (32-bit) |
| `xact_x64` | Microsoft XACT (64-bit) |
| `faudio` | FAudio (XAudio reimplementation) |

### Fonts

| Verb | Description |
|------|-------------|
| `corefonts` | Microsoft core fonts |
| `tahoma` | Tahoma font |
| `liberation` | Liberation fonts |

---

## Troubleshooting

### Winetricks not found

Ensure winetricks is installed:

**NixOS:**
```nix
environment.systemPackages = [ pkgs.winetricks ];
```

**Other distros:**
```bash
# Debian/Ubuntu
sudo apt install winetricks

# Fedora
sudo dnf install winetricks

# Arch
sudo pacman -S winetricks
```

### Verb installation fails

1. Check if the Wine prefix exists:
   ```bash
   ls ~/.local/share/Steam/steamapps/compatdata/<AppID>/pfx
   ```

2. Try manual installation:
   ```bash
   WINEPREFIX=~/.local/share/Steam/steamapps/compatdata/<AppID>/pfx winetricks vcrun2019
   ```

3. Check winetricks logs:
   ```bash
   cat /tmp/winetricks.log
   ```

### Game still crashes after installing verbs

1. Try the `force` option to reinstall:
   ```json
   {
     "winetricks": {
       "enabled": true,
       "verbs": ["vcrun2019"],
       "force": true
     }
   }
   ```

2. Ensure you're using the correct Proton version - some verbs may conflict with Proton's built-in DLLs.

3. Try disabling Proton's built-in DXVK:
   ```bash
   PROTON_USE_WINED3D=1 %command%
   ```

---

## Integration with Proton

When using Proton, STL-Next automatically:

1. Sets `WINEPREFIX` to the game's compatdata directory
2. Points `WINE` to Proton's Wine binary
3. Runs winetricks in the correct environment

**Note:** Some winetricks verbs may conflict with Proton's built-in components. If you encounter issues, try a vanilla Wine prefix first to verify the verb works.

---

## API Reference

### WinetricksConfig

```zig
pub const WinetricksConfig = struct {
    enabled: bool = false,
    verbs: []const []const u8 = &.{},
    silent: bool = true,
    force: bool = false,
    isolate: bool = false,
    binary_path: ?[]const u8 = null,
};
```

### Helper Functions

```zig
// Check if a verb is already installed
pub fn isVerbInstalled(allocator, prefix_path, verb) !bool

// List all available winetricks verbs
pub fn listAvailableVerbs(allocator) ![]const []const u8
```

---

## Related Documentation

- [Game Configuration](./ARCHITECTURE.md#game-configuration)
- [NixOS Installation](./NIXOS_INSTALLATION.md)
- [Bug Verification Matrix](./BUG_VERIFICATION_MATRIX.md)

