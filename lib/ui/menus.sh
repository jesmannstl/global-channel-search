#!/bin/bash

# === Menu Framework ===
# Universal menu system eliminating menu pattern duplication

# ============================================================================
# UNIVERSAL MENU SYSTEM
# ============================================================================

# Universal menu display with template support
show_menu() {
    local menu_config="$1"
    
    # Parse menu configuration (format: "title|status_type|options_array_name")
    IFS='|' read -r title status_type options_var <<< "$menu_config"
    
    clear
    show_menu_header "$title"
    
    # Show status section if specified
    case "$status_type" in
        "system")
            show_unified_system_status
            ;;
        "cache") 
            display_status_database_context
            ;;
        "dispatcharr")
            display_status_dispatcharr_context
            ;;
        "markets")
            _show_markets_menu_status
            ;;
        "settings")
            display_status_settings_menu
            ;;
        "none")
            # No status section
            ;;
    esac
    
    # Show menu options - using eval for compatibility with older Bash versions
    eval "show_menu_options \"\${${options_var}[@]}\""
    echo
}

# Universal menu header formatter
show_menu_header() {
    local title="$1"
    local subtitle="${2:-}"
    
    echo -e "${BOLD}${CYAN}=== $title ===${RESET}\n"
    
    if [[ -n "$subtitle" ]]; then
        echo -e "${BLUE}📍 $subtitle${RESET}"
        echo
    fi
}

# Universal menu options display
show_menu_options() {
    local options=("$@")
    
    echo -e "${BOLD}${CYAN}Menu Options:${RESET}"
    
    for option in "${options[@]}"; do
        # Parse option format: "key|label|description"
        IFS='|' read -r key label description <<< "$option"
        
        if [[ -n "$description" ]]; then
            echo -e "${GREEN}$key)${RESET} $label ${CYAN}($description)${RESET}"
        else
            echo -e "${GREEN}$key)${RESET} $label"
        fi
    done
}

# Universal menu input handling
handle_menu_input() {
    local menu_name="$1"
    local choice="$2"
    shift 2
    local valid_choices=("$@")
    
    # Validate choice
    for valid_choice in "${valid_choices[@]}"; do
        if [[ "$choice" == "$valid_choice" ]]; then
            return 0  # Valid choice
        fi
    done
    
    # Invalid choice handling
    show_invalid_menu_choice "$menu_name" "$choice"
    return 1
}

# Universal invalid choice display
show_invalid_menu_choice() {
    local menu_name="${1:-Unknown Menu}"
    local invalid_choice="${2:-[empty]}"
    
    echo -e "${ERROR_STYLE}❌ Invalid Option: '$invalid_choice'${RESET}"
    echo -e "${CYAN}💡 Please select a valid option from the $menu_name menu${RESET}"
    sleep 2
}

# Universal menu transition messages
show_menu_transition() {
    local transition_type="$1"
    local target="$2"
    
    case "$transition_type" in
        "opening")
            echo -e "${CYAN}🔄 Opening $target...${RESET}"
            ;;
        "returning")
            echo -e "${CYAN}🔄 Returning to $target...${RESET}"
            ;;
        "starting")
            echo -e "${CYAN}🔄 Starting $target...${RESET}"
            ;;
        "loading")
            echo -e "${CYAN}📊 Loading $target...${RESET}"
            ;;
    esac
    
    [[ "$transition_type" != "returning" ]] && sleep 1
}

# ============================================================================
# MENU STATUS TEMPLATES
# ============================================================================

# Cache management menu status
_show_cache_menu_status() {
    # Use modular status system - this function now calls the database context orchestrator
    display_status_database_context
    
    # Keep the processing state summary for now as it's specialized
    _show_processing_state_summary
}

