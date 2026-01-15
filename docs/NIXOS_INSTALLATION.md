# STL-Next on NixOS

This guide covers installation and configuration of STL-Next specifically for NixOS systems. NixOS has unique characteristics that require special handling.

## Why NixOS Needs (and deserves) Special Instructions

NixOS (for user's that somehow missed the memo on the box) differs from traditional Linux distributions in several key ways:

1. **Immutable filesystem**: `/usr/bin`, `/lib` etc. are read-only
2. **Nix store paths**: All software lives in `/nix/store/`
3. **FHS incompatibility**: Most binaries expect standard paths
4. **Declarative configuration**: System state defined in `.nix` files
5. **Reproducibility**: Same config = same system

As an avid Nix enjoyer, I get very fed up being a second class citizen in an already second class ecosystem to many (feels bad man). Therefore, STL-Next is designed with NixOS in mind from the start, and as a first class citizen.

---

## Installation Methods

### Method 1: Nix Flake (Recommended)

Add STL-Next to your system flake:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    stl-next.url = "github:e421/stl-next";  # Or path:/path/to/stl-next
  };

  outputs = { self, nixpkgs, stl-next, ... }: {
    nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        stl-next.nixosModules.default
      ];
    };
  };
}
```

Then in your configuration:

```nix
# configuration.nix
{
  programs.stl-next = {
    enable = true;
    registerNxmHandler = true;  # Auto-register as NXM protocol handler
  };
}
```

### Method 1b: Home Manager (User-Level)

For per-user installation with Home Manager:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    stl-next.url = "github:e421/stl-next";
  };

  outputs = { self, nixpkgs, home-manager, stl-next, ... }: {
    homeConfigurations."user@host" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        ./home.nix
        stl-next.homeManagerModules.default
      ];
    };
  };
}
```

Then in your home.nix:

```nix
# home.nix
{
  programs.stl-next = {
    enable = true;
    registerNxmHandler = true;
    countdownSeconds = 10;
    defaultTinkers = {
      mangohud = false;
      gamescope = false;
      gamemode = true;  # Enable GameMode by default
    };
  };
}
```

### Method 2: Development Shell

For development or testing:

```bash
# Clone the repo
git clone https://github.com/yourusername/stl-next.git
cd stl-next

# Enter development shell
nix develop

# Build
zig build

# Run tests
zig build test

# Install locally
zig build install --prefix ~/.local
```

### Method 3: Home Manager

For user-level installation:

```nix
# home.nix
{ pkgs, ... }:
{
  home.packages = [
    (pkgs.callPackage /path/to/stl-next { })
  ];

  # Or with flakes
  # stl-next.homeManagerModules.default
}
```

---

## NixOS-Specific Configuration

### Steam Integration

STL-Next works with both native and Flatpak Steam on NixOS:

```nix
# For native Steam (recommended on NixOS)
programs.steam = {
  enable = true;
  remotePlay.openFirewall = true;
  dedicatedServer.openFirewall = true;
  
  # Add STL-Next as compatibility tool
  extraCompatPackages = [
    pkgs.stl-next  # When packaged
  ];
};
```

### GPU Drivers

Ensure your GPU drivers are properly configured:

```nix
# For NVIDIA
hardware.nvidia = {
  modesetting.enable = true;
  powerManagement.enable = false;
  open = false;  # Use proprietary driver
  nvidiaSettings = true;
};

# For AMD
hardware.amdgpu.initrd.enable = true;

# For Intel
hardware.graphics = {
  enable = true;
  extraPackages = with pkgs; [
    intel-media-driver
    vaapiIntel
  ];
};
```

### MangoHud

MangoHud is a common Tinker module. On NixOS:

```nix
programs.mangohud = {
  enable = true;
  # Or as a package
};

# Or just add to system packages
environment.systemPackages = with pkgs; [
  mangohud
];
```

### GameMode

```nix
programs.gamemode = {
  enable = true;
  settings = {
    general = {
      renice = 10;
    };
    gpu = {
      apply_gpu_optimisations = "accept-responsibility";
      gpu_device = 0;
    };
  };
};
```

### Gamescope

```nix
programs.gamescope = {
  enable = true;
  capSysNice = true;  # For better scheduling
};
```

---

## Paths and Directories

STL-Next uses XDG-compliant paths on NixOS:

| Purpose | Path |
|---------|------|
| Configuration | `~/.config/stl-next/` |
| Data | `~/.local/share/stl-next/` |
| Cache | `~/.cache/stl-next/` |
| Logs | `~/.local/share/stl-next/logs/` |
| Game configs | `~/.config/stl-next/games/` |
| IPC socket | `$XDG_RUNTIME_DIR/stl-next.sock` |

These paths work correctly with NixOS's home directory structure.

---

## Environment Variables

STL-Next respects these NixOS-relevant environment variables:

