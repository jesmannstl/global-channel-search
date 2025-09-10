#!/bin/bash

# === UI Display Functions ===
# Consolidated display, status, and formatting functions
# Extracted from main script to reduce duplication

# ============================================================================
# CORE DISPLAY UTILITIES
# ============================================================================

# ============================================================================
# MODULAR STATUS BLOCK SYSTEM
# ============================================================================

# Core display primitives
display_status_block_header() {
    local section_name="$1"
    echo -e "${BOLD}${BLUE}=== $section_name ===${RESET}"
}

display_status_line() {
    local emoji="$1"
    local label="$2"
    local value="$3"
    local color="${4:-$RESET}"
    echo -e "$emoji $label: ${color} ${value}${RESET}"
}

display_status_detail() {
    local text="$1"
    local color="${2:-$RESET}"
    echo -e "   ${color}${text}${RESET}"
}

display_status_summary() {
    local message="$1"
    local emoji="${2:-💡}"
    echo -e "${INFO_STYLE}$emoji $message${RESET}"
}

# ============================================================================
# INDIVIDUAL STATUS ITEM FUNCTIONS
# ============================================================================

# Database status items
display_status_base_database() {
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | sed 's/Base: \([0-9]*\).*/\1/')
    
    if [ "$base_count" -gt 0 ]; then
        display_status_line "✅" "Base Station Database" "$base_count stations" "$SUCCESS_STYLE"
        
        # Get available countries from base database
        local base_countries=""
        if [[ -f "$BASE_STATIONS_JSON" ]]; then
            base_countries=$(jq -r '[.[] | .availableIn[]? // empty | select(. != "")] | unique | join(", ")' "$BASE_STATIONS_JSON" 2>/dev/null)
        fi
        
        if [[ -n "$base_countries" && "$base_countries" != "null" ]]; then
            display_status_detail "Coverage: $base_countries" "$INFO_STYLE"
        else
            display_status_detail "Coverage data unavailable" "$INFO_STYLE"
        fi
    else
        display_status_line "⚠️" "Base Station Database" "Not found" "$WARNING_STYLE"
        display_status_detail "Expected in script directory" "$INFO_STYLE"
    fi
}

display_status_user_database() {
    local breakdown=$(get_stations_breakdown)
    local user_count=$(echo "$breakdown" | sed 's/.*User: \([0-9]*\).*/\1/')
    
    if [ "$user_count" -gt 0 ]; then
        display_status_line "✅" "User Station Database" "$user_count stations" "$SUCCESS_STYLE"
        
        # Get available countries from user database
        local user_countries=""
        if [[ -f "$USER_STATIONS_JSON" ]]; then
            user_countries=$(jq -r '[.[] | .availableIn[]? // empty | select(. != "")] | unique | join(", ")' "$USER_STATIONS_JSON" 2>/dev/null)
        fi
        
        if [[ -n "$user_countries" && "$user_countries" != "null" ]]; then
            display_status_detail "Coverage: $user_countries" "$INFO_STYLE"
        fi
        
        local user_size=$(ls -lh "$USER_STATIONS_JSON" 2>/dev/null | awk '{print $5}')
        [[ -n "$user_size" ]] && display_status_detail "Size: $user_size" "$INFO_STYLE"
    else
        display_status_line "⚠️" "User Station Database" "No custom stations" "$WARNING_STYLE"
        display_status_detail "Build via Market Management" "$INFO_STYLE"
    fi
}

display_status_total_stations() {
    local total_count=$(get_total_stations_count)
    if ! [[ "$total_count" =~ ^[0-9]+$ ]]; then
        total_count=0
    fi
    display_status_line "📊" "Total Available Stations" "$total_count" "$INFO_STYLE"
}

display_status_user_markets() {
    local market_count=0
    if [ -f "$CSV_FILE" ]; then
        market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
    fi
    
    if [ "$market_count" -gt 0 ]; then
        display_status_line "📍" "User Markets Configured" "$market_count" "$SUCCESS_STYLE"
    else
        display_status_line "⚠️" "User Markets Configured" "0" "$WARNING_STYLE"
        display_status_detail "No custom markets defined" "$INFO_STYLE"
    fi
}

display_status_search_capability() {
    local total_count=$(get_total_stations_count)
    if ! [[ "$total_count" =~ ^[0-9]+$ ]]; then
        total_count=0
    fi
    
    if [ "$total_count" -gt 0 ]; then
        display_status_line "✅" "Local Database Search" "Available with full features" "$SUCCESS_STYLE"
    else
        display_status_line "❌" "Local Database Search" "No station data available" "$ERROR_STYLE"
        display_status_detail "Configure markets and expand database" "$INFO_STYLE"
    fi
}

