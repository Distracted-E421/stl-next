# STL-Next Agent Test Walkthrough

This document provides step-by-step test cases that any agent (human or AI) can walk through to verify STL-Next functionality. Each test case has:

- **Purpose**: What we're testing
- **Prerequisites**: What needs to be set up first
- **Steps**: Exact commands to run
- **Expected Output**: What success looks like (copy-pasteable patterns)
- **Success Criteria**: Checklist to verify pass/fail

---

## Test Environment Setup

### Prerequisites

```bash
# Navigate to project
cd /home/e421/stl-next

# Build from source
zig build

# Verify binary exists
ls -la ./zig-out/bin/stl-next
```

**Expected**: Binary file exists, size ~3-8MB

---

## Phase 1: Core CLI Tests

### TEST-CLI-001: Help Command

**Purpose**: Verify CLI is functional and shows help

**Steps**:
```bash
./zig-out/bin/stl-next help
```

**Expected Output Contains**:
```
Steam Game Commands:
  run <AppID>           Launch a game with STL-Next configuration
  info <AppID>          Show game information (JSON)
  list-games            List installed Steam games (JSON)
```

**Success Criteria**:
- [ ] Help text displays without errors
- [ ] Contains "run", "info", "list-games" commands
- [ ] Contains "profile" commands
- [ ] Contains "gpu" commands
- [ ] Exit code is 0

### TEST-CLI-002: Version Command

**Purpose**: Verify version reporting

**Steps**:
```bash
./zig-out/bin/stl-next version
```

**Expected Output Contains**:
```
STL-Next v0.9.0-alpha
```

**Success Criteria**:
- [ ] Shows version 0.9.0-alpha
- [ ] No error messages

### TEST-CLI-003: List Games

**Purpose**: Verify Steam game discovery

**Steps**:
```bash
./zig-out/bin/stl-next list-games 2>&1 | head -20
```

**Expected Output Pattern**:
```
[{"app_id":413150,"name":"Stardew Valley",...}]
```

**Success Criteria**:
- [ ] Returns JSON array
- [ ] Contains at least one game (if Steam installed)
- [ ] Each game has `app_id` and `name` fields
- [ ] No crash or panic

---

## Phase 2: NXM URL Handling (THE CRITICAL TEST)

### TEST-NXM-001: Basic Mod URL

**Purpose**: Verify NXM mod URLs parse correctly

**Steps**:
```bash
./zig-out/bin/stl-next nxm "nxm://stardewvalley/mods/12345/files/67890" 2>&1
```

**Expected Output Contains**:
```
Game: stardewvalley
Mod ID: 12345
File ID: 67890
```

**Success Criteria**:
- [ ] Game domain correctly extracted
- [ ] Mod ID parsed as integer
- [ ] File ID parsed as integer
- [ ] No "Invalid URL" error

### TEST-NXM-002: Collection URL with Revision (THE BUG FIX)

**Purpose**: Verify collection URLs preserve revision segment

**Steps**:
```bash
./zig-out/bin/stl-next nxm "nxm://stardewvalley/collections/tckf0m/revisions/100" 2>&1
```

**Expected Output Contains**:
```
Collection: stardewvalley/collections/tckf0m/revisions/100
```

**Critical Check**: The `/revisions/100` segment MUST be present!

**Success Criteria**:
- [ ] Output shows `/revisions/100` NOT truncated
- [ ] Collection slug `tckf0m` parsed
- [ ] Revision `100` present
- [ ] No "Invalid URL" error

### TEST-NXM-003: Wine-Safe URL Encoding

**Purpose**: Verify URLs are properly encoded for Wine

**Steps**:
```bash
./zig-out/bin/stl-next nxm "nxm://stardewvalley/collections/tckf0m/revisions/100" 2>&1 | grep -i wine
```

**Expected Output Contains**:
```
Wine-safe: nxm://stardewvalley%2Fcollections%2Ftckf0m%2Frevisions%2F100
```

**Success Criteria**:
- [ ] Slashes encoded as `%2F`
- [ ] Original URL structure preserved
- [ ] No double-encoding

---

## Phase 3: GPU Detection (D-Bus Integration)

### TEST-GPU-001: List GPUs

**Purpose**: Verify GPU detection works

**Steps**:
```bash
./zig-out/bin/stl-next gpu-list 2>&1
```

