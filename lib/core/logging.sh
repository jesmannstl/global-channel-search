#!/bin/bash
# lib/core/logging.sh - Centralized Logging System
# Comprehensive logging functionality for GlobalStationSearch

# ============================================================================
# LOGGING CONFIGURATION
# ============================================================================

# Log levels (numeric for comparison)
declare -r LOG_LEVEL_DEBUG=10
declare -r LOG_LEVEL_INFO=20
declare -r LOG_LEVEL_WARN=30
declare -r LOG_LEVEL_ERROR=40
declare -r LOG_LEVEL_FATAL=50

# Current log level (can be overridden by LOG_LEVEL environment variable)
LOG_CURRENT_LEVEL="${LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Convert string log levels to numeric
case "${LOG_LEVEL:-INFO}" in
    "DEBUG") LOG_CURRENT_LEVEL=$LOG_LEVEL_DEBUG ;;
    "INFO")  LOG_CURRENT_LEVEL=$LOG_LEVEL_INFO ;;
    "WARN")  LOG_CURRENT_LEVEL=$LOG_LEVEL_WARN ;;
    "ERROR") LOG_CURRENT_LEVEL=$LOG_LEVEL_ERROR ;;
    "FATAL") LOG_CURRENT_LEVEL=$LOG_LEVEL_FATAL ;;
esac

# Logging configuration
LOG_TO_FILE="${LOG_TO_FILE:-true}"
LOG_TO_CONSOLE="${LOG_TO_CONSOLE:-true}"
LOG_WITH_COLORS="${LOG_WITH_COLORS:-true}"
LOG_MAX_FILE_SIZE="${LOG_MAX_FILE_SIZE:-10485760}"  # 10MB
LOG_MAX_BACKUP_FILES="${LOG_MAX_BACKUP_FILES:-5}"

# Log file paths
LOG_MAIN_FILE="${LOGS_DIR}/globalstationsearch.log"
LOG_ERROR_FILE="${LOGS_DIR}/error.log"
LOG_DEBUG_FILE="${LOGS_DIR}/debug.log"

# ============================================================================
# LOGGING SYSTEM INITIALIZATION
# ============================================================================

# Description: Initialize the logging system
# Arguments: None
# Returns: 0 on success, 1 on failure
log_init() {
    # Ensure logs directory exists
    if [[ -n "$LOGS_DIR" ]] && ! mkdir -p "$LOGS_DIR" 2>/dev/null; then
        echo "WARNING: Cannot create logs directory: $LOGS_DIR" >&2
        LOG_TO_FILE="false"
        return 1
    fi
    
    # Initialize log files if logging to file is enabled
    if [[ "$LOG_TO_FILE" == "true" && -n "$LOGS_DIR" ]]; then
        touch "$LOG_MAIN_FILE" "$LOG_ERROR_FILE" "$LOG_DEBUG_FILE" 2>/dev/null || {
            echo "WARNING: Cannot create log files in $LOGS_DIR" >&2
            LOG_TO_FILE="false"
            return 1
        }
    fi
    
    # Log system initialization
    log_info "logging" "Logging system initialized (Level: $(log_level_name $LOG_CURRENT_LEVEL))"
    log_debug "logging" "Log files: Main=$LOG_MAIN_FILE, Error=$LOG_ERROR_FILE, Debug=$LOG_DEBUG_FILE"
    
    return 0
}

# ============================================================================
# CORE LOGGING FUNCTIONS
# ============================================================================

