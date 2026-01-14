# STL-Next Game Testing Guide

This document provides step-by-step testing procedures for validating STL-Next with specific games before public release.

## Target Games for Initial Testing

| Game | Steam ID | Primary Test Focus |
|------|----------|-------------------|
| Stardew Valley | 413150 | SMAPI, NXM mods, Stardrop integration |
| Skyrim SE | 489830 | MO2/Vortex, script extenders, load order |
| Fallout 4 | 377160 | F4SE, Vortex AppData sync, plugins.txt |
| Cyberpunk 2077 | 1091500 | ReShade, large mod files, performance |

---

## Test Environment Setup

### Prerequisites

```bash
# Ensure STL-Next is built
cd /home/e421/stl-next
nix develop
zig build

# Verify binary works
./zig-out/bin/stl-next --version
./zig-out/bin/stl-next list-games
```

### Test Configuration

Create a test config that enables verbose logging:

```bash
mkdir -p ~/.config/stl-next/test
cat > ~/.config/stl-next/test/config.json << 'EOF'
{
  "log_level": "debug",
  "wait_timeout": 30,
  "enable_tinkers": {
    "mangohud": true,
    "gamemode": true,
    "gamescope": false
  }
}
EOF
```

---

## Game 1: Stardew Valley (413150)

### Why This Game

- Native Linux support
- Uses SMAPI mod loader
- Excellent NXM integration test (many collections available)
- Stardrop mod manager support target
- Fast to launch and test

### Test Cases

#### TC-SDV-001: Basic Launch

**Purpose**: Verify STL-Next can launch the game without mods

```bash
# List the game
stl-next list-games | grep -i stardew

# Launch without modifications
stl-next launch 413150

# Expected: Game launches to title screen
# Log location: ~/.local/share/stl-next/logs/413150-*.log
```

**Pass Criteria**:
- [ ] Game window appears
- [ ] No errors in log
- [ ] Game is playable

#### TC-SDV-002: SMAPI Integration

**Purpose**: Verify script extender detection and launch

```bash
# Install SMAPI manually first
# https://smapi.io/

# Configure STL-Next to use SMAPI
stl-next config 413150 --custom-command="StardewModdingAPI"

# Launch
stl-next launch 413150

# Expected: SMAPI console appears, game loads with mod framework
```

**Pass Criteria**:
- [ ] SMAPI console visible
- [ ] Console shows "SMAPI 4.x.x loaded"
- [ ] No mod errors in SMAPI console

#### TC-SDV-003: NXM Link Handling

**Purpose**: Verify NXM mod links are parsed correctly (THE CRITICAL TEST)

```bash
# Test mod link parsing
stl-next test-nxm "nxm://stardewvalley/mods/12345/files/67890"

# Test collection link with revision (the bug we fixed!)
stl-next test-nxm "nxm://stardewvalley/collections/tckf0m/revisions/100"

# Expected output should show:
# - Game domain: stardewvalley
# - Mod ID: 12345 (or collection slug)
# - File ID: 67890 (or revision ID: 100)
```

**Pass Criteria**:
- [ ] Mod links parse correctly
- [ ] Collection links preserve `/revisions/N` segment
- [ ] Wine-encoded URLs contain `%2F` instead of `/`

#### TC-SDV-004: Stardrop Integration (Future)

**Purpose**: Test Stardrop mod manager integration

```bash
# Note: Stardrop integration not yet implemented
# This test case is a placeholder for Phase 5

# Expected workflow:
# 1. stl-next detects Stardrop installation
# 2. stl-next can launch Stardrop
# 3. NXM links forwarded to Stardrop
```

---

## Game 2: Skyrim Special Edition (489830)

### Why This Game

- Poster child for modding
- Complex load order management
- MO2 and Vortex both popular
- SKSE64 script extender
- Tests Windows game under Proton

### Test Cases

#### TC-SKY-001: Basic Proton Launch

```bash
# Verify game detection
stl-next list-games | grep -i skyrim

# Launch with default Proton
stl-next launch 489830

# Expected: Game launches to main menu
```

**Pass Criteria**:
- [ ] Bethesda logo plays
- [ ] Main menu appears
- [ ] No Proton errors

#### TC-SKY-002: MangoHud Overlay

**Purpose**: Test Tinker module injection

```bash
# Configure MangoHud
stl-next config 489830 --enable mangohud

# Launch
stl-next launch 489830

# Expected: MangoHud overlay visible in top-left
```

**Pass Criteria**:
- [ ] FPS counter visible
- [ ] No performance regression
- [ ] Game still playable

#### TC-SKY-003: MO2 Detection (Future)

```bash
# Test MO2 path detection
stl-next detect-modmanager 489830

# Expected: Reports MO2 location if installed
```

#### TC-SKY-004: Custom Proton Version

```bash
# List available Proton versions
stl-next list-proton

# Set specific Proton
stl-next config 489830 --proton "GE-Proton9-25"

# Launch
stl-next launch 489830
```

