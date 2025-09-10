#!/usr/bin/env bash

# Channels DVR Integration Module
# Provides all Channels DVR server functionality including search, configuration, and management

# Module metadata
MODULE_NAME="cdvr"
MODULE_VERSION="1.0.0"
MODULE_DESCRIPTION="Channels DVR integration module"

# Prevent multiple inclusions
if [[ "${CDVR_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi

# Module identification
readonly CDVR_MODULE_LOADED="true"

# Module initialization
# Description: Initialize the CDVR module
# Arguments: None
# Returns: 0 - Success
cdvr_init() {
    # Load configuration if exists
    if [[ -f "$CONFIG_FILE" ]]; then
        cdvr_reload_config
    fi
    
    # Set default values if not configured
    : "${CHANNELS_URL:=}"
    
    # Initialize CDVR-specific cache paths
    : "${API_SEARCH_RESULTS:=$CACHE_DIR/api_search_results.tsv}"
    
    return 0
}

# ============================================================================
# Configuration Management Functions
# ============================================================================

# Description: Save Channels DVR configuration to file
# Arguments: None (uses global CHANNELS_URL)
# Returns: 0 - Success, 1 - Failure
cdvr_save_config() {
    local config_file="${CONFIG_FILE:-$HOME/.config/globalstationsearch/config}"
    
    # Create config directory if it doesn't exist
    local config_dir="$(dirname "$config_file")"
    [[ ! -d "$config_dir" ]] && mkdir -p "$config_dir"
    
    # Update or add CHANNELS_URL in config file
    if [[ -f "$config_file" ]]; then
        # Remove old CHANNELS_URL line if exists
        sed -i.bak '/^CHANNELS_URL=/d' "$config_file"
        rm -f "${config_file}.bak"
    fi
    
    # Append new configuration
    {
        echo "# Channels DVR Configuration"
        echo "CHANNELS_URL=\"$CHANNELS_URL\""
    } >> "$config_file"
    
    # Reload configuration
    cdvr_reload_config
}

# Description: Reload Channels DVR configuration from file
# Arguments: None
# Returns: 0 - Success, 1 - Failure
cdvr_reload_config() {
    local config_file="${CONFIG_FILE:-$HOME/.config/globalstationsearch/config}"
    
    if [[ -f "$config_file" ]]; then
        # Source configuration file
        # shellcheck source=/dev/null
        source "$config_file" 2>/dev/null || {
            echo "Warning: Failed to load configuration from $config_file" >&2
            return 1
        }
    fi
    
    return 0
}

# Description: Update the Channels DVR server URL
# Arguments:
#   $1 - New server URL
# Returns: 0 - Success, 1 - Invalid URL format
cdvr_update_url() {
    local new_url="$1"
    
    # Validate URL format
    if [[ ! "$new_url" =~ ^https?:// ]]; then
        echo "Error: URL must start with http:// or https://" >&2
        return 1
    fi
    
    # Remove trailing slash if present
    new_url="${new_url%/}"
    
    # Update global variable
    CHANNELS_URL="$new_url"
    
    # Save to configuration
    cdvr_save_config
    
    echo "Channels DVR URL updated to: $CHANNELS_URL"
    return 0
}

# ============================================================================
# Connection Testing Functions
# ============================================================================

# Description: Test connection to Channels DVR server
# Arguments: None (uses global CHANNELS_URL)
# Returns: 0 - Success, 1 - Failure
cdvr_test_connection() {
    local timeout=5
    
    # Check if URL is configured
    if [[ -z "$CHANNELS_URL" ]]; then
        echo "Error: Channels DVR URL not configured" >&2
        echo "Please configure the server URL in Settings" >&2
        return 1
    fi
    
    # Test connection to the server (original implementation)
    if curl -s --connect-timeout "$timeout" "$CHANNELS_URL" >/dev/null 2>&1; then
        echo "Successfully connected to Channels DVR server"
        return 0
    else
        local curl_exit_code=$?
        echo "Error: Channels DVR connection failed to $CHANNELS_URL" >&2
        case $curl_exit_code in
            6)
                echo "Could not resolve hostname - check server IP address" >&2
                ;;
            7)
                echo "Connection refused - verify server is running and port is correct" >&2
                ;;
            28)
                echo "Connection timeout - server may be slow or unresponsive" >&2
                ;;
            *)
                echo "Network error (code: $curl_exit_code) - check connection and settings" >&2
                ;;
        esac
        return 1
    fi
}

