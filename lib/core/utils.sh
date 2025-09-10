#!/bin/bash
# lib/core/utils.sh - Core Utility Functions
# Safe utility functions with no external dependencies

# ============================================================================
# USER INTERACTION UTILITIES
# ============================================================================

pause_for_user() {
  read -p "Press Enter to continue..."
}

show_invalid_choice() {
  echo -e "${RED}❌ Invalid Option: Please select a valid option from the menu${RESET}"
  echo -e "${CYAN}💡 Check the available choices and try again${RESET}"
  sleep 2
}

confirm_action() {
  local message="$1"
  local default="${2:-n}"
  
  echo -e "${BOLD}${YELLOW}Confirmation Required:${RESET}"
  read -p "$message (y/n) [default: $default]: " response < /dev/tty
  response=${response:-$default}
  [[ "$response" =~ ^[Yy]$ ]]
}

# ============================================================================
# PROGRESS AND DISPLAY UTILITIES
# ============================================================================

show_progress_bar() {
  local current="$1"
  local total="$2"
  local percent="$3"
  local start_time="$4"  # Keep parameter for compatibility but don't use for ETA
  
  # Create simple progress bar with Unicode blocks
  local bar_width=20
  local filled=$((percent * bar_width / 100))
  local bar=""
  local i=0
  
  # Build progress bar
  while (( i < filled )); do
    bar+="█"
    ((i++))
  done
  while (( i < bar_width )); do
    bar+="░"
    ((i++))
  done

  # Show progress WITHOUT ETA - clean and simple
  printf "\r%3d%% [%s] %d/%d" "$percent" "$bar" "$current" "$total" >&2
  
  # Only add newline when completely finished
  if (( current == total )); then
    echo >&2
  fi
}

# ============================================================================
# UNIVERSAL CONFIGURATION SAVING
# ============================================================================

save_setting() {
    local setting_name="$1"
    local setting_value="$2"
    local config_file="${3:-$CONFIG_FILE}"
    
    # Create temp file
    local temp_config="${config_file}.tmp"
    
    # Remove existing setting
    grep -v "^${setting_name}=" "$config_file" > "$temp_config" 2>/dev/null || touch "$temp_config"
    
    # Add new setting
    echo "${setting_name}=\"${setting_value}\"" >> "$temp_config"
    
    # Atomic update
    if mv "$temp_config" "$config_file"; then
        return 0
    else
        rm -f "$temp_config" 2>/dev/null
        return 1
    fi
}

# Universal input validation
validate_input() {
    local validation_type="$1"
    local input="$2"
    shift 2
    local constraints=("$@")
    
    case "$validation_type" in
        "ip_address")
            _validate_ip_address "$input"
            ;;
        "port")
            _validate_port "$input" "${constraints[0]:-1}" "${constraints[1]:-65535}"
            ;;
        "numeric_range")
            _validate_numeric_range "$input" "${constraints[0]}" "${constraints[1]}"
            ;;
        "choice_list")
            _validate_choice_list "$input" "${constraints[@]}"
            ;;
        "multi_choice_list")
            _validate_multi_choice_list "$input" "${constraints[@]}"
            ;;
        "non_empty")
            _validate_non_empty "$input"
            ;;
    esac
}

# Universal connection testing
test_connection() {
    local connection_type="$1"
    local target="$2"
    local timeout="${3:-5}"
    
    case "$connection_type" in
        "http")
            curl -s --connect-timeout "$timeout" "$target" >/dev/null 2>&1
            ;;
        "api_endpoint")
            curl -s --connect-timeout "$timeout" "$target/api" >/dev/null 2>&1 || \
            curl -s --connect-timeout "$timeout" "$target" >/dev/null 2>&1
            ;;
        "dispatcharr")
            test_dispatcharr_connection "$target" "$timeout"
            ;;
    esac
}

# Universal setting status display
show_setting_status() {
    local setting_name="$1"
    local setting_value="$2"
    local setting_description="$3"
    local status_type="${4:-info}"
    
    echo -e "${BOLD}${BLUE}$setting_description:${RESET}"
    
    case "$status_type" in
        "enabled")
            echo -e "Status: ${GREEN}Enabled${RESET}"
            echo -e "Value: ${YELLOW}$setting_value${RESET}"
            ;;
        "disabled")
            echo -e "Status: ${YELLOW}Disabled${RESET}"
            ;;
        "configured")
            echo -e "Status: ${GREEN}Configured${RESET}"
            echo -e "Value: ${CYAN}$setting_value${RESET}"
            ;;
        "not_configured")
            echo -e "Status: ${RED}Not Configured${RESET}"
            ;;
        *)
            echo -e "Current: ${CYAN}$setting_value${RESET}"
            ;;
    esac
}

ensure_stations_database() {
    if ! has_stations_database; then
        echo -e "${RED}❌ No station database available${RESET}"
        echo -e "${CYAN}💡 Function not available - requires station database${RESET}"
        return 1
    fi
    return 0
}

validate_station_id_input() {
    local input="$1"
    
    # Remove any whitespace
    local cleaned_id=$(echo "$input" | tr -d '[:space:]')
    
    # Validate station ID format
    if [[ "$cleaned_id" =~ ^[0-9]+$ ]]; then
        if (( cleaned_id >= 1 && cleaned_id <= 999999 )); then
            echo "$cleaned_id"  # Return the cleaned valid ID
            return 0
        else
            echo -e "${RED}❌ Station ID out of valid range (1-999999)${RESET}" >&2
            return 1
        fi
    else
        echo -e "${RED}❌ Station ID must be numeric only${RESET}" >&2
        return 1
    fi
}

