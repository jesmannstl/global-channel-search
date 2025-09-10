#!/bin/bash

# ============================================================================
# DISPATCHARR INTEGRATION MODULE
# ============================================================================
# Consolidated Dispatcharr functionality with enhanced just-in-time auth
# All Dispatcharr operations should eventually use this module
# Created: 2025-06-07
# Version: 1.0.0

# ============================================================================
# MODULE CONFIGURATION
# ============================================================================

# Token freshness threshold (seconds) - check token if older than this
DISPATCHARR_TOKEN_FRESHNESS_THRESHOLD=30

# Module state tracking
DISPATCHARR_MODULE_INITIALIZED=false
DISPATCHARR_LAST_TOKEN_VALIDATION=0

# ============================================================================
# TOKEN FILE PATH INITIALIZATION
# ============================================================================

# Ensure DISPATCHARR_TOKENS is set properly
_dispatcharr_init_token_path() {
    if [[ -z "${DISPATCHARR_TOKENS:-}" ]]; then
        # Use cache directory if available, otherwise fall back to /tmp
        local cache_dir="${CACHE_DIR:-/tmp}"
        export DISPATCHARR_TOKENS="$cache_dir/dispatcharr_tokens.json"
        
        # Ensure directory exists
        mkdir -p "$(dirname "$DISPATCHARR_TOKENS")" 2>/dev/null
    fi
}

# ============================================================================
# CORE TOKEN MANAGEMENT FUNCTIONS
# ============================================================================

# Check if current token is fresh enough to skip validation
_dispatcharr_token_needs_check() {
    local current_time=$(date +%s)
    local time_since_check=$((current_time - DISPATCHARR_LAST_TOKEN_VALIDATION))
    
    if [[ $time_since_check -gt $DISPATCHARR_TOKEN_FRESHNESS_THRESHOLD ]]; then
        return 0  # Yes, needs check
    else
        return 1  # No, still fresh
    fi
}

# Ensure we have a valid token with just-in-time verification
dispatcharr_ensure_valid_token() {
    # Quick return if token was recently validated
    if ! _dispatcharr_token_needs_check; then
        return 0
    fi
    
    # Update validation timestamp immediately to prevent race conditions
    DISPATCHARR_LAST_TOKEN_VALIDATION=$(date +%s)
    
    # Check if we have basic configuration
    if [[ -z "${DISPATCHARR_URL:-}" ]] || [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        return 1
    fi
    
    # Try token validation first (fastest)
    if _dispatcharr_validate_current_token; then
        return 0
    fi
    
    # If validation failed, try refresh (faster than full auth)
    if _dispatcharr_refresh_token; then
        return 0
    fi
    
    # Last resort: full authentication
    if _dispatcharr_full_authentication; then
        return 0
    fi
    
    # All methods failed
    return 1
}

# API wrapper that ensures authentication before every call
dispatcharr_api_wrapper() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local extra_headers="$4"
    
    # Input validation
    if [[ -z "$method" || -z "$endpoint" ]]; then
        _dispatcharr_log "error" "API wrapper called with missing method or endpoint"
        return 1
    fi
    
    # Ensure we have a valid token with detailed error reporting
    if ! dispatcharr_ensure_valid_token; then
        _dispatcharr_log "error" "Failed to obtain valid authentication token"
        return 1
    fi
    
    # Get current access token
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    if [[ -z "$access_token" ]]; then
        _dispatcharr_log "error" "No access token available after authentication"
        return 1
    fi
    
    _dispatcharr_log "debug" "Making ${method} request to ${endpoint}"
    
    # Build and execute curl command with error checking
    local response
    local http_code
    
    response=$(curl -s -w "%{http_code}" \
        --connect-timeout "${API_TIMEOUT:-10}" \
        --max-time "${API_MAX_TIME:-30}" \
        -X "$method" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        ${extra_headers:+$extra_headers} \
        ${data:+-d "$data"} \
        "${DISPATCHARR_URL}${endpoint}")
    
    local curl_exit_code=$?
    
    # Extract HTTP status code (last 3 characters)
    http_code="${response: -3}"
    response="${response%???}"  # Remove status code from response
    
    # Handle curl errors
    if [[ $curl_exit_code -ne 0 ]]; then
        _dispatcharr_log "error" "Network error (curl exit code: $curl_exit_code) for ${method} ${endpoint}"
        return 1
    fi
    
    # Handle HTTP errors
    case "$http_code" in
        200|201|204)
            _dispatcharr_log "debug" "Successful ${method} request to ${endpoint} (HTTP $http_code)"
            echo "$response"
            return 0
            ;;
        401)
            _dispatcharr_log "warn" "Authentication failed (HTTP 401) - token may be expired"
            # Invalidate current auth state to force re-authentication
            DISPATCHARR_LAST_TOKEN_VALIDATION=0
            return 1
            ;;
        403)
            _dispatcharr_log "error" "Access forbidden (HTTP 403) for ${method} ${endpoint}"
            return 1
            ;;
        404)
            _dispatcharr_log "error" "Endpoint not found (HTTP 404): ${endpoint}"
            return 1
            ;;
        *)
            _dispatcharr_log "error" "HTTP error $http_code for ${method} ${endpoint}"
            return 1
            ;;
    esac
}

# ============================================================================
# INTERNAL HELPER FUNCTIONS
# ============================================================================

_dispatcharr_validate_current_token() {
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    if [[ -z "$access_token" ]]; then
        return 1
    fi
    
    # Quick validation with version endpoint - DIRECT curl call to avoid circular dependency
    local response
    response=$(curl -s \
        --connect-timeout "${API_TIMEOUT:-10}" \
        --max-time 15 \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        "${DISPATCHARR_URL}/api/core/version/" 2>/dev/null)
    
    local curl_exit_code=$?
    
    # Check if curl succeeded and response is valid JSON
    if [[ $curl_exit_code -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Also check that it's not an error response
        if ! echo "$response" | jq -e '.detail // .error' >/dev/null 2>&1; then
            return 0  # Valid token
        fi
    fi
    
    return 1  # Invalid token
}

_dispatcharr_refresh_token() {
    # Get refresh token
    local refresh_token
    refresh_token=$(get_dispatcharr_access_token)
    if [[ -z "$refresh_token" ]]; then
        # Try to get refresh token specifically
        refresh_token=$(jq -r '.refresh // empty' "$DISPATCHARR_TOKENS" 2>/dev/null)
    fi
    
    if [[ -z "$refresh_token" || "$refresh_token" == "null" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-WARN] No refresh token available, performing full authentication" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        _dispatcharr_full_authentication
        return $?
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-INFO] Refreshing access token using refresh token" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
    
    # Perform refresh request
    local refresh_response
    refresh_response=$(curl -s \
        --connect-timeout ${STANDARD_TIMEOUT:-10} \
        --max-time ${MAX_OPERATION_TIME:-20} \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"refresh\":\"$refresh_token\"}" \
        "${DISPATCHARR_URL}/api/accounts/token/refresh/" 2>&1)
    
    local curl_exit_code=$?
    
    # Handle network errors
    if [[ $curl_exit_code -ne 0 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-WARN] Network error during token refresh, falling back to full auth" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        _dispatcharr_full_authentication
        return $?
    fi
    
    # Validate and process response
    if echo "$refresh_response" | jq -e '.access' >/dev/null 2>&1; then
        # Ensure token directory exists
        mkdir -p "$(dirname "${DISPATCHARR_TOKENS}")" 2>/dev/null
        
        # Update token file with new access token
        local temp_file="${DISPATCHARR_TOKENS}.tmp"
        if jq --argjson new_access "$refresh_response" \
            '. + {access: $new_access.access}' \
            "$DISPATCHARR_TOKENS" > "$temp_file" 2>/dev/null; then
            
            mv "$temp_file" "$DISPATCHARR_TOKENS"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-SUCCESS] Access token refreshed successfully" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
            DISPATCHARR_AUTH_STATE="authenticated"
            DISPATCHARR_LAST_TOKEN_CHECK=$(date +%s)
            return 0
        else
            rm -f "$temp_file"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-WARN] Failed to update token file, falling back to full auth" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
            _dispatcharr_full_authentication
            return $?
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-WARN] Refresh token expired or invalid, performing full authentication" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        _dispatcharr_full_authentication
        return $?
    fi
}

_dispatcharr_full_authentication() {
    # Validation checks
    if [[ -z "${DISPATCHARR_URL:-}" ]] || [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-ERROR] Dispatcharr not configured or disabled" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        return 1
    fi
    
    if [[ -z "${DISPATCHARR_USERNAME:-}" ]] || [[ -z "${DISPATCHARR_PASSWORD:-}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-ERROR] Missing Dispatcharr credentials" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        return 1
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-INFO] Authenticating with Dispatcharr..." >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
    
    # Perform authentication request
    local token_response
    token_response=$(curl -s \
        --connect-timeout ${STANDARD_TIMEOUT:-10} \
        --max-time ${MAX_OPERATION_TIME:-20} \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$DISPATCHARR_USERNAME\",\"password\":\"$DISPATCHARR_PASSWORD\"}" \
        "${DISPATCHARR_URL}/api/accounts/token/" 2>&1)
    
    local curl_exit_code=$?
    
    # Handle network errors
    if [[ $curl_exit_code -ne 0 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-ERROR] Network error during authentication (curl exit: $curl_exit_code)" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        DISPATCHARR_AUTH_STATE="failed"
        return 1
    fi
    
    # Validate JSON response
    if ! echo "$token_response" | jq empty 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-ERROR] Invalid response format from Dispatcharr auth endpoint" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        DISPATCHARR_AUTH_STATE="failed"
        return 1
    fi
    
    # Check for successful authentication
    if echo "$token_response" | jq -e '.access' >/dev/null 2>&1; then
        # Ensure token directory exists
        mkdir -p "$(dirname "${DISPATCHARR_TOKENS}")" 2>/dev/null
        
        # Save tokens securely
        echo "$token_response" > "$DISPATCHARR_TOKENS"
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-SUCCESS] Authentication successful" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        DISPATCHARR_AUTH_STATE="authenticated"
        DISPATCHARR_LAST_TOKEN_CHECK=$(date +%s)
        
        return 0
    else
        # Extract error details
        local error_detail=$(echo "$token_response" | jq -r '.detail // .error // .message // "Authentication failed"' 2>/dev/null)
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [AUTH-ERROR] Authentication failed: $error_detail" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
        DISPATCHARR_AUTH_STATE="failed"
        return 1
    fi
}

_dispatcharr_get_access_token() {
    local token_file="$DISPATCHARR_TOKENS"
    
    if [[ ! -f "$token_file" ]]; then
        return 1
    fi
    
    local access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
    if [[ -n "$access_token" && "$access_token" != "null" ]]; then
        echo "$access_token"
        return 0
    fi
    
    return 1
}

_dispatcharr_get_refresh_token() {
    local token_file="$DISPATCHARR_TOKENS"
    
    if [[ ! -f "$token_file" ]]; then
        return 1
    fi
    
    local refresh_token=$(jq -r '.refresh // empty' "$token_file" 2>/dev/null)
    if [[ -n "$refresh_token" && "$refresh_token" != "null" ]]; then
        echo "$refresh_token"
        return 0
    fi
    
    return 1
}


# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Initialize the module
dispatcharr_init_module() {
    if [[ "$DISPATCHARR_MODULE_INITIALIZED" == "true" ]]; then
        return 0
    fi
    
    # Initialize token path
    _dispatcharr_init_token_path
    
    DISPATCHARR_MODULE_INITIALIZED=true
    DISPATCHARR_LAST_TOKEN_VALIDATION=0
    
    return 0
}

# Auto-initialize when module is loaded
dispatcharr_init_module

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

# Save configuration change and refresh auth state
_dispatcharr_save_config() {
    local config_key="$1"
    local config_value="$2"
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    # Validate required parameters
    if [[ -z "$config_key" ]]; then
        log_auth_error "save_dispatcharr_config: config_key required"
        return 1
    fi
    
    log_auth_info "Saving configuration: $config_key"
    
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
            log_auth_error "Config file not found: $config_file"
            return 1
        fi
    fi
    
    # Reload configuration
    reload_dispatcharr_config
    
    # Invalidate auth state since config changed
    invalidate_auth_state "Configuration changed: $config_key"
    
    return 0
}

# Reload configuration from file and refresh auth state
_dispatcharr_reload_config() {
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    log_auth_info "Reloading configuration from: $config_file"
    
    if [[ -f "$config_file" ]]; then
        # Source the config file to reload variables
        source "$config_file" 2>/dev/null || {
            log_auth_warn "Failed to source config file: $config_file"
            return 1
        }
        
        log_auth_info "Configuration reloaded successfully"
        
        # Log current config state (without sensitive info)
        log_auth_debug "DISPATCHARR_ENABLED: ${DISPATCHARR_ENABLED:-unset}"
        log_auth_debug "DISPATCHARR_URL: ${DISPATCHARR_URL:-unset}"
        log_auth_debug "DISPATCHARR_USERNAME: ${DISPATCHARR_USERNAME:+***set***}"
        log_auth_debug "DISPATCHARR_PASSWORD: ${DISPATCHARR_PASSWORD:+***set***}"
        
        return 0
    else
        log_auth_warn "Config file not found: $config_file"
        return 1
    fi
}