# ============================================================================
# API Functions
# ============================================================================

# Description: Search for stations using Channels DVR API
# Arguments:
#   $1 - Search term (station name or call sign)
# Returns: 0 - Success (outputs JSON), 1 - Failure
cdvr_search_stations() {
    local search_term="$1"
    local timeout=10
    
    # Validate input
    if [[ -z "$search_term" ]]; then
        echo "Error: Search term is required" >&2
        return 1
    fi
    
    # Check if URL is configured
    if [[ -z "$CHANNELS_URL" ]]; then
        echo "Error: Channels DVR URL not configured" >&2
        return 1
    fi
    
    # URL encode the search term
    local encoded_search_term
    encoded_search_term=$(printf '%s' "$search_term" | jq -sRr @uri)
    
    # Make API request
    local api_url="$CHANNELS_URL/tms/stations/$encoded_search_term"
    local response
    local http_code
    
    response=$(curl -s -w "\n%{http_code}" --connect-timeout "$timeout" \
        -H "Accept: application/json" \
        "$api_url" 2>/dev/null)
    
    # Extract HTTP code (last line)
    http_code=$(echo "$response" | tail -n1)
    # Remove HTTP code from response
    response=$(echo "$response" | sed '$d')
    
    # Handle response
    case "$http_code" in
        200)
            # Validate JSON response
            if echo "$response" | jq empty 2>/dev/null; then
                echo "$response"
                return 0
            else
                echo "Error: Invalid JSON response from server" >&2
                return 1
            fi
            ;;
        000)
            echo "Error: Cannot connect to Channels DVR server" >&2
            return 1
            ;;
        404)
            echo "Error: API endpoint not found. Server may be outdated" >&2
            return 1
            ;;
        *)
            echo "Error: Server returned HTTP $http_code" >&2
            return 1
            ;;
    esac
}

# Description: Get Channels DVR server status
# Arguments: None (uses global CHANNELS_URL)
# Returns: 0 - Success (outputs JSON), 1 - Failure
cdvr_get_status() {
    local timeout=5
    
    # Check if URL is configured
    if [[ -z "$CHANNELS_URL" ]]; then
        return 1
    fi
    
    # Get server status (original implementation)
    local response
    response=$(curl -s --connect-timeout "$timeout" \
        "$CHANNELS_URL/api/status" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo "$response"
        return 0
    else
        return 1
    fi
}

# ============================================================================
# UI Interface Functions
# ============================================================================

# Description: Run the Direct API Search interface
# Arguments: None
# Returns: 0 - Normal exit, 1 - Error
cdvr_run_direct_api_search() {
    # Check if CDVR is configured before proceeding
    if ! check_integration_requirement "Channels DVR" "is_cdvr_configured" "configure_cdvr_connection" "Direct API Search"; then
        return 1
    fi
    
    clear
    
    # Use modular header display
    if declare -f display_status_block_header >/dev/null 2>&1; then
        display_status_block_header "Direct Channels DVR API Search"
    else
        echo -e "${BOLD}${BLUE}=== Direct Channels DVR API Search ===${RESET}"
    fi
    echo
    
    # Connection status check with styled output
    if declare -f log_info >/dev/null 2>&1; then
        log_info "cdvr" "Starting Direct API Search interface"
    fi
    
    echo -e "${CYAN}🔌 Testing connection to Channels DVR server...${RESET}"
    if ! cdvr_test_and_display_connection; then
        echo
        echo -e "${RED}❌ Connection failed${RESET}"
        echo -e "${CYAN}💡 Configure your Channels DVR server in Settings first${RESET}"
        echo
        read -p "Press Enter to return to menu..."
        return 1
    fi
    
    echo
    # Connection success with server info
    if declare -f display_status_line >/dev/null 2>&1; then
        display_status_line "🌐" "Connected to" "$CHANNELS_URL" "$SUCCESS_STYLE"
    else
        echo -e "${GREEN}🌐 Connected to: $CHANNELS_URL${RESET}"
    fi
    echo
    
    # Styled limitations box
    echo -e "${BOLD}${YELLOW}⚠️  Direct API Search Limitations${RESET}"
    echo -e "${YELLOW}────────────────────────────────────────────────────────────${RESET}"
    echo -e "${YELLOW}• A result limit is imposed by the API, so results may not be complete${RESET}"
    echo -e "${YELLOW}• No search filters (resolution, country)${RESET}"
    echo -e "${YELLOW}• Less comprehensive than Local Database Search${RESET}"
    echo -e "${YELLOW}────────────────────────────────────────────────────────────${RESET}"
    echo
    
    # Styled search instructions
    echo -e "${CYAN}🔍 Enter search terms (station name or call sign)${RESET}"
    echo -e "${CYAN}💡 Press ${BOLD}Enter${RESET}${CYAN} (blank) or type '${BOLD}q${RESET}${CYAN}' to return to menu${RESET}"
    echo
    
    while true; do
        echo -ne "${BOLD}${BLUE}Search${RESET}${BLUE}:${RESET} "
        read search_input
        
        # Check for quit or blank input (standard UX pattern)
        case "$search_input" in
            q|Q|"")
                if declare -f log_info >/dev/null 2>&1; then
                    log_info "cdvr" "Direct API Search interface closed by user"
                fi
                return 0
                ;;
            *)
                # Validate non-empty search term
                if [[ -n "$search_input" && ! "$search_input" =~ ^[[:space:]]*$ ]]; then
                    # Log search attempt
                    if declare -f log_user_action >/dev/null 2>&1; then
                        log_user_action "Direct API search" "query='$search_input'"
                    fi
                    
                    # Perform the search
                    _cdvr_perform_search "$search_input"
                else
                    echo -e "${RED}❌ Please enter a search term${RESET}"
                    echo -e "${CYAN}💡 Try station names like 'CNN' or call signs like 'WABC'${RESET}"
                fi
                ;;
        esac
    done
}

