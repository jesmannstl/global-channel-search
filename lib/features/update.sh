#!/bin/bash

# === Git-Based Auto-Update Module ===
# Handles git-based version checking and update instructions
# Part of the Global Station Search modular architecture

# ============================================================================
# UPDATE CONFIGURATION
# ============================================================================

# GitHub repository configuration
readonly GITHUB_REPO="jesmannstl/global-channel-search"
readonly GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}"
readonly SCRIPT_NAME="globalstationsearch.sh"

# Update settings (loaded from config)
UPDATE_CHECK_ENABLED="${UPDATE_CHECK_ENABLED:-true}"
UPDATE_CHECK_FREQUENCY="${UPDATE_CHECK_FREQUENCY:-daily}"  # daily, weekly, manual
UPDATE_CHANNEL="${UPDATE_CHANNEL:-main}"  # main, develop, or specific branch
AUTO_GIT_PULL="${AUTO_GIT_PULL:-false}"
BACKUP_BEFORE_UPDATE="${BACKUP_BEFORE_UPDATE:-true}"

# Internal update state
UPDATE_CACHE_DIR="$CACHE_DIR/updates"
UPDATE_LOG="$LOGS_DIR/updates.log"
LAST_CHECK_FILE="$UPDATE_CACHE_DIR/last_check"
AVAILABLE_UPDATE_FILE="$UPDATE_CACHE_DIR/available_update.json"

# ============================================================================
# INITIALIZATION
# ============================================================================

init_update_system() {
    # Create update directories
    mkdir -p "$UPDATE_CACHE_DIR"
    touch "$UPDATE_LOG"
    
    # Load update configuration
    load_update_config
    
    log_update_operation "Git-based update system initialized"
}

