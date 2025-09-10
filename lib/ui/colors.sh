#!/bin/bash

# === Terminal Colors & Styles Framework ===
# Centralized color definitions and styling utilities
# Used throughout GlobalStationSearch for consistent UI

# ============================================================================
# CORE TERMINAL STYLING
# ============================================================================

# ANSI escape sequence base
ESC="\033"

# Basic formatting
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
UNDERLINE="${ESC}[4m"

# Core colors (existing palette)
YELLOW="${ESC}[33m"
GREEN="${ESC}[32m"
RED="${ESC}[31m"
CYAN="${ESC}[36m"
BLUE="${ESC}[34m"
GRAY="${ESC}[90m"

# ============================================================================
# EXTENDED COLOR PALETTE (For Future Use)
# ============================================================================

# Additional standard colors
BLACK="${ESC}[30m"
MAGENTA="${ESC}[35m"
WHITE="${ESC}[37m"

# Bright/light colors  
BRIGHT_BLACK="${ESC}[90m"    # Same as GRAY
BRIGHT_RED="${ESC}[91m"
BRIGHT_GREEN="${ESC}[92m"
BRIGHT_YELLOW="${ESC}[93m"
BRIGHT_BLUE="${ESC}[94m"
BRIGHT_MAGENTA="${ESC}[95m"
BRIGHT_CYAN="${ESC}[96m"
BRIGHT_WHITE="${ESC}[97m"

# Background colors
BG_BLACK="${ESC}[40m"
BG_RED="${ESC}[41m"
BG_GREEN="${ESC}[42m"
BG_YELLOW="${ESC}[43m"
BG_BLUE="${ESC}[44m"
BG_MAGENTA="${ESC}[45m"
BG_CYAN="${ESC}[46m"
BG_WHITE="${ESC}[47m"

# ============================================================================
# STYLE COMBINATIONS (Commonly Used)
# ============================================================================

# Header styles
HEADER_STYLE="${BOLD}${CYAN}"
SUBHEADER_STYLE="${BOLD}${BLUE}"

# Status styles
SUCCESS_STYLE="${BOLD}${GREEN}"
WARNING_STYLE="${BOLD}${YELLOW}"
ERROR_STYLE="${BOLD}${RED}"
INFO_STYLE="${CYAN}"

# Menu styles
MENU_OPTION_STYLE="${GREEN}"
MENU_TITLE_STYLE="${BOLD}${CYAN}"

# ============================================================================
# COLOR UTILITY FUNCTIONS
# ============================================================================

# Check if terminal supports colors
colors_supported() {
    local term="${TERM:-}"
    
    # Basic terminal capability check
    if [[ -z "$term" ]] || [[ "$term" == "dumb" ]]; then
        return 1
    fi
    
    # Check if we're in a pipe or redirect
    if [[ ! -t 1 ]]; then
        return 1
    fi
    
    return 0
}

# Conditionally apply color (only if terminal supports it)
color_if_supported() {
    local color="$1"
    local text="$2"
    
    if colors_supported; then
        echo -e "${color}${text}${RESET}"
    else
        echo "$text"
    fi
}

# Apply color with automatic reset
colorize() {
    local color="$1"
    local text="$2"
    echo -e "${color}${text}${RESET}"
}

# ============================================================================
# SEMANTIC COLOR FUNCTIONS
# ============================================================================

# Semantic color helpers for consistent usage
color_success() {
    colorize "$SUCCESS_STYLE" "$1"
}

color_warning() {
    colorize "$WARNING_STYLE" "$1"
}

color_error() {
    colorize "$ERROR_STYLE" "$1"
}

color_info() {
    colorize "$INFO_STYLE" "$1"
}

color_header() {
    colorize "$HEADER_STYLE" "$1"
}

color_menu_option() {
    colorize "$MENU_OPTION_STYLE" "$1"
}

# ============================================================================
# TERMINAL CAPABILITY DETECTION
# ============================================================================

# Detect number of colors supported
get_color_capability() {
    local colors=0
    
    if command -v tput &> /dev/null; then
        colors=$(tput colors 2>/dev/null || echo 0)
    fi
    
    echo "$colors"
}

# Check if 256 colors are supported
supports_256_colors() {
    local colors=$(get_color_capability)
    [[ "$colors" -ge 256 ]]
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Automatically disable colors if not supported (safety)
if ! colors_supported; then
    # Define empty color variables for unsupported terminals
    ESC=""
    RESET=""
    BOLD=""
    UNDERLINE=""
    YELLOW=""
    GREEN=""
    RED=""
    CYAN=""
    BLUE=""
    GRAY=""
    
    # Extended colors also empty
    BLACK=""
    MAGENTA=""
    WHITE=""
    BRIGHT_BLACK=""
    BRIGHT_RED=""
    BRIGHT_GREEN=""
    BRIGHT_YELLOW=""
    BRIGHT_BLUE=""
    BRIGHT_MAGENTA=""
    BRIGHT_CYAN=""
    BRIGHT_WHITE=""
    
    # Style combinations also empty
    HEADER_STYLE=""
    SUBHEADER_STYLE=""
    SUCCESS_STYLE=""
    WARNING_STYLE=""
    ERROR_STYLE=""
    INFO_STYLE=""
    MENU_OPTION_STYLE=""
    MENU_TITLE_STYLE=""
fi

# Export core colors for backward compatibility
export ESC RESET BOLD UNDERLINE YELLOW GREEN RED CYAN BLUE GRAY

# Functions are automatically available when this module is sourced
# No explicit exports needed - sourcing makes all functions available

# Optional: Log successful module load (only if debug mode)
if [[ "${DEBUG_MODULE_LOADING:-false}" == "true" ]]; then
    echo "[DEBUG] Colors framework loaded ($(get_color_capability) colors supported)" >&2
fi