**Expected Output Pattern**:
```
Detected GPUs:
══════════════════════════════════════════════════════════════════
  [0] Intel Arc A770 (Discrete)
      PCI: 8086:56a0
      Driver: i915
      Env: MESA_VK_DEVICE_SELECT=8086:56a0

  [1] NVIDIA GeForce RTX 2080 (Discrete)
      PCI: 10de:1e82
      Driver: nvidia
      Env: __NV_PRIME_RENDER_OFFLOAD=1
```

**Success Criteria**:
- [ ] Shows at least one GPU
- [ ] Intel Arc labeled as "Discrete" (NOT "Integrated")
- [ ] PCI IDs in format XXXX:XXXX
- [ ] Environment variables shown

### TEST-GPU-002: GPU Test Selection

**Purpose**: Verify GPU preference environment variables

**Steps**:
```bash
./zig-out/bin/stl-next gpu-test nvidia 2>&1
```

**Expected Output Contains**:
```
__NV_PRIME_RENDER_OFFLOAD=1
```

**Steps** (Intel Arc):
```bash
./zig-out/bin/stl-next gpu-test arc 2>&1
```

**Expected Output Contains**:
```
MESA_VK_DEVICE_SELECT=
DRI_PRIME=
```

**Success Criteria**:
- [ ] `nvidia` sets NVIDIA-specific env vars
- [ ] `arc` sets Mesa/DRI_PRIME env vars
- [ ] `integrated` sets different vars than `discrete`

---

## Phase 4: Profile System

### TEST-PROFILE-001: Create Profile

**Purpose**: Verify profile creation with flags

**Steps**:
```bash
# Clean any existing test config
rm -f ~/.config/stl-next/games/413150.json

# Create a new profile
./zig-out/bin/stl-next profile-create 413150 "Test-Arc" --gpu arc --monitor HDMI-1 --resolution 2560x1440@144 2>&1
```

**Expected Output Contains**:
```
Creating profile "Test-Arc" for AppID 413150...
Profile configuration:
  Name: Test-Arc
  GPU: intel_arc
  Monitor: HDMI-1
  Resolution: 2560x1440@144Hz
✅ Profile saved!
```

**Success Criteria**:
- [ ] Shows profile creation message
- [ ] GPU preference shown as `intel_arc`
- [ ] Resolution parsed correctly
- [ ] "Profile saved!" confirmation

### TEST-PROFILE-002: List Profiles

**Purpose**: Verify profile listing loads from disk

**Steps**:
```bash
./zig-out/bin/stl-next profile-list 413150 2>&1
```

**Expected Output Pattern**:
```
Profiles for ... (AppID: 413150)
================================

[0] Default ← ACTIVE
    GPU: auto

[1] Test-Arc
    GPU: intel_arc
    Monitor: HDMI-1
    Resolution: 2560x1440@144Hz
```

**Success Criteria**:
- [ ] Shows at least Default profile
- [ ] Test-Arc profile shows GPU preference
- [ ] One profile marked "← ACTIVE"
- [ ] Resolution shows refresh rate

### TEST-PROFILE-003: Set Active Profile

**Purpose**: Verify profile switching persists

**Steps**:
```bash
# Set Test-Arc as active
./zig-out/bin/stl-next profile-set 413150 "Test-Arc" 2>&1

# Verify it's now active
./zig-out/bin/stl-next profile-list 413150 2>&1 | grep -A2 "Test-Arc"
```

**Expected Output**:
```
✅ Active profile set to "Test-Arc" for AppID 413150
...
[1] Test-Arc ← ACTIVE
```

**Success Criteria**:
- [ ] Success message shown
- [ ] Profile-list shows Test-Arc as ACTIVE
- [ ] Config file updated on disk

### TEST-PROFILE-004: Config File Persistence

**Purpose**: Verify profiles saved to JSON correctly

**Steps**:
```bash
cat ~/.config/stl-next/games/413150.json
```

**Expected Contents Include**:
```json
{
  "app_id": 413150,
  "active_profile": "Test-Arc",
  "profiles": [
    {
      "name": "Default",
      "gpu_preference": "auto"
    },
    {
      "name": "Test-Arc",
      "gpu_preference": "intel_arc",
      "target_monitor": "HDMI-1",
      "resolution_width": 2560,
      "resolution_height": 1440,
      "resolution_refresh_hz": 144
    }
  ]
}
```