load_update_config() {
    # Load from main config file if exists
    if [[ -f "$CONFIG_FILE" ]]; then
        UPDATE_CHECK_ENABLED=$(grep "^UPDATE_CHECK_ENABLED=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        UPDATE_CHECK_FREQUENCY=$(grep "^UPDATE_CHECK_FREQUENCY=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "daily")
        UPDATE_CHANNEL=$(grep "^UPDATE_CHANNEL=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "main")
        AUTO_GIT_PULL=$(grep "^AUTO_GIT_PULL=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "false")
        BACKUP_BEFORE_UPDATE=$(grep "^BACKUP_BEFORE_UPDATE=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
    fi
}

save_update_config() {
    # Save update settings to main config
    save_setting "UPDATE_CHECK_ENABLED" "$UPDATE_CHECK_ENABLED"
    save_setting "UPDATE_CHECK_FREQUENCY" "$UPDATE_CHECK_FREQUENCY"
    save_setting "UPDATE_CHANNEL" "$UPDATE_CHANNEL"
    save_setting "AUTO_GIT_PULL" "$AUTO_GIT_PULL"
    save_setting "BACKUP_BEFORE_UPDATE" "$BACKUP_BEFORE_UPDATE"
}

check_network_connectivity() {
    # Test GitHub connectivity specifically
    if curl -s --connect-timeout 5 --max-time 10 "https://api.github.com" >/dev/null 2>&1; then
        return 0  # Network is good
    else
        return 1  # Network issue
    fi
}

# ============================================================================
# GIT-BASED UPDATE CHECKING
# ============================================================================

get_latest_commit_info() {
    local branch="${1:-$UPDATE_CHANNEL}"
    local api_url="${GITHUB_API_URL}/commits/${branch}"
    
    local response
    response=$(curl -s --connect-timeout 10 --max-time 20 \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_url" 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        log_update_operation "GitHub API call failed: no response for commits"
        return 1
    fi
    
    # Check for GitHub API error responses
    local api_message=$(echo "$response" | jq -r '.message // empty' 2>/dev/null)
    if [[ -n "$api_message" ]]; then
        log_update_operation "GitHub API error: $api_message"
        return 1
    fi
    
    echo "$response"
}

get_local_git_info() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        return 1  # Not a git repository
    fi
    
    # Get current commit hash and info
    local current_commit=$(git rev-parse HEAD 2>/dev/null)
    local current_date=$(git log -1 --format="%ci" 2>/dev/null)
    local current_message=$(git log -1 --format="%s" 2>/dev/null)
    local current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    local current_author=$(git log -1 --format="%an" 2>/dev/null)
    
    if [[ -n "$current_commit" ]]; then
        echo "{\"sha\": \"$current_commit\", \"date\": \"$current_date\", \"message\": \"$current_message\", \"branch\": \"$current_branch\", \"author\": \"$current_author\"}"
        return 0
    else
        return 1
    fi
}

check_for_updates() {
    local force_check="${1:-false}"
    local show_output="${2:-true}"
    
    if [[ "$UPDATE_CHECK_ENABLED" != "true" ]] && [[ "$force_check" != "true" ]]; then
        [[ "$show_output" == "true" ]] && echo -e "${YELLOW}⚠️  Update checking is disabled${RESET}"
        return 1
    fi
    
    # Check if we need to perform a check based on frequency
    if [[ "$force_check" != "true" ]] && ! should_check_for_updates; then
        [[ "$show_output" == "true" ]] && echo -e "${CYAN}💡 Update check not needed yet (frequency: $UPDATE_CHECK_FREQUENCY)${RESET}"
        return 0
    fi
    
    [[ "$show_output" == "true" ]] && echo -e "${CYAN}🔄 Checking for repository updates...${RESET}"
    
    # Force UPDATE_CHANNEL to main if empty
    local check_branch="${UPDATE_CHANNEL:-main}"
    [[ -z "$check_branch" ]] && check_branch="main"
    
    # Get local git information
    local local_git_info
    local is_git_repo=false
    local current_commit=""
    
    if local_git_info=$(get_local_git_info); then
        is_git_repo=true
        current_commit=$(echo "$local_git_info" | jq -r '.sha // empty')
        local current_branch=$(echo "$local_git_info" | jq -r '.branch // "main"')
        local current_date=$(echo "$local_git_info" | jq -r '.date // empty')
        
        if [[ "$show_output" == "true" ]]; then
            echo -e "${CYAN}📍 Local git repository detected${RESET}"
            echo -e "${CYAN}   Branch: $current_branch${RESET}"
            echo -e "${CYAN}   Commit: ${current_commit:0:8}${RESET}"
            echo -e "${CYAN}   Date: $current_date${RESET}"
            echo -e "${CYAN}   Checking remote branch: $check_branch${RESET}"
        fi
    else
        # Not a git repository - use configured branch
        if [[ "$show_output" == "true" ]]; then
            echo -e "${YELLOW}📍 Not a git repository - checking $check_branch branch${RESET}"
        fi
    fi
    
    # Get latest commit info from GitHub
    local latest_commit_info
    latest_commit_info=$(get_latest_commit_info "$check_branch")
    
    if [[ $? -ne 0 ]] || [[ -z "$latest_commit_info" ]]; then
        [[ "$show_output" == "true" ]] && echo -e "${RED}❌ Failed to check for updates${RESET}"
        [[ "$show_output" == "true" ]] && echo -e "${CYAN}💡 Checking branch: $check_branch${RESET}"
        [[ "$show_output" == "true" ]] && echo -e "${CYAN}💡 Repository: https://github.com/${GITHUB_REPO}${RESET}"
        log_update_operation "Update check failed: Unable to fetch commit info for branch $check_branch"
        return 1
    fi
    
    # Parse remote commit information
    local remote_commit=$(echo "$latest_commit_info" | jq -r '.sha // empty' 2>/dev/null)
    local remote_date=$(echo "$latest_commit_info" | jq -r '.commit.committer.date // empty' 2>/dev/null)
    local remote_message=$(echo "$latest_commit_info" | jq -r '.commit.message // empty' 2>/dev/null)
    local remote_author=$(echo "$latest_commit_info" | jq -r '.commit.author.name // empty' 2>/dev/null)
    
    if [[ -z "$remote_commit" ]]; then
        [[ "$show_output" == "true" ]] && echo -e "${RED}❌ Failed to parse remote commit information${RESET}"
        log_update_operation "Update check failed: Unable to parse commit info"
        return 1
    fi
    
    # Compare commits
    if [[ "$is_git_repo" == "true" ]]; then
        if [[ "$current_commit" == "$remote_commit" ]]; then
            # Up to date
            rm -f "$AVAILABLE_UPDATE_FILE"
            record_update_check "up_to_date" "${remote_commit:0:8}"
            
            if [[ "$show_output" == "true" ]]; then
                echo -e "${GREEN}✅ Your repository is up to date${RESET}"
                echo -e "${CYAN}💡 Local and remote commits match: ${remote_commit:0:8}${RESET}"
            fi
            
            log_update_operation "Up to date: ${current_commit:0:8} matches remote ${remote_commit:0:8}"
            return 0
        else
            # Updates available
            create_git_update_info "$latest_commit_info" "$local_git_info"
            record_update_check "update_available" "${remote_commit:0:8}"
            
            if [[ "$show_output" == "true" ]]; then
                show_git_update_notification "$remote_commit" "$remote_date" "$remote_message" "$remote_author" "$current_commit"
            fi
            
            log_update_operation "Updates available: ${current_commit:0:8} -> ${remote_commit:0:8}"
            return 2  # Updates available
        fi
    else
        # Not a git repository - just show latest commit info
        create_git_update_info "$latest_commit_info" "{}"
        record_update_check "not_git_repo" "${remote_commit:0:8}"
        
        if [[ "$show_output" == "true" ]]; then
            show_git_repository_info "$remote_commit" "$remote_date" "$remote_message" "$remote_author"
        fi
        
        log_update_operation "Not a git repository - showed latest commit info"
        return 0
    fi
}

create_git_update_info() {
    local remote_info="$1"
    local local_info="$2"
    
    local update_info=$(jq -n \
        --argjson remote "$remote_info" \
        --argjson local "$local_info" \
        '{
            type: "git_update",
            remote: $remote,
            local: $local,
            timestamp: now
        }')
    
    echo "$update_info" > "$AVAILABLE_UPDATE_FILE"
}

show_git_update_notification() {
    local remote_commit="$1"
    local remote_date="$2"
    local remote_message="$3"
    local remote_author="$4"
    local current_commit="$5"
    
    echo
    echo -e "${BOLD}${GREEN}🎉 Repository Updates Available!${RESET}"
    echo -e "${YELLOW}Your Version: ${current_commit:0:8}${RESET}"
    echo -e "${GREEN}Latest Version: ${remote_commit:0:8}${RESET}"
    echo
    echo -e "${BOLD}Latest Changes:${RESET}"
    echo -e "${CYAN}Date: $remote_date${RESET}"
    echo -e "${CYAN}Author: $remote_author${RESET}"
    echo -e "${CYAN}Message: $remote_message${RESET}"
    echo
    echo -e "${BOLD}${CYAN}To Update:${RESET}"
    echo -e "${GREEN}1. Run: git pull${RESET}"
    echo -e "${GREEN}2. Or use Update Management → Download and Install${RESET}"
    echo -e "${YELLOW}3. Then restart the script to use the latest version${RESET}"
    echo
}

show_git_repository_info() {
    local remote_commit="$1"
    local remote_date="$2"
    local remote_message="$3"
    local remote_author="$4"
    
    echo
    echo -e "${BOLD}${BLUE}📋 Latest Repository Information${RESET}"
    echo -e "${GREEN}Latest Commit: ${remote_commit:0:8}${RESET}"
    echo -e "${CYAN}Date: $remote_date${RESET}"
    echo -e "${CYAN}Author: $remote_author${RESET}"
    echo -e "${CYAN}Message: $remote_message${RESET}"
    echo
    echo -e "${BOLD}${CYAN}To Get This Version:${RESET}"
    echo -e "${GREEN}1. Clone: git clone https://github.com/${GITHUB_REPO}.git${RESET}"
    echo -e "${GREEN}2. Or download: https://github.com/${GITHUB_REPO}/archive/${UPDATE_CHANNEL}.zip${RESET}"
    echo
}

should_check_for_updates() {
    [[ ! -f "$LAST_CHECK_FILE" ]] && return 0
    
    local last_check=$(cat "$LAST_CHECK_FILE" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_check))
    
    case "$UPDATE_CHECK_FREQUENCY" in
        "startup")
            return 0  # Always check on startup
            ;;
        "daily")
            [[ $time_diff -gt 86400 ]]  # 24 hours
            ;;
        "weekly")
            [[ $time_diff -gt 604800 ]] # 7 days
            ;;
        "manual")
            return 1  # Never auto-check
            ;;
        *)
            return 0  # Default to check
            ;;
    esac
}

