#!/bin/bash

# === Settings Configuration Framework ===
# Universal configuration system eliminating massive duplication

# ============================================================================
# UNIVERSAL SETTING CONFIGURATION SYSTEM
# ============================================================================

# Generic setting configurator - handles all setting types
configure_setting() {
    local setting_type="$1"
    local setting_name="$2"
    local current_value="${3:-}"
    shift 3
    local options=("$@")
    
    case "$setting_type" in
        "boolean")
            _configure_boolean_setting "$setting_name" "$current_value"
            ;;
        "choice")
            _configure_choice_setting "$setting_name" "$current_value" "${options[@]}"
            ;;
        "multi_choice") 
            _configure_multi_choice_setting "$setting_name" "$current_value" "${options[@]}"
            ;;
        "numeric")
            _configure_numeric_setting "$setting_name" "$current_value" "${options[@]}"
            ;;
        "network")
            _configure_network_setting "$setting_name" "$current_value"
            ;;
        "credentials")
            _configure_credentials_setting "$setting_name"
            ;;
    esac
}

# ============================================================================
# PRIVATE IMPLEMENTATION FUNCTIONS
# ============================================================================

# Boolean setting (yes/no, enable/disable)
_configure_boolean_setting() {
    local setting_name="$1"
    local current_value="$2"
    
    local action_word="Enable"
    [[ "$current_value" == "true" ]] && action_word="Disable"
    
    if confirm_action "$action_word $setting_name?"; then
        local new_value="true"
        [[ "$current_value" == "true" ]] && new_value="false"
        
        save_setting "$setting_name" "$new_value"
        echo -e "${GREEN}✅ $setting_name $([ "$new_value" = "true" ] && echo "enabled" || echo "disabled")${RESET}"
        return 0
    else
        echo -e "${CYAN}💡 $setting_name unchanged${RESET}"
        return 1
    fi
}

# Choice setting (single selection from options)
_configure_choice_setting() {
    local setting_name="$1"
    local current_value="$2"
    shift 2
    local options=("$@")
    
    echo -e "${BOLD}Select $setting_name:${RESET}"
    for i in "${!options[@]}"; do
        local marker=""
        [[ "${options[$i]}" == "$current_value" ]] && marker=" ${GREEN}(current)${RESET}"
        echo -e "${GREEN}$((i+1)))${RESET} ${options[$i]}$marker"
    done
    echo
    
    while true; do
        read -p "Select option (1-${#options[@]}): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            local selected="${options[$((choice-1))]}"
            save_setting "$setting_name" "$selected"
            echo -e "${GREEN}✅ $setting_name set to: $selected${RESET}"
            return 0
        else
            echo -e "${RED}❌ Invalid choice. Please enter 1-${#options[@]}${RESET}"
        fi
    done
}

# Multi-choice setting (multiple selections)
_configure_multi_choice_setting() {
    local setting_name="$1"
    local current_value="$2"
    shift 2
    local options=("$@")
    
    echo -e "${BOLD}Select $setting_name (space-separated numbers or 'all'):${RESET}"
    for i in "${!options[@]}"; do
        echo -e "${GREEN}$((i+1)))${RESET} ${options[$i]}"
    done
    echo
    
    while true; do
        read -p "Select options: " input
        
        if [[ "$input" =~ [Aa][Ll][Ll] ]]; then
            local all_options=$(IFS=','; echo "${options[*]}")
            
            # FIXED: Set the correct variable based on setting name
            case "$setting_name" in
                *[Rr]esolution*|*[Qq]uality*)
                    ENABLED_RESOLUTIONS="$all_options"
                    ;;
                *[Cc]ountry*|*[Cc]ountries*)
                    ENABLED_COUNTRIES="$all_options"
                    ;;
                *)
                    echo -e "${RED}❌ Unknown setting type: $setting_name${RESET}"
                    return 1
                    ;;
            esac
            echo -e "${GREEN}✅ $setting_name set to: All options${RESET}"
            return 0
        fi
        
        local valid_selections=""
        local invalid_found=false
        
        for selection in $input; do
            if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#options[@]} )); then
                [[ -n "$valid_selections" ]] && valid_selections+=","
                valid_selections+="${options[$((selection-1))]}"
            else
                echo -e "${RED}❌ Invalid selection: $selection${RESET}"
                invalid_found=true
            fi
        done
        
        if [[ "$invalid_found" == "false" && -n "$valid_selections" ]]; then
            # FIXED: Set the correct variable based on setting name
            case "$setting_name" in
                *[Rr]esolution*|*[Qq]uality*)
                    ENABLED_RESOLUTIONS="$valid_selections"
                    ;;
                *[Cc]ountry*|*[Cc]ountries*)
                    ENABLED_COUNTRIES="$valid_selections"
                    ;;
                *)
                    echo -e "${RED}❌ Unknown setting type: $setting_name${RESET}"
                    return 1
                    ;;
            esac
            echo -e "${GREEN}✅ $setting_name set to: $valid_selections${RESET}"
            return 0
        elif [[ -z "$valid_selections" ]]; then
            echo -e "${RED}❌ No valid selections made${RESET}"
        fi
    done
}

