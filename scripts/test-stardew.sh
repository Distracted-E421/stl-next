#!/usr/bin/env bash
# Stardew Valley STL-Next Test Script
# Tests various STL-Next features with Stardew Valley

set -e

STL="${STL_NEXT:-stl-next}"
APPID=413150

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ Stardew Valley + STL-Next Test Suite                           ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║ Testing: $STL"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Test 1: Game Info
echo "▶ TEST 1: Game Info"
echo "─────────────────────"
$STL info $APPID
echo ""

# Test 2: GPU Detection
echo "▶ TEST 2: GPU Detection"
echo "─────────────────────────"
$STL gpu-list
echo ""

# Test 3: Profile Creation
echo "▶ TEST 3: Profile Creation"
echo "────────────────────────────"
$STL profile-create $APPID "Test-Profile" --gpu auto --resolution 1920x1080@60 2>&1 || true
echo ""

# Test 4: Profile List
echo "▶ TEST 4: Profile List"
echo "─────────────────────────"
$STL profile-list $APPID
echo ""

# Test 5: Dry Run Launch
echo "▶ TEST 5: Dry Run Launch"
echo "──────────────────────────"
$STL run $APPID --dry-run 2>&1
echo ""

# Test 6: NXM Parsing
echo "▶ TEST 6: NXM URL Parsing"
echo "────────────────────────────"
$STL nxm "nxm://stardewvalley/collections/tckf0m/revisions/100" 2>&1
echo ""

# Test 7: NXM with Mod ID
echo "▶ TEST 7: NXM Mod URL"
echo "────────────────────────────"
$STL nxm "nxm://stardewvalley/mods/3753/files/12345" 2>&1
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ ✅ All tests completed!                                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"

# Cleanup test profile
rm -f ~/.config/stl-next/games/$APPID.json 2>/dev/null || true