record_update_check() {
    local status="$1"
    local version="$2"
    local timestamp=$(date +%s)
    
    echo "$timestamp" > "$LAST_CHECK_FILE"
    echo "{\"timestamp\": $timestamp, \"status\": \"$status\", \"version\": \"$version\"}" > "$UPDATE_CACHE_DIR/last_check.json"
}

# ============================================================================
# UPDATE NOTIFICATIONS
# ============================================================================

show_startup_update_notification() {
    if [[ ! -f "$AVAILABLE_UPDATE_FILE" ]]; then
        return 0
    fi
    
    local update_info=$(cat "$AVAILABLE_UPDATE_FILE" 2>/dev/null)
    if [[ -z "$update_info" ]]; then
        return 0
    fi
    
    local update_type=$(echo "$update_info" | jq -r '.type // empty' 2>/dev/null)
    if [[ "$update_type" == "git_update" ]]; then
        local remote_commit=$(echo "$update_info" | jq -r '.remote.sha // empty' 2>/dev/null)
        local local_commit=$(echo "$update_info" | jq -r '.local.sha // empty' 2>/dev/null)
        
        if [[ -n "$remote_commit" ]]; then
            echo -e "${CYAN}💡 Repository updates available: ${local_commit:0:8} → ${remote_commit:0:8}${RESET}"
            echo -e "${CYAN}   Use Settings → Update Management or run 'git pull'${RESET}"
        fi
    fi
}