# ============================================================================
# API UTILITY FUNCTIONS
# ============================================================================

# Ensure configuration variables are available
ensure_config_loaded() {
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    if [[ -f "$config_file" ]] && [[ -z "${CHANNELS_URL:-}" || -z "${DISPATCHARR_URL:-}" ]]; then
        source "$config_file" 2>/dev/null
    fi
}

# URL encoding utility
url_encode() {
    local string="$1"
    local encoded=""
    local length=${#string}
    
    for ((i=0; i<length; i++)); do
        local char="${string:i:1}"
        case "$char" in
            [a-zA-Z0-9.~_-])
                encoded+="$char"
                ;;
            ' ')
                encoded+="%20"
                ;;
            *)
                # Convert to hex for other special characters
                printf -v hex "%02X" "'$char"
                encoded+="%$hex"
                ;;
        esac
    done
    
    echo "$encoded"
}

# ============================================================================
# NETWORK VALIDATION FUNCTIONS
# ============================================================================

# Validate IPv4 address
utils_validate_ip_address() {
    local ip="$1"
    
    # IPv4 pattern
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Validate each octet
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if (( octet > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    
    # IPv6 pattern (simplified)
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    fi
    
    return 1
}

# Validate hostname/FQDN
utils_validate_hostname() {
    local host="$1"
    
    # Hostname pattern (RFC 1123)
    if [[ "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    fi
    
    return 1
}

# Validate port number
utils_validate_port() {
    local port="$1"
    
    # Empty port is valid (for reverse proxy)
    if [[ -z "$port" ]]; then
        return 0
    fi
    
    # Check if numeric and in valid range
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
        return 0
    fi
    
    return 1
}

# Combined host validation (IP or hostname)
utils_validate_host() {
    local host="$1"
    
    # Try IP validation first, then hostname
    utils_validate_ip_address "$host" || utils_validate_hostname "$host"
}

# ============================================================================
# SERVICE CONFIGURATION HELPERS
# ============================================================================

# Display service configuration consistently
utils_show_service_config() {
    local service_name="$1"
    local enabled="$2"
    local host="$3"
    local port="$4"
    local connection_status="$5"
    
    echo -e "${BOLD}${BLUE}$service_name Configuration${RESET}"
    echo -e "Status: $([ "$enabled" = "true" ] && echo "${GREEN}Enabled${RESET}" || echo "${YELLOW}Disabled${RESET}")"
    
    if [[ "$enabled" == "true" ]]; then
        if [[ -n "$port" ]]; then
            echo -e "Server: ${CYAN}$host:$port${RESET}"
        else
            echo -e "Server: ${CYAN}$host${RESET}"
        fi
        echo -e "Connection: $connection_status"
    fi
    echo
}

# Prompt for port with reverse proxy support
utils_prompt_for_port() {
    local service_name="$1"
    local default_port="$2"
    local port
    
    echo
    echo "Port Configuration:"
    echo "- Default port: $default_port"
    echo "- Press Enter to leave port blank"
    read -p "Enter port: " port
    
    # Validate if provided
    if [[ -n "$port" ]] && ! utils_validate_port "$port"; then
        echo -e "${RED}Invalid port number. Please enter a number between 1-65535.${RESET}"
        return 1
    fi
    
    echo "$port"  # Returns empty string if user pressed Enter
}

# Build URL with optional port
utils_build_service_url() {
    local protocol="$1"
    local host="$2"
    local port="$3"
    
    if [[ -n "$port" ]]; then
        echo "${protocol}://${host}:${port}"
    else
        echo "${protocol}://${host}"
    fi
}

# ============================================================================
# INTERNAL VALIDATION HELPERS (for validate_input function)
# ============================================================================

_validate_ip_address() {
    utils_validate_ip_address "$1"
}

_validate_port() {
    local port="$1"
    local min="${2:-1}"
    local max="${3:-65535}"
    
    if utils_validate_port "$port" && [[ -n "$port" ]]; then
        if (( port >= min && port <= max )); then
            return 0
        fi
    elif [[ -z "$port" ]]; then
        # Empty port is valid
        return 0
    fi
    
    return 1
}

_validate_numeric_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        if (( value >= min && value <= max )); then
            return 0
        fi
    fi
    
    return 1
}

_validate_choice_list() {
    local choice="$1"
    shift
    local valid_choices=("$@")
    
    for valid in "${valid_choices[@]}"; do
        if [[ "$choice" == "$valid" ]]; then
            return 0
        fi
    done
    
    return 1
}

_validate_multi_choice_list() {
    local choices="$1"
    shift
    local valid_choices=("$@")
    
    # Split comma-separated choices
    IFS=',' read -ra selected <<< "$choices"
    
    for choice in "${selected[@]}"; do
        local found=0
        for valid in "${valid_choices[@]}"; do
            if [[ "$choice" == "$valid" ]]; then
                found=1
                break
            fi
        done
        if [[ $found -eq 0 ]]; then
            return 1
        fi
    done
    
    return 0
}

_validate_non_empty() {
    local value="$1"
    
    if [[ -n "$value" ]]; then
        return 0
    fi
    
    return 1
}

