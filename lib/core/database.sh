#!/bin/bash
# lib/core/database.sh - Database operations and queries
# Part of Global Station Search v3.0.0 modular refactor
#
# Module: Database Operations
# Purpose: Direct database access, queries, lookups, and data manipulation
# Dependencies: lib/core/search.sh (for search utilities)
# Version: 1.0.0

# Module metadata
readonly DATABASE_MODULE_VERSION="1.0.0"
readonly DATABASE_MODULE_NAME="Database Operations"

# Prevent multiple inclusions
[[ -n "${DATABASE_MODULE_LOADED:-}" ]] && return 0
readonly DATABASE_MODULE_LOADED=true

# ============================================================================
# DATABASE EXISTENCE AND VALIDATION
# ============================================================================

# Check if any station database exists
# Returns: 0 if database exists, 1 otherwise
db_has_stations_database() {
    [[ -f "$BASE_STATIONS_JSON" ]] || [[ -f "$USER_STATIONS_JSON" ]] || [[ -f "$COMBINED_STATIONS_JSON" ]]
}

# Fast check for database existence (no merge check)
# Returns: 0 if database exists, 1 otherwise
db_has_stations_database_fast() {
    [[ -f "$BASE_STATIONS_JSON" ]] || [[ -f "$USER_STATIONS_JSON" ]]
}

# Get the effective stations file to use
# Returns: Path to stations file or error
db_get_effective_stations_file() {
    get_effective_stations_file "$@"
}

# ============================================================================
# DATABASE STATISTICS AND COUNTS
# ============================================================================

# Get total station count from database
# Returns: Total number of stations
db_get_total_stations_count() {
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [ $? -eq 0 ] && [ -f "$stations_file" ]; then
        local count
        count=$(jq 'length' "$stations_file" 2>/dev/null || echo "0")
        
        # Log database access
        if declare -f log_debug >/dev/null 2>&1; then
            log_debug "database" "Retrieved station count: $count from $stations_file"
        fi
        
        echo "$count"
    else
        echo "0"
    fi
}

