#!/bin/bash
# lib/core/progress_tracker.sh - Interruption Recovery System
# Enhanced with Phase-Aware Progress Tracking
# Shared module for cache.sh and base_cache_builder.sh
# Provides progress tracking and resume functionality for all phases

# ============================================================================
# PROGRESS TRACKING CONFIGURATION
# ============================================================================

# Progress file locations
PROGRESS_FILE=""
CHECKPOINT_FILE=""
OPERATION_TYPE=""

# Initialize progress tracking based on context
init_progress_context() {
    local context="$1"  # "user_caching" or "base_building"
    
    case "$context" in
        "user_caching")
            PROGRESS_FILE="$CACHE_DIR/user_progress_state.json"
            CHECKPOINT_FILE="$CACHE_DIR/user_market_checkpoint.json"
            ;;
        "base_building")
            PROGRESS_FILE="$CACHE_DIR/base_progress_state.json"
            CHECKPOINT_FILE="$CACHE_DIR/base_market_checkpoint.json"
            ;;
        *)
            echo -e "${RED}❌ Invalid progress context: $context${RESET}" >&2
            return 1
            ;;
    esac
    
    OPERATION_TYPE="$context"
    return 0
}

# ============================================================================
# ENHANCED PHASE-AWARE PROGRESS TRACKING FUNCTIONS
# ============================================================================

# Initialize enhanced progress tracking with phase structure
init_progress_tracking() {
    local operation="$1"        # "user_caching" or "base_building"
    local total_markets="$2"    # Total number of markets to process
    local force_refresh="$3"    # true/false
    local markets_list="$4"     # Path to markets CSV file
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    echo -e "${CYAN}📊 Initializing progress tracking for $operation...${RESET}" >&2
    
    # Create enhanced progress state with granular enhancement tracking
    cat > "$PROGRESS_FILE" << EOF
{
  "operation": "$operation",
  "start_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "current_phase": "initialization",
  "phase_progress": {
    "market_processing": {
      "status": "not_started",
      "completed_markets": [],
      "failed_markets": [],
      "total_markets": $total_markets,
      "processed_markets": 0
    },
    "station_enhancement": {
      "status": "not_started",
      "temp_stations_file": null,
      "temp_enhanced_file": null,
      "total_stations": 0,
      "enhanced_stations": 0,
      "current_station_index": 0
    },
    "cache_finalization": {
      "status": "not_started"
    }
  },
  "session_lineups": [],
  "force_refresh": $force_refresh,
  "markets_file": "$markets_list",
  "pid": $$,
  "last_update": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    # Setup signal handlers for graceful shutdown
    trap 'handle_interruption_signal' INT TERM
    
    echo -e "${GREEN}✅ Progress tracking initialized${RESET}" >&2
    return 0
}

# Update progress for specific phase
update_progress() {
    local phase="$1"
    local current_item="$2"
    local item_index="$3"
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    
    case "$phase" in
        "market_processing")
            jq --arg phase "$phase" \
               --arg market "$current_item" \
               --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
               '. + {
                 current_phase: $phase,
                 phase_progress: (.phase_progress + {
                   market_processing: (.phase_progress.market_processing + {
                     status: "in_progress"
                   })
                 }),
                 last_update: $timestamp
               }' "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
            ;;
        "station_enhancement") 
            local temp_file_path="$current_item"
            local total_stations="$item_index"
            jq --arg phase "$phase" \
               --arg temp_file "$temp_file_path" \
               --arg total "$total_stations" \
               --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
               '. + {
                 current_phase: $phase,
                 phase_progress: (.phase_progress + {
                   station_enhancement: (.phase_progress.station_enhancement + {
                     status: "in_progress",
                     temp_stations_file: $temp_file,
                     total_stations: ($total | tonumber)
                   })
                 }),
                 last_update: $timestamp
               }' "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
            ;;
        "cache_finalization")
            jq --arg phase "$phase" \
               --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
               '. + {
                 current_phase: $phase,
                 phase_progress: (.phase_progress + {
                   cache_finalization: (.phase_progress.cache_finalization + {
                     status: "in_progress"
                   })
                 }),
                 last_update: $timestamp
               }' "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
            ;;
    esac
    
    return 0
}

