#!/bin/bash

# ============================================================================
# EMBY INTEGRATION MODULE
# ============================================================================
# Description: Centralized Emby server integration for GlobalStationSearch
# Version: 1.0.0
# ============================================================================

# Prevent multiple inclusions
if [[ "${EMBY_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi

# Module identification
readonly EMBY_MODULE_LOADED="true"

# ============================================================================
# AUTHENTICATION STATE TRACKING
# ============================================================================

# Authentication state variables
EMBY_AUTH_STATE="unknown"          # unknown, authenticated, failed
EMBY_LAST_TOKEN_CHECK=0            # Timestamp of last token validation
if [[ -z "${EMBY_TOKEN_CHECK_INTERVAL:-}" ]]; then
    EMBY_TOKEN_CHECK_INTERVAL=30
fi

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

# Reload Emby configuration from file and update variables
emby_reload_config() {
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    if [[ -f "$config_file" ]]; then
        _emby_log "info" "Reloading Emby configuration from $config_file"
        
        # Source the config file to update variables
        source "$config_file" 2>/dev/null
        
        # Clear any existing authentication state since config changed
        EMBY_AUTH_STATE="unknown"
        EMBY_LAST_TOKEN_CHECK=0
        
        _emby_log "debug" "Configuration reloaded - EMBY_ENABLED=${EMBY_ENABLED:-false}, EMBY_URL=${EMBY_URL:-unset}"
        return 0
    else
        _emby_log "error" "Configuration file not found: $config_file"
        return 1
    fi
}

# Invalidate authentication state with reason
emby_invalidate_auth_state() {
    local reason="${1:-Configuration change}"
    
    _emby_log "info" "Invalidating authentication state: $reason"
    
    # Clear authentication state
    EMBY_AUTH_STATE="unknown"
    EMBY_LAST_TOKEN_CHECK=0
    EMBY_API_KEY=""
    EMBY_USER_ID=""
    
    _emby_log "debug" "Authentication state cleared"
}

# Save Emby configuration setting and refresh auth state
emby_save_config() {
    local config_key="$1"
    local config_value="$2"
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    # Validate required parameters
    if [[ -z "$config_key" ]]; then
        _emby_log "error" "emby_save_config: config_key required"
        return 1
    fi
    
    _emby_log "info" "Saving Emby configuration: $config_key"
    
    # Use the main script's save_setting function if available
    if declare -f save_setting >/dev/null 2>&1; then
        save_setting "$config_key" "$config_value"
    else
        # Fallback: direct file manipulation
        if [[ -f "$config_file" ]]; then
            # Remove existing line and add new one
            sed -i.bak "/^$config_key=/d" "$config_file"
            echo "$config_key=\"$config_value\"" >> "$config_file"
        else
            _emby_log "error" "Config file not found: $config_file"
            return 1
        fi
    fi
    
    # Reload configuration
    emby_reload_config
    
    # Invalidate auth state since config changed
    emby_invalidate_auth_state "Configuration changed: $config_key"
    
    return 0
}

# Get current authentication status with detailed information
emby_get_auth_status() {
    _emby_log "debug" "Getting Emby authentication status"
    
    # Check basic configuration
    if [[ -z "${EMBY_URL:-}" ]] || [[ "$EMBY_ENABLED" != "true" ]]; then
        echo "disabled"
        return 1
    fi
    
    # Check authentication state
    case "${EMBY_AUTH_STATE:-unknown}" in
        "authenticated")
            # Check if token is still fresh
            local now=$(date +%s)
            if (( now - EMBY_LAST_TOKEN_CHECK <= EMBY_TOKEN_CHECK_INTERVAL )); then
                echo "authenticated"
                return 0
            else
                echo "expired"
                return 1
            fi
            ;;
        "failed")
            echo "failed"
            return 1
            ;;
        *)
            echo "unknown"
            return 1
            ;;
    esac
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# Module-specific logging function
_emby_log() {
    local level="$1"
    local message="$2"
    
    # Use centralized logging system if available
    if declare -f log_${level} >/dev/null 2>&1; then
        log_${level} "emby" "$message"
    else
        # Fallback for cases where logging system isn't loaded yet
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [$level] [EMBY] $message" >&2
    fi
}

