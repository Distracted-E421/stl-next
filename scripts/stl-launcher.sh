#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# STL-Next Launcher with GUI and SMAPI Log Integration
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script provides a complete pre-launch experience:
#   1. Shows the Raylib Wait Requester GUI (if available)
#   2. Optionally opens SMAPI log viewer in a terminal
#   3. Launches the game through STL-Next
#
# Usage: stl-launcher.sh <AppID> [options]
#   --no-gui        Skip the pre-launch GUI
#   --show-logs     Open SMAPI log viewer in a separate terminal
#   --countdown N   Set countdown timer (default: 10)
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STL_NEXT="${SCRIPT_DIR}/../zig-out/bin/stl-next"
STL_GUI="${SCRIPT_DIR}/../zig-out/bin/stl-next-gui"
SMAPI_LOG="$HOME/.local/share/Steam/steamapps/compatdata/413150/pfx/drive_c/users/steamuser/AppData/Roaming/StardewValley/ErrorLogs/SMAPI-latest.txt"
COUNTDOWN=10
SHOW_GUI=true
SHOW_LOGS=false
DRY_RUN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║              STL-Next Launcher v0.1.0                          ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 <AppID> [options]"
    echo ""
    echo "Options:"
    echo "  --no-gui        Skip the pre-launch GUI"
    echo "  --show-logs     Open SMAPI log viewer in a separate terminal"
    echo "  --countdown N   Set countdown timer (default: 10)"
    echo "  --dry-run       Don't actually launch the game"
    echo "  --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 413150                    # Launch Stardew Valley"
    echo "  $0 413150 --show-logs        # Launch with log viewer"
    echo "  $0 413150 --no-gui --dry-run # Test without GUI"
}

# Parse arguments
APP_ID=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-gui)
            SHOW_GUI=false
            shift
            ;;
        --show-logs)
            SHOW_LOGS=true
            shift
            ;;
        --countdown)
            COUNTDOWN="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            EXTRA_ARGS+=("--dry-run")
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        [0-9]*)
            APP_ID="$1"
            shift
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# Validate AppID
if [[ -z "$APP_ID" ]]; then
    echo -e "${RED}Error: AppID is required${NC}"
    print_usage
    exit 1
fi

print_header

# Get game name from Steam
get_game_name() {
    local app_id="$1"
    local manifest_file
    
    # Search for manifest in Steam library folders
    for lib in "$HOME/.local/share/Steam/steamapps" "$HOME/.steam/steam/steamapps"; do
        manifest_file="$lib/appmanifest_${app_id}.acf"
        if [[ -f "$manifest_file" ]]; then
            grep '"name"' "$manifest_file" 2>/dev/null | sed 's/.*"\([^"]*\)"[^"]*$/\1/' | head -1
            return
        fi
    done
    echo "Game $app_id"
}

GAME_NAME=$(get_game_name "$APP_ID")
echo -e "${GREEN}Game:${NC} $GAME_NAME (AppID: $APP_ID)"
echo ""

# Open SMAPI log viewer if requested
LOG_VIEWER_PID=""
if [[ "$SHOW_LOGS" == "true" ]]; then
    echo -e "${BLUE}Opening SMAPI log viewer...${NC}"
    
    # Determine which terminal to use
    TERMINAL=""
    if command -v konsole &>/dev/null; then
        TERMINAL="konsole"
    elif command -v gnome-terminal &>/dev/null; then
        TERMINAL="gnome-terminal"
    elif command -v xterm &>/dev/null; then
        TERMINAL="xterm"
    elif command -v kitty &>/dev/null; then
        TERMINAL="kitty"
    fi
    
    if [[ -n "$TERMINAL" ]]; then
        # Create a log viewer script
        LOG_VIEWER_SCRIPT=$(mktemp /tmp/smapi-log-viewer-XXXXXX.sh)
        cat > "$LOG_VIEWER_SCRIPT" << 'LOGEOF'
#!/usr/bin/env bash
SMAPI_LOG="$1"
echo -e "\033[1;36m╔════════════════════════════════════════════════════════════════╗"
echo -e "║              SMAPI Log Viewer                                   ║"
echo -e "╚════════════════════════════════════════════════════════════════╝\033[0m"
echo ""
echo -e "\033[1;33mWatching:\033[0m $SMAPI_LOG"
echo -e "\033[1;33mPress Ctrl+C to stop\033[0m"
echo ""
echo "─────────────────────────────────────────────────────────────────"
echo ""

# Wait for log file to exist
while [[ ! -f "$SMAPI_LOG" ]]; do
    echo "Waiting for SMAPI to start..."
    sleep 1
done

# Tail the log with color highlighting
tail -f "$SMAPI_LOG" 2>/dev/null | while IFS= read -r line; do
    # Color errors red
    if echo "$line" | grep -qE "ERROR|FATAL|Exception"; then
        echo -e "\033[0;31m$line\033[0m"
    # Color warnings yellow
    elif echo "$line" | grep -qE "WARN"; then
        echo -e "\033[1;33m$line\033[0m"
    # Color loaded mods green
    elif echo "$line" | grep -qE "loaded|Loaded|SUCCESS"; then
        echo -e "\033[0;32m$line\033[0m"
    # Color info cyan
    elif echo "$line" | grep -qE "INFO"; then
        echo -e "\033[0;36m$line\033[0m"
    else
        echo "$line"
    fi
done
LOGEOF
        chmod +x "$LOG_VIEWER_SCRIPT"
        
        case "$TERMINAL" in
            konsole)
                konsole --hold -e "$LOG_VIEWER_SCRIPT" "$SMAPI_LOG" &
                ;;
            gnome-terminal)
                gnome-terminal -- bash -c "$LOG_VIEWER_SCRIPT '$SMAPI_LOG'; exec bash" &
                ;;
            kitty)
                kitty --hold "$LOG_VIEWER_SCRIPT" "$SMAPI_LOG" &
                ;;
            xterm)
                xterm -hold -e "$LOG_VIEWER_SCRIPT" "$SMAPI_LOG" &
                ;;
        esac
        LOG_VIEWER_PID=$!
        echo -e "${GREEN}Log viewer opened in $TERMINAL${NC}"
    else
        echo -e "${YELLOW}Warning: No supported terminal found for log viewer${NC}"
    fi
fi

# Show pre-launch GUI
GUI_RESULT="LAUNCH"
if [[ "$SHOW_GUI" == "true" ]] && [[ -x "$STL_GUI" ]]; then
    echo -e "${BLUE}Opening pre-launch GUI...${NC}"
    echo ""
    
    # Run GUI and capture output
    GUI_OUTPUT=$("$STL_GUI" "$APP_ID" "$GAME_NAME" "$COUNTDOWN" 2>/dev/null || echo "LAUNCH:$APP_ID")
    
    if echo "$GUI_OUTPUT" | grep -q "^CANCELLED"; then
        echo -e "${YELLOW}Launch cancelled by user${NC}"
        # Kill log viewer if running
        if [[ -n "$LOG_VIEWER_PID" ]]; then
            kill "$LOG_VIEWER_PID" 2>/dev/null || true
        fi
        exit 0
    fi
    
    echo -e "${GREEN}GUI confirmed launch${NC}"
fi

# Launch the game
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Launching game through STL-Next...${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would execute:${NC}"
    echo "  $STL_NEXT run $APP_ID ${EXTRA_ARGS[*]}"
else
    exec "$STL_NEXT" run "$APP_ID" "${EXTRA_ARGS[@]}"
fi