# Description: Main logging function
# Arguments:
#   $1 - Log level (numeric)
#   $2 - Module name
#   $3 - Message
#   $4 - Additional context (optional)
# Returns: 0 always
log_write() {
    local level="$1"
    local module="$2"
    local message="$3"
    local context="${4:-}"
    
    # Skip if log level is below current threshold
    [[ $level -lt $LOG_CURRENT_LEVEL ]] && return 0
    
    # Generate timestamp
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get level name and color
    local level_name
    local level_color=""
    case $level in
        $LOG_LEVEL_DEBUG) 
            level_name="DEBUG"
            level_color="${CYAN}"
            ;;
        $LOG_LEVEL_INFO)  
            level_name="INFO "
            level_color="${WHITE}"
            ;;
        $LOG_LEVEL_WARN)  
            level_name="WARN "
            level_color="${YELLOW}"
            ;;
        $LOG_LEVEL_ERROR) 
            level_name="ERROR"
            level_color="${RED}"
            ;;
        $LOG_LEVEL_FATAL) 
            level_name="FATAL"
            level_color="${BOLD}${RED}"
            ;;
        *) 
            level_name="UNKN "
            level_color="${MAGENTA}"
            ;;
    esac
    
    # Format module name (truncate/pad to 12 characters)
    local formatted_module
    if [[ ${#module} -gt 12 ]]; then
        formatted_module="${module:0:9}..."
    else
        formatted_module=$(printf "%-12s" "$module")
    fi
    
    # Build log message
    local log_entry="$timestamp [$level_name] [$formatted_module] $message"
    [[ -n "$context" ]] && log_entry="$log_entry [$context]"
    
    # Console output with colors (redirect to stderr to avoid contaminating command outputs)
    if [[ "$LOG_TO_CONSOLE" == "true" ]]; then
        if [[ "$LOG_WITH_COLORS" == "true" && -t 2 ]]; then
            echo -e "${level_color}$log_entry${RESET}" >&2
        else
            echo "$log_entry" >&2
        fi
    fi
    
    # File output (always without colors)
    if [[ "$LOG_TO_FILE" == "true" && -n "$LOGS_DIR" ]]; then
        # Main log file
        echo "$log_entry" >> "$LOG_MAIN_FILE"
        
        # Separate error log for ERROR and FATAL
        if [[ $level -ge $LOG_LEVEL_ERROR ]]; then
            echo "$log_entry" >> "$LOG_ERROR_FILE"
        fi
        
        # Debug log for DEBUG level
        if [[ $level -eq $LOG_LEVEL_DEBUG ]]; then
            echo "$log_entry" >> "$LOG_DEBUG_FILE"
        fi
        
        # Rotate logs if needed
        log_rotate_if_needed
    fi
    
    return 0
}

# ============================================================================
# CONVENIENCE LOGGING FUNCTIONS
# ============================================================================

# Description: Auto-detect calling module and log message
# Arguments:
#   $1 - Log level (numeric)
#   $2 - Message
#   $3 - Additional context (optional)
log_auto() {
    local level="$1"
    local message="$2"
    local context="${3:-}"
    
    # Auto-detect module from calling script
    local module="unknown"
    if [[ -n "${BASH_SOURCE[2]:-}" ]]; then
        module=$(basename "${BASH_SOURCE[2]}" .sh)
        # Clean up module name
        module="${module#lib_}"
        module="${module//[-_]//}"
    fi
    
    log_write "$level" "$module" "$message" "$context"
}

# Debug logging
log_debug() {
    local module="$1"
    local message="$2"
    local context="${3:-}"
    log_write "$LOG_LEVEL_DEBUG" "$module" "$message" "$context"
}

# Info logging
log_info() {
    local module="$1"
    local message="$2"
    local context="${3:-}"
    log_write "$LOG_LEVEL_INFO" "$module" "$message" "$context"
}

# Warning logging
log_warn() {
    local module="$1"
    local message="$2"
    local context="${3:-}"
    log_write "$LOG_LEVEL_WARN" "$module" "$message" "$context"
}

# Error logging
log_error() {
    local module="$1"
    local message="$2"
    local context="${3:-}"
    log_write "$LOG_LEVEL_ERROR" "$module" "$message" "$context"
}

# Fatal logging (for critical errors)
log_fatal() {
    local module="$1"
    local message="$2"
    local context="${3:-}"
    log_write "$LOG_LEVEL_FATAL" "$module" "$message" "$context"
}

# ============================================================================
# AUTO-DETECTION CONVENIENCE FUNCTIONS
# ============================================================================

# These functions automatically detect the calling module

log_debug_auto() {
    log_auto "$LOG_LEVEL_DEBUG" "$1" "${2:-}"
}

log_info_auto() {
    log_auto "$LOG_LEVEL_INFO" "$1" "${2:-}"
}

log_warn_auto() {
    log_auto "$LOG_LEVEL_WARN" "$1" "${2:-}"
}

log_error_auto() {
    log_auto "$LOG_LEVEL_ERROR" "$1" "${2:-}"
}

log_fatal_auto() {
    log_auto "$LOG_LEVEL_FATAL" "$1" "${2:-}"
}

# ============================================================================
# SPECIALIZED LOGGING FUNCTIONS
# ============================================================================

# Description: Log API operations
# Arguments:
#   $1 - Operation (GET, POST, etc.)
#   $2 - URL
#   $3 - Status code
#   $4 - Response time (optional)
log_api_operation() {
    local operation="$1"
    local url="$2"
    local status_code="$3"
    local response_time="${4:-}"
    
    local message="$operation $url -> $status_code"
    [[ -n "$response_time" ]] && message="$message (${response_time}ms)"
    
    if [[ $status_code -ge 400 ]]; then
        log_error "api" "$message"
    else
        log_info "api" "$message"
    fi
}

# Description: Log user actions
# Arguments:
#   $1 - Action description
#   $2 - Context (optional)
log_user_action() {
    local action="$1"
    local context="${2:-}"
    log_info "user" "$action" "$context"
}

# Description: Log performance metrics
# Arguments:
#   $1 - Operation name
#   $2 - Duration in seconds
#   $3 - Additional metrics (optional)
log_performance() {
    local operation="$1"
    local duration="$2"
    local metrics="${3:-}"
    
    local message="$operation completed in ${duration}s"
    [[ -n "$metrics" ]] && message="$message ($metrics)"
    
    log_info "perf" "$message"
}

# Description: Log configuration changes
# Arguments:
#   $1 - Setting name
#   $2 - Old value
#   $3 - New value
log_config_change() {
    local setting="$1"
    local old_value="$2"
    local new_value="$3"
    
    log_info "config" "Setting changed: $setting: '$old_value' -> '$new_value'"
}

# ============================================================================
# LOG ROTATION AND MAINTENANCE
# ============================================================================

# Description: Rotate log files if they exceed maximum size
# Arguments: None
# Returns: 0 on success
log_rotate_if_needed() {
    [[ "$LOG_TO_FILE" != "true" ]] && return 0
    
    local log_files=("$LOG_MAIN_FILE" "$LOG_ERROR_FILE" "$LOG_DEBUG_FILE")
    
    for log_file in "${log_files[@]}"; do
        [[ ! -f "$log_file" ]] && continue
        
        local file_size
        file_size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
        
        if [[ $file_size -gt $LOG_MAX_FILE_SIZE ]]; then
            log_rotate_file "$log_file"
        fi
    done
}

# Description: Rotate a specific log file
# Arguments:
#   $1 - Log file path
# Returns: 0 on success
log_rotate_file() {
    local log_file="$1"
    [[ ! -f "$log_file" ]] && return 1
    
    local base_name="${log_file%.log}"
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    
    # Rotate existing backup files
    for ((i = LOG_MAX_BACKUP_FILES - 1; i >= 1; i--)); do
        local old_backup="${base_name}.${i}.log"
        local new_backup="${base_name}.$((i + 1)).log"
        [[ -f "$old_backup" ]] && mv "$old_backup" "$new_backup"
    done
    
    # Move current log to backup
    mv "$log_file" "${base_name}.1.log"
    
    # Create new empty log file
    touch "$log_file"
    
    log_info "logging" "Rotated log file: $(basename "$log_file")"
}

# Description: Clean up old log files
# Arguments:
#   $1 - Days to keep (optional, defaults to 30)
# Returns: 0 on success
log_cleanup_old_files() {
    local days_to_keep="${1:-30}"
    [[ "$LOG_TO_FILE" != "true" || -z "$LOGS_DIR" ]] && return 0
    
    local files_removed=0
    
    # Find and remove old log files
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((files_removed++))
    done < <(find "$LOGS_DIR" -name "*.log" -type f -mtime "+$days_to_keep" -print0 2>/dev/null)
    
    if [[ $files_removed -gt 0 ]]; then
        log_info "logging" "Cleaned up $files_removed old log files (>${days_to_keep} days)"
    fi
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Description: Convert numeric log level to name
# Arguments:
#   $1 - Numeric log level
# Returns: Log level name
log_level_name() {
    case "$1" in
        $LOG_LEVEL_DEBUG) echo "DEBUG" ;;
        $LOG_LEVEL_INFO)  echo "INFO" ;;
        $LOG_LEVEL_WARN)  echo "WARN" ;;
        $LOG_LEVEL_ERROR) echo "ERROR" ;;
        $LOG_LEVEL_FATAL) echo "FATAL" ;;
        *) echo "UNKNOWN" ;;
    esac
}