# Integration status items
display_status_channels_dvr() {
    if [[ -n "${CHANNELS_URL:-}" ]]; then
        if curl -s --connect-timeout 2 "$CHANNELS_URL" >/dev/null 2>&1; then
            # Try to get version information
            local version_info=""
            if command -v cdvr_get_status >/dev/null 2>&1; then
                local status_response
                status_response=$(cdvr_get_status 2>/dev/null)
                if [[ $? -eq 0 ]] && [[ -n "$status_response" ]]; then
                    local version=$(echo "$status_response" | jq -r '.version // empty' 2>/dev/null)
                    if [[ -n "$version" ]]; then
                        version_info=" (v$version)"
                    fi
                fi
            fi
            
            display_status_line "✅" "Channels DVR" "Connected$version_info" "$SUCCESS_STYLE"
            display_status_detail "$CHANNELS_URL" "$INFO_STYLE"
        else
            display_status_line "❌" "Channels DVR" "Connection Failed" "$ERROR_STYLE"
            display_status_detail "$CHANNELS_URL" "$INFO_STYLE"
        fi
    else
        display_status_line "⚠️" "Channels DVR" "Not configured" "$WARNING_STYLE"
        display_status_detail "Optional for API search and database expansion" "$INFO_STYLE"
    fi
}

display_status_dispatcharr() {
    if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
        if dispatcharr_test_connection 2>/dev/null; then
            # Try to get version information
            local version_info=""
            if command -v dispatcharr_get_version >/dev/null 2>&1; then
                local version_response
                version_response=$(dispatcharr_get_version 2>/dev/null)
                if [[ $? -eq 0 ]] && [[ -n "$version_response" ]]; then
                    local version=$(echo "$version_response" | jq -r '.version // empty' 2>/dev/null)
                    if [[ -n "$version" ]]; then
                        version_info=" (v$version)"
                    fi
                fi
            fi
            
            display_status_line "✅" "Dispatcharr" "Connected$version_info" "$SUCCESS_STYLE"
            display_status_detail "$DISPATCHARR_URL" "$INFO_STYLE"
        else
            display_status_line "❌" "Dispatcharr" "Connection Failed" "$ERROR_STYLE"
            display_status_detail "$DISPATCHARR_URL" "$INFO_STYLE"
        fi
    else
        display_status_line "⚠️" "Dispatcharr" "Disabled" "$WARNING_STYLE"
        display_status_detail "Enable in Integration Configuration" "$INFO_STYLE"
    fi
}

display_status_emby() {
    if [[ "$EMBY_ENABLED" == "true" ]]; then
        if [[ -n "${EMBY_URL:-}" ]]; then
            # Test connection and get version information
            local connection_status="Configured"
            local version_info=""
            
            if command -v emby_test_connection >/dev/null 2>&1; then
                # Capture emby_test_connection output to get version info
                local test_output
                test_output=$(emby_test_connection 2>&1)
                if [[ $? -eq 0 ]]; then
                    connection_status="Connected"
                    # Extract version from the test output if available
                    local version=$(echo "$test_output" | grep -o 'v[0-9.]*' | head -1)
                    if [[ -n "$version" ]]; then
                        version_info=" ($version)"
                    fi
                else
                    connection_status="Connection Failed"
                fi
            fi
            
            local status_color="$SUCCESS_STYLE"
            if [[ "$connection_status" == "Connection Failed" ]]; then
                status_color="$ERROR_STYLE"
            elif [[ "$connection_status" == "Configured" ]]; then
                status_color="$WARNING_STYLE"
            fi
            
            display_status_line "✅" "Emby" "$connection_status$version_info" "$status_color"
            display_status_detail "$EMBY_URL" "$INFO_STYLE"
        else
            display_status_line "⚠️" "Emby" "Enabled but not configured" "$WARNING_STYLE"
            display_status_detail "Configure server URL in Integration Settings" "$INFO_STYLE"
        fi
    else
        display_status_line "⚠️" "Emby" "Disabled" "$WARNING_STYLE"
        display_status_detail "Enable in Integration Configuration" "$INFO_STYLE"
    fi
}

