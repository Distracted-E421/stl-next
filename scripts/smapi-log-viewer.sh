#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# SMAPI Log Viewer for STL-Next
# ═══════════════════════════════════════════════════════════════════════════════
#
# A colorized, filterable SMAPI log viewer
#
# Usage:
#   smapi-log-viewer.sh              # View latest log
#   smapi-log-viewer.sh --errors     # Show only errors
#   smapi-log-viewer.sh --mods       # Show only mod loading info
#   smapi-log-viewer.sh --live       # Tail the log (follow mode)
#   smapi-log-viewer.sh --path       # Just print log path and exit
#
# ═══════════════════════════════════════════════════════════════════════════════

# Default SMAPI log location
SMAPI_LOG="${SMAPI_LOG:-$HOME/.local/share/Steam/steamapps/compatdata/413150/pfx/drive_c/users/steamuser/AppData/Roaming/StardewValley/ErrorLogs/SMAPI-latest.txt}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

# Options
MODE="full"
FOLLOW=false

print_header() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════════════╗"
    echo "║                     SMAPI Log Viewer                                    ║"
    echo "╚════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --errors, -e    Show only errors and warnings"
    echo "  --mods, -m      Show only mod loading information"
    echo "  --summary, -s   Show mod load summary"
    echo "  --live, -l      Follow the log (like tail -f)"
    echo "  --path, -p      Print log path and exit"
    echo "  --help, -h      Show this help"
    echo ""
    echo "Environment:"
    echo "  SMAPI_LOG       Path to SMAPI log file"
    echo "                  Default: $SMAPI_LOG"
}

colorize_line() {
    local line="$1"
    
    # Errors - red
    if echo "$line" | grep -qE "\[.*ERROR.*\]|Exception:|FATAL"; then
        echo -e "${RED}$line${NC}"
    # Warnings - yellow
    elif echo "$line" | grep -qE "\[.*WARN.*\]"; then
        echo -e "${YELLOW}$line${NC}"
    # Success/loaded - green
    elif echo "$line" | grep -qE "loaded successfully|SUCCESS|✓"; then
        echo -e "${GREEN}$line${NC}"
    # Skipped mods - magenta
    elif echo "$line" | grep -qE "Skipped mods|couldn't be loaded|Failed:"; then
        echo -e "${MAGENTA}$line${NC}"
    # Debug/Trace - dim
    elif echo "$line" | grep -qE "\[.*TRACE.*\]|\[.*DEBUG.*\]"; then
        echo -e "${DIM}$line${NC}"
    # Info headers - cyan
    elif echo "$line" | grep -qE "^SMAPI|^Content Patcher|Loading mods|Reloading|Launching"; then
        echo -e "${CYAN}$line${NC}"
    # Mod names being loaded - blue
    elif echo "$line" | grep -qE "^\s+- "; then
        echo -e "${BLUE}$line${NC}"
    else
        echo "$line"
    fi
}

show_errors() {
    if [[ ! -f "$SMAPI_LOG" ]]; then
        echo -e "${RED}Log file not found: $SMAPI_LOG${NC}"
        exit 1
    fi
    
    echo -e "${WHITE}═══ Errors and Warnings ═══${NC}"
    echo ""
    
    grep -E "ERROR|WARN|Exception:|Failed:|couldn't be loaded" "$SMAPI_LOG" | while IFS= read -r line; do
        colorize_line "$line"
    done
}

show_mods() {
    if [[ ! -f "$SMAPI_LOG" ]]; then
        echo -e "${RED}Log file not found: $SMAPI_LOG${NC}"
        exit 1
    fi
    
    echo -e "${WHITE}═══ Mod Loading Information ═══${NC}"
    echo ""
    
    # Extract mod loading section
    grep -E "Loading [0-9]+ mods|loaded successfully|\s+- .*\d+\.\d+|Skipped mods|couldn't be loaded|needs the" "$SMAPI_LOG" | while IFS= read -r line; do
        colorize_line "$line"
    done
}