show_enhanced_update_notification() {
    if [[ ! -f "$AVAILABLE_UPDATE_FILE" ]]; then
        return 0
    fi
    
    local update_info=$(cat "$AVAILABLE_UPDATE_FILE" 2>/dev/null)
    if [[ -z "$update_info" ]]; then
        return 0
    fi
    
    local update_type=$(echo "$update_info" | jq -r '.type // empty' 2>/dev/null)
    if [[ "$update_type" == "git_update" ]]; then
        local remote_commit=$(echo "$update_info" | jq -r '.remote.sha // empty' 2>/dev/null)
        local local_commit=$(echo "$update_info" | jq -r '.local.sha // empty' 2>/dev/null)
        local remote_date=$(echo "$update_info" | jq -r '.remote.commit.committer.date // empty' 2>/dev/null)
        local remote_message=$(echo "$update_info" | jq -r '.remote.commit.message // empty' 2>/dev/null)
        
        if [[ -n "$remote_commit" ]]; then
            echo
            echo -e "${BOLD}${GREEN}📦 Repository Updates Available!${RESET}"
            echo -e "${CYAN}   Current: ${local_commit:0:8} → Latest: ${remote_commit:0:8}${RESET}"
            
            # Show commit message if available (truncate if too long)
            if [[ -n "$remote_message" ]] && [[ ${#remote_message} -lt 60 ]]; then
                echo -e "${CYAN}   Latest: $remote_message${RESET}"
            fi
            
            # Show age of update if date available
            if [[ -n "$remote_date" ]]; then
                local commit_date=$(date -d "$remote_date" "+%b %d" 2>/dev/null || echo "")
                [[ -n "$commit_date" ]] && echo -e "${CYAN}   Date: $commit_date${RESET}"
            fi
            
            echo -e "${CYAN}   Use Settings → Update Management to install${RESET}"
            echo
        fi
    fi
}

# ============================================================================
# GIT-BASED UPDATE INSTALLATION
# ============================================================================

download_and_install_update() {
    if [[ ! -f "$AVAILABLE_UPDATE_FILE" ]]; then
        echo -e "${RED}❌ No update information available${RESET}"
        echo -e "${CYAN}💡 Run 'Check for Updates' first${RESET}"
        return 1
    fi
    
    local update_info=$(cat "$AVAILABLE_UPDATE_FILE")
    local update_type=$(echo "$update_info" | jq -r '.type // empty' 2>/dev/null)
    
    if [[ "$update_type" != "git_update" ]]; then
        echo -e "${RED}❌ Invalid update information${RESET}"
        return 1
    fi
    
    local remote_commit=$(echo "$update_info" | jq -r '.remote.sha // empty' 2>/dev/null)
    local remote_message=$(echo "$update_info" | jq -r '.remote.commit.message // empty' 2>/dev/null)
    
    echo -e "${BOLD}${CYAN}=== Git-Based Update Installation ===${RESET}"
    echo -e "${CYAN}Latest commit: ${remote_commit:0:8}${RESET}"
    echo -e "${CYAN}Changes: $remote_message${RESET}"
    echo
    
    # Check if we're in a git repository
    if git rev-parse --git-dir >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Git repository detected${RESET}"
        echo
        
        # Check git status
        if ! git diff-index --quiet HEAD --; then
            echo -e "${YELLOW}⚠️  You have uncommitted changes${RESET}"
            echo -e "${CYAN}💡 Commit or stash your changes before updating${RESET}"
            
            if ! confirm_action "Continue with update anyway? (may cause conflicts)"; then
                echo -e "${YELLOW}Update cancelled${RESET}"
                return 1
            fi
        fi
        
        # Create backup if enabled
        if [[ "$BACKUP_BEFORE_UPDATE" == "true" ]]; then
            echo -e "${CYAN}📦 Creating backup before update...${RESET}"
            if backup_create "pre_git_pull_update"; then
                echo -e "${GREEN}✅ Backup created successfully${RESET}"
            else
                echo -e "${YELLOW}⚠️  Backup failed, but continuing...${RESET}"
            fi
        fi
        
        # Offer to run git pull
        echo -e "${BOLD}${CYAN}Update Options:${RESET}"
        echo -e "${GREEN}1. Automatic: Run 'git pull' now${RESET}"
        echo -e "${GREEN}2. Manual: Show git commands to run${RESET}"
        echo
        
        read -p "Select option (1/2): " update_choice
        
        case "$update_choice" in
            1)
                echo -e "${CYAN}🔄 Running git pull...${RESET}"
                
                if git pull; then
                    echo -e "${GREEN}✅ Repository updated successfully!${RESET}"
                    echo -e "${YELLOW}🔄 Please restart the script to use the latest version${RESET}"
                    
                    # Clean up update info
                    rm -f "$AVAILABLE_UPDATE_FILE"
                    log_update_operation "Successfully updated via git pull"
                    
                    return 0
                else
                    echo -e "${RED}❌ Git pull failed${RESET}"
                    echo -e "${CYAN}💡 You may need to resolve conflicts manually${RESET}"
                    echo -e "${CYAN}💡 Run 'git status' to see what needs attention${RESET}"
                    return 1
                fi
                ;;
            2|"")
                echo -e "${BOLD}${CYAN}Manual Update Commands:${RESET}"
                echo -e "${GREEN}1. Update repository:${RESET}"
                echo -e "   git pull"
                echo
                echo -e "${GREEN}2. Check for conflicts:${RESET}"
                echo -e "   git status"
                echo
                echo -e "${GREEN}3. If conflicts exist:${RESET}"
                echo -e "   git mergetool  # or edit files manually"
                echo -e "   git commit"
                echo
                echo -e "${GREEN}4. Restart script:${RESET}"
                echo -e "   ./globalstationsearch.sh"
                echo
                return 0
                ;;
            *)
                echo -e "${RED}❌ Invalid option${RESET}"
                return 1
                ;;
        esac
    else
        echo -e "${YELLOW}⚠️  Not a git repository${RESET}"
        echo
        echo -e "${BOLD}${CYAN}Manual Download Options:${RESET}"
        echo -e "${GREEN}1. Download latest version:${RESET}"
        echo -e "   https://github.com/${GITHUB_REPO}/archive/${UPDATE_CHANNEL}.zip"
        echo
        echo -e "${GREEN}2. Clone repository:${RESET}"
        echo -e "   git clone https://github.com/${GITHUB_REPO}.git"
        echo
        echo -e "${GREEN}3. Download specific file:${RESET}"
        echo -e "   https://raw.githubusercontent.com/${GITHUB_REPO}/${UPDATE_CHANNEL}/globalstationsearch.sh"
        echo
        
        if confirm_action "Open repository URL in browser?"; then
            local repo_url="https://github.com/${GITHUB_REPO}"
            echo -e "${CYAN}🌐 Repository: $repo_url${RESET}"
            
            # Try to open URL (platform-specific)
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$repo_url" 2>/dev/null &
            elif command -v open >/dev/null 2>&1; then
                open "$repo_url" 2>/dev/null &
            fi
        fi
    fi
    
    return 0
}