# Description: Test and display CDVR connection status
# Arguments: None
# Returns: 0 - Connected, 1 - Not connected
cdvr_test_and_display_connection() {
    if cdvr_test_connection; then
        echo -e "${GREEN}✅ Connection successful${RESET}"
        return 0
    else
        echo -e "${RED}❌ Connection failed${RESET}"
        return 1
    fi
}

# Description: Configure Channels DVR server settings
# Arguments: None
# Returns: 0 - Success
cdvr_configure_server() {
    clear
    echo "=== Channels DVR Server Settings ==="
    echo
    echo "Current server URL: ${CHANNELS_URL:-Not configured}"
    echo
    echo "Enter the URL of your Channels DVR server"
    echo "Example: http://192.168.1.100:8089"
    echo
    read -p "Server URL (or press Enter to cancel): " new_url
    
    if [[ -n "$new_url" ]]; then
        if cdvr_update_url "$new_url"; then
            echo "Settings saved successfully!"
        else
            echo "Failed to save settings"
        fi
    fi
    
    read -p "Press Enter to continue..."
}

# ============================================================================
# Private Helper Functions
# ============================================================================

# Description: Perform a search and display results
# Arguments:
#   $1 - Search term
# Returns: 0 - Success, 1 - Failure
_cdvr_perform_search() {
    local search_term="$1"
    
    echo
    echo -e "${CYAN}🔍 Searching for: ${BOLD}$search_term${RESET}"
    echo -e "${CYAN}⏳ Please wait...${RESET}"
    
    # Log the search operation
    if declare -f log_api_operation >/dev/null 2>&1; then
        log_api_operation "SEARCH" "/tms/stations/$search_term" "pending"
    fi
    
    # Call the API
    local json_response
    json_response=$(cdvr_search_stations "$search_term")
    local api_result=$?
    
    if [[ $api_result -ne 0 ]]; then
        echo -e "${RED}❌ Search failed. Please try again.${RESET}"
        echo
        if declare -f log_error >/dev/null 2>&1; then
            log_error "cdvr" "API search failed for term: $search_term"
        fi
        return 1
    fi
    
    # Log successful API call
    if declare -f log_api_operation >/dev/null 2>&1; then
        log_api_operation "SEARCH" "/tms/stations/$search_term" "200"
    fi
    
    # Check if response is empty array
    if [[ "$json_response" == "[]" ]]; then
        echo -e "${YELLOW}⚠️  No stations found matching '${BOLD}$search_term${RESET}${YELLOW}'${RESET}"
        echo -e "${CYAN}💡 Try different spelling, call signs, or partial names${RESET}"
        echo
        return 0
    fi
    
    # Convert JSON to TSV format (original format)
    echo "$json_response" | jq -r '
        .[] | [
            .name // "Unknown", 
            .callSign // "N/A", 
            .videoQuality.videoType // "Unknown", 
            .stationId // "Unknown",
            "API-Direct"
        ] | @tsv
    ' > "$API_SEARCH_RESULTS" 2>/dev/null
    
    # Display results
    _cdvr_display_results "$search_term"
}