# Mark a phase as completed
mark_phase_completed() {
    local phase="$1"
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --arg phase "$phase" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.phase_progress[($phase)] += {status: "completed"} | 
        .last_update = $timestamp' \
       "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
}

# Get current phase from progress file
get_current_phase_from_progress() {
    local operation="$1"
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    jq -r '.current_phase' "$PROGRESS_FILE" 2>/dev/null
}

# Check if a specific phase is completed
is_phase_completed() {
    local operation="$1"
    local phase="$2"
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    local status=$(jq -r ".phase_progress.${phase}.status // \"not_started\"" "$PROGRESS_FILE" 2>/dev/null)
    [[ "$status" == "completed" ]]
}

# Get temp stations file from progress (for enhancement resume)
get_temp_stations_file_from_progress() {
    local operation="$1"
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    local temp_file=$(jq -r '.phase_progress.station_enhancement.temp_stations_file // null' "$PROGRESS_FILE" 2>/dev/null)
    if [[ "$temp_file" != "null" ]]; then
        echo "$temp_file"
    fi
}

# Enhanced resume logic - determine what phase to resume from
determine_resume_phase() {
    local operation="$1"
    
    if ! init_progress_context "$operation"; then
        echo "market_processing"  # Default
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "market_processing"  # Default
        return 1
    fi
    
    # Check phase completion status
    local market_status=$(jq -r '.phase_progress.market_processing.status // "not_started"' "$PROGRESS_FILE" 2>/dev/null)
    local enhancement_status=$(jq -r '.phase_progress.station_enhancement.status // "not_started"' "$PROGRESS_FILE" 2>/dev/null)
    local finalization_status=$(jq -r '.phase_progress.cache_finalization.status // "not_started"' "$PROGRESS_FILE" 2>/dev/null)
    
    # Check enhancement progress details
    local current_station_index=$(jq -r '.phase_progress.station_enhancement.current_station_index // 0' "$PROGRESS_FILE" 2>/dev/null)
    local total_stations=$(jq -r '.phase_progress.station_enhancement.total_stations // 0' "$PROGRESS_FILE" 2>/dev/null)
    
    # Determine which phase to resume from
    if [[ "$finalization_status" == "in_progress" ]]; then
        echo "cache_finalization"
    elif [[ "$enhancement_status" == "in_progress" ]]; then
        # Check if enhancement was actually started (has progress)
        if [[ "$current_station_index" -gt 0 ]]; then
            echo "station_enhancement"
        else
            echo "station_enhancement"  # Start enhancement fresh
        fi
    elif [[ "$enhancement_status" == "not_started" && "$market_status" == "completed" ]]; then
        echo "station_enhancement" 
    elif [[ "$market_status" == "in_progress" ]] || [[ "$market_status" == "not_started" ]]; then
        echo "market_processing"
    else
        echo "completed"  # All phases done
    fi
}