show_summary() {
    if [[ ! -f "$SMAPI_LOG" ]]; then
        echo -e "${RED}Log file not found: $SMAPI_LOG${NC}"
        exit 1
    fi
    
    echo -e "${WHITE}═══ SMAPI Session Summary ═══${NC}"
    echo ""
    
    # Get the "Loaded X mods" line
    local loaded_line=$(grep -oP "Loaded \d+ mods" "$SMAPI_LOG" 2>/dev/null | tail -1)
    local loaded=$(echo "$loaded_line" | grep -oP '\d+' || echo "?")
    
    # Count errors/warnings (unique ERROR/WARN lines, not duplicates)
    local errors=$(grep -c "\[.*ERROR" "$SMAPI_LOG" 2>/dev/null || echo "0")
    local warnings=$(grep -c "\[.*WARN" "$SMAPI_LOG" 2>/dev/null || echo "0")
    
    # Count skipped mods (from the "Skipped mods" section)
    local skipped
    skipped=$(grep -A 100 "Skipped mods" "$SMAPI_LOG" 2>/dev/null | grep -c "^\s*- " 2>/dev/null) || skipped=0
    
    echo -e "${GREEN}✓ Loaded mods:${NC} $loaded"
    echo -e "${MAGENTA}✗ Skipped mods:${NC} $skipped"
    echo -e "${RED}⚠ Errors:${NC} $errors"
    echo -e "${YELLOW}⚠ Warnings:${NC} $warnings"
    echo ""
    
    # Show skipped mods (if any)
    if [[ "${skipped:-0}" -gt 0 ]]; then
        echo -e "${WHITE}═══ Skipped Mods ═══${NC}"
        grep -A 100 "Skipped mods" "$SMAPI_LOG" 2>/dev/null | grep -E "^\s*- " | head -20 | while IFS= read -r line; do
            echo -e "${MAGENTA}$line${NC}"
        done
        echo ""
    fi
    
    # Show SMAPI version
    local smapi_version=$(grep -oP "SMAPI \d+\.\d+\.\d+" "$SMAPI_LOG" 2>/dev/null | head -1 || echo "SMAPI version unknown")
    echo -e "${CYAN}$smapi_version${NC}"
    echo -e "${DIM}Log: $SMAPI_LOG${NC}"
    echo -e "${DIM}Size: $(ls -lh "$SMAPI_LOG" 2>/dev/null | awk '{print $5}')${NC}"
}

show_full() {
    if [[ ! -f "$SMAPI_LOG" ]]; then
        echo -e "${RED}Log file not found: $SMAPI_LOG${NC}"
        echo -e "${YELLOW}The game may not have been launched yet, or SMAPI is not installed.${NC}"
        exit 1
    fi
    
    echo -e "${DIM}Log: $SMAPI_LOG${NC}"
    echo ""
    
    cat "$SMAPI_LOG" | while IFS= read -r line; do
        colorize_line "$line"
    done
}

follow_log() {
    echo -e "${CYAN}Following SMAPI log (Ctrl+C to stop)${NC}"
    echo -e "${DIM}Log: $SMAPI_LOG${NC}"
    echo ""
    
    # Wait for log file if it doesn't exist
    while [[ ! -f "$SMAPI_LOG" ]]; do
        echo -e "${YELLOW}Waiting for SMAPI to start...${NC}"
        sleep 1
    done
    
    # Show last 20 lines first
    echo -e "${WHITE}═══ Last 20 lines ═══${NC}"
    tail -n 20 "$SMAPI_LOG" | while IFS= read -r line; do
        colorize_line "$line"
    done
    
    echo ""
    echo -e "${WHITE}═══ Live feed ═══${NC}"
    
    tail -f "$SMAPI_LOG" 2>/dev/null | while IFS= read -r line; do
        colorize_line "$line"
    done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --errors|-e)
            MODE="errors"
            shift
            ;;
        --mods|-m)
            MODE="mods"
            shift
            ;;
        --summary|-s)
            MODE="summary"
            shift
            ;;
        --live|-l|--follow|-f)
            FOLLOW=true
            shift
            ;;
        --path|-p)
            echo "$SMAPI_LOG"
            exit 0
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            print_usage
            exit 1
            ;;
    esac
done

print_header

if [[ "$FOLLOW" == "true" ]]; then
    follow_log
else
    case "$MODE" in
        errors)
            show_errors
            ;;
        mods)
            show_mods
            ;;
        summary)
            show_summary
            ;;
        full)
            show_full
            ;;
    esac
fi