# Numeric setting with range validation
_configure_numeric_setting() {
    local setting_name="$1"
    local current_value="$2"
    local min_value="${3:-1}"
    local max_value="${4:-100}"
    
    while true; do
        read -p "Enter $setting_name ($min_value-$max_value) [current: $current_value]: " input
        
        # Keep current if empty
        [[ -z "$input" ]] && input="$current_value"
        
        if validate_input "numeric_range" "$input" "$min_value" "$max_value"; then
            save_setting "$setting_name" "$input"
            echo -e "${GREEN}✅ $setting_name set to: $input${RESET}"
            return 0
        fi
    done
}

# Network setting (IP + Port)
_configure_network_setting() {
    local setting_name="$1"
    local current_url="$2"

    # Parse current URL
    local current_ip=$(echo "$current_url" | cut -d'/' -f3 | cut -d':' -f1)
    local current_port=$(echo "$current_url" | cut -d':' -f3)

    # Set defaults based on setting type
    if [[ "$setting_name" == "DISPATCHARR_URL" ]]; then
    current_ip=${current_ip:-"localhost"}
    current_port=${current_port:-"9191"}
    else
    # Channels DVR defaults
    current_ip=${current_ip:-"localhost"}
    current_port=${current_port:-"8089"}
    fi
    
    # Get new values
    local new_ip new_port
    
    while true; do
        read -p "Enter IP address [current: $current_ip]: " new_ip
        new_ip=${new_ip:-$current_ip}
        
        if validate_input "ip_address" "$new_ip"; then
            break
        fi
    done
    
    while true; do
        read -p "Enter port [current: $current_port]: " new_port
        new_port=${new_port:-$current_port}
        
        if validate_input "port" "$new_port"; then
            break
        fi
    done
    
    local new_url="http://$new_ip:$new_port"
    
    # Test connection if changed
    if [[ "$new_url" != "$current_url" ]]; then
        echo -e "${CYAN}🔗 Testing connection to $new_url...${RESET}"
        if test_connection "http" "$new_url"; then
            echo -e "${GREEN}✅ Connection successful${RESET}"
        else
            echo -e "${RED}❌ Connection failed${RESET}"
            if ! confirm_action "Save settings anyway?"; then
                return 1
            fi
        fi
    fi
    
    save_setting "$setting_name" "$new_url"
    echo -e "${GREEN}✅ $setting_name updated to: $new_url${RESET}"
    return 0
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

_validate_ip_address() {
    local ip="$1"
    
    if [[ "$ip" == "localhost" || "$ip" == "127.0.0.1" ]]; then
        return 0
    elif [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra parts <<< "$ip"
        for part in "${parts[@]}"; do
            if (( part < 0 || part > 255 )); then
                echo -e "${RED}❌ Invalid IP: Each number must be 0-255${RESET}"
                return 1
            fi
        done
        return 0
    else
        echo -e "${RED}❌ Invalid IP format${RESET}"
        return 1
    fi
}

_validate_port() {
    local port="$1"
    local min="${2:-1}"
    local max="${3:-65535}"
    
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= min && port <= max )); then
        return 0
    else
        echo -e "${RED}❌ Invalid port: Must be $min-$max${RESET}"
        return 1
    fi
}

_validate_numeric_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= min && value <= max )); then
        return 0
    else
        echo -e "${RED}❌ Invalid number: Must be $min-$max${RESET}"
        return 1
    fi
}

_validate_non_empty() {
    local value="$1"
    
    if [[ -n "$value" && ! "$value" =~ ^[[:space:]]*$ ]]; then
        return 0
    else
        echo -e "${RED}❌ Value cannot be empty${RESET}"
        return 1
    fi
}

# Dispatcharr connection testing
test_dispatcharr_connection() {
    local url="$1"
    local timeout="${2:-5}"
    
    local test_url="${url}/api/core/version/"
    local token_file="$CACHE_DIR/dispatcharr_tokens.json"
    
    if [[ -f "$token_file" ]]; then
        local access_token
        access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
        if [[ -n "$access_token" && "$access_token" != "null" ]]; then
            curl -s --connect-timeout "$timeout" -H "Authorization: Bearer $access_token" "$test_url" >/dev/null 2>&1
            return $?
        fi
    fi
    
    # Fallback to basic connection test
    curl -s --connect-timeout "$timeout" "$url" >/dev/null 2>&1
}

# Credentials setting (username/password)
_configure_credentials_setting() {
    local service_name="$1"
    
    echo -e "${BOLD}${BLUE}=== $service_name Authentication ===${RESET}"
    echo -e "${CYAN}💡 Enter your $service_name login credentials${RESET}"
    echo
    
    local username password
    
    # Username
    while true; do
        read -p "Username: " username
        if validate_input "non_empty" "$username"; then
            break
        fi
    done
    
    # Password (hidden input)
    while true; do
        read -s -p "Password: " password
        echo  # Add newline after hidden input
        if validate_input "non_empty" "$password"; then
            break
        fi
    done
    
    # Save credentials
    save_setting "${service_name^^}_USERNAME" "$username"
    save_setting "${service_name^^}_PASSWORD" "$password"
    
    echo -e "${GREEN}✅ Credentials saved for $service_name${RESET}"
    
    # Test authentication if possible
    if [[ "$service_name" == "Dispatcharr" ]]; then
        echo -e "${CYAN}🔑 Testing authentication...${RESET}"
        DISPATCHARR_USERNAME="$username"
        DISPATCHARR_PASSWORD="$password"
        
        if dispatcharr_test_connection; then
            echo -e "${GREEN}✅ Authentication successful${RESET}"
        else
            echo -e "${RED}❌ Authentication failed - check credentials${RESET}"
        fi
    fi
}