#!/bin/bash

# Simple Backup System for Global Station Search
# Creates timestamped ZIP backups of essential files

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================

# Get backup directory (resolved at runtime)
_backup_get_dir() {
    echo "${BACKUP_DIR:-$HOME/.globalstationsearch/backups}/simple_backups"
}

# Get files to backup (resolved at runtime)
_backup_get_essential_files() {
    echo "$BASE_STATIONS_JSON"      # Base station database
    echo "$USER_STATIONS_JSON"      # User station database  
    echo "$CSV_FILE"               # Markets CSV
    echo "$CONFIG_FILE"            # Configuration/env file
}

# Get optional files to backup (resolved at runtime)
_backup_get_optional_files() {
    echo "$COMBINED_STATIONS_JSON"  # Combined database (if exists)
    echo "$CACHED_MARKETS"         # Cached markets state
    echo "$CACHED_LINEUPS"         # Cached lineups state
}

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

# Initialize backup system
backup_init() {
    local backup_dir="$(_backup_get_dir)"
    mkdir -p "$backup_dir" || {
        echo "Error: Failed to create backup directory: $backup_dir" >&2
        return 1
    }
}

# Create a timestamped backup
backup_create() {
    local backup_reason="${1:-manual}"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_name="globalstationsearch_backup_${timestamp}.tar.gz"
    local backup_dir="$(_backup_get_dir)"
    local backup_path="$backup_dir/$backup_name"
    local temp_dir="/tmp/gss_backup_$$"
    
    echo -e "${CYAN}🔄 Creating backup...${RESET}"
    
    # Create temporary directory for staging files
    mkdir -p "$temp_dir" || {
        echo -e "${RED}❌ Failed to create temporary directory${RESET}"
        return 1
    }
    
    # Copy files to temporary directory with readable names
    local files_backed_up=0
    
    # Copy essential files
    while IFS= read -r file_var; do
        if [[ -f "$file_var" ]]; then
            local basename=$(basename "$file_var")
            cp "$file_var" "$temp_dir/$basename" 2>/dev/null && {
                ((files_backed_up++))
                echo -e "${GREEN}✓${RESET} Added: $basename"
            }
        fi
    done < <(_backup_get_essential_files)
    
    # Copy optional files if they exist
    while IFS= read -r file_var; do
        if [[ -f "$file_var" ]]; then
            local basename=$(basename "$file_var")
            cp "$file_var" "$temp_dir/$basename" 2>/dev/null && {
                ((files_backed_up++))
                echo -e "${GREEN}✓${RESET} Added: $basename (optional)"
            }
        fi
    done < <(_backup_get_optional_files)
    
    if [[ $files_backed_up -eq 0 ]]; then
        echo -e "${RED}❌ No files found to backup${RESET}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Create backup info file
    cat > "$temp_dir/backup_info.txt" << EOF
Global Station Search Backup
Created: $(date)
Reason: $backup_reason
Files backed up: $files_backed_up
Script version: ${VERSION:-unknown}
EOF
    
    # Create tar.gz archive
    echo -e "${CYAN}📦 Creating tar.gz archive...${RESET}"
    if command -v tar >/dev/null 2>&1; then
        (cd "$temp_dir" && tar -czf "$backup_path" .) || {
            echo -e "${RED}❌ Failed to create tar.gz archive${RESET}"
            rm -rf "$temp_dir"
            return 1
        }
    else
        echo -e "${RED}❌ tar command not found. Please install tar.${RESET}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Cleanup temporary directory
    rm -rf "$temp_dir"
    
    # Get backup size
    local backup_size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
    
    echo -e "${GREEN}✅ Backup created successfully${RESET}"
    echo -e "${CYAN}📁 Location: $backup_path${RESET}"
    echo -e "${CYAN}📊 Size: $backup_size${RESET}"
    echo -e "${CYAN}📋 Files: $files_backed_up${RESET}"
    
    return 0
}