# Filter status items
display_status_resolution_filter() {
    if [[ "$FILTER_BY_RESOLUTION" == "true" ]]; then
        display_status_line "✅" "Resolution Filter" "Active" "$SUCCESS_STYLE"
        display_status_detail "$ENABLED_RESOLUTIONS" "$YELLOW"
    else
        display_status_line "⚠️" "Resolution Filter" "Disabled" "$WARNING_STYLE"
        display_status_detail "Showing all resolutions" "$INFO_STYLE"
    fi
}

display_status_country_filter() {
    if [[ "$FILTER_BY_COUNTRY" == "true" ]]; then
        display_status_line "✅" "Country Filter" "Active" "$SUCCESS_STYLE"
        display_status_detail "$ENABLED_COUNTRIES" "$YELLOW"
    else
        display_status_line "⚠️" "Country Filter" "Disabled" "$WARNING_STYLE"
        display_status_detail "Showing all countries" "$INFO_STYLE"
    fi
}

display_status_logo_display() {
    if [[ "$SHOW_LOGOS" == "true" ]]; then
        display_status_line "✅" "Logo Display" "Enabled" "$SUCCESS_STYLE"
        local logo_count=$(find "$LOGO_DIR" -name "*.png" 2>/dev/null | wc -l)
        display_status_detail "$logo_count logos cached" "$INFO_STYLE"
    else
        display_status_line "⚠️" "Logo Display" "Disabled" "$WARNING_STYLE"
        display_status_detail "Enable in Settings menu" "$INFO_STYLE"
    fi
}

# Cache and performance items
display_status_cache_size() {
    local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    display_status_line "💾" "Cache Size" "$cache_size" "$INFO_STYLE"
}

display_status_lineup_cache() {
    if [ -f "$LINEUP_CACHE" ]; then
        local lineup_count=$(wc -l < "$LINEUP_CACHE" 2>/dev/null || echo "0")
        display_status_line "📋" "Cached Lineups" "$lineup_count" "$INFO_STYLE"
    else
        display_status_line "⚠️" "Cached Lineups" "None" "$WARNING_STYLE"
    fi
}

display_status_api_search_results() {
    if [ -f "$API_SEARCH_RESULTS" ]; then
        local result_count=$(wc -l < "$API_SEARCH_RESULTS" 2>/dev/null || echo "0")
        display_status_line "🔍" "API Search Results" "$result_count entries" "$INFO_STYLE"
    else
        display_status_line "🔍" "API Search Results" "None cached" "$WARNING_STYLE"
    fi
}

# Update status check
display_status_update_check() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        display_status_line "⚠️" "Git Repository" "Not detected" "$WARNING_STYLE"
        display_status_detail "Check for updates not available" "$INFO_STYLE"
        return 0
    fi
    
    local current_commit=$(git rev-parse HEAD 2>/dev/null)
    local current_branch=$(git branch --show-current 2>/dev/null)
    
    # Quick fetch check (timeout after 3 seconds)
    local fetch_success=false
    if timeout 3s git fetch origin "$current_branch" >/dev/null 2>&1; then
        fetch_success=true
    fi
    
    if [[ "$fetch_success" == "true" ]]; then
        local remote_commit=$(git rev-parse "origin/$current_branch" 2>/dev/null)
        
        if [[ "$current_commit" == "$remote_commit" ]]; then
            display_status_line "✅" "Repository Status" "Up to date" "$SUCCESS_STYLE"
            display_status_detail "Branch: $current_branch (${current_commit:0:8})" "$INFO_STYLE"
        else
            display_status_line "🔄" "Repository Status" "Updates available" "$WARNING_STYLE"
            display_status_detail "Run 'git pull origin $current_branch' to update" "$INFO_STYLE"
        fi
    else
        display_status_line "🔄" "Repository Status" "Check in Settings" "$INFO_STYLE"
        display_status_detail "Branch: $current_branch (${current_commit:0:8})" "$INFO_STYLE"
    fi
}

# ============================================================================
# STATUS ORCHESTRATOR FUNCTIONS
# ============================================================================

# Main menu - high level overview
display_status_main_menu() {
    display_status_block_header "Database Status"
    display_status_base_database
    display_status_user_database
    display_status_total_stations
    echo
    
    display_status_block_header "Integration Status"
    display_status_channels_dvr
    display_status_dispatcharr
    display_status_emby
    echo
}