# ============================================================================
# JIT AUTHENTICATION SYSTEM
# ============================================================================

# Check if current Emby authentication is valid
emby_is_authenticated() {
    if [[ -z "${EMBY_URL:-}" ]] || [[ "$EMBY_ENABLED" != "true" ]]; then
        return 1
    fi
    
    if [[ -z "${EMBY_API_KEY:-}" ]]; then
        return 1
    fi
    
    local now=$(date +%s)
    
    # Check if we need to revalidate (30 second cache)
    if (( now - EMBY_LAST_TOKEN_CHECK > EMBY_TOKEN_CHECK_INTERVAL )); then
        _emby_log "debug" "Token cache expired, validating authentication"
        
        # Test current API key with a simple endpoint
        local test_response
        test_response=$(curl -s \
            --connect-timeout 5 \
            -H "X-Emby-Token: $EMBY_API_KEY" \
            "${EMBY_URL}/emby/System/Info" 2>/dev/null)
        
        if echo "$test_response" | jq empty 2>/dev/null; then
            _emby_log "debug" "Authentication validated successfully"
            EMBY_AUTH_STATE="authenticated"
            EMBY_LAST_TOKEN_CHECK=$now
            return 0
        else
            _emby_log "warn" "Current API key is invalid or expired"
            EMBY_AUTH_STATE="failed"
            return 1
        fi
    else
        # Recent check was successful
        return 0
    fi
}

# Ensure we have valid Emby authentication
emby_ensure_valid_token() {
    # First check current state
    if emby_is_authenticated; then
        return 0
    fi
    
    _emby_log "info" "Authentication needed, checking configuration"
    
    # Check basic requirements
    if [[ -z "${EMBY_URL:-}" ]] || [[ "$EMBY_ENABLED" != "true" ]]; then
        _emby_log "error" "Emby not configured or disabled"
        return 1
    fi
    
    if [[ -z "${EMBY_USERNAME:-}" ]] || [[ -z "${EMBY_PASSWORD:-}" ]]; then
        _emby_log "error" "Missing Emby credentials"
        return 1
    fi
    
    # Try authentication
    _emby_log "info" "Attempting authentication with Emby server"
    if emby_authenticate; then
        return 0
    fi
    
    # Authentication failed
    _emby_log "error" "Authentication failed"
    EMBY_AUTH_STATE="failed"
    return 1
}

# Core authentication function
emby_authenticate() {
    _emby_log "info" "Authenticating with Emby server..."
    
    # Emby authentication endpoint  
    local auth_response
    auth_response=$(curl -s \
        --connect-timeout ${STANDARD_TIMEOUT:-10} \
        --max-time ${MAX_OPERATION_TIME:-20} \
        -H "Content-Type: application/json" \
        -H "X-Emby-Authorization: MediaBrowser Client=\"GlobalStationSearch\", Device=\"Script\", DeviceId=\"gss-$(hostname)\", Version=\"1.0\"" \
        -d "{\"Username\":\"$EMBY_USERNAME\",\"Pw\":\"$EMBY_PASSWORD\"}" \
        "${EMBY_URL}/emby/Users/AuthenticateByName" 2>&1)
    
    local curl_exit_code=$?
    
    # Handle network errors
    if [[ $curl_exit_code -ne 0 ]]; then
        _emby_log "error" "Network error during authentication (curl exit: $curl_exit_code)"
        EMBY_AUTH_STATE="failed"
        return 1
    fi
    
    # Validate JSON response and extract access token
    if echo "$auth_response" | jq empty 2>/dev/null; then
        local access_token=$(echo "$auth_response" | jq -r '.AccessToken // empty' 2>/dev/null)
        local user_id=$(echo "$auth_response" | jq -r '.User.Id // empty' 2>/dev/null)
        
        if [[ -n "$access_token" && -n "$user_id" ]]; then
            _emby_log "info" "Authentication successful"
            
            # Store the API key (access token) for future use
            EMBY_API_KEY="$access_token"
            EMBY_USER_ID="$user_id"
            
            # Save to config if save_config function exists
            if declare -f save_config >/dev/null 2>&1; then
                save_config "EMBY_API_KEY" "$access_token"
                save_config "EMBY_USER_ID" "$user_id"
            fi
            
            EMBY_AUTH_STATE="authenticated"
            EMBY_LAST_TOKEN_CHECK=$(date +%s)
            return 0
        else
            _emby_log "error" "Invalid authentication response - missing token or user ID"
            EMBY_AUTH_STATE="failed"
            return 1
        fi
    else
        _emby_log "error" "Invalid authentication response - not valid JSON"
        EMBY_AUTH_STATE="failed"
        return 1
    fi
}