# ============================================================================
# UPDATE MANAGEMENT INTERFACE
# ============================================================================

show_update_management_menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== Update Management ===${RESET}\n"
        
        # Show current status
        show_update_status
        
        echo -e "${BOLD}${CYAN}Update Options:${RESET}"
        echo -e "${GREEN}a)${RESET} Check for Updates"
        echo -e "${GREEN}b)${RESET} Download and Install Update"
        echo -e "${GREEN}c)${RESET} Configure Update Settings"
        echo -e "${GREEN}d)${RESET} View Update History"
        echo -e "${GREEN}e)${RESET} Manual Git Commands"
        echo -e "${GREEN}f)${RESET} Test Repository Status"
        echo -e "${GREEN}g)${RESET} Validate Configuration"
        echo -e "${GREEN}h)${RESET} Clean Update Cache"
        echo -e "${GREEN}q)${RESET} Back to Settings"
        echo
        
        read -p "Select option: " choice
        
        case $choice in
            a|A)
                echo
                check_for_updates true true
                pause_for_user
                ;;
            b|B)
                echo
                # Use enhanced version with safety checks
                if command -v download_and_install_update_enhanced >/dev/null 2>&1; then
                    download_and_install_update_enhanced
                else
                    download_and_install_update
                fi
                pause_for_user
                ;;
            c|C)
                configure_update_settings
                ;;
            d|D)
                show_update_history
                pause_for_user
                ;;
            e|E)
                show_manual_git_commands
                pause_for_user
                ;;
            f|F)
                echo
                echo -e "${BOLD}${BLUE}=== Repository Diagnostic ===${RESET}"
                perform_update_safety_checks
                echo
                pause_for_user
                ;;
            g|G)
                echo
                echo -e "${BOLD}${BLUE}=== Configuration Validation ===${RESET}"
                validate_update_configuration
                echo
                pause_for_user
                ;;
            h|H)
                echo
                echo -e "${CYAN}🧹 Cleaning update cache...${RESET}"
                cleanup_update_cache
                echo -e "${GREEN}✅ Update cache cleaned${RESET}"
                pause_for_user
                ;;
            q|Q|"")
                break
                ;;
            *)
                echo -e "${RED}❌ Invalid option${RESET}"
                sleep 1
                ;;
        esac
    done
}