# Settings menu - configuration overview  
display_status_settings_menu() {
    display_status_block_header "Database Configuration"
    display_status_base_database
    display_status_user_database
    display_status_user_markets
    echo
    
    display_status_block_header "Integration Configuration"
    display_status_channels_dvr
    display_status_dispatcharr
    display_status_emby
    echo
    
    display_status_block_header "Display & Filter Settings"
    display_status_logo_display
    display_status_resolution_filter
    display_status_country_filter
    echo
}

# Search context - search-focused info
display_status_search_context() {
    display_status_block_header "Search Capabilities"
    display_status_search_capability
    display_status_total_stations
    echo
    
    display_status_block_header "Active Filters"
    display_status_resolution_filter
    display_status_country_filter
    echo
}

# Dispatcharr context - Dispatcharr-focused info
display_status_dispatcharr_context() {
    display_status_block_header "Dispatcharr Connection"
    display_status_dispatcharr
    echo
    
    display_status_block_header "Channel Management Capability"
    display_status_search_capability
    display_status_total_stations
    echo
}

# Emby context - Emby-focused info
display_status_emby_context() {
    display_status_block_header "Emby Connection"
    display_status_emby
    echo
    
    display_status_block_header "Integration Capability"
    display_status_search_capability
    display_status_total_stations
    echo
}

# Database management context - detailed database info
display_status_database_context() {
    display_status_block_header "Database Status"
    display_status_base_database
    display_status_user_database
    display_status_user_markets
    display_status_total_stations
    echo
    
    display_status_block_header "Cache Information"
    display_status_cache_size
    display_status_lineup_cache
    display_status_api_search_results
    echo
}

# Generic status indicator formatter
format_status_indicator() {
    local status="$1"
    local item="$2"
    local detail="${3:-}"
    
    case "$status" in
        "success"|"ok"|"enabled"|"active")
            echo -e "${GREEN}✅ $item${RESET}${detail:+ ($detail)}"
            ;;
        "warning"|"missing"|"disabled")
            echo -e "${YELLOW}⚠️  $item${RESET}${detail:+ ($detail)}"
            ;;
        "error"|"failed"|"not_found")
            echo -e "${RED}❌ $item${RESET}${detail:+ ($detail)}"
            ;;
        "info"|"note")
            echo -e "${CYAN}💡 $item${RESET}${detail:+ ($detail)}"
            ;;
        *)
            echo -e "${CYAN}$item${RESET}${detail:+ ($detail)}"
            ;;
    esac
}

# Generic table header formatter
format_table_header() {
    local title="$1"
    shift
    local columns=("$@")
    
    echo -e "${BOLD}${BLUE}=== $title ===${RESET}"
    
    # Build header row
    local header_format=""
    local separator=""
    for col in "${columns[@]}"; do
        header_format+="%-20s "
        separator+="--------------------"
    done
    
    printf "${BOLD}${YELLOW}${header_format}${RESET}\n" "${columns[@]}"
    echo "$separator"
}