# ============================================================================
# API WRAPPER
# ============================================================================

# Central API wrapper with authentication and error handling
emby_api_wrapper() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    # Ensure we have valid authentication
    if ! emby_ensure_valid_token; then
        _emby_log "error" "API call failed - authentication required"
        return 1
    fi
    
    _emby_log "debug" "API call: $method $endpoint"
    
    # Build curl command
    local curl_cmd=(
        curl -s
        --connect-timeout 15
        --max-time 30
        -H "X-Emby-Token: $EMBY_API_KEY"
        -X "$method"
    )
    
    # Add content type for POST/PUT
    if [[ "$method" == "POST" || "$method" == "PUT" ]]; then
        curl_cmd+=(-H "Content-Type: application/json")
    fi
    
    # Add data if provided
    if [[ -n "$data" ]]; then
        curl_cmd+=(-d "$data")
    fi
    
    # Add URL
    curl_cmd+=("${EMBY_URL}${endpoint}")
    
    # Execute API call
    local response
    response=$("${curl_cmd[@]}" 2>/dev/null)
    local curl_exit_code=$?
    
    # Handle network errors
    if [[ $curl_exit_code -ne 0 ]]; then
        _emby_log "error" "Network error during API call (curl exit: $curl_exit_code)"
        return 1
    fi
    
    # Check if response is valid JSON (for endpoints that return JSON)
    if [[ "$endpoint" != */ping ]] && ! echo "$response" | jq empty 2>/dev/null; then
        _emby_log "error" "Invalid JSON response from API"
        return 1
    fi
    
    _emby_log "debug" "API call successful"
    echo "$response"
    return 0
}

# ============================================================================
# API FUNCTIONS
# ============================================================================

# Test Emby connection and authentication
emby_test_connection() {
    _emby_log "info" "Testing Emby connection and authentication"
    
    if [[ -z "${EMBY_URL:-}" ]] || [[ "$EMBY_ENABLED" != "true" ]]; then
        echo -e "${RED}❌ Emby: Not configured or disabled${RESET}" >&2
        echo -e "${CYAN}💡 Configure in Settings → Emby Integration${RESET}" >&2
        _emby_log "error" "Emby not configured or disabled"
        return 1
    fi
    
    if ! emby_ensure_valid_token; then
        echo -e "${RED}❌ Emby: Authentication failed${RESET}" >&2
        echo -e "${CYAN}💡 Check server URL, username, and password${RESET}" >&2
        _emby_log "error" "Authentication failed during connection test"
        return 1
    fi
    
    # Test API call using our wrapper
    local server_info
    server_info=$(emby_api_wrapper "GET" "/emby/System/Info")
    
    if [[ $? -eq 0 ]] && [[ -n "$server_info" ]]; then
        local server_name=$(echo "$server_info" | jq -r '.ServerName // "Unknown"' 2>/dev/null)
        local version=$(echo "$server_info" | jq -r '.Version // "Unknown"' 2>/dev/null)
        
        echo -e "${GREEN}✅ Emby: Connected to '$server_name' (v$version)${RESET}" >&2
        _emby_log "info" "Connection test successful, server: $server_name v$version"
        return 0
    else
        echo -e "${RED}❌ Emby: Connection test failed${RESET}" >&2
        _emby_log "error" "Connection test failed - API call unsuccessful"
        return 1
    fi
}

# Get Emby server information
emby_get_server_info() {
    _emby_log "debug" "Getting Emby server information"
    
    local response
    response=$(emby_api_wrapper "GET" "/emby/System/Info")
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        _emby_log "debug" "Server info retrieved successfully"
        echo "$response"
        return 0
    else
        _emby_log "error" "Failed to get server information"
        return 1
    fi
}

