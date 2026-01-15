# Custom Commands Guide

STL-Next supports custom shell commands that run before and after game launch. This is useful for:

- Starting/stopping services
- Mounting/unmounting filesystems
- Killing conflicting processes
- Running game-specific fix scripts
- Performance tuning (CPU governor, etc.)
- Sending notifications

---

## Quick Start

Edit your game configuration at `~/.config/stl-next/games/<AppID>.json`:

```json
{
  "app_id": 413150,
  "custom_commands": {
    "enabled": true,
    "pre_launch": [
      {
        "name": "Kill Discord",
        "command": "pkill -f discord || true",
        "wait": true
      }
    ],
    "post_exit": [
      {
        "name": "Notification",
        "command": "notify-send 'STL-Next' 'Game has exited'",
        "wait": false
      }
    ]
  }
}
```

---

## Configuration

### CustomCommandsConfig

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable custom commands |
| `pre_launch` | array | `[]` | Commands to run BEFORE launch |
| `post_exit` | array | `[]` | Commands to run AFTER game exits |
| `on_error` | array | `[]` | Commands to run if launch fails |
| `timeout_seconds` | u32 | `30` | Global timeout for all commands |
| `ignore_pre_errors` | bool | `false` | Continue if pre-launch fails |
| `working_dir` | string | `null` | Working directory (default: game dir) |