# Update Dispatcharr URL and refresh
_dispatcharr_update_url() {
    local new_url="$1"
    
    if [[ -z "$new_url" ]]; then
        log_auth_error "update_dispatcharr_url: URL required"
        return 1
    fi
    
    # Validate URL format
    if [[ ! "$new_url" =~ ^https?:// ]]; then
        log_auth_error "Invalid URL format: $new_url"
        return 1
    fi
    
    log_auth_info "Updating Dispatcharr URL to: $new_url"
    
    # Save to config and reload
    save_dispatcharr_config "DISPATCHARR_URL" "$new_url"
    
    return $?
}

# Update Dispatcharr credentials and refresh
_dispatcharr_update_credentials() {
    local new_username="$1"
    local new_password="$2"
    
    if [[ -z "$new_username" || -z "$new_password" ]]; then
        log_auth_error "update_dispatcharr_credentials: username and password required"
        return 1
    fi
    
    log_auth_info "Updating Dispatcharr credentials for user: $new_username"
    
    # Save both credentials
    save_dispatcharr_config "DISPATCHARR_USERNAME" "$new_username"
    save_dispatcharr_config "DISPATCHARR_PASSWORD" "$new_password"
    
    return $?
}

# Enable/disable Dispatcharr integration
_dispatcharr_update_enabled() {
    local enabled="$1"
    
    if [[ "$enabled" != "true" && "$enabled" != "false" ]]; then
        log_auth_error "update_dispatcharr_enabled: value must be 'true' or 'false'"
        return 1
    fi
    
    log_auth_info "Setting DISPATCHARR_ENABLED to: $enabled"
    
    save_dispatcharr_config "DISPATCHARR_ENABLED" "$enabled"
    
    return $?
}

# ============================================================================
# API FUNCTIONS
# ============================================================================

# BASIC

# Get Dispatcharr version
dispatcharr_get_version() {
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/core/version/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        echo "$response"
        return 0
    else
        _dispatcharr_log "error" "Failed to get version information"
        return 1
    fi
}

# Test Dispatcharr connection and authentication
dispatcharr_test_connection() {
    _dispatcharr_log "info" "Testing Dispatcharr connection and authentication"
    
    # Check basic configuration
    if [[ -z "${DISPATCHARR_URL:-}" ]] || [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        _dispatcharr_log "error" "Dispatcharr not configured or disabled"
        echo -e "${RED}❌ Dispatcharr: Not configured or disabled${RESET}" >&2
        echo -e "${CYAN}💡 Configure in Settings → Dispatcharr Integration${RESET}" >&2
        return 1
    fi
    
    # Test authentication
    if ! dispatcharr_ensure_valid_token; then
        _dispatcharr_log "error" "Authentication failed during connection test"
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        echo -e "${CYAN}💡 Check server URL, username, and password${RESET}" >&2
        return 1
    fi
    
    # Test API call
    local version_info
    version_info=$(dispatcharr_get_version)
    
    if [[ $? -eq 0 ]]; then
        local version=$(echo "$version_info" | jq -r '.version // "Unknown"' 2>/dev/null)
        _dispatcharr_log "info" "Connection test successful, server version: $version"
        echo -e "${GREEN}✅ Dispatcharr: Connection and authentication successful${RESET}" >&2
        echo -e "${CYAN}💡 Server version: $version${RESET}" >&2
        return 0
    else
        _dispatcharr_log "error" "Connection test failed - API call unsuccessful"
        echo -e "${RED}❌ Dispatcharr: Connection test failed${RESET}" >&2
        return 1
    fi
}

# CHANNELS

# Get all channels
dispatcharr_get_channels() {
    local search_term="$1"
    
    _dispatcharr_log "debug" "Fetching channels from Dispatcharr"
    
    # Build endpoint with optional search parameter
    local endpoint="/api/channels/channels/"
    if [[ -n "$search_term" ]]; then
        # URL encode the search term  
        local encoded_search_term=$(printf '%s' "$search_term" | sed 's/ /%20/g; s/&/%26/g; s/#/%23/g')
        endpoint+="?search=$encoded_search_term"
        _dispatcharr_log "info" "Searching channels for: '$search_term'"
    fi
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "$endpoint")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Channels endpoint returns direct array, not paginated response
        if [[ -n "$response" ]] && [[ "$response" != "[]" ]]; then
            local channel_count=$(echo "$response" | jq 'length' 2>/dev/null || echo "0")
            _dispatcharr_log "debug" "Retrieved $channel_count channels successfully"
            
            # Sort channels by channel number (ascending order)
            local sorted_channels
            sorted_channels=$(echo "$response" | jq 'sort_by(.channel_number | tonumber)' 2>/dev/null)
            
            if [[ -n "$sorted_channels" ]]; then
                echo "$sorted_channels"
            else
                # Fallback to unsorted if sorting fails
                echo "$response"
            fi
        else
            _dispatcharr_log "warn" "No channels found"
            echo "[]"
        fi
        return 0
    else
        _dispatcharr_log "error" "Failed to fetch channels from Dispatcharr"
        return 1
    fi
}

# Get and cache all channels from Dispatcharr
dispatcharr_get_and_cache_channels() {
    local search_term="${1:-}"  # Optional search parameter
    
    _dispatcharr_log "debug" "Fetching and caching channels from Dispatcharr"
    
    local response
    response=$(dispatcharr_get_channels "$search_term")
    
    if [[ $? -eq 0 ]]; then
        # Cache the response
        echo "$response" > "$DISPATCHARR_CACHE"
        _dispatcharr_log "info" "Successfully cached channel data"
        echo "$response"
        return 0
    else
        _dispatcharr_log "error" "Failed to fetch channels for caching"
        return 1
    fi
}

# Get specific channel by ID from Dispatcharr
dispatcharr_get_channel() {
    local channel_id="$1"
    
    if [[ -z "$channel_id" ]]; then
        _dispatcharr_log "error" "Channel ID is required"
        return 1
    fi
    
    _dispatcharr_log "debug" "Fetching channel $channel_id from Dispatcharr"
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/channels/$channel_id/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify we got a channel object with the expected ID
        local returned_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        if [[ "$returned_id" == "$channel_id" ]]; then
            _dispatcharr_log "info" "Successfully retrieved channel $channel_id"
            echo "$response"
            return 0
        else
            _dispatcharr_log "error" "Channel ID mismatch: requested $channel_id, got $returned_id"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to fetch channel $channel_id from Dispatcharr"
        return 1
    fi
}

# Update station ID
dispatcharr_update_channel_station_id() {
    local channel_id="$1"
    local station_id="$2"
    
    if [[ -z "$channel_id" || -z "$station_id" ]]; then
        _dispatcharr_log "error" "Channel ID and Station ID are required"
        return 1
    fi
    
    _dispatcharr_log "info" "Updating channel $channel_id with station ID: $station_id"
    
    # Prepare JSON payload
    local json_data
    json_data=$(jq -n --arg sid "$station_id" '{tvc_guide_stationid: $sid}')
    
    local response
    response=$(dispatcharr_api_wrapper "PATCH" "/api/channels/channels/$channel_id/" "$json_data")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify the update was successful
        local updated_station_id=$(echo "$response" | jq -r '.tvc_guide_stationid // empty' 2>/dev/null)
        if [[ "$updated_station_id" == "$station_id" ]]; then
            _dispatcharr_log "info" "Successfully updated channel $channel_id station ID to: $station_id"
            echo "$response"
            return 0
        else
            _dispatcharr_log "error" "Station ID update verification failed for channel $channel_id"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to update channel $channel_id station ID"
        return 1
    fi
}

# Update channel with data
dispatcharr_update_channel() {
    local channel_id="$1"
    local update_data="$2"
    
    if [[ -z "$channel_id" || -z "$update_data" ]]; then
        _dispatcharr_log "error" "Channel ID and update data are required"
        return 1
    fi
    
    # Validate that update_data is valid JSON
    if ! echo "$update_data" | jq empty 2>/dev/null; then
        _dispatcharr_log "error" "Update data must be valid JSON"
        return 1
    fi
    
    _dispatcharr_log "info" "Updating channel $channel_id with data"
    
    local response
    response=$(dispatcharr_api_wrapper "PATCH" "/api/channels/channels/$channel_id/" "$update_data")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify the update was successful by checking returned ID
        local returned_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        if [[ "$returned_id" == "$channel_id" ]]; then
            _dispatcharr_log "info" "Successfully updated channel $channel_id"
            echo "$response"
            return 0
        else
            _dispatcharr_log "error" "Channel update verification failed for channel $channel_id"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to update channel $channel_id"
        return 1
    fi
}

# Get streams for a specific channel
dispatcharr_get_channel_streams() {
    local channel_id="$1"
    
    if [[ -z "$channel_id" ]]; then
        _dispatcharr_log "error" "Channel ID is required"
        return 1
    fi
    
    _dispatcharr_log "info" "Fetching streams for channel $channel_id"
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/channels/$channel_id/streams/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        echo "$response"
        return 0
    else
        _dispatcharr_log "error" "Failed to fetch streams for channel $channel_id"
        echo "[]"
        return 1
    fi
}

# Create channel in Dispatcharr
dispatcharr_create_channel() {
    local channel_data="$1"
    
    if [[ -z "$channel_data" ]]; then
        _dispatcharr_log "error" "Channel data is required for creation"
        return 1
    fi
    
    # Validate that channel_data is valid JSON
    if ! echo "$channel_data" | jq empty 2>/dev/null; then
        _dispatcharr_log "error" "Channel data must be valid JSON"
        return 1
    fi
    
    _dispatcharr_log "debug" "Creating new channel in Dispatcharr"
    
    local response
    response=$(dispatcharr_api_wrapper "POST" "/api/channels/channels/" "$channel_data")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify the creation was successful by checking for ID in response
        local channel_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        if [[ -n "$channel_id" && "$channel_id" != "null" ]]; then
            _dispatcharr_log "debug" "Successfully created channel (ID: $channel_id)"
            echo "$response"
            return 0
        else
            _dispatcharr_log "error" "Channel creation verification failed - no ID returned"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to create channel in Dispatcharr"
        return 1
    fi
}

# Delete a channel from Dispatcharr
dispatcharr_delete_channel() {
    local channel_id="$1"
    
    if [[ -z "$channel_id" ]]; then
        _dispatcharr_log "error" "Channel ID is required"
        return 1
    fi
    
    _dispatcharr_log "info" "Deleting channel $channel_id from Dispatcharr"
    
    local response
    response=$(dispatcharr_api_wrapper "DELETE" "/api/channels/channels/$channel_id/")
    
    if [[ $? -eq 0 ]]; then
        _dispatcharr_log "info" "Successfully deleted channel $channel_id"
        return 0
    else
        _dispatcharr_log "error" "Failed to delete channel $channel_id"
        return 1
    fi
}

# Find channels that are missing station IDs
dispatcharr_find_missing_station_ids() {
    local channels_data="$1"
    
    _dispatcharr_log "info" "Analyzing channels for missing station IDs"
    
    if [[ -z "$channels_data" ]]; then
        _dispatcharr_log "error" "No channel data provided for analysis"
        return 1
    fi
    
    # Extract missing channels and sort by channel number
    local missing_channels
    missing_channels=$(echo "$channels_data" | jq -r '
        .[] | 
        select((.tvc_guide_stationid // "") == "" or (.tvc_guide_stationid // "") == null) |
        [.id, .name, .channel_group_id // "Ungrouped", (.channel_number // 0)] | 
        @tsv
    ' 2>/dev/null | sort -t$'\t' -k4 -n)
    
    if [[ $? -eq 0 ]]; then
        local count=$(echo "$missing_channels" | wc -l)
        if [[ -n "$missing_channels" ]]; then
            _dispatcharr_log "info" "Found $count channels missing station IDs"
        else
            _dispatcharr_log "info" "No channels missing station IDs"
        fi
        echo "$missing_channels"
        return 0
    else
        _dispatcharr_log "error" "Failed to analyze channel data"
        return 1
    fi
}

#LOGOS

# Check if logo already exists in Dispatcharr (with local caching)
dispatcharr_check_existing_logo() {
    local logo_url="$1"
    
    if [[ -z "$logo_url" || "$logo_url" == "null" ]]; then
        _dispatcharr_log "debug" "No logo URL provided for existence check"
        return 1
    fi
    
    _dispatcharr_log "debug" "Checking for existing logo: $logo_url"
    
    # First check our local cache
    if [[ -f "$DISPATCHARR_LOGOS" ]]; then
        local cached_id=$(jq -r --arg url "$logo_url" '.[$url].id // empty' "$DISPATCHARR_LOGOS" 2>/dev/null)
        if [[ -n "$cached_id" && "$cached_id" != "null" ]]; then
            _dispatcharr_log "debug" "Found logo in local cache (ID: $cached_id)"
            echo "$cached_id"
            return 0
        fi
    fi
    
    # If not in local cache, query Dispatcharr API using modern API wrapper
    _dispatcharr_log "debug" "Logo not in cache, querying Dispatcharr API"
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/logos/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        local logo_id=$(echo "$response" | jq -r --arg url "$logo_url" \
            '.[] | select(.url == $url) | .id // empty' 2>/dev/null)
        
        if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
            # Cache this for future use
            local logo_name=$(echo "$response" | jq -r --arg url "$logo_url" \
                '.[] | select(.url == $url) | .name // "Unknown"' 2>/dev/null)
            
            _dispatcharr_log "info" "Found existing logo via API (ID: $logo_id) - caching locally"
            cache_dispatcharr_logo_info "$logo_url" "$logo_id" "$logo_name"
            echo "$logo_id"
            return 0
        else
            _dispatcharr_log "debug" "Logo not found in Dispatcharr"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to query Dispatcharr logos API"
        return 1
    fi
}

# Download logo file from Dispatcharr to local file
dispatcharr_download_logo_file() {
    local logo_id="$1"
    local output_file="$2"
    
    if [[ -z "$logo_id" || -z "$output_file" ]]; then
        _dispatcharr_log "error" "Logo ID and output file path are required"
        return 1
    fi
    
    _dispatcharr_log "info" "Downloading logo $logo_id to $output_file"
    
    # Get logo information using documented API
    local logo_info
    logo_info=$(dispatcharr_api_wrapper "GET" "/api/channels/logos/$logo_id/")
    
    if [[ $? -ne 0 ]] || [[ -z "$logo_info" ]]; then
        _dispatcharr_log "error" "Failed to get logo info for ID $logo_id"
        return 1
    fi
    
    # Extract cache_url (preferred) or url from the response
    local download_url
    download_url=$(echo "$logo_info" | jq -r '.cache_url // .url // empty' 2>/dev/null)
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        _dispatcharr_log "error" "No download URL found in logo info for ID $logo_id"
        return 1
    fi
    
    # Download directly from the URL (no auth needed for external URLs)
    local http_code
    http_code=$(curl -s \
        --connect-timeout "${API_TIMEOUT:-10}" \
        --max-time "${API_MAX_TIME:-30}" \
        -o "$output_file" \
        -w "%{http_code}" \
        "$download_url" 2>/dev/null)
    
    local curl_exit_code=$?
    
    # Handle curl errors
    if [[ $curl_exit_code -ne 0 ]]; then
        _dispatcharr_log "error" "Network error downloading logo from $download_url (curl exit: $curl_exit_code)"
        [[ -f "$output_file" ]] && rm -f "$output_file"
        return 1
    fi
    
    # Check HTTP status and validate image
    case "$http_code" in
        200)
            if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
                # Verify it's actually an image
                local mime_type=$(file --mime-type -b "$output_file" 2>/dev/null)
                if [[ "$mime_type" == image/* ]]; then
                    _dispatcharr_log "info" "Successfully downloaded logo $logo_id to $output_file"
                    return 0
                else
                    _dispatcharr_log "error" "Downloaded file is not an image (MIME: $mime_type)"
                    [[ -f "$output_file" ]] && rm -f "$output_file"
                    return 1
                fi
            else
                _dispatcharr_log "error" "Logo file download failed - empty or missing file"
                [[ -f "$output_file" ]] && rm -f "$output_file"
                return 1
            fi
            ;;
        404)
            _dispatcharr_log "error" "Logo file not found at URL: $download_url"
            [[ -f "$output_file" ]] && rm -f "$output_file"
            return 1
            ;;
        *)
            _dispatcharr_log "error" "HTTP error $http_code downloading logo from $download_url"
            [[ -f "$output_file" ]] && rm -f "$output_file"
            return 1
            ;;
    esac
}

# Cache logo information locally for faster future lookups
dispatcharr_cache_logo_info() {
    local logo_url="$1"
    local logo_id="$2"
    local logo_name="$3"
    
    if [[ -z "$logo_url" || -z "$logo_id" ]]; then
        _dispatcharr_log "error" "Logo URL and ID required for caching"
        return 1
    fi
    
    _dispatcharr_log "debug" "Caching logo info: ID=$logo_id, name=$logo_name"
    
    # Initialize cache file if needed
    if [[ ! -f "$DISPATCHARR_LOGOS" ]]; then
        echo '{}' > "$DISPATCHARR_LOGOS"
        _dispatcharr_log "debug" "Initialized logo cache file: $DISPATCHARR_LOGOS"
    fi
    
    # Add/update logo info in cache
    local temp_file="${DISPATCHARR_LOGOS}.tmp"
    jq --arg url "$logo_url" \
       --arg id "$logo_id" \
       --arg name "${logo_name:-Unknown}" \
       --arg timestamp "$(date -Iseconds)" \
       '. + {($url): {id: $id, name: $name, cached: $timestamp}}' \
       "$DISPATCHARR_LOGOS" > "$temp_file" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$DISPATCHARR_LOGOS"
        _dispatcharr_log "debug" "Successfully cached logo info for ID $logo_id"
        return 0
    else
        rm -f "$temp_file"
        _dispatcharr_log "error" "Failed to cache logo info for ID $logo_id"
        return 1
    fi
}

# Get specific logo by ID
dispatcharr_get_logo() {
    local logo_id="$1"
    
    if [[ -z "$logo_id" ]]; then
        _dispatcharr_log "error" "Logo ID is required"
        return 1
    fi
    
    _dispatcharr_log "debug" "Fetching logo $logo_id from Dispatcharr"
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/logos/$logo_id/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify we got a logo object with the expected ID
        local returned_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        if [[ "$returned_id" == "$logo_id" ]]; then
            _dispatcharr_log "info" "Successfully retrieved logo $logo_id"
            echo "$response"
            return 0
        else
            _dispatcharr_log "error" "Logo ID mismatch: requested $logo_id, got $returned_id"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to fetch logo $logo_id from Dispatcharr"
        return 1
    fi
}

# Upload logo to Dispatcharr  
dispatcharr_upload_logo() {
    local station_name="$1"
    local logo_url="$2"
    
    if [[ -z "$station_name" || -z "$logo_url" ]]; then
        _dispatcharr_log "error" "Station name and logo URL are required"
        return 1
    fi
    
    _dispatcharr_log "info" "Uploading logo for station: $station_name from URL: $logo_url"
    
    # Prepare JSON payload for logo upload
    local json_data
    json_data=$(jq -n --arg name "$station_name" --arg url "$logo_url" '{
        name: $name,
        url: $url
    }')
    
    local response
    response=$(dispatcharr_api_wrapper "POST" "/api/channels/logos/" "$json_data")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify upload was successful by checking for ID in response
        local logo_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
            _dispatcharr_log "info" "Successfully uploaded logo for $station_name (ID: $logo_id)"
            echo "$response"
            return 0
        else
            _dispatcharr_log "error" "Logo upload verification failed - no ID returned"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to upload logo for station: $station_name"
        return 1
    fi
}

# Upload station logo with caching and duplicate checking
dispatcharr_upload_station_logo() {
    local station_name="$1"
    local logo_url="$2"
    
    if [[ -z "$logo_url" || "$logo_url" == "null" ]]; then
        _dispatcharr_log "error" "No logo URL provided for station: $station_name"
        return 1
    fi
    
    _dispatcharr_log "info" "Processing logo upload for station: $station_name"
    
    # Check for existing logo first to avoid duplicates
    local existing_logo_id=$(check_existing_dispatcharr_logo "$logo_url")
    if [[ -n "$existing_logo_id" && "$existing_logo_id" != "null" ]]; then
        _dispatcharr_log "info" "Logo already exists for $station_name (ID: $existing_logo_id)"
        echo "$existing_logo_id"
        return 0
    fi
    
    # Upload new logo
    _dispatcharr_log "info" "Uploading new logo for $station_name from URL: $logo_url"
    local response
    response=$(dispatcharr_upload_logo "$station_name" "$logo_url")
    
    if [[ $? -eq 0 ]]; then
        local logo_id=$(echo "$response" | jq -r '.id')
        if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
            # Cache the logo info for future use
            cache_dispatcharr_logo_info "$logo_url" "$logo_id" "$station_name"
            _dispatcharr_log "info" "Successfully uploaded and cached logo for $station_name (ID: $logo_id)"
            echo "$logo_id"
            return 0
        else
            _dispatcharr_log "error" "Upload succeeded but no logo ID returned for $station_name"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to upload logo for station: $station_name"
        return 1
    fi
}

# Delete logo from Dispatcharr
dispatcharr_delete_logo() {
    local logo_id="$1"
    
    if [[ -z "$logo_id" ]]; then
        _dispatcharr_log "error" "Logo ID is required"
        return 1
    fi
    
    _dispatcharr_log "info" "Deleting logo $logo_id from Dispatcharr"
    
    local response
    response=$(dispatcharr_api_wrapper "DELETE" "/api/channels/logos/$logo_id/")
    
    # DELETE requests typically return 204 No Content on success
    if [[ $? -eq 0 ]]; then
        _dispatcharr_log "info" "Successfully deleted logo $logo_id"
        return 0
    else
        _dispatcharr_log "error" "Failed to delete logo $logo_id from Dispatcharr"
        return 1
    fi
}

# Clean up old entries from logo cache (removes entries older than 30 days)
dispatcharr_cleanup_logo_cache() {
    _dispatcharr_log "info" "Starting logo cache cleanup"
    
    if [[ ! -f "$DISPATCHARR_LOGOS" ]]; then
        _dispatcharr_log "debug" "No logo cache file found - nothing to clean"
        return 0
    fi
    
    local cache_size_before=$(jq 'length' "$DISPATCHARR_LOGOS" 2>/dev/null || echo "0")
    _dispatcharr_log "debug" "Logo cache contains $cache_size_before entries before cleanup"
    
    # Cross-platform date calculation (30 days ago)
    local cutoff_date
    cutoff_date=$(date -d '30 days ago' -Iseconds 2>/dev/null || date -v-30d -Iseconds 2>/dev/null)
    
    if [[ -z "$cutoff_date" ]]; then
        _dispatcharr_log "error" "Failed to calculate cutoff date for cache cleanup"
        return 1
    fi
    
    _dispatcharr_log "debug" "Removing logo cache entries older than: $cutoff_date"
    
    # Remove entries older than cutoff date
    local temp_file="${DISPATCHARR_LOGOS}.tmp"
    jq --arg cutoff "$cutoff_date" \
        'to_entries | map(select(.value.cached >= $cutoff)) | from_entries' \
        "$DISPATCHARR_LOGOS" > "$temp_file" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$DISPATCHARR_LOGOS"
        local cache_size_after=$(jq 'length' "$DISPATCHARR_LOGOS" 2>/dev/null || echo "0")
        local removed_count=$((cache_size_before - cache_size_after))
        
        _dispatcharr_log "info" "Logo cache cleanup completed: removed $removed_count entries, $cache_size_after entries remaining"
        return 0
    else
        rm -f "$temp_file"
        _dispatcharr_log "error" "Failed to process logo cache cleanup"
        return 1
    fi
}

# ============================================================================
# STREAM MANAGEMENT FUNCTIONS
# ============================================================================

# Get all available streams from Dispatcharr
dispatcharr_get_all_streams() {
    _dispatcharr_log "debug" "Fetching all streams from Dispatcharr"
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/streams/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Handle both direct array and paginated response
        local results
        if echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
            # Direct array response
            results="$response"
        else
            # Paginated response - extract results
            results=$(echo "$response" | jq -r '.results // empty' 2>/dev/null)
        fi
        
        if [[ -n "$results" ]] && [[ "$results" != "[]" ]]; then
            local stream_count=$(echo "$results" | jq 'length' 2>/dev/null || echo "0")
            _dispatcharr_log "debug" "Retrieved $stream_count streams successfully"
            echo "$results"
            return 0
        else
            _dispatcharr_log "warn" "No streams found"
            echo "[]"
            return 0
        fi
    else
        _dispatcharr_log "error" "Failed to retrieve streams from Dispatcharr"
        return 1
    fi
}

# Search streams by name/term using API search
dispatcharr_search_streams() {
    local search_term="$1"
    
    if [[ -z "$search_term" ]]; then
        _dispatcharr_log "error" "Search term is required for stream search"
        return 1
    fi
    
    _dispatcharr_log "debug" "Searching streams with term: $search_term"
    
    # Use API search parameter for better performance
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/streams/?search=$search_term")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Handle both direct array and paginated response
        local results
        if echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
            # Direct array response
            results="$response"
        else
            # Paginated response - extract results
            results=$(echo "$response" | jq -r '.results // empty' 2>/dev/null)
        fi
        
        if [[ -n "$results" ]] && [[ "$results" != "[]" ]]; then
            local match_count=$(echo "$results" | jq 'length' 2>/dev/null || echo "0")
            _dispatcharr_log "debug" "Found $match_count streams matching '$search_term'"
            echo "$results"
            return 0
        else
            _dispatcharr_log "debug" "No streams found matching '$search_term'"
            echo "[]"
            return 0
        fi
    else
        _dispatcharr_log "error" "Failed to search streams for '$search_term'"
        return 1
    fi
}

# Search streams with pagination support
dispatcharr_search_streams_paginated() {
    local search_term="$1"
    local page="${2:-1}"
    
    if [[ -z "$search_term" ]]; then
        _dispatcharr_log "error" "Search term is required for stream search"
        return 1
    fi
    
    _dispatcharr_log "debug" "Searching streams with term: $search_term (page $page)"
    
    # Use API search parameter with pagination
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/streams/?search=$search_term&page=$page")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        echo "$response"
        return 0
    else
        _dispatcharr_log "error" "Failed to search streams for '$search_term' page $page"
        return 1
    fi
}

# Get available M3U accounts for filtering
dispatcharr_get_m3u_accounts() {
    _dispatcharr_log "debug" "Getting available M3U accounts"
    
    local accounts_response
    accounts_response=$(dispatcharr_api_wrapper "GET" "/api/channels/streams/?page_size=100")
    
    if [[ $? -eq 0 ]] && echo "$accounts_response" | jq empty 2>/dev/null; then
        echo "$accounts_response" | jq -r '.results // [] | map(.m3u_account // empty) | sort | unique | .[]' 2>/dev/null
        return 0
    fi
    
    _dispatcharr_log "error" "Failed to get M3U accounts"
    return 1
}

# Get available channel groups for filtering
dispatcharr_get_stream_channel_groups() {
    _dispatcharr_log "debug" "Getting available stream channel groups"
    
    local groups_response
    groups_response=$(dispatcharr_api_wrapper "GET" "/api/channels/streams/?page_size=100")
    
    if [[ $? -eq 0 ]] && echo "$groups_response" | jq empty 2>/dev/null; then
        echo "$groups_response" | jq -r '.results // [] | map(.channel_group // empty) | sort | unique | .[]' 2>/dev/null
        return 0
    fi
    
    _dispatcharr_log "error" "Failed to get stream channel groups"
    return 1
}

# Enhanced stream search with filtering
dispatcharr_search_streams_filtered() {
    local search_term="$1"
    local page="${2:-1}"
    local m3u_accounts="$3"     # Comma-separated list
    local channel_groups="$4"   # Comma-separated list
    
    if [[ -z "$search_term" ]]; then
        _dispatcharr_log "error" "Search term is required for filtered stream search"
        return 1
    fi
    
    _dispatcharr_log "debug" "Filtered stream search: term='$search_term', page=$page, m3u='$m3u_accounts', groups='$channel_groups'"
    
    # Build API URL with filters
    local api_url="/api/channels/streams/?search=$search_term&page=$page"
    
    # Add M3U account filters
    if [[ -n "$m3u_accounts" ]]; then
        IFS=',' read -ra ACCOUNTS <<< "$m3u_accounts"
        for account in "${ACCOUNTS[@]}"; do
            [[ -n "$account" ]] && api_url="${api_url}&m3u_account=${account}"
        done
    fi
    
    # Add channel group filters
    if [[ -n "$channel_groups" ]]; then
        IFS=',' read -ra GROUPS <<< "$channel_groups"
        for group in "${GROUPS[@]}"; do
            [[ -n "$group" ]] && api_url="${api_url}&channel_group=${group}"
        done
    fi
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "$api_url")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        echo "$response"
        return 0
    else
        _dispatcharr_log "error" "Failed filtered search for '$search_term' page $page"
        return 1
    fi
}

# Get streams for a specific channel
dispatcharr_get_channel_streams() {
    local channel_id="$1"
    
    if [[ -z "$channel_id" ]]; then
        _dispatcharr_log "error" "Channel ID is required for getting streams"
        return 1
    fi
    
    _dispatcharr_log "debug" "Fetching streams for channel $channel_id"
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/channels/$channel_id/streams/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Handle both direct array and paginated response
        local results
        if echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
            # Direct array response
            results="$response"
        else
            # Paginated response - extract results
            results=$(echo "$response" | jq -r '.results // empty' 2>/dev/null)
        fi
        
        if [[ -n "$results" ]]; then
            local stream_count=$(echo "$results" | jq 'length' 2>/dev/null || echo "0")
            _dispatcharr_log "debug" "Retrieved $stream_count streams for channel $channel_id"
            echo "$results"
            return 0
        else
            _dispatcharr_log "debug" "No streams found for channel $channel_id"
            echo "[]"
            return 0
        fi
    else
        _dispatcharr_log "error" "Failed to retrieve streams for channel $channel_id"
        return 1
    fi
}

# Assign a stream to a channel
dispatcharr_assign_stream_to_channel() {
    local channel_id="$1"
    local stream_id="$2"
    
    if [[ -z "$channel_id" || -z "$stream_id" ]]; then
        _dispatcharr_log "error" "Channel ID and Stream ID are required for stream assignment"
        return 1
    fi
    
    _dispatcharr_log "debug" "Assigning stream $stream_id to channel $channel_id"
    
    # First get current channel data to get existing streams
    local current_channel
    current_channel=$(dispatcharr_get_channel "$channel_id")
    
    if [[ $? -ne 0 ]] || [[ -z "$current_channel" ]]; then
        _dispatcharr_log "error" "Failed to get current channel data for $channel_id"
        return 1
    fi
    
    # Get current streams and add new stream
    local current_streams
    current_streams=$(echo "$current_channel" | jq -r '.streams // []' 2>/dev/null)
    
    # Check if stream is already assigned
    local already_assigned
    already_assigned=$(echo "$current_streams" | jq --argjson stream_id "$stream_id" 'any(. == $stream_id)' 2>/dev/null)
    
    if [[ "$already_assigned" == "true" ]]; then
        _dispatcharr_log "debug" "Stream $stream_id already assigned to channel $channel_id"
        return 0
    fi
    
    # Add new stream to existing streams array
    local updated_streams
    updated_streams=$(echo "$current_streams" | jq --argjson stream_id "$stream_id" '. + [$stream_id]' 2>/dev/null)
    
    # Create JSON data for PATCH request
    local json_data
    json_data=$(jq -n --argjson streams "$updated_streams" '{ streams: $streams }')
    
    local response
    response=$(dispatcharr_api_wrapper "PATCH" "/api/channels/channels/$channel_id/" "$json_data")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify the stream was added
        local response_streams
        response_streams=$(echo "$response" | jq -r '.streams // []' 2>/dev/null)
        local stream_added
        stream_added=$(echo "$response_streams" | jq --argjson stream_id "$stream_id" 'any(. == $stream_id)' 2>/dev/null)
        
        if [[ "$stream_added" == "true" ]]; then
            _dispatcharr_log "debug" "Successfully assigned stream $stream_id to channel $channel_id"
            return 0
        else
            _dispatcharr_log "error" "Stream assignment failed - stream not found in response"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to assign stream $stream_id to channel $channel_id"
        return 1
    fi
}

# Remove a stream from a channel
dispatcharr_remove_stream_from_channel() {
    local channel_id="$1"
    local stream_id="$2"
    
    if [[ -z "$channel_id" || -z "$stream_id" ]]; then
        _dispatcharr_log "error" "Channel ID and Stream ID are required for stream removal"
        return 1
    fi
    
    _dispatcharr_log "debug" "Removing stream $stream_id from channel $channel_id"
    
    # Get current channel data to get existing streams
    local current_channel
    current_channel=$(dispatcharr_get_channel "$channel_id")
    
    if [[ $? -ne 0 ]] || [[ -z "$current_channel" ]]; then
        _dispatcharr_log "error" "Failed to get current channel data for $channel_id"
        return 1
    fi
    
    # Get current streams and remove the specified stream
    local current_streams
    current_streams=$(echo "$current_channel" | jq -r '.streams // []' 2>/dev/null)
    
    # Check if stream is actually assigned
    local stream_found
    stream_found=$(echo "$current_streams" | jq --argjson stream_id "$stream_id" 'any(. == $stream_id)' 2>/dev/null)
    
    if [[ "$stream_found" != "true" ]]; then
        _dispatcharr_log "debug" "Stream $stream_id not assigned to channel $channel_id"
        return 0  # Not an error - stream wasn't assigned anyway
    fi
    
    # Remove stream from streams array
    local updated_streams
    updated_streams=$(echo "$current_streams" | jq --argjson stream_id "$stream_id" 'map(select(. != $stream_id))' 2>/dev/null)
    
    # Create JSON data for PATCH request
    local json_data
    json_data=$(jq -n --argjson streams "$updated_streams" '{ streams: $streams }')
    
    local response
    response=$(dispatcharr_api_wrapper "PATCH" "/api/channels/channels/$channel_id/" "$json_data")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Verify the stream was removed
        local response_streams
        response_streams=$(echo "$response" | jq -r '.streams // []' 2>/dev/null)
        local stream_removed
        stream_removed=$(echo "$response_streams" | jq --argjson stream_id "$stream_id" 'any(. == $stream_id) | not' 2>/dev/null)
        
        if [[ "$stream_removed" == "true" ]]; then
            _dispatcharr_log "debug" "Successfully removed stream $stream_id from channel $channel_id"
            return 0
        else
            _dispatcharr_log "error" "Stream removal failed - stream still found in response"
            return 1
        fi
    else
        _dispatcharr_log "error" "Failed to remove stream $stream_id from channel $channel_id"
        return 1
    fi
}

# GROUPS

# Get all channel groups from Dispatcharr
dispatcharr_get_groups() {
    _dispatcharr_log "debug" "Fetching channel groups from Dispatcharr"
    
    local response
    response=$(dispatcharr_api_wrapper "GET" "/api/channels/groups/")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Handle both direct array and paginated response
        local results
        if echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
            # Direct array response
            results="$response"
        else
            # Paginated response - extract results
            results=$(echo "$response" | jq -r '.results // empty' 2>/dev/null)
        fi
        if [[ -n "$results" ]] && [[ "$results" != "[]" ]]; then
            local group_count=$(echo "$results" | jq 'length' 2>/dev/null || echo "0")
            _dispatcharr_log "debug" "Retrieved $group_count channel groups successfully"
            echo "$results"
        else
            _dispatcharr_log "warn" "No channel groups found"
            echo "[]"
        fi
        return 0
    else
        _dispatcharr_log "error" "Failed to fetch channel groups from Dispatcharr"
        return 1
    fi
}

# Get only channel groups that are currently assigned to channels (modular function)
dispatcharr_get_assigned_groups() {
    _dispatcharr_log "debug" "Fetching only groups currently assigned to channels"
    
    # First get all channels to see which groups are in use
    local channels
    channels=$(dispatcharr_get_channels)
    
    if [[ $? -ne 0 || -z "$channels" || "$channels" == "[]" ]]; then
        _dispatcharr_log "warn" "No channels found or failed to fetch channels"
        echo "[]"
        return 0
    fi
    
    # Extract unique group IDs that are actually assigned to channels
    local assigned_group_ids
    assigned_group_ids=$(echo "$channels" | jq -r '
        [.[] | .channel_group_id // empty | select(. != null and . != "")] | 
        unique | 
        .[]
    ' 2>/dev/null)
    
    if [[ -z "$assigned_group_ids" ]]; then
        _dispatcharr_log "info" "No groups are currently assigned to any channels"
        echo "[]"
        return 0
    fi
    
    # Now get all groups and filter to only include assigned ones
    local all_groups
    all_groups=$(dispatcharr_get_groups)
    
    if [[ $? -ne 0 || -z "$all_groups" || "$all_groups" == "[]" ]]; then
        _dispatcharr_log "error" "Failed to fetch group details"
        echo "[]"
        return 1
    fi
    
    # Filter groups to only include those that are assigned
    local assigned_groups
    assigned_groups=$(echo "$all_groups" | jq --argjson assigned_ids "$(echo "$assigned_group_ids" | jq -R . | jq -s 'map(tonumber)')" '
        [.[] | select(.id as $id | $assigned_ids | index($id))]
    ' 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$assigned_groups" ]]; then
        local assigned_count=$(echo "$assigned_groups" | jq 'length' 2>/dev/null || echo "0")
        _dispatcharr_log "info" "Found $assigned_count groups currently assigned to channels"
        echo "$assigned_groups"
        return 0
    else
        _dispatcharr_log "error" "Failed to filter assigned groups"
        echo "[]"
        return 1
    fi
}

# View only channel groups that are currently assigned to channels
dispatcharr_view_groups() {
    echo -e "${HEADER_STYLE}=== Channel Groups Currently In Use ===${RESET}\n"
    
    echo -e "${CYAN}Loading groups assigned to channels...${RESET}"
    
    local groups
    groups=$(dispatcharr_get_assigned_groups)
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Failed to load channel groups${RESET}"
        return 1
    fi
    
    local group_count
    group_count=$(echo "$groups" | jq 'length' 2>/dev/null || echo "0")
    
    if [[ "$group_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No groups are currently assigned to any channels${RESET}"
        echo -e "${CYAN}💡 Create channels and assign them to groups first${RESET}"
        return 0
    fi
    
    echo -e "${SUCCESS_STYLE}✅ Found $group_count groups currently in use${RESET}"
    echo
    
    # Display groups with channel counts
    echo -e "${BOLD}${BLUE}Groups Currently Assigned to Channels:${RESET}"
    echo "──────────────────────────────────────────────────────────────"
    printf "%-5s %-30s %-15s %s\n" "ID" "Group Name" "Channels" "Description"
    echo "──────────────────────────────────────────────────────────────"
    
    # Get all channels to count how many are in each group
    local channels
    channels=$(dispatcharr_get_channels)
    
    echo "$groups" | jq -r '.[] | "\(.id)\t\(.name // "Unnamed Group")"' | \
    while IFS=$'\t' read -r group_id group_name; do
        # Count channels in this group
        local channel_count=0
        if [[ -n "$channels" && "$channels" != "[]" ]]; then
            channel_count=$(echo "$channels" | jq --arg gid "$group_id" '[.[] | select(.channel_group_id == ($gid | tonumber))] | length' 2>/dev/null || echo "0")
        fi
        
        printf "%-5s %-30s %-15s %s\n" \
            "$group_id" \
            "${group_name:0:30}" \
            "$channel_count" \
            "Active group"
    done
    
    echo "──────────────────────────────────────────────────────────────"
    echo
    echo -e "${CYAN}💡 This shows only groups currently assigned to channels${RESET}"
    echo -e "${CYAN}💡 Empty or unused groups are not displayed${RESET}"
    echo -e "${CYAN}💡 Groups imported by playlists but not used by any Dispatcharr channels are also not displayed${RESET}"
    
    return 0
}

# Create a new group (standalone menu function)
dispatcharr_create_group() {
    echo -e "${HEADER_STYLE}=== Create New Group ===${RESET}\n"
    
    # Check authentication first
    if ! ensure_dispatcharr_auth; then
        echo -e "${ERROR_STYLE}❌ Authentication failed${RESET}"
        return 1
    fi
    
    echo -e "${INFO_STYLE}Create a new channel group to organize your channels${RESET}"
    echo -e "${CYAN}💡 Groups help organize channels by type, source, or region${RESET}"
    echo
    
    # Get group name
    local group_name
    while true; do
        read -p "Enter group name (or 'q' to cancel): " group_name < /dev/tty
        
        if [[ -z "$group_name" ]]; then
            echo -e "${WARNING_STYLE}⚠️  Group name cannot be empty${RESET}"
            continue
        elif [[ "$group_name" =~ ^[qQ]$ ]]; then
            echo -e "${YELLOW}Cancelled${RESET}"
            return 0
        fi
        
        # Check if group already exists
        local existing_id
        existing_id=$(dispatcharr_get_group_id "$group_name")
        
        if [[ -n "$existing_id" ]]; then
            echo -e "${WARNING_STYLE}⚠️  Group '$group_name' already exists (ID: $existing_id)${RESET}"
            echo -e "${CYAN}Please choose a different name${RESET}"
            continue
        fi
        
        break
    done
    
    # Create the group
    echo -e "${CYAN}Creating group '$group_name'...${RESET}"
    
    local json_data
    json_data=$(jq -n --arg name "$group_name" '{name: $name}')
    
    local response
    response=$(dispatcharr_api_wrapper "POST" "/api/channels/groups/" "$json_data")
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        local new_group_id
        new_group_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        
        if [[ -n "$new_group_id" ]]; then
            echo -e "${SUCCESS_STYLE}✅ Group '$group_name' created successfully (ID: $new_group_id)${RESET}"
            echo -e "${CYAN}💡 You can now assign channels to this group${RESET}"
            return 0
        fi
    fi
    
    echo -e "${ERROR_STYLE}❌ Failed to create group${RESET}"
    return 1
}

# Modify an existing group
dispatcharr_modify_group() {
    echo -e "${HEADER_STYLE}=== Modify Group ===${RESET}\n"
    
    # Check authentication first
    if ! ensure_dispatcharr_auth; then
        echo -e "${ERROR_STYLE}❌ Authentication failed${RESET}"
        return 1
    fi
    
    # Get groups assigned to channels
    echo -e "${CYAN}Loading groups assigned to channels...${RESET}"
    local groups
    groups=$(dispatcharr_get_assigned_groups)
    
    if [[ $? -ne 0 ]] || [[ -z "$groups" ]]; then
        echo -e "${ERROR_STYLE}❌ Failed to load groups${RESET}"
        return 1
    fi
    
    local group_count
    group_count=$(echo "$groups" | jq 'length' 2>/dev/null || echo "0")
    
    if [[ "$group_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No groups are currently assigned to any channels${RESET}"
        echo -e "${CYAN}💡 Create channels and assign them to groups first${RESET}"
        return 0
    fi
    
    # Display groups assigned to channels
    echo -e "${SUCCESS_STYLE}✅ Found $group_count groups currently in use${RESET}"
    echo
    echo -e "${BOLD}${BLUE}Groups Currently Assigned to Channels:${RESET}"
    echo "──────────────────────────────────────────────────────────────"
    printf "%-5s %-5s %-40s\n" "Sel" "ID" "Group Name"
    echo "──────────────────────────────────────────────────────────────"
    
    local selection_index=1
    echo "$groups" | jq -r '.[] | "\(.id)\t\(.name // "Unnamed Group")"' | \
    while IFS=$'\t' read -r group_id group_name; do
        printf "%-5s %-5s %-40s\n" "$selection_index" "$group_id" "${group_name:0:40}"
        ((selection_index++))
    done
    
    echo "──────────────────────────────────────────────────────────────"
    echo
    
    # Select group to modify
    local selected_index
    read -p "Select group to modify (1-$group_count, or 'q' to cancel): " selected_index < /dev/tty
    
    if [[ "$selected_index" =~ ^[qQ]$ ]] || [[ -z "$selected_index" ]]; then
        echo -e "${YELLOW}Cancelled${RESET}"
        return 0
    fi
    
    if ! [[ "$selected_index" =~ ^[0-9]+$ ]] || [[ "$selected_index" -lt 1 ]] || [[ "$selected_index" -gt "$group_count" ]]; then
        echo -e "${ERROR_STYLE}❌ Invalid selection${RESET}"
        return 1
    fi
    
    # Get selected group details
    local selected_group
    selected_group=$(echo "$groups" | jq -r ".[$((selected_index-1))]")
    local group_id=$(echo "$selected_group" | jq -r '.id')
    local current_name=$(echo "$selected_group" | jq -r '.name // "Unnamed Group"')
    
    echo
    echo -e "${INFO_STYLE}Selected group: $current_name (ID: $group_id)${RESET}"
    echo
    
    # Get new name
    local new_name
    read -p "Enter new name (or press Enter to keep current): " new_name < /dev/tty
    
    if [[ -z "$new_name" ]]; then
        echo -e "${YELLOW}No changes made${RESET}"
        return 0
    fi
    
    # Check if new name already exists
    local existing_id
    existing_id=$(dispatcharr_get_group_id "$new_name")
    
    if [[ -n "$existing_id" ]] && [[ "$existing_id" != "$group_id" ]]; then
        echo -e "${ERROR_STYLE}❌ Group '$new_name' already exists (ID: $existing_id)${RESET}"
        return 1
    fi
    
    # Update the group
    echo -e "${CYAN}Updating group...${RESET}"
    
    local json_data
    json_data=$(jq -n --arg name "$new_name" '{name: $name}')
    
    local response
    response=$(dispatcharr_api_wrapper "PATCH" "/api/channels/groups/$group_id/" "$json_data")
    
    if [[ $? -eq 0 ]]; then
        echo -e "${SUCCESS_STYLE}✅ Group renamed from '$current_name' to '$new_name'${RESET}"
        return 0
    else
        echo -e "${ERROR_STYLE}❌ Failed to update group${RESET}"
        return 1
    fi
}

# Delete a group
dispatcharr_delete_group() {
    echo -e "${HEADER_STYLE}=== Delete Group ===${RESET}\n"
    
    # Check authentication first
    if ! ensure_dispatcharr_auth; then
        echo -e "${ERROR_STYLE}❌ Authentication failed${RESET}"
        return 1
    fi
    
    echo -e "${WARNING_STYLE}⚠️  Warning: Only delete groups that you created${RESET}"
    echo -e "${CYAN}💡 Do not delete groups imported by playlists${RESET}"
    echo
    
    # Get groups assigned to channels
    echo -e "${CYAN}Loading groups assigned to channels...${RESET}"
    local groups
    groups=$(dispatcharr_get_assigned_groups)
    
    if [[ $? -ne 0 ]] || [[ -z "$groups" ]]; then
        echo -e "${ERROR_STYLE}❌ Failed to load groups${RESET}"
        return 1
    fi
    
    local group_count
    group_count=$(echo "$groups" | jq 'length' 2>/dev/null || echo "0")
    
    if [[ "$group_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No groups are currently assigned to any channels${RESET}"
        echo -e "${CYAN}💡 Create channels and assign them to groups first${RESET}"
        return 0
    fi
    
    # Get all channels to show channel counts
    local channels
    channels=$(dispatcharr_get_channels)
    
    # Display groups assigned to channels with channel counts
    echo -e "${SUCCESS_STYLE}✅ Found $group_count groups currently in use${RESET}"
    echo
    echo -e "${BOLD}${BLUE}Groups Currently Assigned to Channels:${RESET}"
    echo "──────────────────────────────────────────────────────────────────────────"
    printf "%-5s %-5s %-30s %-15s\n" "Sel" "ID" "Group Name" "Channels"
    echo "──────────────────────────────────────────────────────────────────────────"
    
    local selection_index=1
    echo "$groups" | jq -r '.[] | "\(.id)\t\(.name // "Unnamed Group")"' | \
    while IFS=$'\t' read -r group_id group_name; do
        # Count channels in this group
        local channel_count=0
        if [[ -n "$channels" && "$channels" != "[]" ]]; then
            channel_count=$(echo "$channels" | jq --arg gid "$group_id" '[.[] | select(.channel_group_id == ($gid | tonumber))] | length' 2>/dev/null || echo "0")
        fi
        
        printf "%-5s %-5s %-30s %-15s\n" "$selection_index" "$group_id" "${group_name:0:30}" "$channel_count"
        ((selection_index++))
    done
    
    echo "──────────────────────────────────────────────────────────────────────────"
    echo
    
    # Select group to delete
    local selected_index
    read -p "Select group to delete (1-$group_count, or 'q' to cancel): " selected_index < /dev/tty
    
    if [[ "$selected_index" =~ ^[qQ]$ ]] || [[ -z "$selected_index" ]]; then
        echo -e "${YELLOW}Cancelled${RESET}"
        return 0
    fi
    
    if ! [[ "$selected_index" =~ ^[0-9]+$ ]] || [[ "$selected_index" -lt 1 ]] || [[ "$selected_index" -gt "$group_count" ]]; then
        echo -e "${ERROR_STYLE}❌ Invalid selection${RESET}"
        return 1
    fi
    
    # Get selected group details
    local selected_group
    selected_group=$(echo "$groups" | jq -r ".[$((selected_index-1))]")
    local group_id=$(echo "$selected_group" | jq -r '.id')
    local group_name=$(echo "$selected_group" | jq -r '.name // "Unnamed Group"')
    
    # Check if group has channels
    local channel_count=0
    if [[ -n "$channels" && "$channels" != "[]" ]]; then
        channel_count=$(echo "$channels" | jq --arg gid "$group_id" '[.[] | select(.channel_group_id == ($gid | tonumber))] | length' 2>/dev/null || echo "0")
    fi
    
    echo
    echo -e "${WARNING_STYLE}⚠️  You are about to delete: $group_name (ID: $group_id)${RESET}"
    
    if [[ "$channel_count" -gt 0 ]]; then
        echo -e "${RED}⚠️  This group has $channel_count channel(s) assigned to it!${RESET}"
        echo -e "${CYAN}💡 Channels will be unassigned from this group if you proceed${RESET}"
    fi
    
    echo
    if ! confirm_action "Are you sure you want to delete this group?"; then
        echo -e "${YELLOW}Cancelled${RESET}"
        return 0
    fi
    
    # Delete the group
    echo -e "${CYAN}Deleting group...${RESET}"
    
    local response
    response=$(dispatcharr_api_wrapper "DELETE" "/api/channels/groups/$group_id/")
    
    if [[ $? -eq 0 ]]; then
        echo -e "${SUCCESS_STYLE}✅ Group '$group_name' deleted successfully${RESET}"
        return 0
    else
        echo -e "${ERROR_STYLE}❌ Failed to delete group${RESET}"
        echo -e "${CYAN}💡 The group may be protected or required by the system${RESET}"
        return 1
    fi
}

# Get next available channel number
dispatcharr_get_next_channel_number() {
    local channels
    channels=$(dispatcharr_get_channels)
    
    if [[ $? -eq 0 ]] && [[ -n "$channels" ]]; then
        # Find the highest channel number and add 1
        local max_number
        max_number=$(echo "$channels" | jq -r 'map(.channel_number // 0) | max' 2>/dev/null)
        
        if [[ -n "$max_number" && "$max_number" != "null" ]]; then
            echo $((max_number + 1))
        else
            echo "1000"  # Default starting number
        fi
    else
        echo "1000"  # Default starting number
    fi
}

# Get group name by ID
dispatcharr_get_group_name() {
    local group_id="$1"
    
    if [[ -z "$group_id" || "$group_id" == "null" ]]; then
        echo "N/A"
        return 1
    fi
    
    # Get all groups
    local groups
    groups=$(dispatcharr_get_groups)
    local get_groups_exit_code=$?
    
    if [[ $get_groups_exit_code -eq 0 ]] && [[ -n "$groups" ]] && [[ "$groups" != "[]" ]]; then
        local group_name
        group_name=$(echo "$groups" | jq -r --arg id "$group_id" '.[] | select(.id == ($id | tonumber)) | .name' 2>/dev/null | head -n 1)
        
        if [[ -n "$group_name" && "$group_name" != "null" ]]; then
            echo "$group_name"
            return 0
        fi
    fi
    
    # Fallback
    echo "Group $group_id"
    return 1
}

# Get group ID from group name (case-insensitive matching)
# Args: $1 - group name
# Returns: group ID on stdout, exit code 0 on success
dispatcharr_get_group_id() {
    local group_name="$1"
    
    if [[ -z "$group_name" ]]; then
        return 1
    fi
    
    local groups
    groups=$(dispatcharr_get_groups)
    local get_groups_exit_code=$?
    
    if [[ $get_groups_exit_code -eq 0 ]] && [[ -n "$groups" ]] && [[ "$groups" != "[]" ]]; then
        local group_id
        group_id=$(echo "$groups" | jq -r --arg name "$group_name" '.[] | select(.name | ascii_downcase == ($name | ascii_downcase)) | .id' 2>/dev/null | head -n 1)
        
        if [[ -n "$group_id" && "$group_id" != "null" ]]; then
            echo "$group_id"
            return 0
        fi
    fi
    
    return 1
}

# ============================================================================
# CHANNEL GROUP CACHING
# ============================================================================

# Global associative array for channel group cache
declare -gA DISPATCHARR_GROUP_CACHE
declare -g DISPATCHARR_GROUP_CACHE_TIME=0
declare -g DISPATCHARR_GROUP_CACHE_TTL=300  # 5 minutes TTL

# Get channel group name with caching
dispatcharr_get_group_name_cached() {
    local group_id="$1"
    
    if [[ -z "$group_id" || "$group_id" == "null" || "$group_id" == "N/A" ]]; then
        echo "N/A"
        return 0
    fi
    
    local current_time=$(date +%s)
    local cache_age=$((current_time - DISPATCHARR_GROUP_CACHE_TIME))
    
    # Check if cache needs refresh
    if [[ $cache_age -gt $DISPATCHARR_GROUP_CACHE_TTL || ${#DISPATCHARR_GROUP_CACHE[@]} -eq 0 ]]; then
        _dispatcharr_log "debug" "Refreshing channel group cache"
        
        # Clear existing cache
        unset DISPATCHARR_GROUP_CACHE
        declare -gA DISPATCHARR_GROUP_CACHE
        
        # Fetch all groups
        local groups
        groups=$(dispatcharr_get_groups)
        
        if [[ $? -eq 0 ]] && [[ -n "$groups" ]] && [[ "$groups" != "[]" ]]; then
            # Populate cache
            while IFS=$'\t' read -r id name; do
                if [[ -n "$id" && "$id" != "null" && -n "$name" && "$name" != "null" ]]; then
                    DISPATCHARR_GROUP_CACHE["$id"]="$name"
                fi
            done < <(echo "$groups" | jq -r '.[] | "\(.id)\t\(.name)"' 2>/dev/null)
            
            DISPATCHARR_GROUP_CACHE_TIME=$current_time
            _dispatcharr_log "debug" "Cached ${#DISPATCHARR_GROUP_CACHE[@]} channel groups"
        else
            _dispatcharr_log "warn" "Failed to refresh channel group cache"
        fi
    fi
    
    # Look up in cache
    if [[ -n "${DISPATCHARR_GROUP_CACHE[$group_id]:-}" ]]; then
        echo "${DISPATCHARR_GROUP_CACHE[$group_id]}"
        return 0
    else
        # Fallback to direct lookup if not in cache
        local group_name
        group_name=$(dispatcharr_get_group_name "$group_id")
        if [[ $? -eq 0 ]]; then
            # Add to cache for future use
            DISPATCHARR_GROUP_CACHE["$group_id"]="$group_name"
            echo "$group_name"
            return 0
        else
            echo "Group $group_id"
            return 1
        fi
    fi
}

# ============================================================================
# ENHANCED ERROR HANDLING AND LOGGING
# ============================================================================

# Module-specific logging function
_dispatcharr_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Use centralized logging system if available, otherwise basic logging
    if declare -f log_${level} >/dev/null 2>&1; then
        log_${level} "dispatcharr" "$message"
    else
        echo "[$timestamp] [${level^^}] [DISPATCHARR] $message" >&2
    fi
}

# ============================================================================
# WORKFLOWS
# ============================================================================

# Apply queued station ID matches from file to Dispatcharr channels
dispatcharr_apply_station_id_matches() {
  _dispatcharr_log "info" "Starting batch station ID application workflow"
  
  echo -e "\n${BOLD}${BLUE}📍 Step 3 of 3: Commit Station ID Changes${RESET}"
  echo -e "${CYAN}This will apply all queued station ID matches to your Dispatcharr channels.${RESET}"
  echo
  
  if [[ ! -f "$DISPATCHARR_MATCHES" ]] || [[ ! -s "$DISPATCHARR_MATCHES" ]]; then
    echo -e "${YELLOW}⚠️  No pending station ID matches found${RESET}"
    echo -e "${CYAN}💡 Run 'Interactive Station ID Matching' first to create matches${RESET}"
    echo -e "${CYAN}💡 Ensure you selected 'Batch Mode' during the matching process${RESET}"
    _dispatcharr_log "warn" "No pending station ID matches found in $DISPATCHARR_MATCHES"
    return 1
  fi
  
  local total_matches
  total_matches=$(wc -l < "$DISPATCHARR_MATCHES")
  
  _dispatcharr_log "info" "Found $total_matches pending station ID matches to process"
  echo -e "${GREEN}✅ Found $total_matches pending station ID matches${RESET}"
  echo
  
  # Show enhanced preview of matches with better formatting
  echo -e "${BOLD}${CYAN}=== Pending Station ID Matches ===${RESET}"
  echo -e "${YELLOW}Preview of changes that will be applied to Dispatcharr:${RESET}"
  echo
  printf "${BOLD}${YELLOW}%-8s %-25s %-12s %-20s %s${RESET}\n" "Ch ID" "Channel Name" "Station ID" "Station Name" "Quality"
  echo "--------------------------------------------------------------------------------"
  
  local line_count=0
  while IFS=$'\t' read -r channel_id channel_name station_id station_name confidence; do
    # Get quality info for the station
    local quality=$(get_station_quality "$station_id")
    
    # Format row with proper alignment
    printf "%-8s %-25s " "$channel_id" "${channel_name:0:25}"
    echo -n -e "${CYAN}${station_id}${RESET}"
    printf "%*s" $((12 - ${#station_id})) ""
    printf "%-20s " "${station_name:0:20}"
    echo -e "${GREEN}${quality}${RESET}"
    
    ((line_count++))
    # Show only first 10 for preview
    [[ $line_count -ge 10 ]] && break
  done < "$DISPATCHARR_MATCHES"
  
  if [[ $total_matches -gt 10 ]]; then
    echo -e "${CYAN}... and $((total_matches - 10)) more matches${RESET}"
  fi
  echo
  
  echo -e "${BOLD}Confirmation Required:${RESET}"
  echo -e "Total matches to apply: ${YELLOW}$total_matches${RESET}"
  echo -e "Target: ${CYAN}Dispatcharr at $DISPATCHARR_URL${RESET}"
  echo -e "Action: ${GREEN}Set station IDs for channel EPG matching${RESET}"
  echo
  
  if ! confirm_action "Apply all $total_matches station ID matches to Dispatcharr?"; then
    echo -e "${YELLOW}⚠️  Batch update cancelled${RESET}"
    echo -e "${CYAN}💡 Matches remain queued - you can commit them later${RESET}"
    _dispatcharr_log "info" "Batch update cancelled by user"
    return 1
  fi
  
  local success_count=0
  local failure_count=0
  local current_item=0

  echo -e "\n${BOLD}${CYAN}=== Applying Station ID Updates ===${RESET}"
  echo -e "${CYAN}🔄 Processing $total_matches updates to Dispatcharr...${RESET}"
  echo
  
  while IFS=$'\t' read -r channel_id channel_name station_id station_name confidence; do
    # Skip empty lines
    [[ -z "$channel_id" ]] && continue
    
    ((current_item++))
    local percent=$((current_item * 100 / total_matches))
    
    # Show progress with channel info
    printf "\r${CYAN}[%3d%%] (%d/%d) Updating: %-25s → %-12s${RESET}" \
      "$percent" "$current_item" "$total_matches" "${channel_name:0:25}" "$station_id"
    
    if dispatcharr_update_channel_station_id "$channel_id" "$station_id"; then
      ((success_count++))
    else
      ((failure_count++))
      echo -e "\n${RED}❌ Failed: $channel_name (ID: $channel_id)${RESET}"
    fi
  done < "$DISPATCHARR_MATCHES"
  
  # Clear progress line
  echo
  echo
  
  # Show comprehensive completion summary
  echo -e "${BOLD}${GREEN}=== Batch Update Results ===${RESET}"
  echo -e "${GREEN}✅ Successfully applied: $success_count station IDs${RESET}"
  
  if [[ $failure_count -gt 0 ]]; then
    echo -e "${RED}❌ Failed to apply: $failure_count station IDs${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr logs for failed update details${RESET}"
  fi
  
  echo -e "${CYAN}📊 Total processed: $((success_count + failure_count)) of $total_matches${RESET}"
  echo
  
  if [[ $success_count -gt 0 ]]; then
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "• Changes are now active in Dispatcharr"
    echo -e "• Channels will use station IDs for EPG matching"
    echo -e "• Consider using 'Populate Other Dispatcharr Fields' to enhance remaining data"
    
    if [[ $failure_count -eq 0 ]]; then
      echo -e "${GREEN}💡 Perfect! All station IDs applied successfully${RESET}"
    fi
  fi
  
  # Clear processed matches
  echo
  echo -e "${CYAN}🧹 Clearing processed matches from queue...${RESET}"
  > "$DISPATCHARR_MATCHES"
  echo -e "${GREEN}✅ Match queue cleared${RESET}"
  
  _dispatcharr_log "info" "Batch station ID application completed: $success_count successful, $failure_count failed"
  
  return 0
}

# ============================================================================
# WORKFLOW FUNCTIONS
# ============================================================================

# Channel creation workflow
dispatcharr_create_channel_workflow() {
    clear
    echo -e "${HEADER_STYLE}=== Create New Channel ===${RESET}\n"
    
    echo -e "${BLUE}Step 1: Search for Station${RESET}"
    echo -e "${CYAN}Enter a search term to find your station${RESET}"
    
    read -p "Search term: " search_term < /dev/tty
    
    if [[ -z "$search_term" ]]; then
        echo -e "${WARNING_STYLE}⚠️  Search term required${RESET}"
        pause_for_user
        return 1
    fi
    
    # Search using the common search function
    echo -e "${CYAN}🔍 Searching for '$search_term'...${RESET}"
    
    # Use the shared station search - this will handle display and selection
    # Don't capture output to allow results to display
    _dispatcharr_full_search_workflow "$search_term"
    local selected_station_data="$DISPATCHARR_SELECTED_STATION"
    
    # Check if a station was selected
    if [[ -z "$selected_station_data" ]]; then
        echo -e "${WARNING_STYLE}⚠️  No station selected${RESET}"
        pause_for_user
        return 1
    fi
    
    # Extract station details
    local station_id=$(echo "$selected_station_data" | jq -r '.stationId // ""')
    local callsign=$(echo "$selected_station_data" | jq -r '.callsign // ""')
    local name=$(echo "$selected_station_data" | jq -r '.name // ""')
    local logo_url=$(echo "$selected_station_data" | jq -r '.logo // ""')
    
    echo -e "${BLUE}Step 2: Channel Configuration${RESET}"
    echo -e "${CYAN}Selected Station:${RESET}"
    echo -e "  Name: ${GREEN}$name${RESET}"
    echo -e "  Callsign: ${GREEN}$callsign${RESET}"
    echo -e "  Station ID: ${GREEN}$station_id${RESET}"
    [[ -n "$logo_url" ]] && echo -e "  Logo: ${GREEN}$logo_url${RESET}"
    echo
    
    # Get channel group
    echo -e "${YELLOW}Channel Group Selection:${RESET}"
    local selected_group_id
    selected_group_id=$(_dispatcharr_select_or_create_group)
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Group selection cancelled${RESET}"
        pause_for_user
        return 1
    fi
    
    # Get channel number
    echo -e "${YELLOW}Channel Number:${RESET}"
    local next_number
    next_number=$(dispatcharr_get_next_channel_number)
    
    read -p "Channel number (press Enter for next available: $next_number): " channel_number < /dev/tty
    
    if [[ -z "$channel_number" ]]; then
        channel_number="$next_number"
    fi
    
    # Validate channel number is numeric
    if ! [[ "$channel_number" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo -e "${RED}❌ Invalid channel number format${RESET}"
        pause_for_user
        return 1
    fi
    
    # Create the channel
    echo -e "${BLUE}Step 4: Creating Channel${RESET}"
    echo -e "${CYAN}Creating channel with the following details:${RESET}"
    echo -e "  Number: ${GREEN}$channel_number${RESET}"
    echo -e "  Name: ${GREEN}$name${RESET}"
    echo -e "  Callsign: ${GREEN}$callsign${RESET}"
    echo -e "  Station ID: ${GREEN}$station_id${RESET}"
    echo -e "  Group ID: ${GREEN}$selected_group_id${RESET}"
    [[ -n "$logo_url" ]] && echo -e "  Logo: ${GREEN}$logo_url${RESET}"
    echo
    
    # Create the channel via API
    # Build channel JSON data
    local channel_json
    channel_json=$(jq -n \
        --arg name "$name" \
        --arg callsign "$callsign" \
        --arg station_id "$station_id" \
        --arg group_id "$selected_group_id" \
        --arg channel_number "$channel_number" \
        --arg logo_url "$logo_url" \
        '{
            name: $name,
            tvg_id: $callsign,
            tvc_guide_stationid: $station_id,
            channel_group_id: ($group_id | tonumber),
            channel_number: ($channel_number | tonumber),
            logo_url: (if $logo_url != "" and $logo_url != "null" then $logo_url else null end)
        }')
    
    local result
    result=$(dispatcharr_create_channel "$channel_json")
    
    if [[ $? -eq 0 ]]; then
        echo -e "${SUCCESS_STYLE}✅ Channel created successfully!${RESET}"
        
        # Ask about stream assignment
        echo
        read -p "Would you like to assign streams to this channel now? (y/N): " assign_streams < /dev/tty
        
        if [[ "$assign_streams" =~ ^[Yy] ]]; then
            # Get the channel ID from the result and manage streams
            local channel_id
            channel_id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null)
            if [[ -n "$channel_id" && "$channel_id" != "null" ]]; then
                echo -e "${CYAN}🔄 Opening stream management...${RESET}"
                _dispatcharr_manage_channel_streams "$result"
            else
                echo -e "${WARNING_STYLE}⚠️  Could not get channel ID for stream management${RESET}"
            fi
        fi
        
        pause_for_user
        return 0
    else
        echo -e "${ERROR_STYLE}❌ Failed to create channel${RESET}"
        echo -e "${CYAN}Response: $result${RESET}"
        pause_for_user
        return 1
    fi
}

# Helper function for full search workflow
_dispatcharr_full_search_workflow() {
    local search_term="$1"
    
    # Load the search module functions if not already loaded
    if ! declare -f shared_station_search >/dev/null 2>&1; then
        if [[ -f "lib/core/search.sh" ]]; then
            source "lib/core/search.sh"
        else
            echo -e "${ERROR_STYLE}❌ Search module not available${RESET}"
            return 1
        fi
    fi
    
    # Perform the search using the existing interactive search system
    # This will handle pagination, display, and selection automatically
    echo
    echo -e "${CYAN}🔍 Searching for: '$search_term'${RESET}"
    echo -e "${YELLOW}Use the search interface to select a station${RESET}"
    echo
    
    # Initialize global variable for result
    DISPATCHARR_SELECTED_STATION=""
    
    # Run the interactive search workflow
    if command -v run_station_search >/dev/null 2>&1; then
        # Use the main search function if available
        local search_result=$(run_station_search "$search_term" "return_json")
        if [[ -n "$search_result" && "$search_result" != "cancelled" ]]; then
            DISPATCHARR_SELECTED_STATION="$search_result"
            return 0
        else
            return 1
        fi
    else
        # Fallback to manual search workflow
        _dispatcharr_manual_search_workflow "$search_term"
        return $?
    fi
}

# Fallback manual search workflow
_dispatcharr_manual_search_workflow() {
    local search_term="$1"
    local current_page=1
    
    while true; do
        # Use shared_station_search with proper format
        local results
        results=$(shared_station_search "$search_term" "$current_page" "full")
        
        if [[ -z "$results" ]]; then
            echo -e "${WARNING_STYLE}⚠️  No results found${RESET}"
            return 1
        fi
        
        # Get total results count for display
        local total_results=$(shared_station_search "$search_term" "1" "count")
        
        # Display results using the common display function
        display_search_results "$search_term" "$current_page" "$results" "$total_results" "25"
        
        # Handle user selection
        local selection
        read -p "Select station (number), 'n' for next page, 'p' for previous, '#' to jump to page, 'q' to quit: " selection < /dev/tty
        
        case "$selection" in
            q|Q)
                DISPATCHARR_SELECTED_STATION=""
                return 1
                ;;
            n|N)
                ((current_page++))
                ;;
            p|P)
                if [[ $current_page -gt 1 ]]; then
                    ((current_page--))
                fi
                ;;
            '#')
                echo -e "${CYAN}Jump to Page${RESET}"
                local total_count=$(shared_station_search "$search_term" "1" "count")
                local total_pages=$(( (total_count + 24) / 25 ))
                echo -e "${INFO_STYLE}Current page: $current_page of $total_pages${RESET}"
                read -p "Enter page number (1-$total_pages): " target_page < /dev/tty
                
                if [[ "$target_page" =~ ^[0-9]+$ ]] && [[ "$target_page" -ge 1 ]] && [[ "$target_page" -le "$total_pages" ]]; then
                    current_page="$target_page"
                    echo -e "${SUCCESS_STYLE}✅ Jumped to page $current_page${RESET}"
                    sleep 1
                else
                    echo -e "${ERROR_STYLE}❌ Invalid page number. Must be between 1 and $total_pages${RESET}"
                    sleep 2
                fi
                ;;
            [0-9]*|[a-j]|[A-J])
                # Convert letter selection to line number
                local line_number
                case "$selection" in
                    [aA]) line_number=1 ;;
                    [bB]) line_number=2 ;;
                    [cC]) line_number=3 ;;
                    [dD]) line_number=4 ;;
                    [eE]) line_number=5 ;;
                    [fF]) line_number=6 ;;
                    [gG]) line_number=7 ;;
                    [hH]) line_number=8 ;;
                    [iI]) line_number=9 ;;
                    [jJ]) line_number=10 ;;
                    *) line_number="$selection" ;;
                esac
                
                # Extract the selected station data from the TSV results
                local selected_line
                selected_line=$(echo "$results" | sed -n "${line_number}p")
                
                if [[ -n "$selected_line" ]]; then
                    # Parse TSV format: name, callsign, quality, stationId, country
                    local station_name=$(echo "$selected_line" | cut -f1)
                    local callsign=$(echo "$selected_line" | cut -f2)
                    local quality=$(echo "$selected_line" | cut -f3)
                    local station_id=$(echo "$selected_line" | cut -f4)
                    local country=$(echo "$selected_line" | cut -f5)
                    
                    # Build JSON object
                    local station_json
                    station_json=$(jq -n \
                        --arg name "$station_name" \
                        --arg callsign "$callsign" \
                        --arg stationId "$station_id" \
                        --arg quality "$quality" \
                        --arg country "$country" \
                        '{
                            name: $name,
                            callsign: $callsign,
                            stationId: $stationId,
                            quality: $quality,
                            country: $country,
                            logo: ""
                        }')
                    
                    # Set global variable for result
                    DISPATCHARR_SELECTED_STATION="$station_json"
                    return 0
                fi
                ;;
        esac
    done
}

# Helper function to select or create a group
_dispatcharr_select_or_create_group() {
    echo -e "${CYAN}Loading assigned groups...${RESET}" >&2
    
    local groups
    groups=$(dispatcharr_get_assigned_groups)
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Failed to load groups${RESET}" >&2
        return 1
    fi
    
    local group_count
    group_count=$(echo "$groups" | jq 'length' 2>/dev/null || echo "0")
    
    if [[ "$group_count" -gt 0 ]]; then
        echo -e "${CYAN}Assigned Groups (currently in use):${RESET}" >&2
        echo "─────────────────────────────────────────" >&2
        
        # Display groups with proper numbering (avoid subshell issue)
        local i
        for ((i=1; i<=group_count; i++)); do
            local group_name
            group_name=$(echo "$groups" | jq -r ".[$((i-1))].name" 2>/dev/null)
            printf "${GREEN}%2d)${RESET} %s\n" "$i" "$group_name" >&2
        done
        
        local create_option=$((group_count + 1))
        printf "${GREEN}%2d)${RESET} Create new group\n" "$create_option" >&2
        echo "─────────────────────────────────────────" >&2
        echo >&2
        
        read -p "Select group (1-$create_option), enter group name, or 'q' to cancel: " selection < /dev/tty
        
        if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
            return 1
        fi
        
        if [[ "$selection" == "$create_option" ]]; then
            # Create new group
            _dispatcharr_create_group_inline
            return $?
        elif [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$group_count" ]]; then
            # Select existing group by number
            local selected_group_id
            selected_group_id=$(echo "$groups" | jq -r ".[$((selection-1))].id" 2>/dev/null)
            
            if [[ -n "$selected_group_id" && "$selected_group_id" != "null" ]]; then
                echo "$selected_group_id"
                return 0
            else
                echo -e "${RED}❌ Failed to get group ID${RESET}" >&2
                return 1
            fi
        else
            # Try to match by group name (case-insensitive)
            local selected_group_id
            selected_group_id=$(dispatcharr_get_group_id "$selection")
            
            if [[ -n "$selected_group_id" && "$selected_group_id" != "null" ]]; then
                echo -e "${GREEN}✅ Found group: $selection${RESET}" >&2
                echo "$selected_group_id"
                return 0
            else
                echo -e "${RED}❌ No group found with name '$selection'${RESET}" >&2
                echo -e "${CYAN}💡 Available groups:${RESET}" >&2
                echo "$groups" | jq -r '.[] | "  - " + .name' 2>/dev/null >&2
                return 1
            fi
        fi
    else
        echo -e "${YELLOW}⚠️  No groups found. Creating one is required.${RESET}" >&2
        _dispatcharr_create_group_inline
        return $?
    fi
}

# Helper function to create a group inline during channel creation
_dispatcharr_create_group_inline() {
    echo
    echo -e "${CYAN}Creating New Channel Group${RESET}"
    
    read -p "Group name: " group_name < /dev/tty
    
    if [[ -z "$group_name" ]]; then
        echo -e "${RED}❌ Group name is required${RESET}"
        return 1
    fi
    
    # Build JSON for group creation
    local json_data
    json_data=$(jq -n --arg name "$group_name" '{"name": $name}')
    
    local response
    response=$(dispatcharr_api_wrapper "POST" "/api/channels/groups/" "$json_data")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        local group_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        if [[ -n "$group_id" && "$group_id" != "null" ]]; then
            echo -e "${GREEN}✅ Created group: $group_name (ID: $group_id)${RESET}"
            echo "$group_id"
            return 0
        else
            echo -e "${RED}❌ Failed to create group - no ID returned${RESET}"
            return 1
        fi
    else
        echo -e "${RED}❌ Failed to create channel group${RESET}"
        return 1
    fi
}

# Main workflow for managing existing channels
dispatcharr_manage_channels_workflow() {
    while true; do
        clear
        echo -e "${HEADER_STYLE}=== Manage Existing Channels ===${RESET}\n"
        
        # Load/refresh existing channels
        echo -e "${BLUE}Loading Existing Channels${RESET}"
        echo -e "${CYAN}Fetching channels from Dispatcharr...${RESET}"
        
        local channels
        channels=$(dispatcharr_get_channels)
        
        if [[ $? -eq 0 ]] && [[ -n "$channels" ]]; then
            local channel_count=$(echo "$channels" | jq 'length' 2>/dev/null || echo "0")
            
            if [[ "$channel_count" -eq 0 ]]; then
                echo -e "${WARNING_STYLE}⚠️  No channels found in Dispatcharr${RESET}"
                echo -e "${CYAN}💡 Create some channels first before trying to manage them${RESET}"
                pause_for_user
                return 0
            fi
            
            echo -e "${SUCCESS_STYLE}✅ Found $channel_count channels${RESET}"
            echo
            
            # Select and manage channel
            local selection_result
            _dispatcharr_select_channel_for_management "$channels"
            selection_result=$?
            
            # If selection was cancelled (q pressed), exit the workflow
            if [[ $selection_result -eq 1 ]]; then
                return 0
            fi
            
            # Otherwise, loop continues to refresh the channel list
        else
            echo -e "${ERROR_STYLE}❌ Failed to fetch channels from Dispatcharr${RESET}"
            pause_for_user
            return 1
        fi
    done
}

# Helper function to select a channel for management
_dispatcharr_select_channel_for_management() {
    local channels="$1"
    
    # Get total channel count
    local total_channels
    total_channels=$(echo "$channels" | jq 'length' 2>/dev/null || echo "0")
    
    if [[ "$total_channels" -eq 0 ]]; then
        echo -e "${WARNING_STYLE}⚠️  No channels found${RESET}"
        pause_for_user
        return 0
    fi
    
    # Pagination settings
    local results_per_page=20
    local current_page=1
    local total_pages=$(((total_channels + results_per_page - 1) / results_per_page))
    
    while true; do
        clear
        echo -e "${HEADER_STYLE}=== Manage Existing Channels ===${RESET}"
        echo -e "${INFO_STYLE}Total: $total_channels channels | Page $current_page of $total_pages${RESET}"
        echo
        
        # Calculate offset for current page
        local start_index=$(((current_page - 1) * results_per_page))
        local end_index=$((start_index + results_per_page - 1))
        
        echo -e "${SUBHEADER_STYLE}Available Channels (Page $current_page/$total_pages):${RESET}"
        echo "────────────────────────────────────────────────────────────────────────────────────────────"
        printf "${MENU_OPTION_STYLE}%-3s %-6s %-25s %-20s %-15s %s${RESET}\n" "Sel" "Ch#" "Name" "TVG-ID" "Station ID" "Group"
        echo "────────────────────────────────────────────────────────────────────────────────────────────"
        
        local display_index=1
        local page_channel_data=()
        
        # Get channels for current page
        for ((i = start_index; i <= end_index && i < total_channels; i++)); do
            local channel_data
            channel_data=$(echo "$channels" | jq ".[$i]" 2>/dev/null)
            if [[ -n "$channel_data" && "$channel_data" != "null" ]]; then
                page_channel_data+=("$channel_data")
                
                local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
                local channel_name=$(echo "$channel_data" | jq -r '.name // "Unknown"')
                local tvg_id=$(echo "$channel_data" | jq -r '.tvg_id // "N/A"')
                local station_id=$(echo "$channel_data" | jq -r '.tvc_guide_stationid // "N/A"')
                local group_id=$(echo "$channel_data" | jq -r '.channel_group // .channel_group_id // "N/A"')
                
                # Get group name if we have a group ID
                local group_name="N/A"
                if [[ "$group_id" != "N/A" && "$group_id" != "null" ]]; then
                    group_name=$(dispatcharr_get_group_name "$group_id" 2>/dev/null || echo "Group $group_id")
                fi
                
                printf "%-3s %-6s %-25s %-20s %-15s %s\n" \
                    "$display_index" \
                    "$channel_number" \
                    "${channel_name:0:25}" \
                    "${tvg_id:0:20}" \
                    "${station_id:0:15}" \
                    "${group_name:0:20}"
                ((display_index++))
            fi
        done
        
        echo "────────────────────────────────────────────────────────────────────────────────────────────"
        echo
        
        # Navigation and selection options
        echo -e "${MENU_OPTION_STYLE}Channel Management Options:${RESET}"
        echo "• Enter a number (1-$((display_index-1))) to manage that channel"
        echo "• 'g' - Batch assign group to multiple channels"
        if [[ $current_page -lt $total_pages ]]; then
            echo "• 'n' or 'next' - Go to next page"
        fi
        if [[ $current_page -gt 1 ]]; then
            echo "• 'p' - Go to previous page"
        fi
        echo "• '#' - Jump to specific page"
        echo "• 'q' or 'quit' - Return to main menu"
        echo
        
        read -p "Selection (number/g/n/p/#/q): " input < /dev/tty
        
        case "$input" in
            q|quit)
                return 1  # Signal to main workflow to exit
                ;;
            n|next)
                if [[ $current_page -lt $total_pages ]]; then
                    ((current_page++))
                else
                    echo -e "${WARNING_STYLE}⚠️  Already on last page${RESET}"
                    sleep 1
                fi
                ;;
            p)
                if [[ $current_page -gt 1 ]]; then
                    ((current_page--))
                else
                    echo -e "${WARNING_STYLE}⚠️  Already on first page${RESET}"
                    sleep 1
                fi
                ;;
            '#')
                echo -e "${CYAN}Jump to Page${RESET}"
                echo -e "${INFO_STYLE}Current page: $current_page of $total_pages${RESET}"
                read -p "Enter page number (1-$total_pages): " target_page < /dev/tty
                
                if [[ "$target_page" =~ ^[0-9]+$ ]] && [[ "$target_page" -ge 1 ]] && [[ "$target_page" -le "$total_pages" ]]; then
                    current_page="$target_page"
                    echo -e "${SUCCESS_STYLE}✅ Jumped to page $current_page${RESET}"
                    sleep 1
                else
                    echo -e "${ERROR_STYLE}❌ Invalid page number. Must be between 1 and $total_pages${RESET}"
                    sleep 2
                fi
                ;;
            g|G)
                # Batch group assignment
                _dispatcharr_batch_assign_group "$channels"
                return 0  # Return to refresh the channel list
                ;;
            "")
                # Empty input - show warning
                echo -e "${WARNING_STYLE}⚠️  Please make a selection or press 'q' to return to main menu${RESET}"
                sleep 1
                ;;
            *)
                # Process channel selection
                if [[ "$input" =~ ^[0-9]+$ ]] && [[ "$input" -ge 1 ]] && [[ "$input" -le ${#page_channel_data[@]} ]]; then
                    local selected_channel="${page_channel_data[$((input-1))]}"
                    _dispatcharr_channel_management_menu "$selected_channel"
                    # Return to main workflow to refresh channel list
                    return 0
                else
                    echo -e "${ERROR_STYLE}❌ Invalid selection. Enter a number between 1 and ${#page_channel_data[@]}, or use navigation commands.${RESET}"
                    sleep 1
                fi
                ;;
        esac
    done
}

# Batch assign group to multiple channels
_dispatcharr_batch_assign_group() {
    local all_channels="$1"
    
    clear
    echo -e "${HEADER_STYLE}=== Batch Assign Group to Channels ===${RESET}\n"
    
    # First, select the group to assign
    echo -e "${INFO_STYLE}Step 1: Select the group to assign${RESET}"
    echo
    
    local selected_group_id
    selected_group_id=$(_dispatcharr_select_or_create_group)
    
    if [[ $? -ne 0 || -z "$selected_group_id" ]]; then
        echo -e "${YELLOW}Group selection cancelled${RESET}"
        pause_for_user
        return 0
    fi
    
    local group_name=$(dispatcharr_get_group_name "$selected_group_id")
    echo
    echo -e "${SUCCESS_STYLE}✅ Selected group: $group_name (ID: $selected_group_id)${RESET}"
    echo
    pause_for_user
    
    # Now use multipage selection interface similar to stream assignment
    _dispatcharr_multipage_channel_group_assignment "$all_channels" "$selected_group_id" "$group_name"
}

# New multipage channel group assignment function based on stream assignment workflow
_dispatcharr_multipage_channel_group_assignment() {
    local all_channels="$1"
    local selected_group_id="$2"
    local group_name="$3"
    
    local total_channels=$(echo "$all_channels" | jq 'length' 2>/dev/null || echo "0")
    local current_page=1
    local channels_per_page=25
    local total_pages=$(((total_channels + channels_per_page - 1) / channels_per_page))
    local selected_channels=()  # Array to store selected channel IDs
    
    while true; do
        clear
        echo -e "${HEADER_STYLE}=== Batch Assign Group: $group_name ===${RESET}\n"
        echo -e "${INFO_STYLE}Page $current_page of $total_pages • Total Channels: $total_channels${RESET}"
        echo
        
        local start=$(((current_page - 1) * channels_per_page))
        local end=$((start + channels_per_page - 1))
        
        echo "────────────────────────────────────────────────────────────────────────────────"
        printf "%-4s %-6s %-30s %-20s %-8s\n" "Sel" "Ch#" "Name" "Current Group" "Status"
        echo "────────────────────────────────────────────────────────────────────────────────"
        
        local display_index=1
        for ((i = start; i <= end && i < total_channels; i++)); do
            local channel=$(echo "$all_channels" | jq ".[$i]" 2>/dev/null)
            if [[ -n "$channel" && "$channel" != "null" ]]; then
                local ch_id=$(echo "$channel" | jq -r '.id // ""')
                local ch_number=$(echo "$channel" | jq -r '.channel_number // "N/A"')
                local ch_name=$(echo "$channel" | jq -r '.name // "Unknown"')
                local current_group_id=$(echo "$channel" | jq -r '.channel_group_id // "N/A"')
                
                local current_group_name="N/A"
                if [[ "$current_group_id" != "N/A" && "$current_group_id" != "null" ]]; then
                    current_group_name=$(dispatcharr_get_group_name "$current_group_id" 2>/dev/null || echo "Group $current_group_id")
                fi
                
                # Check if channel is selected
                local selection_status=" "
                for selected_id in "${selected_channels[@]}"; do
                    if [[ "$selected_id" == "$ch_id" ]]; then
                        selection_status="✓"
                        break
                    fi
                done
                
                printf "%-4s %-6s %-30s %-20s %-8s\n" \
                    "$display_index" \
                    "$ch_number" \
                    "${ch_name:0:30}" \
                    "${current_group_name:0:20}" \
                    "$selection_status"
                ((display_index++))
            fi
        done
        
        echo "────────────────────────────────────────────────────────────────────────────────"
        echo -e "${INFO_STYLE}Selected channels: ${#selected_channels[@]}${RESET}"
        echo
        echo -e "${MENU_OPTION_STYLE}Options:${RESET}"
        echo -e "${CYAN}[1-$channels_per_page])${RESET} Toggle channel selection"
        echo -e "${CYAN}n)${RESET} Next page  ${CYAN}p)${RESET} Previous page  ${CYAN}#)${RESET} Jump to page"
        echo -e "${CYAN}r)${RESET} Reset selections  ${CYAN}a)${RESET} Select all on current page"
        echo -e "${CYAN}c)${RESET} Commit selected channels  ${CYAN}q)${RESET} Cancel"
        echo
        
        read -p "Select option: " choice < /dev/tty
        
        case "$choice" in
            [1-9]|[12][0-9]|[3][0-5])
                # Toggle channel selection
                local channel_index=$((start + choice - 1))
                if [[ $channel_index -lt $total_channels ]]; then
                    local channel=$(echo "$all_channels" | jq ".[$channel_index]" 2>/dev/null)
                    local selected_channel_id=$(echo "$channel" | jq -r '.id // ""')
                    
                    if [[ -n "$selected_channel_id" ]]; then
                        # Check if already selected
                        local already_selected=false
                        local new_selected_channels=()
                        
                        for selected_id in "${selected_channels[@]}"; do
                            if [[ "$selected_id" == "$selected_channel_id" ]]; then
                                already_selected=true
                            else
                                new_selected_channels+=("$selected_id")
                            fi
                        done
                        
                        if [[ "$already_selected" == "false" ]]; then
                            selected_channels+=("$selected_channel_id")
                            echo -e "${SUCCESS_STYLE}✅ Added channel to selection${RESET}"
                        else
                            selected_channels=("${new_selected_channels[@]}")
                            echo -e "${WARNING_STYLE}⚠️  Removed channel from selection${RESET}"
                        fi
                        sleep 1
                    else
                        echo -e "${ERROR_STYLE}❌ Invalid channel selection${RESET}"
                        sleep 1
                    fi
                else
                    echo -e "${ERROR_STYLE}❌ Invalid channel number${RESET}"
                    sleep 1
                fi
                ;;
            n|N)
                if [[ $current_page -lt $total_pages ]]; then
                    ((current_page++))
                else
                    echo -e "${WARNING_STYLE}⚠️  Already on last page${RESET}"
                    sleep 1
                fi
                ;;
            p|P)
                if [[ $current_page -gt 1 ]]; then
                    ((current_page--))
                else
                    echo -e "${WARNING_STYLE}⚠️  Already on first page${RESET}"
                    sleep 1
                fi
                ;;
            '#')
                echo -e "${CYAN}Jump to Page${RESET}"
                echo -e "${INFO_STYLE}Current page: $current_page of $total_pages${RESET}"
                read -p "Enter page number (1-$total_pages): " target_page < /dev/tty
                
                if [[ "$target_page" =~ ^[0-9]+$ ]] && [[ "$target_page" -ge 1 ]] && [[ "$target_page" -le "$total_pages" ]]; then
                    current_page="$target_page"
                    echo -e "${SUCCESS_STYLE}✅ Jumped to page $current_page${RESET}"
                    sleep 1
                else
                    echo -e "${ERROR_STYLE}❌ Invalid page number. Must be between 1 and $total_pages${RESET}"
                    sleep 2
                fi
                ;;
            a|A)
                # Select all channels on current page
                local page_selections_added=0
                for ((i = start; i <= end && i < total_channels; i++)); do
                    local channel=$(echo "$all_channels" | jq ".[$i]" 2>/dev/null)
                    local ch_id=$(echo "$channel" | jq -r '.id // ""')
                    
                    if [[ -n "$ch_id" ]]; then
                        # Check if not already selected
                        local already_selected=false
                        for selected_id in "${selected_channels[@]}"; do
                            if [[ "$selected_id" == "$ch_id" ]]; then
                                already_selected=true
                                break
                            fi
                        done
                        
                        if [[ "$already_selected" == "false" ]]; then
                            selected_channels+=("$ch_id")
                            ((page_selections_added++))
                        fi
                    fi
                done
                
                if [[ $page_selections_added -gt 0 ]]; then
                    echo -e "${SUCCESS_STYLE}✅ Added $page_selections_added channels from current page${RESET}"
                else
                    echo -e "${INFO_STYLE}ℹ️  All channels on current page already selected${RESET}"
                fi
                sleep 1
                ;;
            r|R)
                selected_channels=()
                echo -e "${INFO_STYLE}ℹ️  Selections reset${RESET}"
                sleep 1
                ;;
            c|C)
                if [[ ${#selected_channels[@]} -gt 0 ]]; then
                    echo -e "${CYAN}🔄 Committing ${#selected_channels[@]} selected channels to group '$group_name'...${RESET}"
                    local success_count=0
                    local failed_count=0
                    
                    for channel_id in "${selected_channels[@]}"; do
                        if dispatcharr_assign_channel_to_group "$channel_id" "$selected_group_id"; then
                            ((success_count++))
                        else
                            ((failed_count++))
                        fi
                    done
                    
                    echo -e "${SUCCESS_STYLE}✅ Successfully assigned $success_count channels to group '$group_name'${RESET}"
                    if [[ $failed_count -gt 0 ]]; then
                        echo -e "${ERROR_STYLE}❌ Failed to assign $failed_count channels${RESET}"
                    fi
                    pause_for_user
                    return 0
                else
                    echo -e "${WARNING_STYLE}⚠️  No channels selected${RESET}"
                    sleep 1
                fi
                ;;
            q|Q)
                echo -e "${YELLOW}Batch assignment cancelled${RESET}"
                pause_for_user
                return 0
                ;;
            *)
                echo -e "${WARNING_STYLE}⚠️  Invalid option${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Process batch group assignment
_dispatcharr_process_batch_assignment() {
    local all_channels="$1"
    local group_id="$2"
    local selection="$3"
    
    local group_name=$(dispatcharr_get_group_name "$group_id")
    local selected_indices=()
    
    if [[ "$selection" == "all" ]]; then
        # Select all channels
        local total=$(echo "$all_channels" | jq 'length')
        for ((i = 0; i < total; i++)); do
            selected_indices+=("$i")
        done
    else
        # Parse selection ranges and individual numbers
        IFS=',' read -ra parts <<< "$selection"
        for part in "${parts[@]}"; do
            part=$(echo "$part" | tr -d ' ')  # Remove spaces
            if [[ "$part" =~ ^[0-9]+$ ]]; then
                # Single number (display index, so subtract 1 for array index)
                selected_indices+=($((part - 1)))
            elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                # Range
                local start=$((${BASH_REMATCH[1]} - 1))
                local end=$((${BASH_REMATCH[2]} - 1))
                for ((i = start; i <= end; i++)); do
                    selected_indices+=("$i")
                done
            fi
        done
    fi
    
    # Remove duplicates and sort
    selected_indices=($(printf "%s\n" "${selected_indices[@]}" | sort -nu))
    
    local total_selected=${#selected_indices[@]}
    if [[ $total_selected -eq 0 ]]; then
        echo -e "${ERROR_STYLE}❌ No valid channels selected${RESET}"
        pause_for_user
        return 1
    fi
    
    echo
    echo -e "${INFO_STYLE}Assigning group '$group_name' to $total_selected channels...${RESET}"
    echo
    
    local success_count=0
    local fail_count=0
    
    for idx in "${selected_indices[@]}"; do
        local channel=$(echo "$all_channels" | jq ".[$idx]" 2>/dev/null)
        if [[ -n "$channel" && "$channel" != "null" ]]; then
            local channel_id=$(echo "$channel" | jq -r '.id')
            local channel_name=$(echo "$channel" | jq -r '.name // "Unknown"')
            
            echo -n "Updating $channel_name... "
            
            # Build update JSON with just the group ID
            local update_json=$(jq -n --arg group_id "$group_id" '{
                "channel_group_id": ($group_id | tonumber)
            }')
            
            if dispatcharr_update_channel "$channel_id" "$update_json" >/dev/null 2>&1; then
                echo -e "${GREEN}✅${RESET}"
                ((success_count++))
            else
                echo -e "${RED}❌${RESET}"
                ((fail_count++))
            fi
        fi
    done
    
    echo
    echo -e "${INFO_STYLE}Batch assignment complete:${RESET}"
    echo -e "${GREEN}✅ Success: $success_count channels${RESET}"
    if [[ $fail_count -gt 0 ]]; then
        echo -e "${RED}❌ Failed: $fail_count channels${RESET}"
    fi
    
    pause_for_user
}

# Channel management menu for a specific channel
_dispatcharr_channel_management_menu() {
    local channel_data="$1"
    local channel_id=$(echo "$channel_data" | jq -r '.id')
    local channel_name=$(echo "$channel_data" | jq -r '.name // "Unknown"')
    
    while true; do
        clear
        echo -e "${HEADER_STYLE}=== Channel Management: $channel_name ===${RESET}\n"
        
        # Show channel details
        _dispatcharr_show_channel_details "$channel_data"
        echo
        
        echo -e "${MENU_OPTION_STYLE}Channel Management Options:${RESET}"
        echo -e "${CYAN}1)${RESET} Edit Channel Details"
        echo -e "${CYAN}2)${RESET} Manage Streams"
        echo -e "${CYAN}3)${RESET} Update from Search"
        echo -e "${CYAN}4)${RESET} Delete Channel"
        echo -e "${CYAN}q)${RESET} Back to Channel List"
        echo
        
        read -p "Select option: " choice < /dev/tty
        
        case $choice in
            1)
                _dispatcharr_edit_channel_details "$channel_data"
                # Refresh channel data after edit
                channel_data=$(dispatcharr_get_channel "$channel_id")
                ;;
            2)
                _dispatcharr_manage_channel_streams "$channel_data"
                ;;
            3)
                _dispatcharr_update_channel_from_search "$channel_data"
                # Refresh channel data after update
                channel_data=$(dispatcharr_get_channel "$channel_id")
                ;;
            4)
                if _dispatcharr_delete_channel_confirm "$channel_data"; then
                    return 0  # Channel deleted, return to channel list
                fi
                ;;
            q|Q|"")
                return 0
                ;;
            *)
                echo -e "${ERROR_STYLE}❌ Invalid selection${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Show channel details
_dispatcharr_show_channel_details() {
    local channel_data="$1"
    
    echo -e "${YELLOW}Current Channel Information:${RESET}"
    echo "────────────────────────────────────────────────────────────────────"
    
    local id=$(echo "$channel_data" | jq -r '.id // "N/A"')
    local name=$(echo "$channel_data" | jq -r '.name // "N/A"')
    local number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
    local tvg_id=$(echo "$channel_data" | jq -r '.tvg_id // "N/A"')
    local station_id=$(echo "$channel_data" | jq -r '.tvc_guide_stationid // "N/A"')
    local group_id=$(echo "$channel_data" | jq -r '.channel_group_id // "N/A"')
    local logo_url=$(echo "$channel_data" | jq -r '.logo_url // "N/A"')
    
    # Get group name if available
    local group_name="N/A"
    if [[ "$group_id" != "N/A" && "$group_id" != "null" ]]; then
        group_name=$(dispatcharr_get_group_name "$group_id" 2>/dev/null || echo "Group $group_id")
    fi
    
    printf "%-15s: %s\n" "ID" "$id"
    printf "%-15s: %s\n" "Name" "$name"
    printf "%-15s: %s\n" "Channel Number" "$number"
    printf "%-15s: %s\n" "TVG-ID" "$tvg_id"
    printf "%-15s: %s\n" "Station ID" "$station_id"
    printf "%-15s: %s\n" "Group" "$group_name"
    printf "%-15s: %s\n" "Logo URL" "$logo_url"
    
    echo "────────────────────────────────────────────────────────────────────"
}

# Edit channel details
_dispatcharr_edit_channel_details() {
    local channel_data="$1"
    local channel_id=$(echo "$channel_data" | jq -r '.id')
    
    clear
    echo -e "${HEADER_STYLE}=== Edit Channel Details ===${RESET}\n"
    
    # Display current values
    local current_name=$(echo "$channel_data" | jq -r '.name // ""')
    local current_number=$(echo "$channel_data" | jq -r '.channel_number // ""')
    local current_tvg_id=$(echo "$channel_data" | jq -r '.tvg_id // ""')
    local current_station_id=$(echo "$channel_data" | jq -r '.tvc_guide_stationid // ""')
    local current_group_id=$(echo "$channel_data" | jq -r '.channel_group_id // ""')
    
    # Get current group name
    local current_group_name="N/A"
    if [[ -n "$current_group_id" && "$current_group_id" != "null" ]]; then
        current_group_name=$(dispatcharr_get_group_name "$current_group_id")
    fi
    
    echo -e "${INFO_STYLE}Current channel information:${RESET}"
    echo -e "Name: ${CYAN}$current_name${RESET}"
    echo -e "Number: ${CYAN}$current_number${RESET}"
    echo -e "TVG-ID: ${CYAN}$current_tvg_id${RESET}"
    echo -e "Station ID: ${CYAN}$current_station_id${RESET}"
    echo -e "Group: ${CYAN}$current_group_name${RESET}"
    echo
    
    # Prompt for new values
    echo -e "${INFO_STYLE}Enter new values (press Enter to keep current value):${RESET}"
    echo
    
    # Channel name
    read -p "Channel name [$current_name]: " new_name
    [[ -z "$new_name" ]] && new_name="$current_name"
    
    # Channel number
    read -p "Channel number [$current_number]: " new_number
    [[ -z "$new_number" ]] && new_number="$current_number"
    
    # TVG-ID
    read -p "TVG-ID [$current_tvg_id]: " new_tvg_id
    [[ -z "$new_tvg_id" ]] && new_tvg_id="$current_tvg_id"
    
    # Group selection
    echo
    echo -e "${INFO_STYLE}Current group: ${CYAN}$current_group_name${RESET}"
    echo -e "Select new group (press Enter to keep current):"
    
    local new_group_id="$current_group_id"
    selected_group_id=$(_dispatcharr_select_or_create_group)
    if [[ $? -eq 0 && -n "$selected_group_id" ]]; then
        new_group_id="$selected_group_id"
    fi
    
    # Build update JSON
    local update_json=$(jq -n \
        --arg name "$new_name" \
        --arg number "$new_number" \
        --arg tvg_id "$new_tvg_id" \
        --arg group_id "$new_group_id" \
        '{
            "name": $name,
            "channel_number": $number,
            "tvg_id": $tvg_id,
            "channel_group_id": ($group_id | tonumber)
        }')
    
    # Confirm changes
    echo
    echo -e "${INFO_STYLE}Summary of changes:${RESET}"
    echo -e "Name: ${CYAN}$current_name${RESET} → ${GREEN}$new_name${RESET}"
    echo -e "Number: ${CYAN}$current_number${RESET} → ${GREEN}$new_number${RESET}"
    echo -e "TVG-ID: ${CYAN}$current_tvg_id${RESET} → ${GREEN}$new_tvg_id${RESET}"
    
    local new_group_name=$(dispatcharr_get_group_name "$new_group_id")
    echo -e "Group: ${CYAN}$current_group_name${RESET} → ${GREEN}$new_group_name${RESET}"
    echo
    
    read -p "Apply these changes? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Updating channel...${RESET}"
        
        if dispatcharr_update_channel "$channel_id" "$update_json"; then
            echo -e "${GREEN}✅ Channel updated successfully${RESET}"
        else
            echo -e "${RED}❌ Failed to update channel${RESET}"
        fi
    else
        echo -e "${YELLOW}Changes cancelled${RESET}"
    fi
    
    pause_for_user
}

# Manage channel streams
_dispatcharr_manage_channel_streams() {
    local channel_data="$1"
    local channel_id=$(echo "$channel_data" | jq -r '.id')
    local channel_name=$(echo "$channel_data" | jq -r '.name // "Unknown"')
    
    while true; do
        clear
        echo -e "${HEADER_STYLE}=== Manage Streams: $channel_name ===${RESET}\n"
        
        echo -e "${CYAN}Loading current streams...${RESET}"
        local current_streams
        current_streams=$(dispatcharr_get_channel_streams "$channel_id")
        
        if [[ $? -eq 0 ]]; then
            local stream_count=$(echo "$current_streams" | jq 'length' 2>/dev/null || echo "0")
            
            echo -e "${SUBHEADER_STYLE}Current Streams ($stream_count):${RESET}"
            echo "────────────────────────────────────────────────────────────────────"
            
            if [[ "$stream_count" -gt 0 ]]; then
                printf "%-5s %-30s %-40s %-20s\n" "ID" "Name" "URL Preview" "Channel Group"
                echo "────────────────────────────────────────────────────────────────────────────────────────────"
                echo "$current_streams" | jq -r '.[] | "\(.id // "N/A")\t\(.name // "Unknown")\t\(.url // "N/A")\t\(.channel_group // "N/A")"' | \
                while IFS=$'\t' read -r stream_id stream_name stream_url channel_group; do
                    # Create URL preview (first 40 chars)
                    local url_preview="${stream_url:0:40}"
                    [[ ${#stream_url} -gt 40 ]] && url_preview="${url_preview}..."
                    
                    # Get channel group name
                    local group_name
                    group_name=$(dispatcharr_get_group_name_cached "$channel_group")
                    
                    printf "%-5s %-30s %-40s %-20s\n" "$stream_id" "${stream_name:0:30}" "$url_preview" "${group_name:0:20}"
                done
            else
                echo "No streams currently assigned to this channel"
            fi
            
            echo "────────────────────────────────────────────────────────────────────"
            echo
            
            echo -e "${MENU_OPTION_STYLE}Stream Management Options:${RESET}"
            echo -e "${CYAN}1)${RESET} Add Streams (search and select)"
            echo -e "${CYAN}2)${RESET} Remove Streams"
            echo -e "${CYAN}q)${RESET} Back to Channel Management"
            echo
            
            read -p "Select option: " choice < /dev/tty
            
            case $choice in
                1)
                    _dispatcharr_add_streams_workflow "$channel_id" "$channel_name"
                    ;;
                2)
                    if [[ "$stream_count" -gt 0 ]]; then
                        _dispatcharr_remove_streams_workflow "$channel_id" "$channel_name" "$current_streams"
                    else
                        echo -e "${WARNING_STYLE}⚠️  No streams to remove${RESET}"
                        sleep 1
                    fi
                    ;;
                q|Q|"")
                    return 0
                    ;;
                *)
                    echo -e "${ERROR_STYLE}❌ Invalid selection${RESET}"
                    sleep 1
                    ;;
            esac
        else
            echo -e "${ERROR_STYLE}❌ Failed to load streams${RESET}"
            pause_for_user
            return 1
        fi
    done
}

# Stream filtering interface with pagination and multi-selection
_dispatcharr_stream_filter_interface() {
    local current_search_term="$1"
    
    # Global variables to store filter selections
    local selected_channel_groups=()
    
    while true; do
        clear
        echo -e "${HEADER_STYLE}=== Stream Filters ===${RESET}\n"
        
        echo -e "${INFO_STYLE}Current search: ${CYAN}$current_search_term${RESET}"
        echo -e "${INFO_STYLE}Active filters:${RESET}"
        echo -e "Channel Groups: ${CYAN}${#selected_channel_groups[@]} selected${RESET}"
        echo
        
        echo -e "${MENU_OPTION_STYLE}Filter Options:${RESET}"
        echo -e "${CYAN}1)${RESET} Select Channel Groups"
        echo -e "${CYAN}2)${RESET} Clear all filters"
        echo -e "${CYAN}3)${RESET} Apply filters and return"
        echo -e "${CYAN}q)${RESET} Cancel and return"
        echo
        
        read -p "Select option: " choice < /dev/tty
        
        case "$choice" in
            1)
                _dispatcharr_select_channel_groups selected_channel_groups
                ;;
            2)
                selected_channel_groups=()
                echo -e "${INFO_STYLE}🔄 Cleared all filters${RESET}"
                sleep 1
                ;;
            3)
                # Return the selected filters as comma-separated strings
                local group_filter=""
                
                if [[ ${#selected_channel_groups[@]} -gt 0 ]]; then
                    group_filter=$(IFS=','; echo "${selected_channel_groups[*]}")
                fi
                
                # Set global variables for the calling function
                DISPATCHARR_M3U_FILTER=""  # Always empty now
                DISPATCHARR_GROUP_FILTER="$group_filter"
                return 0
                ;;
            q|Q|"")
                return 1
                ;;
            *)
                echo -e "${ERROR_STYLE}❌ Invalid selection${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Select M3U accounts with pagination - DEPRECATED: M3U account filtering removed
_dispatcharr_select_m3u_accounts() {
    # Function body removed - M3U account filtering no longer supported
    echo -e "${WARNING_STYLE}⚠️  M3U account filtering has been removed${RESET}"
    sleep 2
    return 1
}

# Select channel groups with pagination (similar to M3U accounts)
_dispatcharr_select_channel_groups() {
    local -n selected_groups_ref=$1
    local current_page=1
    local groups_per_page=25
    
    echo -e "${CYAN}Loading channel groups...${RESET}"
    local all_groups
    all_groups=$(dispatcharr_get_stream_channel_groups)
    
    if [[ $? -ne 0 || -z "$all_groups" ]]; then
        echo -e "${ERROR_STYLE}❌ Failed to load channel groups${RESET}"
        sleep 2
        return 1
    fi
    
    # Convert to array
    local groups_array=()
    while IFS= read -r group; do
        [[ -n "$group" ]] && groups_array+=("$group")
    done <<< "$all_groups"
    
    local total_groups=${#groups_array[@]}
    local total_pages=$(( (total_groups + groups_per_page - 1) / groups_per_page ))
    
    while true; do
        clear
        echo -e "${HEADER_STYLE}=== Select Channel Groups ===${RESET}\n"
        
        echo -e "${INFO_STYLE}Page $current_page of $total_pages (${#selected_groups_ref[@]} selected)${RESET}"
        echo "────────────────────────────────────────────────────────────────────"
        printf "%-3s %-8s %-50s\n" "Sel" "Group" "Status"
        echo "────────────────────────────────────────────────────────────────────"
        
        local start_idx=$(( (current_page - 1) * groups_per_page ))
        local end_idx=$(( start_idx + groups_per_page - 1 ))
        [[ $end_idx -ge $total_groups ]] && end_idx=$((total_groups - 1))
        
        local display_index=1
        for ((i=start_idx; i<=end_idx; i++)); do
            local group="${groups_array[i]}"
            local selected_mark=""
            
            # Check if selected
            for selected_group in "${selected_groups_ref[@]}"; do
                if [[ "$selected_group" == "$group" ]]; then
                    selected_mark="✓ Selected"
                    break
                fi
            done
            
            [[ -z "$selected_mark" ]] && selected_mark="Available"
            
            printf "%-3s %-8s %-50s\n" "$display_index" "$group" "$selected_mark"
            ((display_index++))
        done
        
        echo "────────────────────────────────────────────────────────────────────"
        echo -e "${MENU_OPTION_STYLE}Options:${RESET}"
        echo -e "${CYAN}[1-$((end_idx - start_idx + 1))])${RESET} Toggle group selection"
        echo -e "${CYAN}n)${RESET} Next page  ${CYAN}p)${RESET} Previous page  ${CYAN}#)${RESET} Jump to page"
        echo -e "${CYAN}c)${RESET} Commit selections  ${CYAN}r)${RESET} Reset selections  ${CYAN}q)${RESET} Cancel"
        echo
        
        read -p "Select option: " choice < /dev/tty
        
        case "$choice" in
            [1-9]|[12][0-9])
                if [[ "$choice" -le $((end_idx - start_idx + 1)) ]]; then
                    local group_idx=$((start_idx + choice - 1))
                    local group="${groups_array[group_idx]}"
                    
                    # Toggle selection
                    local already_selected=false
                    local new_selected=()
                    
                    for selected_group in "${selected_groups_ref[@]}"; do
                        if [[ "$selected_group" == "$group" ]]; then
                            already_selected=true
                        else
                            new_selected+=("$selected_group")
                        fi
                    done
                    
                    if [[ "$already_selected" == "false" ]]; then
                        new_selected+=("$group")
                    fi
                    
                    selected_groups_ref=("${new_selected[@]}")
                fi
                ;;
            n|N)
                [[ $current_page -lt $total_pages ]] && ((current_page++))
                ;;
            p|P)
                [[ $current_page -gt 1 ]] && ((current_page--))
                ;;
            '#')
                read -p "Enter page number (1-$total_pages): " page_num < /dev/tty
                if [[ "$page_num" =~ ^[0-9]+$ ]] && [[ "$page_num" -ge 1 ]] && [[ "$page_num" -le "$total_pages" ]]; then
                    current_page="$page_num"
                fi
                ;;
            c|C)
                return 0
                ;;
            r|R)
                selected_groups_ref=()
                ;;
            q|Q|"")
                return 1
                ;;
            *)
                echo -e "${ERROR_STYLE}❌ Invalid selection${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Add streams workflow with pagination and multi-page selection
_dispatcharr_add_streams_workflow() {
    local channel_id="$1"
    local channel_name="$2"
    
    local current_page=1
    local streams_per_page=25
    local selected_streams=()  # Array to store selected stream IDs
    local search_term="$channel_name"  # Start with channel name as search term
    
    # Filter variables (global for use in filter interface)
    DISPATCHARR_M3U_FILTER=""
    DISPATCHARR_GROUP_FILTER=""
    
    echo -e "${CYAN}🔄 Searching for streams matching '$channel_name'...${RESET}"
    local search_response
    search_response=$(dispatcharr_search_streams_paginated "$search_term" 1)
    
    # Extract results and total count from API response
    local all_streams total_streams
    if [[ $? -eq 0 ]] && [[ -n "$search_response" ]]; then
        all_streams=$(echo "$search_response" | jq -r '.results // empty' 2>/dev/null)
        total_streams=$(echo "$search_response" | jq -r '.count // 0' 2>/dev/null)
    fi
    
    if [[ -z "$all_streams" ]] || [[ "$all_streams" == "[]" ]] || [[ "$total_streams" == "0" ]]; then
        echo -e "${WARNING_STYLE}⚠️  No streams found matching '$search_term'${RESET}"
        echo -e "${CYAN}Would you like to:${RESET}"
        echo -e "${CYAN}1)${RESET} Enter a custom search term"
        echo -e "${CYAN}2)${RESET} Browse all available streams"
        echo
        
        read -p "Select option (1/2): " initial_choice < /dev/tty
        
        case "$initial_choice" in
            1)
                echo -e "${CYAN}Custom Search${RESET}"
                read -p "Enter search term: " custom_search_term < /dev/tty
                
                if [[ -n "$custom_search_term" ]]; then
                    echo -e "${CYAN}🔄 Searching for streams matching '$custom_search_term'...${RESET}"
                    search_response=$(dispatcharr_search_streams_paginated "$custom_search_term" 1)
                    search_term="$custom_search_term"
                    
                    if [[ $? -eq 0 ]] && [[ -n "$search_response" ]]; then
                        all_streams=$(echo "$search_response" | jq -r '.results // empty' 2>/dev/null)
                        total_streams=$(echo "$search_response" | jq -r '.count // 0' 2>/dev/null)
                    fi
                    
                    if [[ -z "$all_streams" ]] || [[ "$all_streams" == "[]" ]] || [[ "$total_streams" == "0" ]]; then
                        echo -e "${WARNING_STYLE}⚠️  No streams found matching '$custom_search_term'${RESET}"
                        echo -e "${INFO_STYLE}💡 Loading all available streams instead...${RESET}"
                        search_response=$(dispatcharr_api_wrapper "GET" "/api/channels/streams/?page=1")
                        all_streams=$(echo "$search_response" | jq -r '.results // empty' 2>/dev/null)
                        total_streams=$(echo "$search_response" | jq -r '.count // 0' 2>/dev/null)
                        search_term="(all streams)"
                    fi
                else
                    echo -e "${INFO_STYLE}💡 No search term entered, loading all streams...${RESET}"
                    search_response=$(dispatcharr_api_wrapper "GET" "/api/channels/streams/?page=1")
                    all_streams=$(echo "$search_response" | jq -r '.results // empty' 2>/dev/null)
                    total_streams=$(echo "$search_response" | jq -r '.count // 0' 2>/dev/null)
                    search_term="(all streams)"
                fi
                ;;
            2|*)
                echo -e "${INFO_STYLE}💡 Loading all available streams...${RESET}"
                search_response=$(dispatcharr_api_wrapper "GET" "/api/channels/streams/?page=1")
                all_streams=$(echo "$search_response" | jq -r '.results // empty' 2>/dev/null)
                total_streams=$(echo "$search_response" | jq -r '.count // 0' 2>/dev/null)
                search_term="(all streams)"
                ;;
        esac
        
        if [[ -z "$all_streams" ]] || [[ "$total_streams" == "0" ]]; then
            echo -e "${ERROR_STYLE}❌ Failed to load streams${RESET}"
            pause_for_user
            return 1
        fi
    fi
    
    # Use API pagination instead of local pagination
    local results_per_page=$(echo "$search_response" | jq -r '.results | length' 2>/dev/null || echo "25")
    local total_pages=$(( (total_streams + results_per_page - 1) / results_per_page ))
    
    while true; do
        clear
        echo -e "${HEADER_STYLE}=== Add Streams to: $channel_name ===${RESET}\n"
        
        # Fetch current page from API if not already cached
        local page_streams
        if [[ $current_page -eq 1 ]]; then
            # Use already loaded first page
            page_streams="$all_streams"
        else
            # Fetch the specific page from API
            if [[ "$search_term" == "(all streams)" ]]; then
                local page_response
                page_response=$(dispatcharr_api_wrapper "GET" "/api/channels/streams/?page=$current_page")
            else
                local page_response
                page_response=$(dispatcharr_search_streams_paginated "$search_term" "$current_page")
            fi
            
            if [[ $? -eq 0 ]] && [[ -n "$page_response" ]]; then
                page_streams=$(echo "$page_response" | jq -r '.results // empty' 2>/dev/null)
            else
                echo -e "${ERROR_STYLE}❌ Failed to load page $current_page${RESET}"
                sleep 2
                continue
            fi
        fi
        
        echo -e "${INFO_STYLE}Search: $search_term${RESET}"
        echo -e "${SUBHEADER_STYLE}Available Streams (Page $current_page of $total_pages):${RESET}"
        echo "────────────────────────────────────────────────────────────────────────────────────────────────"
        printf "%-3s %-5s %-30s %-35s %-20s\n" "Sel" "ID" "Stream Name" "URL Preview" "Channel Group"
        echo "────────────────────────────────────────────────────────────────────────────────────────────────"
        
        local display_index=1
        echo "$page_streams" | jq -r '.[] | "\(.id // "N/A")\t\(.name // "Unknown")\t\(.url // "N/A")\t\(.channel_group // "N/A")"' | \
        while IFS=$'\t' read -r stream_id stream_name stream_url channel_group; do
            # Check if this stream is selected
            local selected_mark=""
            for selected_id in "${selected_streams[@]}"; do
                if [[ "$selected_id" == "$stream_id" ]]; then
                    selected_mark="✓"
                    break
                fi
            done
            
            # Display with selection number if not selected, checkmark if selected
            local selection_display
            if [[ -n "$selected_mark" ]]; then
                selection_display="✓"
            else
                selection_display="$display_index"
            fi
            
            # Create URL preview (first 35 chars)
            local url_preview="${stream_url:0:35}"
            [[ ${#stream_url} -gt 35 ]] && url_preview="${url_preview}..."
            
            # Get channel group name
            local group_name
            group_name=$(dispatcharr_get_group_name_cached "$channel_group")
            
            printf "%-3s %-5s %-30s %-35s %-20s\n" \
                "$selection_display" \
                "$stream_id" \
                "${stream_name:0:30}" \
                "$url_preview" \
                "${group_name:0:20}"
            ((display_index++))
        done
        
        echo "────────────────────────────────────────────────────────────────────"
        echo -e "${INFO_STYLE}Selected streams: ${#selected_streams[@]}${RESET}"
        echo
        echo -e "${MENU_OPTION_STYLE}Options:${RESET}"
        echo -e "${CYAN}[1-$streams_per_page])${RESET} Toggle stream selection"
        echo -e "${CYAN}n)${RESET} Next page  ${CYAN}p)${RESET} Previous page  ${CYAN}#)${RESET} Jump to page"
        echo -e "${CYAN}s)${RESET} New search  ${CYAN}a)${RESET} Show all streams  ${CYAN}f)${RESET} Filter streams"
        echo -e "${CYAN}c)${RESET} Commit selected streams  ${CYAN}r)${RESET} Reset selections  ${CYAN}q)${RESET} Cancel"
        echo
        
        read -p "Select option: " choice < /dev/tty
        
        case "$choice" in
            [1-9]|[12][0-9]|[3][0-5])
                # Toggle stream selection
                local selected_stream_id
                selected_stream_id=$(echo "$page_streams" | jq -r ".[$((choice-1))].id // empty")
                
                if [[ -n "$selected_stream_id" ]]; then
                    # Check if already selected
                    local already_selected=false
                    local new_selected_streams=()
                    
                    for selected_id in "${selected_streams[@]}"; do
                        if [[ "$selected_id" == "$selected_stream_id" ]]; then
                            already_selected=true
                        else
                            new_selected_streams+=("$selected_id")
                        fi
                    done
                    
                    if [[ "$already_selected" == "false" ]]; then
                        selected_streams+=("$selected_stream_id")
                        echo -e "${SUCCESS_STYLE}✅ Added stream $selected_stream_id to selection${RESET}"
                    else
                        selected_streams=("${new_selected_streams[@]}")
                        echo -e "${WARNING_STYLE}⚠️  Removed stream $selected_stream_id from selection${RESET}"
                    fi
                    sleep 1
                else
                    echo -e "${ERROR_STYLE}❌ Invalid stream selection${RESET}"
                    sleep 1
                fi
                ;;
            n|N)
                if [[ $current_page -lt $total_pages ]]; then
                    ((current_page++))
                fi
                ;;
            p|P)
                if [[ $current_page -gt 1 ]]; then
                    ((current_page--))
                fi
                ;;
            '#')
                echo -e "${CYAN}Jump to Page${RESET}"
                echo -e "${INFO_STYLE}Current page: $current_page of $total_pages${RESET}"
                read -p "Enter page number (1-$total_pages): " target_page < /dev/tty
                
                if [[ "$target_page" =~ ^[0-9]+$ ]] && [[ "$target_page" -ge 1 ]] && [[ "$target_page" -le "$total_pages" ]]; then
                    current_page="$target_page"
                    echo -e "${SUCCESS_STYLE}✅ Jumped to page $current_page${RESET}"
                    sleep 1
                else
                    echo -e "${ERROR_STYLE}❌ Invalid page number. Must be between 1 and $total_pages${RESET}"
                    sleep 2
                fi
                ;;
            c|C)
                if [[ ${#selected_streams[@]} -gt 0 ]]; then
                    echo -e "${CYAN}🔄 Committing ${#selected_streams[@]} selected streams...${RESET}"
                    local success_count=0
                    local failed_count=0
                    
                    for stream_id in "${selected_streams[@]}"; do
                        if dispatcharr_assign_stream_to_channel "$channel_id" "$stream_id"; then
                            ((success_count++))
                        else
                            ((failed_count++))
                        fi
                    done
                    
                    echo -e "${SUCCESS_STYLE}✅ Successfully added $success_count streams${RESET}"
                    if [[ $failed_count -gt 0 ]]; then
                        echo -e "${ERROR_STYLE}❌ Failed to add $failed_count streams${RESET}"
                    fi
                    pause_for_user
                    return 0
                else
                    echo -e "${WARNING_STYLE}⚠️  No streams selected${RESET}"
                    sleep 1
                fi
                ;;
            s|S)
                echo -e "${CYAN}New Search${RESET}"
                read -p "Enter search term: " new_search_term < /dev/tty
                
                if [[ -n "$new_search_term" ]]; then
                    echo -e "${CYAN}🔄 Searching for streams matching '$new_search_term'...${RESET}"
                    local new_response
                    new_response=$(dispatcharr_search_streams_paginated "$new_search_term" 1)
                    
                    if [[ $? -eq 0 ]] && [[ -n "$new_response" ]]; then
                        local new_streams new_total
                        new_streams=$(echo "$new_response" | jq -r '.results // empty' 2>/dev/null)
                        new_total=$(echo "$new_response" | jq -r '.count // 0' 2>/dev/null)
                        
                        if [[ -n "$new_streams" ]] && [[ "$new_streams" != "[]" ]] && [[ "$new_total" != "0" ]]; then
                            all_streams="$new_streams"
                            search_term="$new_search_term"
                            search_response="$new_response"
                            current_page=1
                            selected_streams=()  # Reset selections with new search
                            total_streams="$new_total"
                            total_pages=$(( (total_streams + results_per_page - 1) / results_per_page ))
                            echo -e "${SUCCESS_STYLE}✅ Found $total_streams streams${RESET}"
                            sleep 1
                        else
                            echo -e "${WARNING_STYLE}⚠️  No streams found matching '$new_search_term'${RESET}"
                            sleep 2
                        fi
                    else
                        echo -e "${WARNING_STYLE}⚠️  No streams found matching '$new_search_term'${RESET}"
                        sleep 2
                    fi
                fi
                ;;
            a|A)
                echo -e "${CYAN}🔄 Loading all available streams...${RESET}"
                local new_response
                new_response=$(dispatcharr_api_wrapper "GET" "/api/channels/streams/?page=1")
                
                if [[ $? -eq 0 ]] && [[ -n "$new_response" ]]; then
                    local new_streams new_total
                    new_streams=$(echo "$new_response" | jq -r '.results // empty' 2>/dev/null)
                    new_total=$(echo "$new_response" | jq -r '.count // 0' 2>/dev/null)
                    
                    all_streams="$new_streams"
                    search_term="(all streams)"
                    search_response="$new_response"
                    current_page=1
                    selected_streams=()  # Reset selections when showing all
                    total_streams="$new_total"
                    total_pages=$(( (total_streams + results_per_page - 1) / results_per_page ))
                    echo -e "${SUCCESS_STYLE}✅ Loaded $total_streams streams${RESET}"
                    sleep 1
                else
                    echo -e "${ERROR_STYLE}❌ Failed to load all streams${RESET}"
                    sleep 2
                fi
                ;;
            f|F)
                echo -e "${CYAN}🔧 Opening filter interface...${RESET}"
                if _dispatcharr_stream_filter_interface "$search_term"; then
                    # Apply filters and refresh search
                    local filtered_response
                    if [[ "$search_term" == "(all streams)" ]]; then
                        # For "all streams", use empty search with filters
                        filtered_response=$(dispatcharr_search_streams_filtered "*" 1 "$DISPATCHARR_M3U_FILTER" "$DISPATCHARR_GROUP_FILTER")
                    else
                        filtered_response=$(dispatcharr_search_streams_filtered "$search_term" 1 "$DISPATCHARR_M3U_FILTER" "$DISPATCHARR_GROUP_FILTER")
                    fi
                    
                    if [[ $? -eq 0 ]] && [[ -n "$filtered_response" ]]; then
                        local filtered_streams filtered_total
                        filtered_streams=$(echo "$filtered_response" | jq -r '.results // empty' 2>/dev/null)
                        filtered_total=$(echo "$filtered_response" | jq -r '.count // 0' 2>/dev/null)
                        
                        if [[ -n "$filtered_streams" && "$filtered_streams" != "[]" ]]; then
                            all_streams="$filtered_streams"
                            search_response="$filtered_response"
                            current_page=1
                            selected_streams=()  # Reset selections when applying filters
                            total_streams="$filtered_total"
                            total_pages=$(( (total_streams + results_per_page - 1) / results_per_page ))
                            
                            local filter_summary=""
                            if [[ -n "$DISPATCHARR_GROUP_FILTER" ]]; then
                                # Convert group IDs to names for display
                                local group_names=""
                                IFS=',' read -ra group_ids <<< "$DISPATCHARR_GROUP_FILTER"
                                for gid in "${group_ids[@]}"; do
                                    local gname
                                    gname=$(dispatcharr_get_group_name_cached "$gid")
                                    [[ -n "$group_names" ]] && group_names="$group_names, "
                                    group_names="$group_names$gname"
                                done
                                filter_summary="Groups: $group_names"
                            fi
                            [[ -n "$filter_summary" ]] && search_term="$search_term (filtered: $filter_summary)"
                            
                            echo -e "${SUCCESS_STYLE}✅ Applied filters - found $filtered_total streams${RESET}"
                            sleep 1
                        else
                            echo -e "${WARNING_STYLE}⚠️  No streams found with applied filters${RESET}"
                            sleep 2
                        fi
                    else
                        echo -e "${ERROR_STYLE}❌ Failed to apply filters${RESET}"
                        sleep 2
                    fi
                else
                    echo -e "${INFO_STYLE}Filter cancelled${RESET}"
                    sleep 1
                fi
                ;;
            r|R)
                selected_streams=()
                echo -e "${INFO_STYLE}🔄 Reset all selections${RESET}"
                sleep 1
                ;;
            q|Q|"")
                return 0
                ;;
            *)
                echo -e "${ERROR_STYLE}❌ Invalid selection${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Remove streams workflow
_dispatcharr_remove_streams_workflow() {
    local channel_id="$1"
    local channel_name="$2"
    local current_streams="$3"
    
    while true; do
        clear
        echo -e "${HEADER_STYLE}=== Remove Streams from: $channel_name ===${RESET}\n"
        
        echo -e "${SUBHEADER_STYLE}Current Streams:${RESET}"
        echo "────────────────────────────────────────────────────────────────────────────────────────────"
        printf "%-3s %-5s %-30s %-35s %-20s\n" "Sel" "ID" "Name" "URL Preview" "Channel Group"
        echo "────────────────────────────────────────────────────────────────────────────────────────────"
        
        local stream_count=0
        local stream_data_array=()
        
        # Build array and display (avoid subshell variable scoping issue)
        while IFS=$'\t' read -r stream_id stream_name stream_url channel_group; do
            ((stream_count++))
            stream_data_array+=("$stream_id|$stream_name|$stream_url")
            
            # Create URL preview (first 35 chars)
            local url_preview="${stream_url:0:35}"
            [[ ${#stream_url} -gt 35 ]] && url_preview="${url_preview}..."
            
            # Get channel group name
            local group_name
            group_name=$(dispatcharr_get_group_name_cached "$channel_group")
            
            printf "%-3s %-5s %-30s %-35s %-20s\n" \
                "$stream_count" \
                "$stream_id" \
                "${stream_name:0:30}" \
                "$url_preview" \
                "${group_name:0:20}"
        done < <(echo "$current_streams" | jq -r '.[] | "\(.id // "N/A")\t\(.name // "Unknown")\t\(.url // "N/A")\t\(.channel_group // "N/A")"')
        
        echo "────────────────────────────────────────────────────────────────────"
        echo
        echo -e "${MENU_OPTION_STYLE}Options:${RESET}"
        echo -e "${CYAN}[1-$stream_count])${RESET} Remove stream  ${CYAN}q)${RESET} Back to stream management"
        echo
        
        read -p "Select stream to remove (or 'q' to cancel): " choice < /dev/tty
        
        case "$choice" in
            [0-9]|[1-9][0-9])
                if [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$stream_count" ]]; then
                    # Get stream data from our array
                    local stream_data="${stream_data_array[$((choice-1))]}"
                    local selected_stream_id="${stream_data%%|*}"
                    local temp="${stream_data#*|}"
                    local selected_stream_name="${temp%%|*}"
                    
                    if [[ -n "$selected_stream_id" && "$selected_stream_id" != "N/A" ]]; then
                        echo -e "${WARNING_STYLE}⚠️  Remove stream: $selected_stream_name (ID: $selected_stream_id)?${RESET}"
                        read -p "Confirm removal (y/N): " confirm < /dev/tty
                        
                        if [[ "$confirm" =~ ^[Yy]$ ]]; then
                            if dispatcharr_remove_stream_from_channel "$channel_id" "$selected_stream_id"; then
                                echo -e "${SUCCESS_STYLE}✅ Stream removed successfully${RESET}"
                                # Refresh current streams
                                current_streams=$(dispatcharr_get_channel_streams "$channel_id")
                            else
                                echo -e "${ERROR_STYLE}❌ Failed to remove stream${RESET}"
                            fi
                            pause_for_user
                        fi
                    fi
                else
                    echo -e "${ERROR_STYLE}❌ Invalid selection${RESET}"
                    sleep 1
                fi
                ;;
            q|Q|"")
                return 0
                ;;
            *)
                echo -e "${ERROR_STYLE}❌ Invalid selection${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Update channel from search results
_dispatcharr_update_channel_from_search() {
    local channel_data="$1"
    local channel_id=$(echo "$channel_data" | jq -r '.id')
    local channel_name=$(echo "$channel_data" | jq -r '.name // "Unknown"')
    
    clear
    echo -e "${HEADER_STYLE}=== Update Channel from Search ===${RESET}\n"
    echo -e "${INFO_STYLE}Current channel: $channel_name${RESET}"
    echo
    
    # Prompt for search term
    read -p "Enter search term (station name/callsign): " search_term
    
    if [[ -z "$search_term" ]]; then
        echo -e "${YELLOW}Search cancelled${RESET}"
        pause_for_user
        return 1
    fi
    
    # Use existing search workflow to get station data
    echo -e "${CYAN}Searching for: $search_term${RESET}"
    echo
    
    _dispatcharr_full_search_workflow "$search_term"
    local selected_station_data="$DISPATCHARR_SELECTED_STATION"
    
    if [[ -z "$selected_station_data" ]]; then
        echo -e "${YELLOW}No station selected or search cancelled${RESET}"
        pause_for_user
        return 1
    fi
    
    # Extract station information
    local station_id=$(echo "$selected_station_data" | jq -r '.stationId // ""')
    local station_callsign=$(echo "$selected_station_data" | jq -r '.callsign // ""')
    local station_name=$(echo "$selected_station_data" | jq -r '.name // ""')
    local station_logo=$(echo "$selected_station_data" | jq -r '.logoURL // ""')
    
    # Show what will be updated
    clear
    echo -e "${HEADER_STYLE}=== Update Channel from Search Results ===${RESET}\n"
    echo -e "${INFO_STYLE}Selected Station Information:${RESET}"
    echo -e "Station ID: ${CYAN}$station_id${RESET}"
    echo -e "Callsign: ${CYAN}$station_callsign${RESET}"
    echo -e "Name: ${CYAN}$station_name${RESET}"
    [[ -n "$station_logo" ]] && echo -e "Logo: ${CYAN}$station_logo${RESET}"
    echo
    
    echo -e "${INFO_STYLE}This will update channel: ${CYAN}$channel_name${RESET}"
    echo
    
    read -p "Update channel with this station data? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Updating channel...${RESET}"
        
        if dispatcharr_update_channel_station_id "$channel_id" "$station_id"; then
            echo -e "${GREEN}✅ Channel updated successfully with station ID: $station_id${RESET}"
        else
            echo -e "${RED}❌ Failed to update channel${RESET}"
        fi
    else
        echo -e "${YELLOW}Update cancelled${RESET}"
    fi
    
    pause_for_user
}

# Delete channel with confirmation
_dispatcharr_delete_channel_confirm() {
    local channel_data="$1"
    local channel_id=$(echo "$channel_data" | jq -r '.id')
    local channel_name=$(echo "$channel_data" | jq -r '.name // "Unknown"')
    local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
    
    clear
    echo -e "${HEADER_STYLE}=== Delete Channel ===${RESET}\n"
    
    echo -e "${WARNING_STYLE}⚠️  WARNING: This action cannot be undone!${RESET}"
    echo
    echo -e "${YELLOW}You are about to delete:${RESET}"
    echo -e "  Channel: ${RED}$channel_name${RESET}"
    echo -e "  Number: ${RED}$channel_number${RESET}"
    echo -e "  ID: ${RED}$channel_id${RESET}"
    echo
    
    read -p "Type 'DELETE' to confirm deletion: " confirmation < /dev/tty
    
    if [[ "$confirmation" == "DELETE" ]]; then
        echo -e "${CYAN}Deleting channel...${RESET}"
        
        if dispatcharr_delete_channel "$channel_id"; then
            echo -e "${SUCCESS_STYLE}✅ Channel deleted successfully${RESET}"
            pause_for_user
            return 0
        else
            echo -e "${ERROR_STYLE}❌ Failed to delete channel${RESET}"
            pause_for_user
            return 1
        fi
    else
        echo -e "${INFO_STYLE}ℹ️  Deletion cancelled${RESET}"
        pause_for_user
        return 1
    fi
}

# ============================================================================
# LEGACY COMPATIBILITY WRAPPERS
# ============================================================================
# These functions provide backwards compatibility with existing code.
# TODO: Eventually update all calling code to use the core functions directly
# and remove these wrappers for a cleaner API.

update_dispatcharr_channel_epg() {
    local channel_id="$1"
    local station_id="$2"
    dispatcharr_update_channel_station_id "$channel_id" "$station_id"
}

authenticate_dispatcharr() {
    _dispatcharr_full_authentication
}

refresh_dispatcharr_access_token() {
    _dispatcharr_refresh_token
}

is_dispatcharr_authenticated() {
    # Delegate to JIT system instead of managing state locally
    dispatcharr_test_connection >/dev/null 2>&1
}

ensure_dispatcharr_auth() {
    dispatcharr_ensure_valid_token
}

get_dispatcharr_access_token() {
    _dispatcharr_get_access_token "$@";
}

get_dispatcharr_refresh_token() {
    _dispatcharr_get_refresh_token "$@";
}

save_dispatcharr_config() {
    _dispatcharr_save_config "$@";
}

reload_dispatcharr_config() {
    _dispatcharr_reload_config "$@";
}

update_dispatcharr_url() {
    _dispatcharr_update_url "$@";
}

update_dispatcharr_credentials() {
    _dispatcharr_update_credentials "$@";
}

update_dispatcharr_enabled() {
    _dispatcharr_update_enabled "$@";
}

batch_update_stationids() {
    dispatcharr_apply_station_id_matches "$@"
}

get_and_cache_dispatcharr_channels() {
    dispatcharr_get_and_cache_channels "$@"
}

find_channels_missing_stationid() {
    dispatcharr_find_missing_station_ids "$@"
}

upload_station_logo_to_dispatcharr() {
    dispatcharr_upload_station_logo "$@"
}

check_existing_dispatcharr_logo() {
    dispatcharr_check_existing_logo "$@"
}

cache_dispatcharr_logo_info() {
    dispatcharr_cache_logo_info "$@"
}

cleanup_dispatcharr_logo_cache() {
    dispatcharr_cleanup_logo_cache "$@"
}