# Description: Get current log level name
# Arguments: None
# Returns: Current log level name
log_get_current_level_name() {
    log_level_name "$LOG_CURRENT_LEVEL"
}

# Description: Set log level by name
# Arguments:
#   $1 - Log level name (DEBUG, INFO, WARN, ERROR, FATAL)
# Returns: 0 on success, 1 on invalid level
log_set_level() {
    case "${1^^}" in
        "DEBUG") LOG_CURRENT_LEVEL=$LOG_LEVEL_DEBUG; return 0 ;;
        "INFO")  LOG_CURRENT_LEVEL=$LOG_LEVEL_INFO; return 0 ;;
        "WARN")  LOG_CURRENT_LEVEL=$LOG_LEVEL_WARN; return 0 ;;
        "ERROR") LOG_CURRENT_LEVEL=$LOG_LEVEL_ERROR; return 0 ;;
        "FATAL") LOG_CURRENT_LEVEL=$LOG_LEVEL_FATAL; return 0 ;;
        *) log_error "logging" "Invalid log level: $1"; return 1 ;;
    esac
}

# Description: Check if a log level would be logged
# Arguments:
#   $1 - Log level to check (numeric)
# Returns: 0 if would be logged, 1 if would be skipped
log_would_log() {
    [[ $1 -ge $LOG_CURRENT_LEVEL ]]
}

# Description: Get log statistics
# Arguments: None
# Returns: Outputs log statistics
log_get_stats() {
    [[ "$LOG_TO_FILE" != "true" || -z "$LOGS_DIR" ]] && return 1
    
    echo "=== Log Statistics ==="
    echo "Current Level: $(log_get_current_level_name)"
    echo "Log Directory: $LOGS_DIR"
    
    for log_file in "$LOG_MAIN_FILE" "$LOG_ERROR_FILE" "$LOG_DEBUG_FILE"; do
        if [[ -f "$log_file" ]]; then
            local size lines
            size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
            lines=$(wc -l < "$log_file" 2>/dev/null || echo 0)
            printf "%-20s: %'d bytes, %'d lines\n" "$(basename "$log_file")" "$size" "$lines"
        fi
    done
}


# Initialize logging system if not already done
if [[ -z "${LOG_SYSTEM_INITIALIZED:-}" ]]; then
    log_init
    LOG_SYSTEM_INITIALIZED=true
fi