**Success Criteria**:
- [ ] Valid JSON file
- [ ] `active_profile` set to "Test-Arc"
- [ ] Both profiles present
- [ ] Test-Arc has GPU preference
- [ ] Resolution fields populated

### TEST-PROFILE-005: Steam Shortcut Creation

**Purpose**: Verify Steam shortcuts.vdf writing

**Steps**:
```bash
./zig-out/bin/stl-next profile-shortcut 413150 "Test-Arc" 2>&1
```

**Expected Output Contains**:
```
Creating Steam shortcut for "..." [Test-Arc]
==========================================
Shortcut details:
  Name: ... [Test-Arc]
  Exe: /home/.../stl-next
  Args: run 413150 --profile "Test-Arc"
  GPU: intel_arc

Steam shortcuts file: /home/.../.steam/steam/userdata/.../config/shortcuts.vdf
✅ Steam shortcut created successfully!
   Shortcut ID: ...
   Restart Steam to see "... [Test-Arc]" in your library.
```

**Success Criteria**:
- [ ] Shows shortcut name with [Profile]
- [ ] Shows correct exe path
- [ ] Shows launch args with --profile
- [ ] Shows shortcuts.vdf path
- [ ] Success message shown
- [ ] Shortcut ID generated

### TEST-PROFILE-006: Verify Shortcuts VDF

**Purpose**: Verify binary VDF file is valid

**Steps**:
```bash
xxd ~/.steam/steam/userdata/*/config/shortcuts.vdf 2>/dev/null | head -10
```

**Expected Output Pattern**:
```
00000000: 0073 686f 7274 6375 7473 0000 2230 2200  .shortcuts.."0".
00000010: 0261 7070 6964 00...                     .appid..
```

**Success Criteria**:
- [ ] File exists and is readable
- [ ] Starts with `\x00shortcuts\x00`
- [ ] Contains `appid` entry
- [ ] Contains profile name in `AppName`

---

## Phase 5: Run Command with Profile

### TEST-RUN-001: Run with Profile Flag (Dry Run)

**Purpose**: Verify --profile flag parsing

**Note**: We use a non-existent AppID or dry-run to avoid actually launching a game.

**Steps**:
```bash
# This will fail to find the game but show that profile parsing works
./zig-out/bin/stl-next run 413150 --profile "Test-Arc" --dry-run 2>&1 | head -20
```

**Expected Output Contains**:
```
║ Profile: Test-Arc
```

**Success Criteria**:
- [ ] Profile name shown in banner
- [ ] No "profile not found" error (if profile exists)
- [ ] GPU env vars shown (if applicable)

---

## Phase 6: Error Handling

### TEST-ERR-001: Invalid NXM URL

**Purpose**: Verify graceful error handling

**Steps**:
```bash
./zig-out/bin/stl-next nxm "" 2>&1
```

**Expected**: Error message, no crash

**Steps**:
```bash
./zig-out/bin/stl-next nxm "not-a-url" 2>&1
```

**Expected**: Error message about invalid scheme

**Success Criteria**:
- [ ] No panic or segfault
- [ ] Clear error message
- [ ] Non-zero exit code

### TEST-ERR-002: Invalid Profile Name

**Purpose**: Verify profile not found handling

**Steps**:
```bash
./zig-out/bin/stl-next profile-set 413150 "NonExistentProfile" 2>&1
```

**Expected Output Contains**:
```
Profile "NonExistentProfile" not found
```

**Success Criteria**:
- [ ] Clear error message
- [ ] Lists available profiles
- [ ] No crash

### TEST-ERR-003: Invalid AppID

**Purpose**: Verify game not found handling

**Steps**:
```bash
./zig-out/bin/stl-next info 999999999 2>&1
```

**Expected**: Error about game not found

**Success Criteria**:
- [ ] No panic
- [ ] Clear error message

---

## Phase 7: Session Management

### TEST-SESSION-001: Session Capabilities

**Purpose**: Verify D-Bus session features

**Steps**:
```bash
./zig-out/bin/stl-next session-test 2>&1
```

**Expected Output Contains**:
```
D-Bus Session Manager Test
═══════════════════════════════════════════════════════════════════
  Power Profiles: ...
  Screen Saver Inhibit: ...
  Desktop Notifications: ...
```

**Success Criteria**:
- [ ] Shows power profile support status
- [ ] Shows screen saver inhibit status
- [ ] Shows notification status
- [ ] No crash

---

## Full Integration Test