```bash
# Steam paths (auto-detected)
STEAM_COMPAT_CLIENT_INSTALL_PATH
STEAM_COMPAT_DATA_PATH

# XDG paths (standard on NixOS)
XDG_CONFIG_HOME
XDG_DATA_HOME
XDG_CACHE_HOME
XDG_RUNTIME_DIR

# Wine/Proton
WINEPREFIX
PROTON_LOG
```

---

## Troubleshooting NixOS Issues

### Issue: Binary not found after install

**Symptom**: `stl-next: command not found`

**Solution**: Ensure the package is in your path:

```nix
# Add to configuration.nix or home.nix
environment.systemPackages = [ pkgs.stl-next ];

# Or for development
nix develop  # Activates the dev shell with all deps
```

### Issue: Steam can't find STL-Next

**Symptom**: STL-Next not appearing in compatibility tools

**Solution**:

1. Check installation location:

```bash
ls ~/.local/share/Steam/compatibilitytools.d/
# Should contain stl-next/
```

1. For system install, use `extraCompatPackages`:

```nix
programs.steam.extraCompatPackages = [ pkgs.stl-next ];
```

### Issue: IPC socket permission denied

**Symptom**: Daemon can't create socket

**Solution**: Check `XDG_RUNTIME_DIR`:

```bash
echo $XDG_RUNTIME_DIR
# Should be /run/user/1000 or similar

# If not set:
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
```

### Issue: Proton not detected

**Symptom**: STL-Next can't find Proton installations

**Solution**: Check Steam library paths:

```bash
stl-next list-proton

# If empty, verify Steam paths:
ls ~/.local/share/Steam/compatibilitytools.d/
ls ~/.steam/steam/steamapps/common/
```

### Issue: Game launch fails with "command not found"

**Symptom**: MangoHud/gamemoderun not found

**Solution**: Add packages to system:

```nix
environment.systemPackages = with pkgs; [
  mangohud
  gamemode
  gamescope
];
```

---

## NixOS vs Other Distributions

| Feature | NixOS | Traditional Linux |
|---------|-------|-------------------|
| Installation | Declarative Nix | Package manager |
| Path handling | FHS shim automatic | Standard paths |
| Dependency management | Nix closure | Shared libraries |
| Updates | `nixos-rebuild` | `apt/dnf/pacman` |
| Rollback | Trivial | Complex |
| Reproducibility | 100% | Best-effort |

STL-Next handles all these differences automatically when installed via Nix.

---

## Development on NixOS

### Building from Source

```bash
# Clone
git clone https://github.com/yourusername/stl-next.git
cd stl-next

# Enter dev shell (includes Zig, all dependencies)
nix develop

# Build
zig build

# Run tests
zig build test

# Build with specific options
zig build -Doptimize=ReleaseFast

# Install to user directory
mkdir -p ~/.local/share/Steam/compatibilitytools.d/stl-next
cp zig-out/bin/stl-next ~/.local/share/Steam/compatibilitytools.d/stl-next/
```

### Running the Test Suite

```bash
# All tests
zig build test

# Specific test
zig build test -- --test-filter "NXM"

# With verbose output
zig build test 2>&1 | head -100
```

### Debugging on NixOS

```bash
# Run with debug logging
STL_LOG=debug stl-next launch 12345

# Check logs
tail -f ~/.local/share/stl-next/logs/latest.log

# IPC debugging
STL_LOG=debug stl-next daemon &
stl-next client status
```

---

## Integration with NixOS Services

### SystemD User Service (Optional)

You can run STL-Next daemon as a user service:

```nix
# home.nix
systemd.user.services.stl-next-daemon = {
  Unit = {
    Description = "STL-Next Daemon";
    After = [ "graphical-session.target" ];
  };
  Service = {
    ExecStart = "${pkgs.stl-next}/bin/stl-next daemon";
    Restart = "on-failure";
    RestartSec = 5;
  };
  Install = {
    WantedBy = [ "graphical-session.target" ];
  };
};
```

---

## Known NixOS Limitations

1. **Flatpak Steam**: Works but requires extra Flatpak permissions
2. **Snap**: Not supported on NixOS (and not recommended)
3. **Steam Deck**: Use SteamOS, not NixOS
4. **DXVK/VKD3D**: Automatically handled by Proton, no STL-Next config needed

---

## Reporting NixOS-Specific Issues

When reporting bugs, please include:

```bash
# System info
nixos-version
nix --version

# STL-Next version
stl-next --version

# Relevant config
cat /etc/nixos/configuration.nix | grep -A20 "programs.steam"

# Logs
cat ~/.local/share/stl-next/logs/latest.log
```

---

## Resources

- [NixOS Wiki - Gaming](https://wiki.nixos.org/wiki/Gaming)
- [NixOS Wiki - Steam](https://wiki.nixos.org/wiki/Steam)
- [Nix Packages - Proton](https://search.nixos.org/packages?query=proton)
- [STL-Next Documentation](./README.md)