# Dispatcharr menu status
_show_dispatcharr_menu_status() {
    # Use modular status system - this function now calls the dispatcharr context orchestrator
    display_status_dispatcharr_context
    
    # Keep specialized sections for now (pending operations, token status)
    echo -e "${BOLD}${BLUE}=== Pending Operations ===${RESET}"
    if [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
        local pending_count=$(wc -l < "$DISPATCHARR_MATCHES")
        display_status_line "📋" "Pending Station ID Changes" "$pending_count matches queued" "$WARNING_STYLE"
    else
        display_status_line "✅" "Pending Operations" "No pending changes" "$SUCCESS_STYLE"
    fi
    echo
}

# Emby menu status
_show_emby_menu_status() {
    echo -e "${BOLD}${BLUE}=== Emby Integration Status ===${RESET}"
    
    if [[ "$EMBY_ENABLED" == "true" ]]; then
        if [[ -n "${EMBY_URL:-}" ]]; then
            local auth_status
            auth_status=$(get_emby_auth_status)
            local status_code=$?
            
            echo -e "${GREEN}✅ Emby Integration: Enabled${RESET}"
            echo -e "${CYAN}   📍 Server: $EMBY_URL${RESET}"
            echo -e "${CYAN}   🔐 Authentication: $auth_status${RESET}"
            
            if [[ $status_code -eq 0 ]]; then
                # Try to get server info for additional details
                local server_info
                server_info=$(emby_get_server_info 2>/dev/null)
                if [[ $? -eq 0 ]]; then
                    local server_name=$(echo "$server_info" | jq -r '.ServerName // "Unknown"' 2>/dev/null)
                    local version=$(echo "$server_info" | jq -r '.Version // "Unknown"' 2>/dev/null)
                    echo -e "${CYAN}   🖥️  Server: $server_name (v$version)${RESET}"
                fi
            fi
        else
            echo -e "${YELLOW}⚠️  Emby Integration: Enabled but not configured${RESET}"
        fi
    else
        echo -e "${CYAN}💡 Emby Integration: Disabled${RESET}"
    fi
    echo
}

# Markets menu status
_show_markets_menu_status() {
    echo -e "${BOLD}${BLUE}Current Market Configuration:${RESET}"
    
    if [ -f "$CSV_FILE" ] && [ -s "$CSV_FILE" ]; then
        local market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
        display_status_line "📍" "Markets configured" "$market_count" "$SUCCESS_STYLE"
        echo
        
        # Show market table
        _show_markets_table
        
        # FIXED: Status summary - count markets from CSV, not state file
        local cached_count=0
        local pending_count=0
        local base_cache_count=0
        
        while IFS=, read -r country zip; do
            [[ "$country" == "Country" ]] && continue
            
            if is_market_cached "$country" "$zip"; then
                ((cached_count++))
            elif is_market_in_base_cache "$country" "$zip" 2>/dev/null; then
                ((base_cache_count++))
            else
                ((pending_count++))
            fi
        done < "$CSV_FILE"
        
        if [ "$base_cache_count" -gt 0 ]; then
            echo -e "${CYAN}📊 Status Summary: ${GREEN}$cached_count cached${RESET}, ${YELLOW}$base_cache_count in base${RESET}, ${RED}$pending_count pending${RESET}"
        else
            echo -e "${CYAN}📊 Status Summary: ${GREEN}$cached_count cached${RESET}, ${RED}$pending_count pending${RESET}"
        fi
    else
        display_status_line "⚠️" "Markets configured" "0" "$WARNING_STYLE"
    fi
}

# Settings menu status
_show_settings_menu_status() {
    # Use modular status system - this function now just calls the orchestrator
    display_status_settings_menu
}

# Private helpers
_show_token_status() {
    local token_file="$CACHE_DIR/dispatcharr_tokens.json"
    if [[ -f "$token_file" ]]; then
        local token_time=$(stat -c %Y "$token_file" 2>/dev/null || stat -f %m "$token_file" 2>/dev/null)
        if [[ -n "$token_time" ]]; then
            local current_time=$(date +%s)
            local age_minutes=$(( (current_time - token_time) / 60 ))
            
            if [ "$age_minutes" -lt 30 ]; then
                echo -e "   ${GREEN}🔑 Tokens: Fresh (${age_minutes}m old)${RESET}"
            else
                echo -e "   ${YELLOW}🔑 Tokens: Aging (${age_minutes}m old)${RESET}"
            fi
        fi
    fi
}

_show_processing_state_summary() {
    echo -e "${BOLD}${BLUE}=== Processing State ===${RESET}"
    
    local market_count=0
    if [ -f "$CSV_FILE" ]; then
        market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
    fi
    
    if [ "$market_count" -gt 0 ]; then
        local cached_markets=0
        if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
            cached_markets=$(jq -s 'length' "$CACHED_MARKETS" 2>/dev/null || echo "0")
        fi
        local pending_markets=$((market_count - cached_markets))
        
        display_status_line "📍" "Market Configuration" "$market_count markets configured" "$SUCCESS_STYLE"
        if [ "$pending_markets" -gt 0 ]; then
            echo -e "   ${WARNING_STYLE}📊 Pending Markets: $pending_markets${RESET}"
        fi
    else
        display_status_line "⚠️" "Market Configuration" "No markets configured" "$WARNING_STYLE"
    fi
    
    # Cache health
    if [ -d "$CACHE_DIR" ]; then
        local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "${INFO_STYLE}📊 Total Cache Size: $cache_size${RESET}"
    fi
}

_show_markets_table() {
    if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
        return 0
    fi
    
    # Show compact market table
    printf "${BOLD}${YELLOW}%-12s %-15s %-12s %s${RESET}\n" "Country" "ZIP/Postal" "Status" "Notes"
    echo "-------------------------------------------------------"
    
    while IFS=, read -r country zip; do
        [[ "$country" == "Country" ]] && continue
        
        local status_text notes=""
        if is_market_cached "$country" "$zip"; then
            status_text="${GREEN}Cached${RESET}"
            notes="Ready"
        elif is_market_in_base_cache "$country" "$zip" 2>/dev/null; then
            status_text="${YELLOW}In base${RESET}"
            notes="May skip"
        else
            status_text="${RED}Pending${RESET}"
            notes="Not cached"
        fi
        
        # FIXED: Use echo -e instead of printf for colored text
        local country_field=$(printf "%-12s" "$country")
        local zip_field=$(printf "%-15s" "$zip")
        local notes_field=$(printf "%s" "$notes")
        echo -e "${country_field} ${zip_field} ${status_text}       ${notes_field}"
    done < "$CSV_FILE"
    echo
}

# ============================================================================
# MENU TEMPLATES
# ============================================================================

# Main menu template
show_main_menu() {
  # Define menu options without 'local' for eval access
  main_options=(
    "1|Search"
    "2|Dispatcharr Integration" 
    "3|Emby Integration"
    "4|Settings"
    "q|Exit"
  )
  
  show_menu "Global Station Search v$VERSION|system|main_options"

    local total_count=$(get_total_stations_count 2>/dev/null || echo "0")
    if [[ "${total_count:-0}" -eq 0 ]]; then
    echo
    echo -e "${BOLD}${YELLOW}💡 Quick Start:${RESET}"
    echo -e "${CYAN}No station database found.${RESET}"
    echo
    echo -e "• Create a user database using 'Manage Television Markets'"
    echo -e "• Or contact the developer for a base database"
    echo
  fi
}

# Settings menu template
show_settings_menu() {
    # Define without 'local' for eval access
    settings_options=(
        "1|Database Management"
        "2|Integration Configuration|Channels DVR, Dispatcharr, Emby"
        "3|Toggle Logo Display"
        "4|Search Filters"
        "5|Logging"
        "6|Check for Updates"
        "7|Backup Management"
        "8|Clear Temporary Files"
        "q|Back to Main Menu"
    )
    
    show_menu "Settings|settings|settings_options"
}

# Cache management menu template
show_database_management_menu() {
    # Define without 'local' for eval access
    cache_options=(
        "1|Incremental Update|add new markets only"
        "2|Full User Database Refresh|rebuild entire user database"
        "3|View Cache Statistics|detailed breakdown"
        "4|Export Combined Database to CSV|backup/external use"
        "5|Clear User Database|remove custom stations"
        "6|Clear Temporary Files|cleanup disk space"
        "7|Advanced Cache Operations|developer tools"
        "8|Clean Dispatcharr Logo Cache|remove old logo entries"
        "q|Back to Main Menu"
    )
    
    show_menu "Local Database Management|cache|cache_options"
    
    # Show smart recommendations
    _show_cache_recommendations
}

# Dispatcharr integration menu template
show_dispatcharr_menu() {
    # Define without 'local' for eval access
    dispatcharr_options=(
        "1|Match Missing Station IDs|scan, match, commit changes"
        "2|Channel Management|create, modify, populate fields"
        "3|Group Management|view, create, modify groups"
        "q|Back to Main Menu"
    )
    
    show_menu "Dispatcharr Integration|dispatcharr|dispatcharr_options"
    
    # Show smart recommendations
    _show_dispatcharr_recommendations
}

# Match Missing Station IDs submenu
show_dispatcharr_stationid_menu() {
    stationid_options=(
        "a|Scan Channels for Missing Station IDs"
        "b|Interactive Station ID Matching"
        "c|Commit Station ID Changes"
        "q|Back to Dispatcharr Menu"
    )
    
    show_menu "Match Missing Station IDs|dispatcharr|stationid_options"
}

# Channel Management submenu
show_dispatcharr_channel_menu() {
    channel_options=(
        "a|Populate Dispatcharr Fields|channel names, logos, tvg-ids"
        "b|Create New Channel|from search results"
        "c|Manage Existing Channels|modify, delete, streams"
        "q|Back to Dispatcharr Menu"
    )
    
    show_menu "Channel Management|dispatcharr|channel_options"
}

# Group Management submenu
show_dispatcharr_group_menu() {
    group_options=(
        "a|View Channel Groups"
        "b|Create New Group"
        "c|Modify Group"
        "d|Delete Group"
        "q|Back to Dispatcharr Menu"
    )
    
    show_menu "Group Management|dispatcharr|group_options"
}

show_markets_menu() {
    # Define without 'local' for eval access
    markets_options=(
        "1|Add Market|Configure new country/ZIP combination"
        "2|Remove Market|Remove existing market from configuration"
        "3|Import Markets from File|Bulk import from CSV file"
        "4|Export Markets to File|Backup current configuration"
        "5|Clean Up Postal Code Formats|Standardize existing entries"
        "6|Force Refresh Market|Reprocess specific market"
        "7|Ready to Expand Database|Proceed to User Database Expansion"
        "q|Back to Main Menu"
    )
    
    show_menu "Manage Television Markets|markets|markets_options"
}

# Private: Smart recommendations
_show_cache_recommendations() {
    local total_count=$(get_total_stations_count)
    local market_count=0
    if [ -f "$CSV_FILE" ]; then
        market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
    fi
    
    if [ "$total_count" -eq 0 ] && [ "$market_count" -eq 0 ]; then
        echo -e "${BOLD}${YELLOW}💡 Quick Start Recommendation:${RESET}"
        echo -e "${CYAN}   1. First: Use 'Manage Television Markets' from main menu${RESET}"
        echo -e "${CYAN}   2. Then: Return here for 'Incremental Update'${RESET}"
    elif [ "$total_count" -eq 0 ] && [ "$market_count" -gt 0 ]; then
        echo -e "${BOLD}${YELLOW}💡 Quick Start Recommendation:${RESET}"
        echo -e "${CYAN}   Try option 'a' Incremental Update to build your station database${RESET}"
    fi
}

_show_dispatcharr_recommendations() {
    local total_count=$(get_total_stations_count)
    
    if [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        echo -e "${BOLD}${YELLOW}💡 Quick Start Recommendation:${RESET}"
        echo -e "${CYAN}   Start with option 'e' to configure your Dispatcharr connection${RESET}"
    elif [[ "${DISPATCHARR_CONNECTION_VERIFIED:-}" != "true" ]] && ! dispatcharr_test_connection >/dev/null 2>&1; then
        echo -e "${BOLD}${YELLOW}💡 Connection Issue Detected:${RESET}"
        echo -e "${CYAN}   Try option 'e' to reconfigure connection or 'g' to refresh tokens${RESET}"
    elif [ "$total_count" -eq 0 ]; then
        echo -e "${BOLD}${YELLOW}💡 Database Required:${RESET}"
        echo -e "${CYAN}   Build station database first via 'Manage Television Markets'${RESET}"
    elif [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
        local pending_count=$(wc -l < "$DISPATCHARR_MATCHES")
        echo -e "${BOLD}${YELLOW}💡 Pending Changes Detected:${RESET}"
        echo -e "${CYAN}   You have $pending_count matches ready - try option 'c' to commit${RESET}"
    fi
}