# Enhanced get remaining markets - only if market processing not completed
get_remaining_markets_from_progress() {
    local operation="$1"
    local safety_buffer="${2:-2}"  # Default 2 market safety buffer
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    # Check if market processing is completed
    local market_status=$(jq -r '.phase_progress.market_processing.status // "not_started"' "$PROGRESS_FILE" 2>/dev/null)
    if [[ "$market_status" == "completed" ]]; then
        return 1  # No markets to process
    fi
    
    # Get completed and failed markets
    local completed_markets=($(jq -r '.phase_progress.market_processing.completed_markets[]?' "$PROGRESS_FILE" 2>/dev/null))
    local failed_markets=($(jq -r '.phase_progress.market_processing.failed_markets[]?' "$PROGRESS_FILE" 2>/dev/null))
    local markets_file=$(jq -r '.markets_file' "$PROGRESS_FILE" 2>/dev/null)
    
    # Apply safety buffer - remove the last N completed markets to reprocess them
    local safe_completed_markets=()
    local total_completed=${#completed_markets[@]}
    local safe_count=$((total_completed - safety_buffer))
    
    if [[ $safe_count -gt 0 ]]; then
        # Keep only the first (total - safety_buffer) completed markets
        safe_completed_markets=("${completed_markets[@]:0:$safe_count}")
        
        echo -e "${CYAN}📊 Market safety buffer applied: Reprocessing last $safety_buffer completed markets${RESET}" >&2
        echo -e "${CYAN}📊 Originally completed: $total_completed markets → Safe completed: ${#safe_completed_markets[@]} markets${RESET}" >&2
    else
        # If we have fewer completed markets than the safety buffer, reprocess all
        echo -e "${CYAN}📊 Market safety buffer: Reprocessing all $total_completed completed markets (less than buffer size)${RESET}" >&2
    fi
    
    # Combine safe completed and failed (we skip both)
    local processed_markets=("${safe_completed_markets[@]}" "${failed_markets[@]}")
    
    # Read all markets from CSV and filter out processed ones
    while IFS=, read -r country zip; do
        [[ "$country" == "Country" ]] && continue
        
        local market_key="$country,$zip"
        local already_processed=false
        
        # Check if this market was already processed (and is in the safe zone)
        for processed_market in "${processed_markets[@]}"; do
            if [[ "$processed_market" == "$market_key" ]]; then
                already_processed=true
                break
            fi
        done
        
        # Output remaining markets (not in safe processed list)
        if [[ "$already_processed" == "false" ]]; then
            echo "$market_key"
        fi
        
    done < "$markets_file"
    
    return 0
}

# Enhanced market completion tracking
mark_market_completed() {
    local operation="$1"
    local market_key="$2"
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    # Add market to completed_markets array and increment processed_markets
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --arg market "$market_key" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.phase_progress.market_processing += {
         completed_markets: (.phase_progress.market_processing.completed_markets + [$market] | unique),
         processed_markets: (.phase_progress.market_processing.processed_markets + 1)
       } |
       .last_update = $timestamp' "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
}

# Enhanced market failure tracking
mark_market_failed() {
    local operation="$1" 
    local market_key="$2"
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    # Add market to failed_markets array and increment processed_markets
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --arg market "$market_key" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.phase_progress.market_processing += {
         failed_markets: (.phase_progress.market_processing.failed_markets + [$market] | unique),
         processed_markets: (.phase_progress.market_processing.processed_markets + 1)
       } |
       .last_update = $timestamp' "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
}

# ============================================================================
# SIGNAL HANDLING AND INTERRUPTION RECOVERY
# ============================================================================

# Handle interruption signals (Ctrl+C, SIGTERM)
handle_interruption_signal() {
    echo -e "\n${YELLOW}🚨 Interruption detected! ${RESET}" >&2
    echo -e "${CYAN}💾 Saving progress...${RESET}" >&2
    
    # Update session lineups one final time
    update_session_lineups
    
    # Mark as interrupted
    if [[ -f "$PROGRESS_FILE" ]]; then
        local temp_file="${PROGRESS_FILE}.tmp.$$"
        jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '.current_phase = "interrupted" | .last_update = $timestamp' \
           "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
    fi
    
    echo -e "${GREEN}✅ Progress saved. You can resume later by running the same command.${RESET}" >&2
    echo -e "${CYAN}💡 Progress file: $PROGRESS_FILE${RESET}" >&2
    
    exit 0
}

# ============================================================================
# RECOVERY DETECTION AND MENU
# ============================================================================

# Check for interrupted session and handle user choice
check_for_interrupted_session() {
    local operation="$1"  # "user_caching" or "base_building"
    
    if ! init_progress_context "$operation"; then
        return 2  # No recovery needed
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 2  # No interrupted session
    fi
    
    # Parse progress file
    local operation_type=$(jq -r '.operation' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
    local start_time=$(jq -r '.start_time' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
    local current_phase=$(jq -r '.current_phase' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
    local pid=$(jq -r '.pid // 0' "$PROGRESS_FILE" 2>/dev/null || echo "0")
    local last_update=$(jq -r '.last_update' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
    
    # Get phase-specific progress
    local market_processed=$(jq -r '.phase_progress.market_processing.processed_markets // 0' "$PROGRESS_FILE" 2>/dev/null || echo "0")
    local market_total=$(jq -r '.phase_progress.market_processing.total_markets // 0' "$PROGRESS_FILE" 2>/dev/null || echo "0")
    
    # Validate progress file
    if [[ "$operation_type" == "null" ]] || [[ "$operation_type" == "unknown" ]]; then
        echo -e "${YELLOW}⚠️  Found corrupted progress file, removing...${RESET}" >&2
        rm -f "$PROGRESS_FILE" "$CHECKPOINT_FILE"
        return 2
    fi
    
    # Check if operation type matches
    if [[ "$operation_type" != "$operation" ]]; then
        echo -e "${YELLOW}⚠️  Found progress for different operation ($operation_type), ignoring...${RESET}" >&2
        return 2
    fi
    
    # Check if process is still running
    if [[ "$pid" -gt 0 ]] && kill -0 "$pid" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Another $operation process appears to be running (PID: $pid)${RESET}" >&2
        echo -e "${CYAN}💡 If this is incorrect, you can safely delete: $PROGRESS_FILE${RESET}" >&2
        return 1  # Cannot proceed
    fi
    
    # Calculate progress percentage
    local progress_percent=0
    if [[ "$market_total" -gt 0 ]]; then
        progress_percent=$((market_processed * 100 / market_total))
    fi
    
    # Show recovery menu
    echo
    echo -e "${BOLD}${YELLOW}📋 Interrupted Session Detected${RESET}"
    echo -e "${CYAN}Operation: $operation_type${RESET}"
    echo -e "${CYAN}Started: $start_time${RESET}"
    echo -e "${CYAN}Last Update: $last_update${RESET}"
    echo -e "${CYAN}Progress: $market_processed/$market_total markets (${progress_percent}%) - $current_phase${RESET}"
    echo
    echo -e "${GREEN}1)${RESET} Resume from where we left off"
    echo -e "${GREEN}2)${RESET} Start over (will backup current progress)"
    echo -e "${GREEN}3)${RESET} Cancel operation"
    echo
    
    while true; do
        read -p "Choose option (1-3): " choice
        case "$choice" in
            1) 
                echo -e "${CYAN}🔄 Resuming interrupted session...${RESET}"
                return 0  # Resume
                ;;
            2) 
                # Backup current progress and start fresh
                local backup_file="${PROGRESS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
                mv "$PROGRESS_FILE" "$backup_file"
                [[ -f "$CHECKPOINT_FILE" ]] && mv "$CHECKPOINT_FILE" "${CHECKPOINT_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
                echo -e "${CYAN}💾 Progress backed up to: $(basename "$backup_file")${RESET}"
                echo -e "${GREEN}✅ Starting fresh...${RESET}"
                return 2  # Start fresh
                ;;
            3) 
                echo -e "${YELLOW}Operation cancelled${RESET}"
                return 1  # Cancel
                ;;
            *) 
                echo -e "${RED}Invalid option. Please choose 1, 2, or 3.${RESET}"
                ;;
        esac
    done
}

# ============================================================================
# RESUME FUNCTIONALITY
# ============================================================================

# Resume progress tracking from existing progress file
resume_progress_tracking() {
    local operation="$1"
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo -e "${RED}❌ No progress file found to resume${RESET}" >&2
        return 1
    fi
    
    # Validate progress file
    if ! jq empty "$PROGRESS_FILE" 2>/dev/null; then
        echo -e "${RED}❌ Progress file is corrupted${RESET}" >&2
        return 1
    fi
    
    # Update PID and timestamp for current session
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --arg pid "$$" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '. + {
         pid: ($pid | tonumber),
         last_update: $timestamp,
         current_phase: "resumed"
       }' "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
    
    # Setup signal handlers for graceful shutdown
    trap 'handle_interruption_signal' INT TERM
    
    echo -e "${GREEN}✅ Progress tracking resumed${RESET}" >&2
    return 0
}