# Get fast station count without merge
# Returns: Total stations from base + user files
db_get_total_stations_count_fast() {
    local base_count=0
    local user_count=0
    
    if [[ -f "$BASE_STATIONS_JSON" ]]; then
        base_count=$(jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
    fi
    
    if [[ -f "$USER_STATIONS_JSON" ]]; then
        user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    fi
    
    echo $((base_count + user_count))
}

# Get breakdown of base vs user stations
# Returns: Formatted string with counts
db_get_stations_breakdown() {
    local base_count=0
    local user_count=0
    local combined_count=0
    
    if [[ -f "$BASE_STATIONS_JSON" ]]; then
        base_count=$(jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
    fi
    
    if [[ -f "$USER_STATIONS_JSON" ]]; then
        user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    fi
    
    if [[ -f "$COMBINED_STATIONS_JSON" ]]; then
        combined_count=$(jq 'length' "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
    else
        combined_count=$((base_count + user_count))
    fi
    
    echo "Base: $base_count | User: $user_count | Total: $combined_count"
}

# ============================================================================
# STATION LOOKUPS AND QUERIES
# ============================================================================

# Reverse lookup station by ID
# Args: $1 - Station ID
# Returns: Station details or error message
db_reverse_station_id_lookup() {
    local station_id="$1"
    
    if [[ -z "$station_id" ]]; then
        echo -e "${ERROR_STYLE}Error: Station ID is required${RESET}"
        return 1
    fi
    
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [ $? -ne 0 ]; then
        echo -e "${ERROR_STYLE}Error: No station database available${RESET}"
        return 1
    fi
    
    # Find station by ID
    local station_data
    station_data=$(jq -r --arg id "$station_id" '.[] | select(.stationId == $id)' "$stations_file" 2>/dev/null)
    
    if [[ -z "$station_data" ]]; then
        echo -e "${WARNING_STYLE}Station ID '$station_id' not found in database${RESET}"
        return 1
    fi
    
    # Display station details
    echo -e "\n${SUCCESS_STYLE}Station Found:${RESET}"
    echo "$station_data" | jq -r '
        "  Name: " + (.name // "N/A") + "\n" +
        "  Call Sign: " + (.callSign // "N/A") + "\n" +
        "  Station ID: " + (.stationId // "N/A") + "\n" +
        "  Quality: " + (if (.videoQuality.videoType // "") == "" then "Unknown" else .videoQuality.videoType end) + "\n" +
        "  Countries: " + ((.availableIn // []) | if length > 1 then join(", ") else .[0] // "Unknown" end) + "\n" +
        "  Logo: " + (if (.preferredImage.uri // "") != "" then .preferredImage.uri else "None" end)
    '
    
    return 0
}

# Get station details as JSON
# Args: $1 - Station ID
# Returns: JSON object or empty
db_get_station_json() {
    local station_id="$1"
    local stations_file
    
    stations_file=$(get_effective_stations_file)
    if [ $? -eq 0 ] && [ -f "$stations_file" ]; then
        jq -r --arg id "$station_id" '.[] | select(.stationId == $id)' "$stations_file" 2>/dev/null
    fi
}

# Get station name by ID
# Args: $1 - Station ID
# Returns: Station name or empty
db_get_station_name() {
    local station_id="$1"
    local stations_file
    
    stations_file=$(get_effective_stations_file)
    if [ $? -eq 0 ] && [ -f "$stations_file" ]; then
        jq -r --arg id "$station_id" '.[] | select(.stationId == $id) | .name // empty' "$stations_file" 2>/dev/null | head -n 1
    fi
}

# Get station call sign by ID
# Args: $1 - Station ID
# Returns: Call sign or empty
db_get_station_callsign() {
    local station_id="$1"
    local stations_file
    
    stations_file=$(get_effective_stations_file)
    if [ $? -eq 0 ] && [ -f "$stations_file" ]; then
        jq -r --arg id "$station_id" '.[] | select(.stationId == $id) | .callSign // empty' "$stations_file" 2>/dev/null | head -n 1
    fi
}

# ============================================================================
# DATABASE EXPORT FUNCTIONS
# ============================================================================

# Export stations to CSV format
# Args: $1 - Output filename (optional)
# Returns: 0 on success, 1 on failure
db_export_stations_to_csv() {
    local output_file="${1:-stations_export_$(date +%Y%m%d_%H%M%S).csv}"
    local stations_file
    
    stations_file=$(get_effective_stations_file)
    if [ $? -ne 0 ]; then
        echo -e "${ERROR_STYLE}Error: No station database available${RESET}"
        return 1
    fi
    
    echo -e "${INFO_STYLE}Exporting stations to CSV...${RESET}"
    
    # Create CSV header
    echo "StationID,Name,CallSign,Quality,Countries,LogoURL" > "$output_file"
    
    # Export stations data
    jq -r '.[] | [
        .stationId // "",
        .name // "",
        .callSign // "",
        (if (.videoQuality.videoType // "") == "" then "Unknown" else .videoQuality.videoType end),
        ((.availableIn // []) | if length > 1 then join(";") else .[0] // "" end),
        .preferredImage.uri // ""
    ] | @csv' "$stations_file" >> "$output_file" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local count=$(tail -n +2 "$output_file" | wc -l)
        echo -e "${SUCCESS_STYLE}Successfully exported $count stations to: $output_file${RESET}"
        return 0
    else
        echo -e "${ERROR_STYLE}Error exporting stations to CSV${RESET}"
        return 1
    fi
}

# Export station database as JSON (pretty-printed)
# Args: $1 - Output filename (optional)
# Returns: 0 on success, 1 on failure
db_export_stations_json() {
    local output_file="${1:-stations_export_$(date +%Y%m%d_%H%M%S).json}"
    local stations_file
    
    stations_file=$(get_effective_stations_file)
    if [ $? -ne 0 ]; then
        echo -e "${ERROR_STYLE}Error: No station database available${RESET}"
        return 1
    fi
    
    echo -e "${INFO_STYLE}Exporting stations to JSON...${RESET}"
    
    if jq '.' "$stations_file" > "$output_file" 2>/dev/null; then
        local count=$(jq 'length' "$output_file" 2>/dev/null || echo "0")
        echo -e "${SUCCESS_STYLE}Successfully exported $count stations to: $output_file${RESET}"
        return 0
    else
        echo -e "${ERROR_STYLE}Error exporting stations to JSON${RESET}"
        return 1
    fi
}

# ============================================================================
# DATABASE SEARCH INTERFACE
# ============================================================================

# Main database search interface
# Args: $1 - Search term (optional)
# Returns: Interactive search results
db_search_local_database() {
    search_local_database "$@"
}

# Perform database search
# Args: $1 - Search term, $2 - Page number
# Returns: Search results
db_perform_search() {
    perform_search "$@"
}

# ============================================================================
# STATION DATA MANIPULATION
# ============================================================================

# Find channels missing station IDs
# Args: $1 - Integration type (dispatcharr/emby)
# Returns: List of channels without station IDs
db_find_channels_missing_stationid() {
    find_channels_missing_stationid "$@"
}

# Update station ID for a channel
# Args: $1 - Channel data, $2 - New station ID, $3 - Integration type
# Returns: 0 on success, 1 on failure
db_update_channel_station_id() {
    update_dispatcharr_channel_station_id "$@"
}

# ============================================================================
# DATABASE MAINTENANCE
# ============================================================================

# Rebuild combined database
rebuild_combined_database() {
    echo -e "${BOLD}${BLUE}=== Rebuilding Combined Database ===${RESET}"
    echo
    
    # Clear existing combined cache
    if [[ -f "$COMBINED_STATIONS_JSON" ]]; then
        echo -e "${CYAN}🗑️  Removing existing combined database...${RESET}"
        rm -f "$COMBINED_STATIONS_JSON"
    fi
    
    # Force regeneration on next access
    echo -e "${CYAN}🔄 Combined database will be rebuilt on next use${RESET}"
    echo -e "${GREEN}✅ Database rebuild initiated${RESET}"
    echo
    echo -e "${CYAN}💡 The database will be automatically rebuilt when you:${RESET}"
    echo -e "${CYAN}   - Perform a station search${RESET}"
    echo -e "${CYAN}   - View database statistics${RESET}"
    echo -e "${CYAN}   - Use any feature requiring station data${RESET}"
    
    return 0
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Module uses global variables defined in main script:
# - BASE_STATIONS_JSON
# - USER_STATIONS_JSON  
# - COMBINED_STATIONS_JSON

# ============================================================================
# LEGACY COMPATIBILITY WRAPPERS
# ============================================================================

# These functions are handled by the main script or other modules
# Removed to prevent circular dependencies

# Module validation
db_module_loaded() {
    echo "database module loaded (v${DATABASE_MODULE_VERSION})"
}