**Pass Criteria**:
- [ ] Correct Proton version used (check log)
- [ ] Game launches successfully

---

## Game 3: Fallout 4 (377160)

### Why This Game

- Similar to Skyrim (Bethesda engine)
- F4SE script extender
- Known Vortex AppData sync issues (STL bug #1268)
- Tests plugins.txt handling

### Test Cases

#### TC-FO4-001: Basic Launch

```bash
stl-next launch 377160
```

**Pass Criteria**:
- [ ] Game launches
- [ ] Creation Club doesn't cause issues

#### TC-FO4-002: Plugin Load Order

```bash
# Check if plugins.txt is handled
ls ~/.local/share/Steam/steamapps/compatdata/377160/pfx/drive_c/users/steamuser/AppData/Local/Fallout4/

# Expected: plugins.txt present with correct load order
```

#### TC-FO4-003: AppData Preservation

**Purpose**: Verify mod data survives across launches

```bash
# Launch game, make changes, exit
stl-next launch 377160

# Check AppData still intact
ls ~/.local/share/Steam/steamapps/compatdata/377160/pfx/drive_c/users/steamuser/AppData/
```

---

## Game 4: Cyberpunk 2077 (1091500)

### Why This Game

- Modern AAA game
- Tests ReShade injection
- Large mod file downloads
- Performance-critical

### Test Cases

#### TC-CP77-001: Basic Launch

```bash
stl-next launch 1091500
```

**Pass Criteria**:
- [ ] REDLauncher appears (or bypassed)
- [ ] Game loads to main menu
- [ ] No GPU driver issues

#### TC-CP77-002: ReShade Injection (Future)

```bash
# Configure ReShade
stl-next config 1091500 --enable reshade

# Launch
stl-next launch 1091500

# Expected: ReShade overlay accessible via Home key
```

#### TC-CP77-003: Performance Overlay

```bash
# Enable MangoHud
stl-next config 1091500 --enable mangohud

# Launch and check FPS
stl-next launch 1091500
```

**Pass Criteria**:
- [ ] FPS counter shows reasonable values
- [ ] No significant performance drop from overlay

---

## IPC Daemon Testing

### TC-IPC-001: Daemon Startup

```bash
# Start daemon in background
stl-next daemon &
DAEMON_PID=$!

# Wait for socket
sleep 2

# Check socket exists
ls $XDG_RUNTIME_DIR/stl-next.sock

# Stop daemon
kill $DAEMON_PID
```

### TC-IPC-002: Client Communication

```bash
# Start daemon
stl-next daemon &

# Query status
stl-next client status

# Expected: JSON response with daemon state
```

### TC-IPC-003: Wait Requester

```bash
# Configure wait requester
stl-next config 413150 --wait-timeout 10

# Launch game
stl-next launch 413150

# Expected: TUI appears with countdown
# User can press keys to interact
```

---

## Error Handling Tests

### TC-ERR-001: Invalid NXM URL

```bash
# Test various malformed URLs
stl-next test-nxm ""
# Expected: EmptyUrl error

stl-next test-nxm "https://nexusmods.com"
# Expected: InvalidScheme error

stl-next test-nxm "nxm://"
# Expected: MissingGameDomain error

stl-next test-nxm "nxm://game/mods/notanumber"
# Expected: InvalidModId error
```

### TC-ERR-002: Missing Game

```bash
# Try to launch non-existent game
stl-next launch 99999999

# Expected: Clear error message, not crash
```

### TC-ERR-003: IPC Timeout

```bash
# No daemon running
stl-next client status

# Expected: Connection refused error, not hang
```

---

## Performance Benchmarks

### Startup Time

```bash
# Measure launch overhead
time stl-next launch 413150 --dry-run

# Target: < 500ms for config load + preparation
```

### VDF Parsing

```bash
# Already tested, but verify:
stl-next benchmark-vdf

# Target: < 50ms for full Steam library
```

---

## Test Result Template

```markdown
## Test Report: [Game Name] - [Date]

**Tester**: [Name]
**STL-Next Version**: [Version]
**System**: [NixOS version, GPU]
**Proton**: [Version used]

### Results

| Test Case | Status | Notes |
|-----------|--------|-------|
| TC-XXX-001 | ✅/❌ | |
| TC-XXX-002 | ✅/❌ | |

### Issues Found

1. [Issue description, steps to reproduce]

### Log Files

- Attached: [log file names]
```

---

## Continuous Testing

### Pre-Release Checklist

- [ ] All 4 target games launch successfully
- [ ] NXM URLs parse correctly (especially collections with revisions)
- [ ] IPC daemon starts and responds
- [ ] MangoHud tinker works
- [ ] GameMode tinker works
- [ ] No regressions from previous test run
- [ ] NixOS installation instructions verified
- [ ] Build from source works on NixOS

### Automated Tests

```bash
# Run full test suite
zig build test

# Run edge case tests specifically
zig build test -- --test-filter "edge"

# Run NXM tests
zig build test -- --test-filter "NXM"
```