# Description: Display search results (original implementation)
# Arguments:
#   $1 - Search term
# Returns: 0 - Success
_cdvr_display_results() {
    local search_term="$1"
    
    mapfile -t RESULTS < "$API_SEARCH_RESULTS"
    local count=${#RESULTS[@]}
    
    clear
    
    # Use modular header display
    if declare -f display_status_block_header >/dev/null 2>&1; then
        display_status_block_header "Direct Channels DVR API Search Results"
    else
        echo -e "${BOLD}${BLUE}=== Direct Channels DVR API Search Results ===${RESET}"
    fi
    echo
    
    # Search summary with styled output
    if declare -f display_status_line >/dev/null 2>&1; then
        display_status_line "🔍" "Search Term" "'$search_term'" "$INFO_STYLE"
        display_status_line "🌐" "Server" "$CHANNELS_URL" "$INFO_STYLE"
        display_status_line "✅" "API Status" "Search completed successfully" "$SUCCESS_STYLE"
    else
        echo -e "${CYAN}🔍 Search Term: ${BOLD}'$search_term'${RESET}"
        echo -e "${CYAN}🌐 Server: $CHANNELS_URL${RESET}"
        echo -e "${GREEN}✅ API Status: Search completed successfully${RESET}"
    fi
    echo
    
    if [[ $count -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No results found for '${BOLD}$search_term${RESET}${YELLOW}' in API${RESET}"
        echo -e "${CYAN}💡 Try: Different spelling, call signs, or partial names${RESET}"
        echo -e "${CYAN}💡 Local Database Search may have more comprehensive results${RESET}"
    else
        # Results summary
        if declare -f display_status_line >/dev/null 2>&1; then
            display_status_line "📊" "Results Found" "$count result(s)" "$SUCCESS_STYLE"
        else
            echo -e "${GREEN}📊 Results Found: $count result(s)${RESET}"
        fi
        echo
        
        # Table header (matches local database search format)
        printf "%-30s %-10s %-8s %-12s\n" "Channel Name" "Call Sign" "Quality" "Station ID"
        echo "----------------------------------------------------------------"
        
        for ((i = 0; i < count; i++)); do
            IFS=$'\t' read -r NAME CALLSIGN RES STID SOURCE <<< "${RESULTS[$i]}"
            printf "%-30s %-10s %-8s %-12s\n" "$NAME" "$CALLSIGN" "$RES" "$STID"
            
            # Display logo if available
            if declare -f display_logo >/dev/null 2>&1; then
                display_logo "$STID"
            else
                echo "[logo display function not available]"
            fi
            echo
        done
        
        echo -e "${CYAN}💡 Tip: Local Database Search provides more comprehensive results and advanced filtering${RESET}"
    fi
    
    echo
    read -p "Press Enter to continue..."
}

# ============================================================================
# Legacy Compatibility Wrappers (Deprecated - will be removed in v4.0.0)
# ============================================================================

# Legacy wrapper - will be removed in v4.0.0
channels_dvr_test_connection() {
    cdvr_test_connection "$@"
}

# Legacy wrapper - will be removed in v4.0.0
channels_dvr_search_stations() {
    cdvr_search_stations "$@"
}

# Legacy wrapper - will be removed in v4.0.0
channels_dvr_get_status() {
    cdvr_get_status "$@"
}

# Legacy wrapper - will be removed in v4.0.0
save_channels_dvr_config() {
    cdvr_save_config "$@"
}

# Legacy wrapper - will be removed in v4.0.0
reload_channels_dvr_config() {
    cdvr_reload_config "$@"
}

# Legacy wrapper - will be removed in v4.0.0
update_channels_dvr_url() {
    cdvr_update_url "$@"
}

# Legacy wrapper - will be removed in v4.0.0
test_and_display_cdvr_connection() {
    cdvr_test_and_display_connection "$@"
}

# Legacy wrapper - will be removed in v4.0.0
run_direct_api_search() {
    cdvr_run_direct_api_search "$@"
}

# Legacy wrapper - will be removed in v4.0.0
perform_direct_api_search() {
    _cdvr_perform_search "$@"
}

# Legacy wrapper - will be removed in v4.0.0
display_direct_api_results() {
    _cdvr_display_results "$@"
}

# Legacy wrapper - will be removed in v4.0.0
change_server_settings() {
    cdvr_configure_server "$@"
}

# Initialize module when sourced
cdvr_init