# Restore session state from progress file
restore_session_state_from_progress() {
    local operation="$1"
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    # Get session lineups from progress file
    local session_lineups=($(jq -r '.session_lineups[]?' "$PROGRESS_FILE" 2>/dev/null))
    
    if [[ ${#session_lineups[@]} -gt 0 ]]; then
        # Restore the global session tracking array
        PROCESSED_LINEUPS_THIS_SESSION=("${session_lineups[@]}")
        echo -e "${CYAN}🔄 Restored ${#session_lineups[@]} processed lineups from previous session${RESET}" >&2
    fi
    
    return 0
}

# Get original start time from progress file
get_original_start_time_from_progress() {
    local operation="$1"
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    # Extract start time from progress file
    jq -r '.start_time' "$PROGRESS_FILE" 2>/dev/null | head -1
}

# Update session lineups in progress file
update_session_lineups() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    # Convert bash array to JSON array
    local lineups_json=$(printf '%s\n' "${PROCESSED_LINEUPS_THIS_SESSION[@]}" | jq -R . | jq -s .)
    
    # Update progress file with current session lineups
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --argjson lineups "$lineups_json" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '. + {
         session_lineups: $lineups,
         last_update: $timestamp
       }' "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
}

# Finalize progress tracking
finalize_progress_tracking() {
    local operation="$1"
    local status="${2:-completed}"  # completed, no_new_stations, cancelled, restart_needed
    
    if ! init_progress_context "$operation"; then
        return 0  # Don't fail if we can't finalize
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0  # Nothing to finalize
    fi
    
    case "$status" in
        "completed")
            echo -e "${GREEN}✅ Operation completed successfully${RESET}" >&2
            ;;
        "no_new_stations")
            echo -e "${YELLOW}⚠️  Operation completed with no new stations${RESET}" >&2
            ;;
        "cancelled")
            echo -e "${YELLOW}⚠️  Operation was cancelled${RESET}" >&2
            ;;
        "restart_needed")
            echo -e "${YELLOW}⚠️  Restart required due to missing files${RESET}" >&2
            ;;
    esac
    
    # Remove progress files
    rm -f "$PROGRESS_FILE" "$CHECKPOINT_FILE"
    
    # Reset signal handlers
    trap - INT TERM
    
    echo -e "${CYAN}🧹 Progress tracking cleaned up${RESET}" >&2
    return 0
}