# Get Emby Live TV channels
emby_get_livetv_channels() {
    _emby_log "debug" "Fetching ALL Emby Live TV channels"
    
    local response
    response=$(emby_api_wrapper "GET" "/emby/LiveTv/Manage/Channels?Fields=ManagementId,ListingsId,Name,ChannelNumber,Id")
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        # Handle both array and object responses
        local channels
        if echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
            # Direct array
            channels="$response"
        elif echo "$response" | jq -e '.Items' >/dev/null 2>&1; then
            # Object with Items property
            channels=$(echo "$response" | jq '.Items')
        else
            _emby_log "error" "Unexpected response structure"
            return 1
        fi
        
        local channel_count=$(echo "$channels" | jq 'length' 2>/dev/null || echo "0")
        _emby_log "info" "Retrieved $channel_count Live TV channels"
        
        if [[ "$channel_count" -eq 0 ]]; then
            _emby_log "warn" "No channels found"
            return 1
        fi
        
        echo "$channels"
        return 0
    else
        _emby_log "error" "Failed to get channel data"
        return 1
    fi
}

# Find channels missing Listings ID and extract Station ID
emby_find_channels_missing_listingsid() {
    _emby_log "info" "Scanning Emby channels for missing ListingsId"
    
    local channels_data
    channels_data=$(emby_get_livetv_channels)
    
    if [[ $? -ne 0 ]] || [[ -z "$channels_data" ]]; then
        _emby_log "error" "Failed to get channel data"
        return 1
    fi
    
    _emby_log "debug" "Processing channels to find missing ListingsId"
    
    # Filter channels missing ListingsId first
    local missing_channels_raw
    missing_channels_raw=$(echo "$channels_data" | jq -c '.[] | select(.ListingsId == null or .ListingsId == "" or .ListingsId == "null")')
    
    if [[ -z "$missing_channels_raw" ]]; then
        _emby_log "info" "All channels have ListingsId assigned"
        echo "[]"
        return 0
    fi
    
    # Count total channels to process
    local missing_channels_array=()
    while IFS= read -r channel_line; do
        if [[ -n "$channel_line" ]]; then
            missing_channels_array+=("$channel_line")
        fi
    done <<< "$missing_channels_raw"
    
    local total_missing=${#missing_channels_array[@]}
    _emby_log "info" "Processing $total_missing channels missing ListingsId"
    
    # Process each channel with progress indicator
    local processed_count=0
    local successful_extractions=0
    local processed_channels=()
    
    for channel_line in "${missing_channels_array[@]}"; do
        ((processed_count++))
        
        # Extract station ID from ManagementId
        local management_id=$(echo "$channel_line" | jq -r '.ManagementId // empty')
        local channel_name=$(echo "$channel_line" | jq -r '.Name // "Unknown"')
        local extracted_id=""

        # Add this debug RIGHT AFTER the jq extraction, BEFORE the validation
        local management_id=$(echo "$channel_line" | jq -r '.ManagementId // empty')
        local channel_name=$(echo "$channel_line" | jq -r '.Name // "Unknown"')

        local extracted_id=""
        
        if [[ -n "$management_id" && "$management_id" != "null" ]]; then
        # Extract everything after the last underscore
        extracted_id="${management_id##*_}"
        
        # Validate it's a reasonable station ID (numeric, reasonable length)
        if [[ "$extracted_id" =~ ^[0-9]+$ ]] && [[ ${#extracted_id} -ge 4 ]] && [[ ${#extracted_id} -le 10 ]]; then
            # Add ExtractedId to the channel object
            local enhanced_channel
            enhanced_channel=$(echo "$channel_line" | jq --arg extracted_id "$extracted_id" '. + {ExtractedId: $extracted_id}')
            processed_channels+=("$enhanced_channel")
            ((successful_extractions++))
            _emby_log "debug" "Extracted station ID $extracted_id from channel: $channel_name"
        else
            _emby_log "debug" "Could not extract valid station ID from ManagementId: $management_id"
        fi
    fi
        
        # Small delay for visual progress (keeping original behavior)
        sleep 0.005
    done
    
    _emby_log "info" "Station ID extraction completed: $successful_extractions of $total_missing successful"
    
    if [[ "$successful_extractions" -eq 0 ]]; then
        _emby_log "warn" "No valid station IDs could be extracted"
        echo "[]"
        return 0
    fi
    
    # Return processed channels as individual JSON objects (maintain existing format)
    printf '%s\n' "${processed_channels[@]}"
    return 0
}

# ============================================================================
# COMPATIBILITY WRAPPERS
# ============================================================================

# Still used by UI - will be removed when UI is updated
get_emby_auth_status() {
    emby_get_auth_status "$@"
}

# ============================================================================
# REVERSE LOOKUP AND LISTING FUNCTIONS
# ============================================================================

# Reverse lookup station IDs in local database
emby_reverse_lookup_station_ids() {
    local station_ids_array=("$@")
    local total_ids=${#station_ids_array[@]}
    
    # Check if we have a station database
    if ! has_stations_database; then
        echo -e "${RED}❌ No station database available for reverse lookup${RESET}" >&2
        echo -e "${CYAN}💡 Build database via 'Manage Television Markets' → 'User Database Expansion'${RESET}" >&2
        return 1
    fi
    
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Failed to access station database${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}💡 Searching your local station database for matching stations...${RESET}" >&2
    echo >&2
    
    # Create result array for lookup results
    local lookup_results=()
    local found_count=0
    local not_found_count=0
    local processed_count=0
    
    for station_id in "${station_ids_array[@]}"; do
        ((processed_count++))
        
        # Show CLEAN progress indicator
        echo -ne "\r${CYAN}🔍 Looking up station ID ${BOLD}$processed_count${RESET}${CYAN} of ${BOLD}$total_ids${RESET}${CYAN} (${BOLD}$found_count${RESET}${CYAN} found)...${RESET}" >&2
        
        # Query using the CORRECT structure for your database
        local station_data
        station_data=$(jq -r --arg id "$station_id" '
            .[] | select(.stationId == $id) |
            if .lineupTracing and (.lineupTracing | length > 0) then
                {
                    stationId: .stationId,
                    lineupId: .lineupTracing[0].lineupId,
                    country: .lineupTracing[0].country,
                    lineupName: .lineupTracing[0].lineupName
                }
            else
                empty
            end
        ' "$stations_file" 2>/dev/null)
        
        if [[ -n "$station_data" && "$station_data" != "null" && "$station_data" != "{}" ]]; then
            lookup_results+=("$station_data")
            ((found_count++))
        else
            ((not_found_count++))
        fi
    done
    
    # Clear progress line and show results
    echo -e "\r${GREEN}✅ Lookup completed: ${BOLD}$found_count${RESET}${GREEN} found, ${BOLD}$not_found_count${RESET}${GREEN} not found                    ${RESET}" >&2
    echo >&2
    
    if [[ "$found_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No station matches found in your database${RESET}" >&2
        return 1
    fi
    
    # Output results as JSON array
    printf '%s\n' "${lookup_results[@]}" | jq -s '.' 2>/dev/null
    return 0
}

# Add listing provider to Emby
emby_add_listing_provider() {
    local listings_id="$1"
    local country="$2"
    local lineup_name="$3"
    local type="${4:-embygn}"
    
    if [[ -z "$listings_id" || -z "$country" ]]; then
        return 1
    fi
    
    if ! emby_ensure_valid_token; then
        return 1
    fi
    
    # Prepare JSON payload for listing provider
    local provider_payload
    provider_payload=$(jq -n \
        --arg listings_id "$listings_id" \
        --arg type "$type" \
        --arg country "$country" \
        --arg name "${lineup_name:-$listings_id}" \
        '{
            ListingsId: $listings_id,
            Type: $type,
            Country: $country,
            Name: $name
        }')
    
    _emby_log "debug" "Adding listing provider - Payload: $provider_payload"
    
    # Add to Emby listing providers (silent operation for progress display)
    local response
    response=$(curl -s \
        --connect-timeout ${API_STANDARD_TIMEOUT:-10} \
        --max-time $((${API_STANDARD_TIMEOUT:-10} * 2)) \
        -w "HTTPSTATUS:%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-Emby-Token: $EMBY_API_KEY" \
        -d "$provider_payload" \
        "${EMBY_URL}/emby/LiveTv/ListingProviders" 2>/dev/null)
    
    local curl_exit_code=$?
    local http_status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$response" | sed 's/HTTPSTATUS:[0-9]*//')
    
    # Log debug information
    _emby_log "debug" "Add listing provider response - Status: $http_status, Curl exit: $curl_exit_code"
    if [[ -n "$response_body" ]] && [[ "$response_body" != "{}" ]]; then
        _emby_log "debug" "Response body: $response_body"
    fi
    
    # Handle results (return codes only, progress display handles messaging)
    if [[ $curl_exit_code -ne 0 ]]; then
        _emby_log "error" "Curl command failed with exit code: $curl_exit_code"
        return 1
    fi
    
    # Check if we got an HTTP status
    if [[ -z "$http_status" ]]; then
        _emby_log "error" "No HTTP status received - possible connection or timeout issue"
        return 1
    fi
    
    case "$http_status" in
        200|201|204)
            return 0
            ;;
        409)  # Already exists
            _emby_log "debug" "Listing provider already exists: $listings_id"
            return 0
            ;;
        401)
            _emby_log "error" "Authentication failed - invalid token"
            return 1
            ;;
        404)
            _emby_log "error" "API endpoint not found - check Emby version"
            return 1
            ;;
        *)
            _emby_log "error" "Failed with HTTP status: $http_status"
            return 1
            ;;
    esac
}

# Process missing listings and add providers to Emby
process_emby_missing_listings() {
    local lookup_results="$1"
    local channel_mapping=("${@:2}")
    
    # Extract unique listing providers from lookup results
    local unique_providers
    unique_providers=$(echo "$lookup_results" | jq -r '.[] | "\(.lineupId)|\(.country)|\(.lineupName)"' | sort -u)
    
    local provider_count=$(echo "$unique_providers" | wc -l)
    
    # Add each unique listing provider
    echo -e "\n${CYAN}📡 Processing listing providers...${RESET}"
    
    local added_count=0
    local failed_count=0
    local already_exists_count=0
    local provider_details=()
    
    while IFS='|' read -r lineup_id country lineup_name; do
        echo -e "${CYAN}  📡 Adding provider: ${BOLD}$lineup_id${RESET}${CYAN} ($lineup_name)${RESET}"
        
        # Call the function and capture its return status immediately
        emby_add_listing_provider "$lineup_id" "$country" "$lineup_name" "embygn"
        local add_result=$?
        
        if [[ $add_result -eq 0 ]]; then
            ((added_count++))
            echo -e "${GREEN}     ✅ Successfully added${RESET}"
            provider_details+=("$lineup_id ($country): $lineup_name")
        else
            ((failed_count++))
            echo -e "${RED}     ❌ Failed to add${RESET}"
        fi
        echo
    done <<< "$unique_providers"
    
    # Final summary
    echo -e "${BOLD}${BLUE}=== Listing Provider Addition Complete ===${RESET}"
    echo
    
    if [[ $added_count -gt 0 ]]; then
        echo -e "${GREEN}🎉 SUCCESS: ${BOLD}$added_count listing providers${RESET}${GREEN} added!${RESET}"
        echo
        echo -e "${BOLD}${GREEN}Providers Added:${RESET}"
        for detail in "${provider_details[@]}"; do
            echo -e "${GREEN}  ✅ $detail${RESET}"
        done
        echo
    fi
    
    if [[ $already_exists_count -gt 0 ]]; then
        echo -e "${CYAN}ℹ️  ${BOLD}$already_exists_count providers${RESET}${CYAN} already existed${RESET}"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  ${BOLD}$failed_count providers${RESET}${YELLOW} failed to add${RESET}"
    fi
    
    echo
    echo -e "${CYAN}📊 Final Summary:${RESET}"
    echo -e "${GREEN}  • Listing providers added: $added_count${RESET}"
    echo -e "${CYAN}  • Already existed: $already_exists_count${RESET}"
    echo -e "${YELLOW}  • Failed: $failed_count${RESET}"
    
    if [[ $added_count -gt 0 ]]; then
        echo
        echo -e "${BOLD}${GREEN}🎯 Emby Listing Provider Addition Complete!${RESET}"
        echo -e "${CYAN}Emby will now automatically map your channels to the new listing providers.${RESET}"
        echo -e "${CYAN}💡 Check your Emby Live TV settings to see the automatic channel mapping.${RESET}"
        echo -e "${CYAN}💡 It may take a few minutes for Emby to process the new listings.${RESET}"
    fi
    
    return 0
}

# Delete all channel logos from Emby
emby_delete_all_logos() {
    echo -e "${BOLD}${BLUE}=== Emby Channel Logo Deletion ===${RESET}"
    echo
    
    # Ensure authentication
    if ! emby_ensure_valid_token; then
        echo -e "${RED}❌ Authentication failed${RESET}"
        return 1
    fi
    
    # Get all channels
    echo -e "${CYAN}🔄 Retrieving channel list...${RESET}"
    local channels_response=$(emby_api_wrapper "GET" "/LiveTv/Channels" "" "{}")
    
    if [[ -z "$channels_response" ]]; then
        echo -e "${RED}❌ Failed to retrieve channels${RESET}"
        return 1
    fi
    
    # Parse channel IDs and names
    local channel_data=$(echo "$channels_response" | jq -r '.Items[]? | "\(.Id)|\(.Name)"' 2>/dev/null)
    
    if [[ -z "$channel_data" ]]; then
        echo -e "${YELLOW}⚠️  No channels found${RESET}"
        return 0
    fi
    
    local total_channels=$(echo "$channel_data" | wc -l)
    echo -e "${GREEN}✅ Found $total_channels channels${RESET}"
    echo
    
    # Delete logos for each channel
    local deleted_count=0
    local failed_count=0
    
    while IFS='|' read -r channel_id channel_name; do
        [[ -z "$channel_id" ]] && continue
        
        echo -e "${CYAN}🗑️  Deleting logos for: $channel_name${RESET}"
        
        local logo_types=("Primary" "LogoLight" "LogoLightColor")
        local channel_success=true
        
        for logo_type in "${logo_types[@]}"; do
            echo -ne "   - $logo_type..."
            
            # Delete each logo type
            local delete_response=$(emby_api_wrapper "DELETE" "/Items/$channel_id/Images/$logo_type" "" "{}")
            
            if [[ $? -eq 0 ]]; then
                echo -e " ${GREEN}✓${RESET}"
            else
                # Some channels may not have all logo types, which is okay
                echo -e " ${YELLOW}−${RESET}"
                channel_success=false
            fi
        done
        
        if [[ "$channel_success" == "true" ]]; then
            ((deleted_count++))
        else
            ((failed_count++))
        fi
    done <<< "$channel_data"
    
    echo
    echo -e "${BOLD}${BLUE}=== Logo Deletion Complete ===${RESET}"
    echo -e "${GREEN}✅ Channels processed successfully: $deleted_count${RESET}"
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Channels with partial deletions: $failed_count${RESET}"
    fi
    echo
    echo -e "${CYAN}💡 Deleted logo types: Primary, LogoLight, LogoLightColor${RESET}"
    echo -e "${CYAN}💡 Emby will redownload logos when channels are accessed${RESET}"
    
    return 0
}

# Clear all channel numbers from all Live TV channels
emby_clear_all_channel_numbers() {
    echo -e "${BOLD}${BLUE}=== Emby Channel Number Clearing ===${RESET}"
    echo
    
    # Ensure authentication
    if ! emby_ensure_valid_token; then
        echo -e "${RED}❌ Authentication failed${RESET}"
        return 1
    fi
    
    # Get user ID for API calls
    local user_id="${EMBY_USER_ID}"
    if [[ -z "$user_id" ]]; then
        echo -e "${RED}❌ User ID not found. Please re-authenticate.${RESET}"
        return 1
    fi
    
    # Get all channels from management endpoint
    echo -e "${CYAN}🔄 Retrieving channel list...${RESET}"
    local channels_response=$(emby_api_wrapper "GET" "/LiveTv/Manage/Channels" "" "{}")
    
    if [[ -z "$channels_response" ]]; then
        echo -e "${RED}❌ Failed to retrieve channels${RESET}"
        return 1
    fi
    
    # Parse channel IDs and current channel numbers
    local channel_data=$(echo "$channels_response" | jq -r '.Items[]? | "\(.Id)|\(.Name)|\(.ChannelNumber // "")"' 2>/dev/null)
    
    if [[ -z "$channel_data" ]]; then
        echo -e "${YELLOW}⚠️  No channels found${RESET}"
        return 0
    fi
    
    local total_channels=$(echo "$channel_data" | wc -l)
    local channels_with_numbers=$(echo "$channel_data" | grep -E '\|[^|]+$' | grep -v '\|$' | wc -l)
    
    echo -e "${GREEN}✅ Found $total_channels channels${RESET}"
    echo -e "${CYAN}📊 Channels with numbers: $channels_with_numbers${RESET}"
    echo
    
    if [[ $channels_with_numbers -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No channels have channel numbers to clear${RESET}"
        return 0
    fi
    
    # Process each channel
    local processed_count=0
    local cleared_count=0
    local failed_count=0
    
    echo -e "${CYAN}🔄 Processing channels...${RESET}"
    echo
    
    while IFS='|' read -r channel_id channel_name channel_number; do
        [[ -z "$channel_id" ]] && continue
        
        ((processed_count++))
        
        # Show progress
        echo -ne "${CYAN}[$processed_count/$total_channels] Processing: ${channel_name:0:40}...${RESET}"
        
        # Skip if no channel number
        if [[ -z "$channel_number" ]]; then
            echo -e " ${YELLOW}skipped (no number)${RESET}"
            continue
        fi
        
        # Get complete channel data
        local channel_full_data=$(emby_api_wrapper "GET" "/Users/$user_id/Items/$channel_id" "" "{}")
        
        if [[ -z "$channel_full_data" ]] || ! echo "$channel_full_data" | jq -e '.Id' >/dev/null 2>&1; then
            echo -e " ${RED}failed to get data${RESET}"
            ((failed_count++))
            continue
        fi
        
        # Modify the data to clear channel numbers
        local modified_data=$(echo "$channel_full_data" | jq '. + {"Number": "", "ChannelNumber": ""}')
        
        # Build query parameters matching web UI
        local query_params="X-Emby-Client=Emby+Web"
        query_params="${query_params}&X-Emby-Device-Name=GlobalStationSearch"
        query_params="${query_params}&X-Emby-Device-Id=globalstationsearch"
        query_params="${query_params}&X-Emby-Client-Version=4.8.11.0"
        query_params="${query_params}&X-Emby-Token=${EMBY_API_KEY}"
        query_params="${query_params}&X-Emby-Language=en-us"
        query_params="${query_params}&reqformat=json"
        
        # POST the modified data back
        local update_response=$(curl -s -X POST \
            "${EMBY_URL}/emby/Items/${channel_id}?${query_params}" \
            -H "Content-Type: application/json" \
            -d "$modified_data")
        
        if [[ $? -eq 0 ]]; then
            echo -e " ${GREEN}✓ cleared${RESET}"
            ((cleared_count++))
        else
            echo -e " ${RED}✗ failed${RESET}"
            ((failed_count++))
        fi
        
        # Small delay to avoid overwhelming the server
        sleep 0.2
    done <<< "$channel_data"
    
    echo
    echo -e "${BOLD}${BLUE}=== Channel Number Clearing Complete ===${RESET}"
    echo -e "${GREEN}✅ Channels cleared: $cleared_count${RESET}"
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${RED}❌ Failed: $failed_count${RESET}"
    fi
    echo -e "${CYAN}📊 Total processed: $processed_count${RESET}"
    echo
    
    # Verify results
    echo -e "${CYAN}🔍 Verifying results...${RESET}"
    local verify_response=$(emby_api_wrapper "GET" "/LiveTv/Manage/Channels" "" "{}")
    local remaining_with_numbers=$(echo "$verify_response" | jq -r '.Items[]? | select(.ChannelNumber != null and .ChannelNumber != "") | .Id' 2>/dev/null | wc -l)
    
    if [[ $remaining_with_numbers -eq 0 ]]; then
        echo -e "${GREEN}✅ SUCCESS: All channel numbers have been cleared!${RESET}"
    else
        echo -e "${YELLOW}⚠️  Warning: $remaining_with_numbers channels still have channel numbers${RESET}"
    fi
    
    return 0
}