show_update_status() {
    echo -e "${BOLD}${BLUE}Current Update Status:${RESET}"
    echo -e "${CYAN}Current Version: ${BOLD}$VERSION${RESET}"
    local display_branch="${UPDATE_CHANNEL:-main}"
    [[ -z "$display_branch" ]] && display_branch="main"
    echo -e "${CYAN}Update Branch: ${BOLD}$display_branch${RESET}"
    
    # Enhanced frequency display
    local frequency_display="$UPDATE_CHECK_FREQUENCY"
    case "$UPDATE_CHECK_FREQUENCY" in
        "startup") frequency_display="Every startup" ;;
        "daily") frequency_display="Daily" ;;
        "weekly") frequency_display="Weekly" ;;
        "manual") frequency_display="Manual only" ;;
    esac
    
    echo -e "${CYAN}Auto-Check: ${BOLD}$([ "$UPDATE_CHECK_ENABLED" == "true" ] && echo "Enabled ($frequency_display)" || echo "Disabled")${RESET}"
    
    # Show git repository status
    if git rev-parse --git-dir >/dev/null 2>&1; then
        local current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        local current_commit=$(git rev-parse HEAD 2>/dev/null)
        echo -e "${CYAN}Git Repository: ${GREEN}Yes${RESET} (branch: $current_branch, commit: ${current_commit:0:8})"
    else
        echo -e "${CYAN}Git Repository: ${YELLOW}No${RESET} (manual download mode)"
    fi
    
    # Show last check info
    if [[ -f "$UPDATE_CACHE_DIR/last_check.json" ]]; then
        local last_check_info=$(cat "$UPDATE_CACHE_DIR/last_check.json" 2>/dev/null)
        if [[ -n "$last_check_info" ]]; then
            local last_check_time=$(echo "$last_check_info" | jq -r '.timestamp // empty' 2>/dev/null)
            local last_check_status=$(echo "$last_check_info" | jq -r '.status // empty' 2>/dev/null)
            
            if [[ -n "$last_check_time" ]]; then
                local check_date=$(date -d "@$last_check_time" 2>/dev/null || date -r "$last_check_time" 2>/dev/null || echo "Unknown")
                echo -e "${CYAN}Last Check: ${BOLD}$check_date${RESET} ($last_check_status)"
            fi
        fi
    fi
    
    # Show available update
    if [[ -f "$AVAILABLE_UPDATE_FILE" ]]; then
        local update_info=$(cat "$AVAILABLE_UPDATE_FILE" 2>/dev/null)
        local remote_commit=$(echo "$update_info" | jq -r '.remote.sha // empty' 2>/dev/null)
        if [[ -n "$remote_commit" ]]; then
            echo -e "${GREEN}📦 Available Update: ${BOLD}${remote_commit:0:8}${RESET}"
        fi
    fi
    
    echo
}

configure_update_settings() {
    clear
    echo -e "${BOLD}${CYAN}=== Configure Update Settings ===${RESET}\n"
    
    # Update check enabled/disabled
    echo -e "${BOLD}1. Enable Automatic Update Checking?${RESET}"
    echo -e "Current: $([ "$UPDATE_CHECK_ENABLED" == "true" ] && echo "${GREEN}Enabled${RESET}" || echo "${RED}Disabled${RESET}")"
    echo -e "${GREEN}y)${RESET} Enable automatic checking"
    echo -e "${GREEN}n)${RESET} Disable automatic checking"
    echo -e "${GREEN}c)${RESET} Keep current setting"
    
    read -p "Choice: " enable_choice
    case "$enable_choice" in
        y|Y) UPDATE_CHECK_ENABLED="true" ;;
        n|N) UPDATE_CHECK_ENABLED="false" ;;
    esac
    
    if [[ "$UPDATE_CHECK_ENABLED" == "true" ]]; then
        echo
        echo -e "${BOLD}2. Update Check Frequency?${RESET}"
        echo -e "Current: ${CYAN}$UPDATE_CHECK_FREQUENCY${RESET}"
        echo -e "${GREEN}s)${RESET} Every startup (check each time script runs)"
        echo -e "${GREEN}d)${RESET} Daily (once per day)"
        echo -e "${GREEN}w)${RESET} Weekly (once per week)"
        echo -e "${GREEN}m)${RESET} Manual only (never auto-check)"
        echo -e "${GREEN}c)${RESET} Keep current setting"
        echo
        echo -e "${CYAN}💡 'Every startup' is recommended for active development${RESET}"
        
        read -p "Choice: " freq_choice
        case "$freq_choice" in
            s|S) UPDATE_CHECK_FREQUENCY="startup" ;;
            d|D) UPDATE_CHECK_FREQUENCY="daily" ;;
            w|W) UPDATE_CHECK_FREQUENCY="weekly" ;;
            m|M) UPDATE_CHECK_FREQUENCY="manual" ;;
        esac
    fi
    
    echo
    echo -e "${BOLD}3. Update Branch/Channel?${RESET}"
    echo -e "Current: ${CYAN}$UPDATE_CHANNEL${RESET}"
    echo -e "${GREEN}m)${RESET} main (stable releases) ${GREEN}[AVAILABLE]${RESET}"
    echo -e "${YELLOW}d)${RESET} develop (latest development) ${YELLOW}[DISABLED - Not implemented yet]${RESET}"
    echo -e "${YELLOW}o)${RESET} other (specify branch name) ${YELLOW}[DISABLED - Not implemented yet]${RESET}"
    echo -e "${GREEN}c)${RESET} Keep current setting"
    echo
    echo -e "${CYAN}💡 Currently only 'main' branch is supported${RESET}"
    
    read -p "Choice: " channel_choice
    case "$channel_choice" in
        m|M) 
            UPDATE_CHANNEL="main" 
            ;;
        d|D) 
            echo -e "${YELLOW}⚠️  Develop branch is not available yet${RESET}"
            echo -e "${CYAN}💡 Keeping current setting: $UPDATE_CHANNEL${RESET}"
            ;;
        o|O) 
            echo -e "${YELLOW}⚠️  Custom branches are not available yet${RESET}"
            echo -e "${CYAN}💡 Keeping current setting: $UPDATE_CHANNEL${RESET}"
            ;;
    esac
    
    echo
    echo -e "${BOLD}4. Backup Before Updates?${RESET}"
    echo -e "Current: $([ "$BACKUP_BEFORE_UPDATE" == "true" ] && echo "${GREEN}Enabled${RESET}" || echo "${RED}Disabled${RESET}")"
    echo -e "${GREEN}y)${RESET} Create backup before each update (recommended)"
    echo -e "${GREEN}n)${RESET} Skip backup creation"
    echo -e "${GREEN}c)${RESET} Keep current setting"
    
    read -p "Choice: " backup_choice
    case "$backup_choice" in
        y|Y) BACKUP_BEFORE_UPDATE="true" ;;
        n|N) BACKUP_BEFORE_UPDATE="false" ;;
    esac
    
    # Save settings
    save_update_config
    
    echo
    echo -e "${GREEN}✅ Update settings saved${RESET}"
    if [[ "$UPDATE_CHECK_FREQUENCY" == "startup" ]]; then
        echo -e "${CYAN}💡 Updates will be checked every time the script starts${RESET}"
    fi
    echo -e "${CYAN}💡 Note: Only 'main' branch updates are currently supported${RESET}"
    pause_for_user
}