display_logo() {
  local stid="$1"
  local logo_file="$LOGO_DIR/${stid}.png"
  
  if [[ "$SHOW_LOGOS" == true ]]; then
    if [[ ! -f "$logo_file" ]]; then
      # Use search module for data extraction
      local logo_url=$(search_get_station_logo_url "$stid")
      
      # CRITICAL PERFORMANCE CHECK - Skip invalid/local URLs
      if [[ -n "$logo_url" ]] && [[ "$logo_url" =~ ^https?:// ]] && [[ ! "$logo_url" =~ ^sources/ ]]; then
        curl -sL --connect-timeout 5 --max-time 10 "$logo_url" --output "$logo_file" 2>/dev/null
      fi
    fi
    
    if [[ -f "$logo_file" ]]; then
      local mime_type=$(file --mime-type -b "$logo_file")
      if [[ "$mime_type" == image/* ]]; then
        viu -h 3 -w 20 "$logo_file" || echo "[no logo available]"
      else
        echo "[no logo available]"
      fi
    else
      echo "[no logo available]"
    fi
  else
    echo "[logo previews disabled]"
  fi
}

show_active_filters() {
    local filter_status=""
    if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
        filter_status+="Resolution: ${GREEN}$ENABLED_RESOLUTIONS${RESET} "
    fi
    if [ "$FILTER_BY_COUNTRY" = "true" ]; then
        filter_status+="Country: ${GREEN}$ENABLED_COUNTRIES${RESET} "
    fi
    if [ -n "$filter_status" ]; then
        echo -e "${INFO_STYLE}🔍 Active Filters: $filter_status${RESET}"
    else
        echo -e "${INFO_STYLE}🔍 No filters active - showing all available stations${RESET}"
    fi
}

display_search_results() {
    local search_term="$1"
    local page="$2"
    local results="$3"
    local total_results="$4"
    local results_per_page="$5"
    local mode="${6:-local}"  # "local" or "api"
    
    local result_count=0
    
    # Mode-specific configuration
    local show_selection_keys=true
    local show_country=true
    local show_pagination=true
    
    if [[ "$mode" == "api" ]]; then
        show_selection_keys=false
        show_country=false
        show_pagination=false
    fi
    
    # STANDARDIZED: Result display with mode-specific error handling
    if [[ -z "$results" ]]; then
        echo -e "\n${YELLOW}⚠️  No results found for '$search_term'${RESET}"
        echo
        echo -e "${BOLD}${CYAN}Suggestions to improve your search:${RESET}"
        
        if [[ "$mode" == "local" ]]; then
            # Local search suggestions
            if [ "$FILTER_BY_RESOLUTION" = "true" ] || [ "$FILTER_BY_COUNTRY" = "true" ]; then
                echo -e "${INFO_STYLE}💡 Try disabling filters in Settings → Search Filters${RESET}"
            fi
            echo -e "${INFO_STYLE}💡 Try partial names: 'ESPN' instead of 'ESPN Sports Center'${RESET}"
            echo -e "${INFO_STYLE}💡 Try call signs: 'CNN' for CNN stations${RESET}"
            echo -e "${INFO_STYLE}💡 Check spelling and try alternative names${RESET}"
        else
            # API search suggestions
            echo -e "${CYAN}💡 Try: Different spelling, call signs, or partial names${RESET}"
            echo -e "${GREEN}💡 Local Database Search may have more comprehensive results${RESET}"
        fi
        echo
    else
        # Success case - show results
        if [[ "$mode" == "local" ]]; then
            echo -e "\n${SUCCESS_STYLE}✅ Found $total_results total results${RESET}"
            if [[ "$show_pagination" == "true" ]]; then
                echo -e "${INFO_STYLE}💡 Showing page $page with up to $results_per_page results${RESET}"
            fi
        else
            echo -e "${GREEN}✅ Found $total_results result(s) for '$search_term'${RESET}"
            echo -e "${YELLOW}⚠️  Direct API results (limited to 6 maximum)${RESET}"
            echo -e "${CYAN}💡 No country data available, no filtering applied${RESET}"
            echo -e "${RED}⚠️  Station details not available for API results${RESET}"
        fi
        echo

        # Table header - adaptive based on mode
        if [[ "$show_selection_keys" == "true" && "$show_country" == "true" ]]; then
            # Local mode: Full header with selection keys and country
            printf "${BOLD}${YELLOW}%-3s %-30s %-10s %-8s %-12s %s${RESET}\n" "Key" "Channel Name" "Call Sign" "Quality" "Station ID" "Country"
            echo "---------------------------------------------------------------------------------"
        else
            # API mode: No selection keys, no country
            printf "${BOLD}${YELLOW}%-30s %-10s %-8s %-12s${RESET}\n" "Channel Name" "Call Sign" "Quality" "Station ID"
            echo "----------------------------------------------------------------"
        fi

        local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")

        # Process search results with mode-specific formatting
        while IFS=$'\t' read -r name call_sign quality station_id country; do
            [[ -z "$name" ]] && continue

            if [[ "$show_selection_keys" == "true" ]]; then
                # Local mode: Show selection keys
                local key="${key_letters[$result_count]}"
                printf "${GREEN}%-3s${RESET} " "${key})"
                printf "%-30s %-10s %-8s " "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}"
                echo -n -e "${CYAN}${station_id}${RESET}"
                printf "%*s" $((12 - ${#station_id})) ""
                if [[ "$show_country" == "true" ]]; then
                    echo -e "${GREEN}${country}${RESET}"
                else
                    echo
                fi
            else
                # API mode: No selection keys, simpler format
                printf "%-30s %-10s %-8s ${CYAN}%-12s${RESET}\n" "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}" "$station_id"
            fi

            # STANDARDIZED: Logo display with consistent messaging
            if [[ "$SHOW_LOGOS" == true ]]; then
                display_logo "$station_id"
            else
                echo "   [logo previews disabled - enable in Settings]"
            fi
            echo

            ((result_count++))
        done <<< "$results"
        
        # Mode-specific footer messages
        if [[ "$mode" == "api" ]]; then
            echo -e "${CYAN}💡 Tip: For detailed station information and filtering, use Local Database Search${RESET}"
            echo -e "${CYAN}💡 Local Database Search provides comprehensive station details and advanced features${RESET}"
        fi
    fi
    
    # Return result count for navigation logic (local mode only)
    if [[ "$mode" == "local" ]]; then
        SEARCH_RESULT_COUNT=$result_count
    fi
}

display_station_info() {
    local name="$1"
    local call_sign="$2" 
    local station_id="$3"
    local country="$4"
    local quality="$5"
    
    # Basic Information
    echo -e "${BOLD}${BLUE}Basic Information:${RESET}"
    echo -e "${CYAN}Station Name:${RESET} ${GREEN}$name${RESET}"
    echo -e "${CYAN}Call Sign:${RESET} ${GREEN}$call_sign${RESET}"
    echo -e "${CYAN}Station ID:${RESET} ${GREEN}$station_id${RESET}"
    echo -e "${CYAN}Country:${RESET} ${GREEN}$country${RESET}"
    echo -e "${CYAN}Video Quality:${RESET} ${GREEN}$quality${RESET}"
    echo
    
    # Extended Information
    echo -e "${CYAN}🔄 Retrieving additional station information...${RESET}"
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [[ $? -eq 0 ]]; then
        local details=$(jq -r --arg id "$station_id" \
          '.[] | select(.stationId == $id) | 
           "Network: " + (.network // "N/A") + "\n" +
           "Language: " + (.language // "N/A") + "\n" +
           "Logo URL: " + (.preferredImage.uri // "N/A") + "\n" +
           "Description: " + (.description // "N/A")' \
          "$stations_file" 2>/dev/null)
        
        if [[ -n "$details" ]]; then
            echo -e "${BOLD}${BLUE}Extended Information:${RESET}"
            echo "$details"
            echo
        else
            echo -e "${YELLOW}⚠️  Extended information not available for this station${RESET}"
            echo -e "${CYAN}💡 This may occur with manually-added or API-sourced stations${RESET}"
            echo
        fi
    else
        echo -e "${RED}❌ Station Database: Unable to access extended information${RESET}"
        echo -e "${CYAN}💡 Database may be temporarily unavailable${RESET}"
        echo
    fi
    
    # Logo Display
    echo -e "${BOLD}${BLUE}Station Logo:${RESET}"
    if [[ "$SHOW_LOGOS" == true ]]; then
        echo -e "${CYAN}🖼️  Logo preview:${RESET}"
        display_logo "$station_id"
        echo
    else
        echo -e "${YELLOW}⚠️  Logo previews disabled${RESET}"
        echo -e "${CYAN}💡 Enable in Settings → Logo Display for visual previews${RESET}"
        echo -e "${CYAN}💡 Requires 'viu' tool for terminal image display${RESET}"
        echo
    fi
    
    # Data Source Information
    local data_source="Unknown"
    if [[ $? -eq 0 ]]; then
        local stations_data=$(jq -r --arg id "$station_id" '.[] | select(.stationId == $id) | .source // "Unknown"' "$stations_file" 2>/dev/null)
        if [[ -n "$stations_data" && "$stations_data" != "null" ]]; then
            data_source="$stations_data"
        fi
    fi
    
    echo -e "${BOLD}${BLUE}Data Source:${RESET}"
    case "$data_source" in
        "user")
            echo -e "${GREEN}✅ User Station Database${RESET} (from your configured markets)"
            ;;
        "base"|"combined")
            echo -e "${GREEN}✅ Base Station Database${RESET} (distributed with script)"
            ;;
        *)
            echo -e "${CYAN}💡 Combined Database${RESET} (merged from available sources)"
            ;;
    esac
    echo
}

display_reverse_lookup_result() {
    local station_id="$1"
    local station_data="$2"
    
    echo -e "${GREEN}✅ Station found:${RESET}"
    
    # Extract individual fields from the JSON station data
    local name call_sign country quality
    name=$(echo "$station_data" | jq -r '.name // "Unknown"')
    call_sign=$(echo "$station_data" | jq -r '.callSign // "N/A"')
    country=$(echo "$station_data" | jq -r '.country // "Unknown"')
    quality=$(echo "$station_data" | jq -r '.videoQuality.videoType // "Unknown"')
    
    # Use our existing station info display function for consistency
    display_station_info "$name" "$call_sign" "$station_id" "$country" "$quality"
    
    echo -e "${GREEN}✅ Lookup completed successfully${RESET}"
}

# Function moved to lib/integrations/cdvr.sh

# ============================================================================
# UNIFIED STATUS DISPLAY SYSTEM
# ============================================================================

# Main system status display (consolidates show_system_status)
show_unified_system_status() {
    local context="${1:-normal}"  # normal, detailed, summary
    local debug_trace=${DEBUG_CACHE_TRACE:-false}
    
    if [ "$debug_trace" = true ]; then
        echo -e "${CYAN}[TRACE] show_unified_system_status($context) called${RESET}" >&2
    fi
    
    # Use new modular status system
    case "$context" in
        "detailed")
            display_status_database_context
            ;;
        *)
            display_status_main_menu
            ;;
    esac
}

# DEPRECATED FUNCTIONS REMOVED - Now using modular status system
# - _show_database_status() → display_status_*_database() functions
# - _show_integration_status() → display_status_*() integration functions

# Private: Market status section (detailed mode only)
_show_market_status() {
    if [ ! -f "$CSV_FILE" ]; then
        return 0
    fi
    
    echo -e "${BOLD}${BLUE}Market Status:${RESET}"
    
    local total_markets=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
    local cached_markets=0
    local base_cache_markets=0
    local pending_markets=0
    
    # CORRECT WAY: Count markets from CSV, not from state file
    if [ "$total_markets" -gt 0 ]; then
        while IFS=, read -r country zip; do
            [[ "$country" == "Country" ]] && continue
            
            if is_market_cached "$country" "$zip"; then
                ((cached_markets++))
            elif is_market_in_base_cache "$country" "$zip" 2>/dev/null; then
                ((base_cache_markets++))
            else
                ((pending_markets++))
            fi
        done < "$CSV_FILE"
    fi
    
    echo -e "${CYAN}📊 Total configured: $total_markets${RESET}"
    echo -e "${CYAN}📊 User database: $cached_markets${RESET}"
    echo -e "${CYAN}📊 Base covered: $base_cache_markets${RESET}"
    echo -e "${CYAN}📊 Pending: $pending_markets${RESET}"
    
    # Verification
    local total_counted=$((cached_markets + base_cache_markets + pending_markets))
    if [ "$total_counted" -ne "$total_markets" ]; then
        echo -e "${RED}⚠️  Market count verification failed${RESET}"
    fi
}

display_database_status() {
    local total_count=$(get_total_stations_count)
    
    if [ "$total_count" -gt 0 ]; then
        local stations_file
        stations_file=$(get_effective_stations_file)
        
        local source_type="Combined"
        if [[ "$stations_file" == *"base"* ]]; then
            source_type="Base"
        elif [[ "$stations_file" == *"user"* ]]; then
            source_type="User"
        fi
        
        echo -e "${GREEN}✅ Database Available: $total_count stations ($source_type)${RESET}"
        return 0
    else
        echo -e "${RED}❌ No station database available${RESET}"
        return 1
    fi
}

# ============================================================================
# CACHE STATISTICS DISPLAY
# ============================================================================

# Unified cache statistics (consolidates display_cache_statistics + show_cache_state_stats)
show_unified_cache_stats() {
    local detail_level="${1:-summary}"  # summary, detailed, debug
    
    echo -e "${BOLD}${BLUE}📊 Cache Statistics${RESET}"
    echo
    
    # Core cache breakdown
    _show_cache_breakdown
    
    # Additional file information
    _show_cache_files "$detail_level"
    
    # State tracking info
    if [[ "$detail_level" != "summary" ]]; then
        _show_state_tracking_stats
    fi
    
    echo
}

# Private: Core cache breakdown
_show_cache_breakdown() {
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | sed 's/Base: \([0-9]*\).*/\1/')
    local user_count=$(echo "$breakdown" | sed 's/.*User: \([0-9]*\).*/\1/')  
    local total_count=$(get_total_stations_count)
    
    echo -e "${BOLD}Station Database:${RESET}"
    if [ "$base_count" -gt 0 ]; then
        echo -e "${SUCCESS_STYLE}📍 Base Stations: ${BOLD}$base_count${RESET}"
    else
        echo -e "${WARNING_STYLE}📍 Base Stations: ${BOLD}0${RESET} ${GRAY}(not found)${RESET}"
    fi
    
    if [ "$user_count" -gt 0 ]; then
        echo -e "${SUCCESS_STYLE}👤 User Stations: ${BOLD}$user_count${RESET}"
    else
        echo -e "${INFO_STYLE}👤 User Stations: ${BOLD}0${RESET} ${GRAY}(none added)${RESET}"
    fi
    
    echo -e "${SUCCESS_STYLE}📺 Total Available: ${BOLD}$total_count${RESET}"
    echo
}

# Private: Cache files information
_show_cache_files() {
    local detail_level="$1"
    
    echo -e "${BOLD}Cache Information:${RESET}"
    
    # Lineups
    if [ -f "$LINEUP_CACHE" ]; then
        local lineup_count=$(wc -l < "$LINEUP_CACHE" 2>/dev/null || echo "0")
        echo -e "${INFO_STYLE}📋 Lineups: ${BOLD}$lineup_count${RESET}"
    else
        echo -e "${INFO_STYLE}📋 Lineups: ${BOLD}0${RESET}"
    fi
    
    # Logos
    if [ -d "$LOGO_DIR" ]; then
        local logo_count=$(find "$LOGO_DIR" -name "*.png" 2>/dev/null | wc -l)
        echo -e "${INFO_STYLE}🖼️  Logos cached: ${BOLD}$logo_count${RESET}"
    else
        echo -e "${INFO_STYLE}🖼️  Logos cached: ${BOLD}0${RESET}"
    fi
    
    # API search results
    if [ -f "$API_SEARCH_RESULTS" ]; then
        local api_count=$(wc -l < "$API_SEARCH_RESULTS" 2>/dev/null || echo "0")
        echo -e "${INFO_STYLE}🔍 API search results: ${BOLD}$api_count${RESET} entries"
    else
        echo -e "${INFO_STYLE}🔍 API search results: ${BOLD}0${RESET} entries"
    fi
    
    # Total cache size
    local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    echo -e "${INFO_STYLE}💾 Total cache size: ${BOLD}$cache_size${RESET}"
    echo
}

# Private: State tracking statistics  
_show_state_tracking_stats() {
    echo -e "${BOLD}State Tracking:${RESET}"
    
    # Cached Markets
    if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
        local cached_market_count=$(jq -s 'length' "$CACHED_MARKETS" 2>/dev/null || echo "0")
        echo -e "${INFO_STYLE}🌍 Cached Markets: ${BOLD}$cached_market_count${RESET}"
        
        # Show breakdown by country
        if command -v jq >/dev/null 2>&1; then
            local countries=$(jq -s '.[] | .country' "$CACHED_MARKETS" 2>/dev/null | sort | uniq -c | sort -rn)
            if [ -n "$countries" ]; then
                echo -e "${GRAY}  📊 By Country:${RESET}"
                echo "$countries" | while read -r count country; do
                    if [ -n "$country" ] && [ "$country" != "null" ] && [ "$country" != '""' ]; then
                        country=$(echo "$country" | tr -d '"')
                        echo -e "${GRAY}    🏳️  $country: ${BOLD}$count${RESET} ${GRAY}markets${RESET}"
                    fi
                done
            fi
        fi
    else
        echo -e "${INFO_STYLE}🌍 Cached Markets: ${BOLD}0${RESET}"
    fi
    
    # Cached Lineups
    if [ -f "$CACHED_LINEUPS" ] && [ -s "$CACHED_LINEUPS" ]; then
        local cached_lineup_count=$(jq -s 'length' "$CACHED_LINEUPS" 2>/dev/null || echo "0")
        echo -e "${INFO_STYLE}📡 Cached Lineups: ${BOLD}$cached_lineup_count${RESET}"
        
        if command -v jq >/dev/null 2>&1; then
            local total_stations=$(jq -s '.[] | .stations_found' "$CACHED_LINEUPS" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
            echo -e "${GRAY}  📊 Total Stations (pre-dedup): ${BOLD}$total_stations${RESET}"
        fi
    else
        echo -e "${INFO_STYLE}📡 Cached Lineups: ${BOLD}0${RESET}"
    fi
    
    # Show last update
    if [ -f "$CACHE_STATE_LOG" ] && [ -s "$CACHE_STATE_LOG" ]; then
        local last_update=$(tail -1 "$CACHE_STATE_LOG" 2>/dev/null | cut -d' ' -f1-2)
        if [ -n "$last_update" ]; then
            echo -e "${INFO_STYLE}🕒 Last Cache Update: ${BOLD}$last_update${RESET}"
        fi
    else
        echo -e "${INFO_STYLE}🕒 Last Cache Update: ${GRAY}Never${RESET}"
    fi
    echo
}