# Enhanced resume logic with safety buffer
get_enhancement_resume_point() {
    local operation="$1"
    local safety_buffer="${2:-50}"  # Default 50 station safety buffer
    
    if ! init_progress_context "$operation"; then
        echo "0 0"  # start_index enhanced_count
        return 0
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "0 0"  # start_index enhanced_count
        return 0
    fi
    
    local enhancement_status=$(jq -r '.phase_progress.station_enhancement.status // "not_started"' "$PROGRESS_FILE" 2>/dev/null)
    
    if [[ "$enhancement_status" == "in_progress" ]]; then
        local last_recorded_index=$(jq -r '.phase_progress.station_enhancement.current_station_index // 0' "$PROGRESS_FILE" 2>/dev/null)
        local enhanced_from_api=$(jq -r '.phase_progress.station_enhancement.enhanced_stations // 0' "$PROGRESS_FILE" 2>/dev/null)
        
        # Apply safety buffer - go back 50 stations (or to 0 if less than 50)
        local safe_start_index=$((last_recorded_index - safety_buffer))
        if [[ $safe_start_index -lt 0 ]]; then
            safe_start_index=0
        fi
        
        # Estimate enhanced count based on the safety buffer
        # We'll lose some tracking of enhanced count due to re-processing, but that's safer
        local estimated_enhanced=0
        if [[ $last_recorded_index -gt 0 ]]; then
            estimated_enhanced=$((enhanced_from_api * safe_start_index / last_recorded_index))
            if [[ $estimated_enhanced -lt 0 ]]; then
                estimated_enhanced=0
            fi
        fi
        
        echo -e "${CYAN}📊 Safety buffer applied: Starting $safety_buffer stations back from interruption point${RESET}" >&2
        echo -e "${CYAN}📊 Last recorded: station $last_recorded_index → Safe start: station $safe_start_index${RESET}" >&2
        
        echo "$safe_start_index $estimated_enhanced"
        return 0
    else
        echo "0 0"  # start_index enhanced_count
        return 0
    fi
}

# ============================================================================
# LEGACY COMPATIBILITY FUNCTIONS
# ============================================================================

# Get completed markets from progress file (for compatibility)
get_completed_markets_from_progress() {
    local operation="$1"
    local safety_buffer="${2:-2}"  # Default 2 market safety buffer
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    # Get completed markets
    local completed_markets=($(jq -r '.phase_progress.market_processing.completed_markets[]?' "$PROGRESS_FILE" 2>/dev/null))
    
    # Apply safety buffer - only return markets that are safely completed (not in last N)
    local total_completed=${#completed_markets[@]}
    local safe_count=$((total_completed - safety_buffer))
    
    if [[ $safe_count -gt 0 ]]; then
        # Return only the safely completed markets (excluding last N)
        for ((i = 0; i < safe_count; i++)); do
            echo "${completed_markets[$i]}"
        done
    fi
    # If safe_count <= 0, return nothing (all markets will be reprocessed)
}