### TEST-INT-001: Complete Profile Workflow

**Purpose**: Test the entire profile workflow end-to-end

**Steps**:
```bash
#!/bin/bash
set -e

echo "=== Step 1: Clean slate ==="
rm -f ~/.config/stl-next/games/413150.json

echo "=== Step 2: Create profile ==="
./zig-out/bin/stl-next profile-create 413150 "Integration-Test" --gpu nvidia --resolution 1920x1080@60 2>&1 | grep -v "error(gpa)"

echo "=== Step 3: Verify profile created ==="
./zig-out/bin/stl-next profile-list 413150 2>&1 | grep "Integration-Test"

echo "=== Step 4: Set as active ==="
./zig-out/bin/stl-next profile-set 413150 "Integration-Test" 2>&1 | grep -v "error(gpa)"

echo "=== Step 5: Verify active ==="
./zig-out/bin/stl-next profile-list 413150 2>&1 | grep "ACTIVE"

echo "=== Step 6: Create shortcut ==="
./zig-out/bin/stl-next profile-shortcut 413150 "Integration-Test" 2>&1 | grep -v "error(gpa)"

echo "=== Step 7: Verify config file ==="
cat ~/.config/stl-next/games/413150.json | grep "Integration-Test"

echo "=== ALL STEPS PASSED ==="
```

**Success Criteria**:
- [ ] All 7 steps complete without error
- [ ] Final message "ALL STEPS PASSED" shown
- [ ] Config file contains profile
- [ ] Steam shortcuts.vdf updated

---

## Test Result Summary Template

```markdown
## STL-Next Test Results - [DATE]

**Tester**: [Agent Name/Human]
**Version**: 0.9.0-alpha
**System**: NixOS 25.11 / [OTHER]
**Build**: zig build (debug/release)

### Results

| Test ID | Test Name | Status | Notes |
|---------|-----------|--------|-------|
| TEST-CLI-001 | Help Command | ✅/❌ | |
| TEST-CLI-002 | Version Command | ✅/❌ | |
| TEST-CLI-003 | List Games | ✅/❌ | |
| TEST-NXM-001 | Basic Mod URL | ✅/❌ | |
| TEST-NXM-002 | Collection URL | ✅/❌ | CRITICAL |
| TEST-NXM-003 | Wine Encoding | ✅/❌ | |
| TEST-GPU-001 | List GPUs | ✅/❌ | |
| TEST-GPU-002 | GPU Test | ✅/❌ | |
| TEST-PROFILE-001 | Create Profile | ✅/❌ | |
| TEST-PROFILE-002 | List Profiles | ✅/❌ | |
| TEST-PROFILE-003 | Set Active | ✅/❌ | |
| TEST-PROFILE-004 | Config Persistence | ✅/❌ | |
| TEST-PROFILE-005 | Steam Shortcut | ✅/❌ | |
| TEST-PROFILE-006 | VDF Verification | ✅/❌ | |
| TEST-RUN-001 | Run with Profile | ✅/❌ | |
| TEST-ERR-001 | Invalid NXM | ✅/❌ | |
| TEST-ERR-002 | Invalid Profile | ✅/❌ | |
| TEST-ERR-003 | Invalid AppID | ✅/❌ | |
| TEST-SESSION-001 | Session Test | ✅/❌ | |
| TEST-INT-001 | Integration | ✅/❌ | |

### Issues Found

[List any failures with reproduction steps]

### Recommendations

[Any suggested fixes or improvements]
```

---

## Quick Smoke Test

For a fast validation, run these in sequence:

```bash
cd /home/e421/stl-next
./zig-out/bin/stl-next version && echo "✅ CLI works"
./zig-out/bin/stl-next nxm "nxm://test/collections/abc/revisions/100" 2>&1 | grep -q "revisions" && echo "✅ NXM collection parsing works"
./zig-out/bin/stl-next gpu-list 2>&1 | grep -q "GPU" && echo "✅ GPU detection works"
rm -f ~/.config/stl-next/games/999999.json
./zig-out/bin/stl-next profile-create 999999 "Smoke" --gpu arc 2>&1 | grep -q "saved" && echo "✅ Profile creation works"
cat ~/.config/stl-next/games/999999.json | grep -q "intel_arc" && echo "✅ Profile persistence works"
rm -f ~/.config/stl-next/games/999999.json
echo ""
echo "=== SMOKE TEST COMPLETE ==="
```