# List all backups with details
backup_list() {
    echo -e "${BOLD}${BLUE}📋 Available Backups${RESET}\n"
    
    local backup_dir="$(_backup_get_dir)"
    if [[ ! -d "$backup_dir" ]] || [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        echo -e "${YELLOW}No backups found${RESET}"
        return 0
    fi
    
    local backup_count=0
    local total_size=0
    
    # List backups sorted by date (newest first)
    for backup_file in $(ls -t "$backup_dir"/*.tar.gz 2>/dev/null); do
        if [[ -f "$backup_file" ]]; then
            local basename=$(basename "$backup_file")
            local size=$(du -sh "$backup_file" 2>/dev/null | cut -f1)
            local date_modified=$(stat -c %Y "$backup_file" 2>/dev/null)
            local human_date=$(date -d "@$date_modified" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
            
            ((backup_count++))
            echo -e "${SUCCESS_STYLE}📦 $basename${RESET}"
            echo -e "${INFO_STYLE}   📅 Created: $human_date${RESET}"
            echo -e "${INFO_STYLE}   📊 Size: $size${RESET}"
            echo
        fi
    done
    
    if [[ $backup_count -eq 0 ]]; then
        echo -e "${YELLOW}No valid backup files found${RESET}"
    else
        local total_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
        echo -e "${BOLD}Total: $backup_count backups, $total_size${RESET}"
    fi
}

# Cleanup old backups
backup_cleanup() {
    echo -e "${BOLD}${YELLOW}🗑️  Cleanup Backups${RESET}\n"
    
    local backup_dir="$(_backup_get_dir)"
    if [[ ! -d "$backup_dir" ]] || [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        echo -e "${YELLOW}No backups found to cleanup${RESET}"
        return 0
    fi
    
    # List backups with numbers for selection
    local backups=($(ls -t "$backup_dir"/*.tar.gz 2>/dev/null))
    local backup_count=${#backups[@]}
    
    if [[ $backup_count -eq 0 ]]; then
        echo -e "${YELLOW}No backup files found${RESET}"
        return 0
    fi
    
    echo -e "${CYAN}Select backups to delete:${RESET}\n"
    
    local i=1
    for backup_file in "${backups[@]}"; do
        local basename=$(basename "$backup_file")
        local size=$(du -sh "$backup_file" 2>/dev/null | cut -f1)
        local date_modified=$(stat -c %Y "$backup_file" 2>/dev/null)
        local human_date=$(date -d "@$date_modified" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
        
        echo -e "${SUCCESS_STYLE}$i) $basename${RESET}"
        echo -e "${INFO_STYLE}   📅 $human_date | 📊 $size${RESET}"
        ((i++))
    done
    
    echo
    echo -e "${CYAN}Options:${RESET}"
    echo -e "  ${GREEN}1-$backup_count)${RESET} Delete specific backup"
    echo -e "  ${YELLOW}a)${RESET} Delete all backups"
    echo -e "  ${RED}q)${RESET} Cancel"
    echo
    
    read -p "Select option: " choice
    choice=$(echo "$choice" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    
    case "$choice" in
        a)
            if confirm_action "Delete ALL backups"; then
                rm -f "$backup_dir"/*.tar.gz 2>/dev/null
                echo -e "${GREEN}✅ All backups deleted${RESET}"
            else
                echo -e "${YELLOW}Cleanup cancelled${RESET}"
            fi
            ;;
        [1-9]*)
            if [[ "$choice" -ge 1 ]] && [[ "$choice" -le $backup_count ]]; then
                local selected_backup="${backups[$((choice-1))]}"
                local basename=$(basename "$selected_backup")
                if confirm_action "Delete backup: $basename"; then
                    rm -f "$selected_backup"
                    echo -e "${GREEN}✅ Backup deleted: $basename${RESET}"
                else
                    echo -e "${YELLOW}Deletion cancelled${RESET}"
                fi
            else
                echo -e "${RED}Invalid selection${RESET}"
            fi
            ;;
        q|"")
            echo -e "${YELLOW}Cleanup cancelled${RESET}"
            ;;
        *)
            echo -e "${RED}Invalid option${RESET}"
            ;;
    esac
}

# Restore from backup
backup_restore() {
    echo -e "${BOLD}${YELLOW}📥 Restore from Backup${RESET}\n"
    
    local backup_dir="$(_backup_get_dir)"
    if [[ ! -d "$backup_dir" ]] || [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        echo -e "${YELLOW}No backups found to restore from${RESET}"
        return 0
    fi
    
    # List available backups
    local backups=($(ls -t "$backup_dir"/*.tar.gz 2>/dev/null))
    local backup_count=${#backups[@]}
    
    if [[ $backup_count -eq 0 ]]; then
        echo -e "${YELLOW}No backup files found${RESET}"
        return 0
    fi
    
    echo -e "${CYAN}Select backup to restore:${RESET}\n"
    
    local i=1
    for backup_file in "${backups[@]}"; do
        local basename=$(basename "$backup_file")
        local size=$(du -sh "$backup_file" 2>/dev/null | cut -f1)
        local date_modified=$(stat -c %Y "$backup_file" 2>/dev/null)
        local human_date=$(date -d "@$date_modified" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
        
        echo -e "${SUCCESS_STYLE}$i) $basename${RESET}"
        echo -e "${INFO_STYLE}   📅 $human_date | 📊 $size${RESET}"
        ((i++))
    done
    
    echo
    read -p "Select backup (1-$backup_count) or 'q' to cancel: " choice
    choice=$(echo "$choice" | tr -d '[:space:]')
    
    if [[ "$choice" == "q" ]] || [[ -z "$choice" ]]; then
        echo -e "${YELLOW}Restore cancelled${RESET}"
        return 0
    fi
    
    if [[ "$choice" -ge 1 ]] && [[ "$choice" -le $backup_count ]]; then
        local selected_backup="${backups[$((choice-1))]}"
        local basename=$(basename "$selected_backup")
        
        echo -e "${YELLOW}⚠️  This will overwrite your current files with the backup.${RESET}"
        if confirm_action "Restore from backup: $basename"; then
            _backup_perform_restore "$selected_backup"
        else
            echo -e "${YELLOW}Restore cancelled${RESET}"
        fi
    else
        echo -e "${RED}Invalid selection${RESET}"
    fi
}

# Internal function to perform the actual restore
_backup_perform_restore() {
    local backup_file="$1"
    local temp_dir="/tmp/gss_restore_$$"
    
    echo -e "${CYAN}🔄 Extracting backup...${RESET}"
    
    # Create temporary directory
    mkdir -p "$temp_dir" || {
        echo -e "${RED}❌ Failed to create temporary directory${RESET}"
        return 1
    }
    
    # Extract tar.gz file
    if command -v tar >/dev/null 2>&1; then
        tar -xzf "$backup_file" -C "$temp_dir" || {
            echo -e "${RED}❌ Failed to extract backup${RESET}"
            rm -rf "$temp_dir"
            return 1
        }
    else
        echo -e "${RED}❌ tar command not found. Please install tar.${RESET}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    echo -e "${CYAN}🔄 Restoring files...${RESET}"
    
    # Create backup of current files before restore
    echo -e "${CYAN}Creating safety backup before restore...${RESET}"
    backup_create "pre_restore_safety"
    
    local files_restored=0
    
    # Restore files
    for extracted_file in "$temp_dir"/*; do
        if [[ -f "$extracted_file" ]]; then
            local basename=$(basename "$extracted_file")
            
            # Skip info file
            if [[ "$basename" == "backup_info.txt" ]]; then
                continue
            fi
            
            # Determine target location based on filename
            local target_file=""
            case "$basename" in
                "$(basename "$BASE_STATIONS_JSON")")     target_file="$BASE_STATIONS_JSON" ;;
                "$(basename "$USER_STATIONS_JSON")")     target_file="$USER_STATIONS_JSON" ;;
                "$(basename "$CSV_FILE")")               target_file="$CSV_FILE" ;;
                "$(basename "$CONFIG_FILE")")            target_file="$CONFIG_FILE" ;;
                "$(basename "$COMBINED_STATIONS_JSON")") target_file="$COMBINED_STATIONS_JSON" ;;
                "$(basename "$CACHED_MARKETS")")         target_file="$CACHED_MARKETS" ;;
                "$(basename "$CACHED_LINEUPS")")         target_file="$CACHED_LINEUPS" ;;
                *)
                    echo -e "${YELLOW}⚠️  Unknown file: $basename${RESET}"
                    continue
                    ;;
            esac
            
            if [[ -n "$target_file" ]]; then
                # Ensure target directory exists
                mkdir -p "$(dirname "$target_file")"
                
                # Copy file
                cp "$extracted_file" "$target_file" && {
                    ((files_restored++))
                    echo -e "${GREEN}✓${RESET} Restored: $basename"
                } || {
                    echo -e "${RED}✗${RESET} Failed to restore: $basename"
                }
            fi
        fi
    done
    
    # Cleanup temporary directory
    rm -rf "$temp_dir"
    
    if [[ $files_restored -gt 0 ]]; then
        echo -e "${GREEN}✅ Restore completed${RESET}"
        echo -e "${CYAN}📋 Files restored: $files_restored${RESET}"
        echo -e "${YELLOW}💡 Please restart the script to use restored configuration${RESET}"
    else
        echo -e "${RED}❌ No files were restored${RESET}"
    fi
    
    return 0
}

# Show what files will be backed up
backup_show_info() {
    echo -e "${BOLD}${BLUE}📋 Backup Information${RESET}\n"
    
    echo -e "${CYAN}The following files will be included in backups:${RESET}\n"
    
    echo -e "${BOLD}Essential Files:${RESET}"
    while IFS= read -r file_var; do
        local basename=$(basename "$file_var")
        if [[ -f "$file_var" ]]; then
            local size=$(du -sh "$file_var" 2>/dev/null | cut -f1)
            echo -e "${SUCCESS_STYLE}✓ $basename${RESET} ${GRAY}($size)${RESET}"
        else
            echo -e "${WARNING_STYLE}✗ $basename${RESET} ${GRAY}(not found)${RESET}"
        fi
    done < <(_backup_get_essential_files)
    
    echo
    echo -e "${BOLD}Optional Files:${RESET}"
    while IFS= read -r file_var; do
        local basename=$(basename "$file_var")
        if [[ -f "$file_var" ]]; then
            local size=$(du -sh "$file_var" 2>/dev/null | cut -f1)
            echo -e "${SUCCESS_STYLE}✓ $basename${RESET} ${GRAY}($size)${RESET}"
        else
            echo -e "${INFO_STYLE}○ $basename${RESET} ${GRAY}(not found - will be skipped)${RESET}"
        fi
    done < <(_backup_get_optional_files)
    
    echo
    echo -e "${BOLD}File Descriptions:${RESET}"
    echo -e "${INFO_STYLE}• Base database: Core station data (33k+ stations)${RESET}"
    echo -e "${INFO_STYLE}• User database: Custom stations you've added${RESET}"
    echo -e "${INFO_STYLE}• Markets CSV: Your configured television markets${RESET}"
    echo -e "${INFO_STYLE}• Config file: Application settings and integrations${RESET}"
    echo -e "${INFO_STYLE}• State files: Caching progress and optimization data${RESET}"
    echo
}

# Legacy function for compatibility with other parts of the system
create_backup() {
    backup_create "$@"
}

# Legacy wrapper for automatic backups called from other parts of the system
backup_existing_data() {
    backup_create "automatic"
}