show_update_history() {
    echo -e "${BOLD}${BLUE}Update History:${RESET}"
    
    if [[ -f "$UPDATE_LOG" ]] && [[ -s "$UPDATE_LOG" ]]; then
        echo
        tail -20 "$UPDATE_LOG" | while IFS= read -r line; do
            if [[ "$line" == *"Successfully updated"* ]]; then
                echo -e "${GREEN}$line${RESET}"
            elif [[ "$line" == *"failed"* ]] || [[ "$line" == *"Failed"* ]]; then
                echo -e "${RED}$line${RESET}"
            else
                echo -e "${CYAN}$line${RESET}"
            fi
        done
    else
        echo -e "${YELLOW}⚠️  No update history available${RESET}"
    fi
    echo
}

show_manual_git_commands() {
    echo -e "${BOLD}${BLUE}Manual Git Commands:${RESET}"
    echo
    
    if git rev-parse --git-dir >/dev/null 2>&1; then
        echo -e "${GREEN}✅ You are in a git repository${RESET}"
        echo
        echo -e "${BOLD}Common Update Commands:${RESET}"
        echo -e "${CYAN}Check for updates:${RESET}"
        echo -e "  git fetch"
        echo -e "  git status"
        echo
        echo -e "${CYAN}Update to latest:${RESET}"
        echo -e "  git pull"
        echo
        echo -e "${CYAN}Check differences:${RESET}"
        echo -e "  git log HEAD..origin/$(git branch --show-current 2>/dev/null || echo "main") --oneline"
        echo
        echo -e "${CYAN}Switch branches:${RESET}"
        echo -e "  git checkout main      # Switch to main branch"
        echo -e "  git checkout develop   # Switch to develop branch"
        echo
        echo -e "${CYAN}Reset if needed:${RESET}"
        echo -e "  git reset --hard origin/$(git branch --show-current 2>/dev/null || echo "main")  # ⚠️  Discards local changes"
    else
        echo -e "${YELLOW}⚠️  Not a git repository${RESET}"
        echo
        echo -e "${BOLD}Setup Git Repository:${RESET}"
        echo -e "${CYAN}Clone repository:${RESET}"
        echo -e "  git clone https://github.com/${GITHUB_REPO}.git"
        echo -e "  cd $(basename "$GITHUB_REPO")"
        echo
        echo -e "${CYAN}Or initialize in current directory:${RESET}"
        echo -e "  git init"
        echo -e "  git remote add origin https://github.com/${GITHUB_REPO}.git"
        echo -e "  git fetch"
        echo -e "  git checkout -b main origin/main"
    fi
    echo
}