### CommandEntry

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | string | `"Custom Command"` | Human-readable name for logging |
| `command` | string | **required** | Shell command to execute |
| `wait` | bool | `true` | Wait for command to complete |
| `timeout_seconds` | u32 | `0` | Per-command timeout (0 = use global) |
| `background` | bool | `false` | Run in background (don't wait) |
| `app_ids` | array | `[]` | Only run for specific AppIDs |
| `shell` | string | `"/bin/sh"` | Shell to use |

---

## Environment Variables

Custom commands have access to these environment variables:

| Variable | Description |
|----------|-------------|
| `$STL_APP_ID` | The Steam AppID (or negative for non-Steam) |
| `$STL_GAME_NAME` | Game name |
| `$STL_PREFIX_PATH` | Wine prefix path |
| `$STL_INSTALL_DIR` | Game installation directory |
| `$STL_CONFIG_DIR` | STL-Next configuration directory |
| `$STL_SCRATCH_DIR` | Temporary scratch directory |
| `$STL_PROTON_PATH` | Proton path (if applicable) |

### Example Using Variables

```json
{
  "pre_launch": [
    {
      "name": "Backup Save",
      "command": "cp -r \"$STL_PREFIX_PATH/drive_c/users/steamuser/Saved Games\" ~/backups/$STL_APP_ID/"
    }
  ]
}
```

---

## Common Templates

STL-Next includes built-in command templates:

### Kill Discord (Prevent Overlay Conflicts)

```json
{
  "name": "Kill Discord",
  "command": "pkill -f discord || true",
  "wait": true
}
```

### CPU Performance Mode

```json
{
  "name": "CPU Performance Mode",
  "command": "echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor",
  "wait": true
}
```

### CPU Powersave Mode (for post_exit)

```json
{
  "name": "CPU Powersave Mode",
  "command": "echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor",
  "wait": true
}
```

### Stop Syncthing

```json
{
  "name": "Stop Syncthing",
  "command": "systemctl --user stop syncthing.service || true",
  "wait": true
}
```

### Start Syncthing (for post_exit)

```json
{
  "name": "Start Syncthing",
  "command": "systemctl --user start syncthing.service || true",
  "wait": true
}
```

### Game Start Notification

```json
{
  "name": "Game Started Notification",
  "command": "notify-send 'STL-Next' \"Starting $STL_GAME_NAME\"",
  "wait": false
}
```

### Game Exit Notification

```json
{
  "name": "Game Exited Notification",
  "command": "notify-send 'STL-Next' \"$STL_GAME_NAME has exited\"",
  "wait": false
}
```

---

## Real-World Examples

### Skyrim with Performance Tweaks

```json
{
  "app_id": 489830,
  "custom_commands": {
    "enabled": true,
    "pre_launch": [
      {
        "name": "Set CPU Performance",
        "command": "echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
      },
      {
        "name": "Stop Background Services",
        "command": "systemctl --user stop syncthing kdeconnect"
      },
      {
        "name": "Kill Browsers",
        "command": "pkill -f firefox || pkill -f chromium || true"
      }
    ],
    "post_exit": [
      {
        "name": "Restore CPU Governor",
        "command": "echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
      },
      {
        "name": "Restart Services",
        "command": "systemctl --user start syncthing kdeconnect"
      }
    ]
  }
}
```

### VR Game with SteamVR

```json
{
  "app_id": 250820,
  "custom_commands": {
    "enabled": true,
    "pre_launch": [
      {
        "name": "Start SteamVR",
        "command": "steam steam://rungameid/250820 &",
        "wait": false,
        "background": true
      },
      {
        "name": "Wait for VR",
        "command": "sleep 10"
      }
    ]
  }
}
```

### Stardew Valley with SMAPI Backup

```json
{
  "app_id": 413150,
  "custom_commands": {
    "enabled": true,
    "pre_launch": [
      {
        "name": "Backup Saves",
        "command": "tar -czf ~/backups/stardew/$(date +%Y%m%d_%H%M%S).tar.gz ~/.config/StardewValley/Saves/"
      }
    ],
    "post_exit": [
      {
        "name": "Sync Saves",
        "command": "rsync -av ~/.config/StardewValley/Saves/ ~/nextcloud/gaming/stardew/"
      }
    ]
  }
}
```

---

## AppID Filtering

Run commands only for specific games:

```json
{
  "custom_commands": {
    "enabled": true,
    "pre_launch": [
      {
        "name": "Bethesda Games - Backup",
        "command": "~/scripts/backup-bethesda.sh",
        "app_ids": [489830, 377160, 22330]
      }
    ]
  }
}
```

This command only runs for:
- 489830 (Skyrim SE)
- 377160 (Fallout 4)
- 22330 (Fallout: New Vegas)

---

## Error Handling

### Continue on Pre-Launch Failure

```json
{
  "custom_commands": {
    "enabled": true,
    "ignore_pre_errors": true,
    "pre_launch": [
      {
        "name": "Optional Tweak",
        "command": "some-optional-command"
      }
    ]
  }
}
```

### On-Error Commands

```json
{
  "custom_commands": {
    "enabled": true,
    "on_error": [
      {
        "name": "Error Notification",
        "command": "notify-send 'STL-Next' 'Game failed to launch!'"
      },
      {
        "name": "Log Error",
        "command": "echo \"$(date): Launch failed\" >> ~/stl-errors.log"
      }
    ]
  }
}
```

---

## Timeouts

### Global Timeout

```json
{
  "custom_commands": {
    "enabled": true,
    "timeout_seconds": 60,
    "pre_launch": [...]
  }
}
```

### Per-Command Timeout

```json
{
  "pre_launch": [
    {
      "name": "Quick Check",
      "command": "ping -c 1 google.com",
      "timeout_seconds": 5
    },
    {
      "name": "Long Setup",
      "command": "~/scripts/long-setup.sh",
      "timeout_seconds": 120
    }
  ]
}
```

---

## Background Commands

For commands that should keep running while the game plays:

```json
{
  "pre_launch": [
    {
      "name": "Start Recording",
      "command": "obs-cli recording start",
      "background": true
    }
  ],
  "post_exit": [
    {
      "name": "Stop Recording",
      "command": "obs-cli recording stop",
      "wait": true
    }
  ]
}
```

---

## Troubleshooting

### Command Not Running

1. Check if `enabled` is `true`
2. Verify the command works in a terminal
3. Check STL-Next logs for errors

### Permission Denied

For commands requiring sudo, either:
1. Add NOPASSWD rule to sudoers
2. Use polkit for graphical auth

### Command Timeout

Increase the timeout:
```json
{
  "timeout_seconds": 120
}
```

Or set `"wait": false` for fire-and-forget.

---

## Security Considerations

⚠️ **Warning:** Custom commands run with your user privileges. Be careful:

1. Never put passwords or secrets in commands
2. Validate paths in scripts
3. Use `|| true` for non-critical commands
4. Test commands manually first

---

## Related Documentation

- [Game Configuration](./ARCHITECTURE.md#game-configuration)
- [Winetricks Guide](./WINETRICKS_GUIDE.md)
- [NixOS Installation](./NIXOS_INSTALLATION.md)