cleanup_update_cache() {
    # Remove update cache files older than 7 days
    if [[ -d "$UPDATE_CACHE_DIR" ]]; then
        find "$UPDATE_CACHE_DIR" -name "*.json" -type f -mtime +7 -delete 2>/dev/null
        find "$UPDATE_CACHE_DIR" -name "last_check*" -type f -mtime +7 -delete 2>/dev/null
    fi
    
    # Clean up old log entries (keep last 100 lines)
    if [[ -f "$UPDATE_LOG" ]] && [[ $(wc -l < "$UPDATE_LOG") -gt 100 ]]; then
        tail -100 "$UPDATE_LOG" > "${UPDATE_LOG}.tmp"
        mv "${UPDATE_LOG}.tmp" "$UPDATE_LOG"
    fi
}

validate_update_configuration() {
    local issues=0
    
    echo -e "${CYAN}🔍 Validating update configuration...${RESET}"
    
    # Check UPDATE_CHANNEL
    if [[ -z "$UPDATE_CHANNEL" ]]; then
        echo -e "${YELLOW}⚠️  UPDATE_CHANNEL is empty, defaulting to 'main'${RESET}"
        UPDATE_CHANNEL="main"
        save_update_config
        ((issues++))
    fi
    
    # Check UPDATE_CHECK_FREQUENCY
    case "$UPDATE_CHECK_FREQUENCY" in
        "startup"|"daily"|"weekly"|"manual")
            echo -e "${GREEN}✅ Update frequency: $UPDATE_CHECK_FREQUENCY${RESET}"
            ;;
        *)
            echo -e "${YELLOW}⚠️  Invalid update frequency '$UPDATE_CHECK_FREQUENCY', defaulting to 'daily'${RESET}"
            UPDATE_CHECK_FREQUENCY="daily"
            save_update_config
            ((issues++))
            ;;
    esac
    
    # Check cache directory
    if [[ ! -d "$UPDATE_CACHE_DIR" ]]; then
        echo -e "${YELLOW}⚠️  Update cache directory missing, creating...${RESET}"
        mkdir -p "$UPDATE_CACHE_DIR"
        ((issues++))
    else
        echo -e "${GREEN}✅ Update cache directory: OK${RESET}"
    fi
    
    # Check GitHub API connectivity (non-blocking)
    if check_network_connectivity; then
        echo -e "${GREEN}✅ GitHub connectivity: OK${RESET}"
    else
        echo -e "${YELLOW}⚠️  GitHub connectivity: Failed (may be temporary)${RESET}"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}✅ Update configuration validation passed${RESET}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Found $issues configuration issues (auto-fixed)${RESET}"
        return 1
    fi
}

# ============================================================================
# STARTUP INTEGRATION
# ============================================================================

perform_startup_update_check() {
    # Only check if enabled
    if [[ "$UPDATE_CHECK_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # Different behavior based on frequency
    case "$UPDATE_CHECK_FREQUENCY" in
        "startup")
            # For startup frequency, show brief status during check
            echo -e "${CYAN}🔄 Checking for updates...${RESET}"
            
            # Quick network check first
            if ! check_network_connectivity; then
                echo -e "${YELLOW}⚠️  No network connection - skipping update check${RESET}"
                echo
                return 0
            fi
            
            # Perform check with enhanced context
            local check_result=0
            check_for_updates false false
            check_result=$?
            
            case $check_result in
                0) 
                    echo -e "${GREEN}✅ Repository is up to date${RESET}"
                    ;;
                2)
                    # Updates available - show enhanced notification
                    show_enhanced_update_notification
                    ;;
                *)
                    echo -e "${YELLOW}⚠️  Update check failed${RESET}"
                    ;;
            esac
            echo  # Add spacing after update check
            ;;
        "daily"|"weekly")
            # For time-based frequencies, check if it's time
            if should_check_for_updates; then
                # Perform silent background check
                check_for_updates false false >/dev/null 2>&1 &
            fi
            
            # Show enhanced notification if update was previously found
            show_enhanced_update_notification
            ;;
        "manual")
            # Manual only - just show notification if updates were previously found
            show_enhanced_update_notification
            ;;
        *)
            # Invalid frequency - fix it
            echo -e "${YELLOW}⚠️  Invalid update frequency, resetting to 'daily'${RESET}"
            UPDATE_CHECK_FREQUENCY="daily"
            save_update_config
            ;;
    esac
}

# ============================================================================
# LOGGING
# ============================================================================

log_update_operation() {
    local message="$1"
    
    # Use centralized logging if available, fallback to file
    if declare -f log_info >/dev/null 2>&1; then
        log_info "update" "$message"
    else
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] $message" >> "$UPDATE_LOG"
    fi
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

init_update_system_enhanced() {
    init_update_system
    
    cleanup_update_cache
    validate_update_configuration >/dev/null 2>&1  # Silent validation on startup
    
    log_update_operation "Enhanced git-based update system initialized with cleanup and validation"
}

init_update_system_enhanced
