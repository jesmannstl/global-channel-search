#!/bin/bash
# lib/core/cache.sh - Cache Management Module
# Extracted from Global Station Search v1.4.0
# Core cache operations, station management, and data processing

# ============================================================================
# SESSION-LEVEL LINEUP DEDUPLICATION - GLOBAL STATE
# ============================================================================

# Session-level lineup tracking for deduplication optimization
PROCESSED_LINEUPS_THIS_SESSION=()

# Function to check if lineup was already processed in this session
session_lineup_already_processed() {
    local lineup_id="$1"
    
    # Check if lineup was already processed in this session
    for processed_lineup in "${PROCESSED_LINEUPS_THIS_SESSION[@]}"; do
        if [[ "$processed_lineup" == "$lineup_id" ]]; then
            return 0  # Already processed
        fi
    done
    
    return 1  # Not processed yet
}

# Function to mark lineup as processed in this session
mark_lineup_processed_this_session() {
    local lineup_id="$1"
    PROCESSED_LINEUPS_THIS_SESSION+=("$lineup_id")
}

# Function to reset session state (called at start of caching operations)
reset_session_lineup_tracking() {
    PROCESSED_LINEUPS_THIS_SESSION=()
    echo -e "${CYAN}🔄 Session lineup tracking reset${RESET}" >&2
}

# ============================================================================
# CACHE INITIALIZATION AND SETUP
# ============================================================================

init_combined_cache_startup() {
  # Build combined cache if both base and user caches exist
  if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ] && 
     [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    
    local user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    local base_count=$(jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
    
    # Check if we can skip the rebuild using persistent state
    if check_combined_cache_freshness; then
      echo -e "${GREEN}✅ Station database ready (using cached version)${RESET}"
    else
      echo -e "${CYAN}🔄 Building combined station database...${RESET}"
      echo -e "${CYAN}💡 Merging $base_count base stations + $user_count user stations${RESET}"
      echo -e "${CYAN}💡 This may take a moment for large datasets...${RESET}"
      build_combined_cache_with_progress # Show the progress output
    fi
  elif [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
    # Only base database exists
    echo -e "${GREEN}✅ Station database ready (base database only)${RESET}"
  elif [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    # Only user database exists
    local user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Station database ready ($user_count user stations)${RESET}"
  fi
}

init_user_cache() {
  if [ ! -f "$USER_STATIONS_JSON" ]; then
    echo '[]' > "$USER_STATIONS_JSON"
    echo -e "${YELLOW}Initialized empty user stations cache${RESET}" >&2
  fi
}

setup_optimized_cache() {
  # Initialize cache validity checking
  COMBINED_CACHE_VALID=false
  COMBINED_CACHE_TIMESTAMP=0
  
  # Pre-build combined cache if it will be needed and is significant
  init_combined_cache_startup
}

# ============================================================================
# CACHE CLEANUP AND MAINTENANCE
# ============================================================================

cleanup_cache() {
  echo -e "${YELLOW}Cleaning up cached station files...${RESET}"
  
  # IMPORTANT: Create backup before cleanup if user cache exists
  if [[ -f "$USER_STATIONS_JSON" ]] && [[ -s "$USER_STATIONS_JSON" ]]; then
    backup_existing_data
    echo "  ✓ User cache backed up before cleanup"
  fi
  
  # Remove station cache files
  if [ -d "$STATION_CACHE_DIR" ]; then
    rm -f "$STATION_CACHE_DIR"/*.json 2>/dev/null || true
    echo "  ✓ Station cache files removed"
  fi
  
  # Remove raw API response files
  rm -f "$CACHE_DIR"/last_raw_*.json 2>/dev/null || true
  echo "  ✓ Raw API response files removed"
  
  # Remove temporary files
  rm -f "$CACHE_DIR"/*.tmp 2>/dev/null || true
  echo "  ✓ Temporary files removed"

  # Remove API search results
  rm -f "$API_SEARCH_RESULTS" 2>/dev/null || true
  echo "  ✓ API search results removed"
  
  # Remove combined cache files
  cleanup_combined_cache
  echo "  ✓ Combined cache files removed"
  
  # Remove legacy master JSON files (all variants)
  rm -f "$CACHE_DIR"/all_stations_master.json* 2>/dev/null || true
  rm -f "$CACHE_DIR"/working_stations.json* 2>/dev/null || true
  echo "  ✓ Legacy cache files removed"
  
  # Remove lineup cache (will be rebuilt)
  rm -f "$LINEUP_CACHE" 2>/dev/null || true
  echo "  ✓ Lineup cache removed"
  
  # CRITICAL: PRESERVE these important files:
  # - $BASE_STATIONS_JSON (distributed base database)
  # - $USER_STATIONS_JSON (user's personal database) - BACKED UP ABOVE
  # - Station metadata provides all coverage information
  # - $CACHED_MARKETS (state tracking)
  # - $CACHED_LINEUPS (state tracking)
  # - $LINEUP_TO_MARKET (state tracking)
  # - $CACHE_STATE_LOG (state tracking)
  # - $DISPATCHARR_* files (Dispatcharr integration)
  
  echo "  ✓ User database, base database, and state tracking files preserved"
  echo -e "${GREEN}Cache cleanup completed (important files preserved and backed up)${RESET}"
}

invalidate_combined_cache() {
  COMBINED_CACHE_VALID=false
  cleanup_combined_cache
  
  # Remove saved state from config file
  if [ -f "$CONFIG_FILE" ]; then
    local temp_config="${CONFIG_FILE}.tmp"
    grep -v -E '^COMBINED_CACHE_TIMESTAMP=|^COMBINED_CACHE_BASE_TIME=|^COMBINED_CACHE_USER_TIME=' "$CONFIG_FILE" > "$temp_config" 2>/dev/null
    mv "$temp_config" "$CONFIG_FILE"
  fi
}

mark_user_cache_updated() {
  invalidate_combined_cache
  echo -e "${CYAN}💡 Station database will be refreshed on next search${RESET}"
}

# ============================================================================
# COMBINED CACHE MANAGEMENT
# ============================================================================

build_combined_cache_with_progress() {
  echo -e "${CYAN}🔄 Building station database (3 steps)...${RESET}" >&2
  
  # Step 1: Basic validation
  echo -e "${CYAN}🔍 [1/3] Validating cache files...${RESET}" >&2
  
  if [[ -f "$BASE_STATIONS_JSON" ]] && [[ -s "$BASE_STATIONS_JSON" ]]; then
    if ! jq empty "$BASE_STATIONS_JSON" 2>/dev/null; then
      echo -e "${RED}❌ Base database is invalid JSON${RESET}" >&2
      return 1
    fi
    
    # CRITICAL: Validate base database format - REJECT if legacy
    local base_legacy_count=$(jq '[.[] | select(.country and (.availableIn | not))] | length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
    if [[ "$base_legacy_count" -gt 0 ]]; then
      echo -e "${RED}❌ Base database contains $base_legacy_count legacy format stations${RESET}" >&2
      echo -e "${RED}❌ Base database must use clean format (availableIn array)${RESET}" >&2
      echo -e "${CYAN}💡 Update your base database to use the new format${RESET}" >&2
      return 1
    fi
  fi
  
  if [[ -f "$USER_STATIONS_JSON" ]] && [[ -s "$USER_STATIONS_JSON" ]]; then
    if ! jq empty "$USER_STATIONS_JSON" 2>/dev/null; then
      echo -e "${RED}❌ User database is invalid JSON${RESET}" >&2
      return 1
    fi
    
    # CRITICAL: Validate user database format - REJECT if legacy
    local user_legacy_count=$(jq '[.[] | select(.country and (.availableIn | not))] | length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    if [[ "$user_legacy_count" -gt 0 ]]; then
      echo -e "${RED}❌ User database contains $user_legacy_count legacy format stations${RESET}" >&2
      echo -e "${RED}❌ User database must use clean format (availableIn array)${RESET}" >&2
      echo -e "${CYAN}💡 Delete user database and rebuild with User Database Expansion${RESET}" >&2
      return 1
    fi
  fi
  
  echo -e "${GREEN}✅ [1/3] Cache files are valid and use clean format${RESET}" >&2
  
  # Step 2: Analyze source files
  echo -e "${CYAN}📊 [2/3] Analyzing source databases...${RESET}" >&2
  local base_count=$([ -f "$BASE_STATIONS_JSON" ] && jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
  local user_count=$([ -f "$USER_STATIONS_JSON" ] && jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
  echo -e "${CYAN}   Base: $base_count stations, User: $user_count stations${RESET}" >&2
  
  if [[ "$base_count" -eq 0 && "$user_count" -eq 0 ]]; then
    echo -e "${RED}❌ No station data found${RESET}" >&2
    return 1
  fi
  
  # Step 3: Perform clean format merge
  echo -e "${CYAN}🔄 [3/3] Merging clean format caches...${RESET}" >&2

  if [[ "$base_count" -eq 0 ]]; then
    # Only user database - copy directly
    cp "$USER_STATIONS_JSON" "$COMBINED_STATIONS_JSON"
  elif [[ "$user_count" -eq 0 ]]; then
    # Only base database - copy directly  
    cp "$BASE_STATIONS_JSON" "$COMBINED_STATIONS_JSON"
  else
    # Both exist - perform clean format merge
    if ! perform_clean_format_merge "$BASE_STATIONS_JSON" "$USER_STATIONS_JSON" "$COMBINED_STATIONS_JSON"; then
      echo -e "${RED}❌ Clean format merge operation failed${RESET}" >&2
      return 1
    fi
  fi

  local final_count=$(jq 'length' "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
  echo -e "${GREEN}✅ Database ready: $final_count total stations${RESET}" >&2
  
  # Validate final output is clean format
  local final_clean_count=$(jq '[.[] | select(.availableIn)] | length' "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
  if [[ "$final_clean_count" -eq "$final_count" ]]; then
    echo -e "${GREEN}✅ All stations in combined cache use clean format${RESET}" >&2
  else
    echo -e "${RED}❌ WARNING: Combined cache contains $(($final_count - $final_clean_count)) non-clean format stations${RESET}" >&2
  fi
  
  # Save state
  save_combined_cache_state "$(date +%s)" \
    "$(stat -c %Y "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")" \
    "$(stat -c %Y "$USER_STATIONS_JSON" 2>/dev/null || echo "0")"
  
  COMBINED_CACHE_VALID=true
  return 0
}

force_rebuild_combined_cache() {
  echo -e "\n${BOLD}Force Rebuild Combined Cache${RESET}"
  echo -e "${YELLOW}This will rebuild the combined station database from base and user databases.${RESET}"
  echo -e "${CYAN}Use this if you suspect the combined cache is corrupted or outdated.${RESET}"
  echo
  
  # Show current cache status
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)
  
  echo -e "${BOLD}Current Cache Status:${RESET}"
  echo -e "Base stations: $base_count"
  echo -e "User stations: $user_count"
  
  if [ -f "$COMBINED_STATIONS_JSON" ]; then
    local combined_count=$(jq 'length' "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
    local file_size=$(ls -lh "$COMBINED_STATIONS_JSON" 2>/dev/null | awk '{print $5}')
    echo -e "Combined cache: $combined_count stations ($file_size)"
  else
    echo -e "Combined cache: Not found"
  fi
  echo
  
  # Check if rebuild is actually needed
  if [ "$base_count" -eq 0 ] && [ "$user_count" -eq 0 ]; then
    echo -e "${RED}❌ No source caches available to rebuild from${RESET}"
    echo -e "${CYAN}💡 You need either a base database or user database to rebuild${RESET}"
    return 1
  fi
  
  if ! confirm_action "Force rebuild combined cache from source files?"; then
    echo -e "${YELLOW}⚠️  Rebuild cancelled${RESET}"
    return 1
  fi
  
  echo -e "${CYAN}🔄 Force rebuilding combined cache...${RESET}"
  
  # Force invalidate current cache
  invalidate_combined_cache
  
  # Backup existing combined cache if it exists
  if [ -f "$COMBINED_STATIONS_JSON" ]; then
    local backup_file="${COMBINED_STATIONS_JSON}.backup.$(date +%Y%m%d_%H%M%S)"
    if cp "$COMBINED_STATIONS_JSON" "$backup_file" 2>/dev/null; then
      echo -e "${CYAN}💾 Backed up existing cache to: $(basename "$backup_file")${RESET}"
    fi
  fi
  
  # Force rebuild
  if build_combined_cache_with_progress; then
    local new_count=$(jq 'length' "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Combined cache rebuilt successfully${RESET}"
    echo -e "${CYAN}📊 New combined cache: $new_count stations${RESET}"
    
    # Verify the rebuild worked
    if [ "$new_count" -gt 0 ]; then
      echo -e "${GREEN}✅ Rebuild verification passed${RESET}"
    else
      echo -e "${RED}❌ Rebuild verification failed - cache appears empty${RESET}"
      return 1
    fi
  else
    echo -e "${RED}❌ Failed to rebuild combined cache${RESET}"
    echo -e "${CYAN}💡 Check disk space and file permissions${RESET}"
    return 1
  fi
  
  return 0
}

get_effective_stations_file() {
  # Simple, clean logic without excessive validation
  
  # If no user stations, use base
  if [ ! -f "$USER_STATIONS_JSON" ] || [ ! -s "$USER_STATIONS_JSON" ]; then
    if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
      echo "$BASE_STATIONS_JSON"
      return 0
    else
      return 1
    fi
  fi
  
  # If no base stations, use user
  if [ ! -f "$BASE_STATIONS_JSON" ] || [ ! -s "$BASE_STATIONS_JSON" ]; then
    echo "$USER_STATIONS_JSON"
    return 0
  fi
  
  # Both exist - use combined
  if check_combined_cache_freshness; then
    echo "$COMBINED_STATIONS_JSON"
    return 0
  else
    if build_combined_cache_with_progress; then
      echo "$COMBINED_STATIONS_JSON"
      return 0
    else
      # Fallback to base database if combine fails
      echo "$BASE_STATIONS_JSON"
      return 0
    fi
  fi
}

# ============================================================================
# USER DATABASE MANAGEMENT
# ============================================================================

add_stations_to_user_cache() {
  local new_stations_file="$1"
  
  echo -e "${CYAN}🔄 Starting user database integration process...${RESET}"
  
  # File validation with detailed feedback
  if [ ! -f "$new_stations_file" ]; then
    echo -e "${RED}❌ File Validation: New stations file not found${RESET}"
    echo -e "${CYAN}💡 Expected file: $new_stations_file${RESET}"
    echo -e "${CYAN}💡 Check if caching process completed successfully${RESET}"
    return 1
  fi
  
  echo -e "${CYAN}🔍 Validating new stations file format...${RESET}"
  if ! jq empty "$new_stations_file" 2>/dev/null; then
    echo -e "${RED}❌ File Validation: New stations file contains invalid JSON${RESET}"
    echo -e "${CYAN}💡 File: $new_stations_file${RESET}"
    echo -e "${CYAN}💡 File may be corrupted or incomplete${RESET}"
    echo -e "${CYAN}💡 Try running User Database Expansion again${RESET}"
    return 1
  fi
  echo -e "${GREEN}✅ New stations file validation passed${RESET}"

  # CRITICAL: Validate new stations are in clean format - REJECT if not
  echo -e "${CYAN}🔍 Validating new stations format (clean format required)...${RESET}"
  local new_legacy_count=$(jq '[.[] | select(.country and (.availableIn | not))] | length' "$new_stations_file" 2>/dev/null || echo "0")
  if [[ "$new_legacy_count" -gt 0 ]]; then
    echo -e "${RED}❌ Format Validation: New stations file contains $new_legacy_count legacy format stations${RESET}"
    echo -e "${RED}❌ REJECTED: Legacy format stations cannot be processed${RESET}"
    echo -e "${CYAN}💡 The user database creation process should only generate clean format stations${RESET}"
    echo -e "${CYAN}💡 This indicates a bug in the station creation logic${RESET}"
    echo -e "${CYAN}💡 Action: Report this issue - stations should have 'availableIn' arrays${RESET}"
    return 1
  fi
  
  local new_clean_count=$(jq '[.[] | select(.availableIn)] | length' "$new_stations_file" 2>/dev/null || echo "0")
  local new_total_count=$(jq 'length' "$new_stations_file" 2>/dev/null || echo "0")
  
  if [[ "$new_clean_count" -eq "$new_total_count" ]]; then
    echo -e "${GREEN}✅ All $new_total_count new stations use clean format${RESET}"
  else
    echo -e "${RED}❌ Format Validation: $(($new_total_count - $new_clean_count)) stations have unknown format${RESET}"
    echo -e "${CYAN}💡 All stations must have 'availableIn' arrays${RESET}"
    return 1
  fi

  # ENHANCED: Clean existing user database by removing ONLY legacy entries
  if [[ -f "$USER_STATIONS_JSON" ]] && [[ -s "$USER_STATIONS_JSON" ]]; then
    echo -e "${CYAN}🔍 Validating existing user database format...${RESET}"
    
    if ! jq empty "$USER_STATIONS_JSON" 2>/dev/null; then
      echo -e "${RED}❌ Existing user database contains invalid JSON${RESET}"
      echo -e "${CYAN}💡 Creating fresh user database to replace corrupted file${RESET}"
      echo '[]' > "$USER_STATIONS_JSON" || {
        echo -e "${RED}❌ Cannot create fresh user database file${RESET}"
        return 1
      }
      echo -e "${GREEN}✅ Corrupted cache replaced with empty cache${RESET}"
    else
      # Check format of existing cache
      local user_legacy_count=$(jq '[.[] | select(.country and (.availableIn | not))] | length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
      local user_clean_count=$(jq '[.[] | select(.availableIn)] | length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
      local user_total_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
      
      if [[ "$user_legacy_count" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Found $user_legacy_count legacy format stations in existing cache${RESET}"
        echo -e "${CYAN}🔧 Removing ONLY legacy entries, keeping $user_clean_count clean format stations${RESET}"
        
        # Create cleaned cache (remove only legacy entries)
        local temp_clean="${USER_STATIONS_JSON}.cleaned.$"
        if jq '[.[] | select(.availableIn)]' "$USER_STATIONS_JSON" > "$temp_clean" 2>/dev/null; then
          # Create backup of original
          local backup_file="${USER_STATIONS_JSON}.backup.legacy_removed.$(date +%Y%m%d_%H%M%S)"
          cp "$USER_STATIONS_JSON" "$backup_file" 2>/dev/null
          
          # Replace with cleaned version
          mv "$temp_clean" "$USER_STATIONS_JSON"
          echo -e "${GREEN}✅ Removed $user_legacy_count legacy stations, kept $user_clean_count clean stations${RESET}"
          echo -e "${CYAN}💡 Original cache backed up to: $(basename "$backup_file")${RESET}"
        else
          echo -e "${RED}❌ Failed to clean legacy entries from cache${RESET}"
          rm -f "$temp_clean" 2>/dev/null
          return 1
        fi
      elif [[ "$user_clean_count" -eq "$user_total_count" ]] && [[ "$user_total_count" -gt 0 ]]; then
        echo -e "${GREEN}✅ Existing user database ($user_total_count stations) uses clean format${RESET}"
        echo -e "${CYAN}💡 New stations will be appended to existing database${RESET}"
      elif [[ "$user_total_count" -eq 0 ]]; then
        echo -e "${CYAN}💡 Existing user database is empty - will add new stations${RESET}"
      else
        echo -e "${RED}❌ Existing user database has mixed or unknown format${RESET}"
        echo -e "${CYAN}💡 Clean: $user_clean_count, Legacy: $user_legacy_count, Total: $user_total_count${RESET}"
        echo -e "${CYAN}💡 Cache must be in consistent clean format${RESET}"
        return 1
      fi
    fi
  else
    echo -e "${CYAN}💡 No existing user database - will create new database${RESET}"
    init_user_cache
  fi

  echo -e "${GREEN}✅ Format validation passed - proceeding with clean format append${RESET}"
  
  # Perform clean format merge using corrected logic
  echo -e "${CYAN}🔄 Merging new stations with existing user cache...${RESET}"
  local temp_file="${USER_STATIONS_JSON}.merge.$"
  
  if ! perform_clean_format_merge "$USER_STATIONS_JSON" "$new_stations_file" "$temp_file"; then
    echo -e "${RED}❌ Merge Operation: Failed to merge station data${RESET}"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi

  # Backup original cache with feedback
  if [ -s "$USER_STATIONS_JSON" ]; then
    echo -e "${CYAN}💾 Creating backup of current user database...${RESET}"
    local backup_file="${USER_STATIONS_JSON}.backup.$(date +%Y%m%d_%H%M%S)"
    if ! cp "$USER_STATIONS_JSON" "$backup_file" 2>/dev/null; then
      echo -e "${YELLOW}⚠️  Backup Warning: Could not create safety backup${RESET}"
      echo -e "${CYAN}💡 Continuing without backup (original cache will be overwritten)${RESET}"
      
      if ! confirm_action "Continue without backup?"; then
        echo -e "${YELLOW}⚠️  User database merge cancelled by user${RESET}"
        rm -f "$temp_file" 2>/dev/null
        return 1
      fi
    else
      echo -e "${GREEN}✅ Safety backup created: $(basename "$backup_file")${RESET}"
    fi
  fi
  
  # Replace original with merged data
  echo -e "${CYAN}💾 Finalizing user database update...${RESET}"
  if ! mv "$temp_file" "$USER_STATIONS_JSON" 2>/dev/null; then
    echo -e "${RED}❌ Database Update: Cannot finalize user database file${RESET}"
    echo -e "${CYAN}💡 Check file permissions: $USER_STATIONS_JSON${RESET}"
    echo -e "${CYAN}💡 Check disk space and try again${RESET}"
    
    # Try to restore from backup if it exists
    local latest_backup=$(ls -t "${USER_STATIONS_JSON}.backup."* 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
      echo -e "${CYAN}🔄 Attempting to restore from backup...${RESET}"
      if cp "$latest_backup" "$USER_STATIONS_JSON" 2>/dev/null; then
        echo -e "${GREEN}✅ User database restored from backup${RESET}"
      fi
    fi
    
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  
  # Success validation and reporting
  echo -e "${CYAN}🔍 Validating final user database...${RESET}"
  local new_count
  if new_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null); then
    echo -e "${GREEN}✅ User database integration completed successfully${RESET}"
    echo -e "${CYAN}📊 Total stations in user database: $new_count${RESET}"
    
    # Validate final format compliance
    local final_clean_count=$(jq '[.[] | select(.availableIn)] | length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    if [[ "$final_clean_count" -eq "$new_count" ]]; then
      echo -e "${GREEN}✅ All stations in final database use clean format${RESET}"
    else
      echo -e "${RED}❌ WARNING: $((new_count - final_clean_count)) stations do not use clean format${RESET}"
      echo -e "${CYAN}💡 This indicates a merge logic error${RESET}"
    fi
    
    # Cleanup old backups with feedback
    echo -e "${CYAN}🧹 Cleaning up old backup files...${RESET}"
    local backup_pattern="${USER_STATIONS_JSON}.backup.*"
    local backup_count=$(ls -1 $backup_pattern 2>/dev/null | wc -l)
    if [[ $backup_count -gt 5 ]]; then
      ls -t $backup_pattern 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
      echo -e "${GREEN}✅ Cleaned up old backup files (kept 5 most recent)${RESET}"
    else
      echo -e "${CYAN}💡 Backup file count within limits ($backup_count kept)${RESET}"
    fi
    
    mark_user_cache_updated

    # Rebuild combined cache using corrected logic
    echo -e "${CYAN}🔄 Rebuilding combined cache with new stations...${RESET}"
    if build_combined_cache_with_progress >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Combined cache rebuilt and ready${RESET}"
    else
      echo -e "${YELLOW}⚠️  Combined cache will rebuild on next access${RESET}"
    fi
      
    return 0
  else
    echo -e "${RED}❌ Final Validation: Cannot read final user database${RESET}"
    return 1
  fi
}

perform_clean_format_merge() {
  local existing_file="$1"
  local new_file="$2" 
  local output_file="$3"
  
  echo -e "${CYAN}🔄 Performing clean format merge with simplified lineup tracing...${RESET}"
  
  # SIMPLIFIED: Use first trace only logic
  if jq -s '
    (.[0] // []) as $existing |
    (.[1] // []) as $new |
    (($existing + $new) | group_by(.stationId) | map(
      if length == 1 then
        .[0]
      else
        .[0] as $primary |
        ([.[] | .availableIn[]? // empty] | select(. != null and . != "") | unique | sort) as $all_countries |
        
        # SIMPLIFIED: Take the first lineup trace from any station being merged
        (([.[] | .lineupTracing[]? // empty] | .[0]) // null) as $first_trace |
        (if $first_trace then
          [$first_trace + {discoveredOrder: 1, isPrimary: true}]
        else
          []
        end) as $final_traces |
        
        $primary + {
          availableIn: $all_countries,
          multiCountry: ($all_countries | length > 1),
          lineupTracing: $final_traces,
          source: "combined"
        }
      end
    )) | sort_by(.name // "")
  ' "$existing_file" "$new_file" > "$output_file"; then
    
    # Validate result
    if jq empty "$output_file" 2>/dev/null; then
      local output_total=$(jq 'length' "$output_file" 2>/dev/null || echo "0")
      local output_traces=$(jq '[.[] | .lineupTracing[]?] | length' "$output_file" 2>/dev/null || echo "0")
      echo -e "${GREEN}✅ Simplified lineup optimization completed: $output_total stations${RESET}"
      echo -e "${BLUE}📊 Optimized lineup traces: $output_traces (1 per station)${RESET}"
      return 0
    else
      echo -e "${RED}❌ Output validation failed${RESET}"
      return 1
    fi
  else
    echo -e "${RED}❌ Clean format merge operation failed${RESET}"
    return 1
  fi
}

# ============================================================================
# MARKET AND LINEUP COVERAGE FUNCTIONS
# ============================================================================

# MARKET FUNCTIONS
is_market_in_base_cache() {
  local country="$1"
  local zip="$2"
  grep -Fxq "$country,$zip" "$BASE_MARKETS_CSV" 2>/dev/null
}

is_market_in_user_cache() {
  local country="$1" 
  local zip="$2"
  # Check user's state tracking file
  is_market_cached "$country" "$zip"  # This function already exists
}

is_market_processed() {
  local country="$1"
  local zip="$2"
  # Check if market is covered by EITHER base or user database
  is_market_in_base_cache "$country" "$zip" || is_market_in_user_cache "$country" "$zip"
}

# LINEUP FUNCTIONS  
is_lineup_in_base_cache() {
  local lineup_id="$1"
  if [ ! -f "$BASE_STATIONS_JSON" ] || [ ! -s "$BASE_STATIONS_JSON" ]; then
    return 1
  fi
  jq -e --arg lineup "$lineup_id" \
    '[.[] | select(.lineupTracing[]? | .lineupId == $lineup)] | length > 0' \
    "$BASE_STATIONS_JSON" >/dev/null 2>&1
}

is_lineup_cached() {
  local lineup_id="$1"
  
  if [ ! -f "$CACHED_LINEUPS" ]; then
    return 1  # Not cached (file doesn't exist)
  fi
  
  grep -q "\"lineup_id\":\"$lineup_id\"" "$CACHED_LINEUPS" 2>/dev/null
}

is_lineup_processed() {
  local lineup_id="$1"
  # Check if lineup is covered by EITHER base or user database
  is_lineup_in_base_cache "$lineup_id" || is_lineup_cached "$lineup_id"
}

# COUNTRY FUNCTIONS
get_base_cache_countries() {
  if [ ! -f "$BASE_STATIONS_JSON" ] || [ ! -s "$BASE_STATIONS_JSON" ]; then
    echo ""
    return 1
  fi
  jq -r '[.[] | .availableIn[]?] | unique | join(",")' \
    "$BASE_STATIONS_JSON" 2>/dev/null || echo ""
}

get_user_cache_countries() {
  if [ ! -f "$USER_STATIONS_JSON" ] || [ ! -s "$USER_STATIONS_JSON" ]; then
    echo ""
    return 1
  fi
  jq -r '[.[] | .availableIn[]?] | unique | join(",")' \
    "$USER_STATIONS_JSON" 2>/dev/null || echo ""
}

get_all_cache_countries() {
  # Get countries from both base and user databases, combined and deduplicated
  local base_countries=$(get_base_cache_countries)
  local user_countries=$(get_user_cache_countries)
  
  # Combine and deduplicate
  echo "$base_countries,$user_countries" | tr ',' '\n' | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//'
}

# ============================================================================
# USER DATABASE EXPANSION - COMPONENT FUNCTIONS
# ============================================================================

validate_caching_prerequisites() {
  local force_refresh="${1:-false}"
  
  # Check if server is configured for API operations - REQUIRED for user database expansion
  if [[ -z "${CHANNELS_URL:-}" ]]; then
    echo -e "${RED}❌ Channels DVR Integration: Server not configured${RESET}"
    echo -e "${CYAN}💡 User Database Expansion requires a Channels DVR server to function${RESET}"
    return 1
  fi

  echo -e "${GREEN}✅ Channels DVR server configured: $CHANNELS_URL${RESET}"
  echo -e "${CYAN}🔗 Testing server connection...${RESET}"
  
  # Test server connection before starting caching process
  if ! curl -s --connect-timeout $QUICK_TIMEOUT "$CHANNELS_URL" >/dev/null 2>&1; then
    echo -e "${RED}❌ Channels DVR Integration: Cannot connect to server${RESET}"
    echo -e "${CYAN}💡 Server: $CHANNELS_URL${RESET}"
    if ! confirm_action "Continue anyway? (caching will likely fail)"; then
      echo -e "${YELLOW}⚠️  User Database Expansion cancelled${RESET}"
      return 1
    fi
  else
    echo -e "${GREEN}✅ Server connection confirmed${RESET}"
  fi

  # Initialize user cache and state tracking
  init_user_cache
  init_cache_state_tracking
  
  return 0
}

analyze_markets_for_processing() {
  local force_refresh="$1"
  
  # Initialize counters and arrays
  local markets_to_process=()
  local total_configured=0
  local already_cached=0
  local base_cache_skipped=0
  local will_process=0
  
  # Read through CSV and categorize each market - STATUS MESSAGES TO STDERR
  while IFS=, read -r country zip; do
    [[ "$country" == "Country" ]] && continue
    ((total_configured++))
    
    # Check various conditions to determine if we should process this market
    if [[ "$force_refresh" == "true" ]]; then
      # Force refresh mode - process everything
      markets_to_process+=("$country,$zip")
      ((will_process++))
      echo -e "${CYAN}🔄 Will force refresh: $country/$zip${RESET}" >&2
    elif is_market_cached "$country" "$zip"; then
      # Market already processed in user database
      ((already_cached++))
      echo -e "${GREEN}✅ Already cached: $country/$zip${RESET}" >&2
    elif [[ "$FORCE_REFRESH_ACTIVE" != "true" ]] && is_market_in_base_cache "$country" "$zip"; then
      # Market exactly covered by base database
      ((base_cache_skipped++))
      echo -e "${YELLOW}⏭️  Skipping (in base database): $country/$zip${RESET}" >&2
      # Record as processed since it's covered by base database
      record_market_processed "$country" "$zip" 0
    else
      # Market needs processing
      markets_to_process+=("$country,$zip")
      ((will_process++))
      echo -e "${BLUE}📋 Will process: $country/$zip${RESET}" >&2
    fi
  done < "$CSV_FILE"
  
  # Show processing summary - ALL TO STDERR
  echo -e "\n${BOLD}${BLUE}=== Market Analysis Results ===${RESET}" >&2
  echo -e "${CYAN}📊 Total configured markets: $total_configured${RESET}" >&2
  echo -e "${GREEN}📊 Already cached: $already_cached${RESET}" >&2
  echo -e "${YELLOW}📊 Skipped (base database): $base_cache_skipped${RESET}" >&2
  echo -e "${BLUE}📊 Will process: $will_process${RESET}" >&2
  
  # Early exit if nothing to process
  if [ "$will_process" -eq 0 ]; then
    echo -e "\n${GREEN}✅ All markets are already processed!${RESET}" >&2
    echo -e "${CYAN}💡 No new stations to add to user database${RESET}" >&2
    echo -e "${CYAN}💡 Add new markets or use force refresh to reprocess existing ones${RESET}" >&2
    return 1  # Signal no processing needed
  fi
  
  echo -e "\n${CYAN}🔄 Starting incremental caching for $will_process markets...${RESET}" >&2
  
  # Export markets array for use by calling function - ONLY DATA TO STDOUT
  # Convert array to newline-separated string and echo to stdout
  printf '%s\n' "${markets_to_process[@]}"
  
  return 0
}

setup_caching_environment() {
  # Clean up temporary files (but preserve user and base databases)
  echo -e "${CYAN}🧹 Preparing cache environment...${RESET}" >&2
  rm -f "$LINEUP_CACHE" cache/unique_lineups.txt "$STATION_CACHE_DIR"/*.json cache/enhanced_stations.log >&2 2>/dev/null
  rm -f "$CACHE_DIR"/all_stations_master.json* "$CACHE_DIR"/working_stations.json* >&2 2>/dev/null || true
  
  local start_time=$(date +%s.%N)
  mkdir -p "cache" "$STATION_CACHE_DIR" >&2 2>/dev/null
  > "$LINEUP_CACHE"
  
  # Initialize session-level lineup tracking
  reset_session_lineup_tracking
  
  # Return ONLY start time for duration calculations - NO OTHER OUTPUT
  echo "$start_time"
}

validate_user_building_prerequisites() {
    local force_refresh="$1"
    
    echo -e "${CYAN}🔍 Validating user database expansion prerequisites...${RESET}" >&2
    
    # Check for Channels DVR server connectivity
    if ! curl -s --connect-timeout $QUICK_TIMEOUT "$CHANNELS_URL" >/dev/null 2>&1; then
        echo -e "${RED}❌ Cannot connect to Channels DVR server: $CHANNELS_URL${RESET}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✅ Server connection confirmed${RESET}" >&2
    
    # Validate markets CSV exists
    if [[ ! -f "$CSV_FILE" ]] || [[ ! -s "$CSV_FILE" ]]; then
        echo -e "${RED}❌ Markets CSV not found or empty: $CSV_FILE${RESET}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✅ Markets configuration found${RESET}" >&2
    return 0
}

process_single_market_for_user_cache() {
    local country="$1"
    local zip="$2"
    local market_number="$3"
    local total_markets="$4"
    local force_refresh="$5"
    
    # Show progress
    local percent=$((market_number * 100 / total_markets))
    printf "\r${CYAN}[%3d%%] (%d/%d) Processing market $country/$zip...${RESET}\n" \
        "$percent" "$market_number" "$total_markets" >&2
    
    # MARKET-LEVEL CACHING CHECK - Skip if already processed
    if [[ "$force_refresh" != "true" ]]; then
        # Check if market is already cached in user database
        if is_market_cached "$country" "$zip"; then
            return 0  # Already processed, skip silently
        fi
        
        # Check if market is covered by base database
        if is_market_in_base_cache "$country" "$zip"; then
            record_market_processed "$country" "$zip" 0
            return 0  # Covered by base database, skip silently
        fi
    fi
    
    # Step 1: Fetch lineups for this market
    local api_url="$CHANNELS_URL/tms/lineups/$country/$zip"
    local lineups_response
    lineups_response=$(curl -s --connect-timeout $STANDARD_TIMEOUT --max-time $MAX_OPERATION_TIME "$api_url" 2>/dev/null)
    local curl_exit_code=$?
    
    # Handle API errors
    if [[ $curl_exit_code -ne 0 ]] || [[ -z "$lineups_response" ]]; then
        echo -e "\n${RED}❌ API Error for $country/$zip: Curl failed with code $curl_exit_code${RESET}" >&2
        record_market_processed "$country" "$zip" 0
        return 1
    fi
    
    # Save raw market data (preserve existing behavior)
    echo "$lineups_response" > "cache/last_raw_${country}_${zip}.json"
    
    # Validate JSON response
    if ! echo "$lineups_response" | jq -e . > /dev/null 2>&1; then
        echo -e "\n${RED}❌ Invalid JSON response for $country/$zip${RESET}" >&2
        record_market_processed "$country" "$zip" 0
        return 1
    fi
    
    # Check if response has lineups
    local lineup_count=$(echo "$lineups_response" | jq 'length' 2>/dev/null || echo "0")
    if [[ "$lineup_count" -eq 0 ]]; then
        echo -e "\n${YELLOW}⚠️  No lineups found for $country/$zip (check if postcode is valid)${RESET}" >&2
        record_market_processed "$country" "$zip" 0
        return 1
    fi
    
    # Step 2: Create temporary file for this market's lineups (PERFORMANCE FIX - NO SUBSHELLS)
    local temp_lineups_file="$CACHE_DIR/market_lineups_${market_number}.tmp"
    echo "$lineups_response" | jq -c '.[]' 2>/dev/null > "$temp_lineups_file"
    
    # Step 3: Process each lineup with smart real-time filtering
    local processed_lineups=0
    local total_stations_added=0
    local skipped_session_lineups=0
    local skipped_cache_lineups=0
    local skipped_base_lineups=0

    while IFS= read -r lineup_json; do
        # Validate individual lineup JSON
        if ! echo "$lineup_json" | jq -e . > /dev/null 2>&1; then
            continue  # Skip invalid lineup JSON
        fi
        
        # Step 1: Get lineup_id with minimal parsing
        local lineup_id=$(echo "$lineup_json" | jq -r '.lineupId // ""' 2>/dev/null)
        
        # Skip if no lineup ID
        if [[ -z "$lineup_id" || "$lineup_id" == "null" ]]; then
            continue
        fi
        
        # Step 2: Smart skip checks (NO API calls yet)
        
        # Session skip check
        if session_lineup_already_processed "$lineup_id"; then
            echo -e "${MAGENTA}⏭️  Session Skip: $lineup_id (already processed in this session)${RESET}" >&2
            ((skipped_session_lineups++))
            continue  # ZERO API calls, ZERO file I/O
        fi
        
        # Cache skip check (if not force refresh)
        if [[ "$force_refresh" != "true" ]] && is_lineup_cached "$lineup_id"; then
            echo -e "${YELLOW}⏭️  Database Skip: $lineup_id (in user database)${RESET}" >&2
            ((skipped_cache_lineups++))
            record_lineup_processed "$lineup_id" "$country" "$zip" 0
            continue  # ZERO API calls
        fi
        
        # Base database skip check (if not force refresh)  
        if [[ "$force_refresh" != "true" ]] && is_lineup_in_base_cache "$lineup_id"; then
            echo -e "${GREEN}⏭️  Base Skip: $lineup_id (in base database)${RESET}" >&2
            ((skipped_base_lineups++))
            record_lineup_processed "$lineup_id" "$country" "$zip" 0
            continue  # ZERO API calls
        fi
        
        # Step 3: ONLY if processing - extract metadata and make API call
        local lineup_name=$(echo "$lineup_json" | jq -r '.name // ""' 2>/dev/null)
        local lineup_location=$(echo "$lineup_json" | jq -r '.location // ""' 2>/dev/null)
        local lineup_type=$(echo "$lineup_json" | jq -r '.type // ""' 2>/dev/null)
        
        # Step 4: Fetch stations for this lineup (existing logic)
        local station_api_url="$CHANNELS_URL/dvr/guide/stations/$lineup_id"
        local stations_response
        stations_response=$(curl -s --connect-timeout $STANDARD_TIMEOUT --max-time $MAX_OPERATION_TIME "$station_api_url" 2>/dev/null)
        
        # Mark as processed in session
        mark_lineup_processed_this_session "$lineup_id"
        
        # Validate and process stations (existing logic continues unchanged...)
        if echo "$stations_response" | jq empty 2>/dev/null; then
            local station_count=$(echo "$stations_response" | jq 'length' 2>/dev/null || echo "0")
            
            # Save stations to file for potential reuse
            echo "$stations_response" > "$STATION_CACHE_DIR/${lineup_id}.json"
            
            if [[ "$station_count" -gt 0 ]]; then
                # Process stations with metadata injection (unchanged)
                echo "$stations_response" | 
                jq --arg country "$country" \
                   --arg source "user" \
                   --arg lineup_id "$lineup_id" \
                   --arg lineup_name "$lineup_name" \
                   --arg lineup_location "$lineup_location" \
                   --arg lineup_type "$lineup_type" \
                   -c 'map(. + {
                       source: $source,
                       availableIn: [$country],
                       multiCountry: false,
                       lineupTracing: [{
                         lineupId: $lineup_id,
                         lineupName: $lineup_name,
                         country: $country,
                         location: $lineup_location,
                         type: $lineup_type,
                         discoveredOrder: 1,
                         isPrimary: true
                       }]
                     } | del(.country, .originLineupId, .originLineupName, .originLocation, .originType))[]' 2>/dev/null >> "$CACHE_DIR/temp_user_stations.tmp"
                
                # Show successful processing message
                echo -e "${GREEN}✅ Processed: $lineup_id ($station_count stations)${RESET}" >&2
                
                ((processed_lineups++))
                ((total_stations_added += station_count))
                
                # Record successful lineup processing
                record_lineup_processed "$lineup_id" "$country" "$zip" "$station_count"
            else
                # Record failed lineup processing
                record_lineup_processed "$lineup_id" "$country" "$zip" 0
            fi
        else
            # Record failed lineup processing
            record_lineup_processed "$lineup_id" "$country" "$zip" 0
        fi
    done < "$temp_lineups_file"

    # Cleanup temp file
    rm -f "$temp_lineups_file"
    
    # Record market processing
    record_market_processed "$country" "$zip" "$lineup_count"
    
    # Report market processing summary
    local total_lineups_in_market="$lineup_count"
    local total_processed=$((processed_lineups))
    local total_skipped=$((skipped_session_lineups + skipped_cache_lineups + skipped_base_lineups))

    if [[ $total_skipped -gt 0 ]]; then
        echo -e "${MAGENTA}📊 Market Summary: $total_processed processed, $total_skipped skipped ($skipped_session_lineups session, $skipped_cache_lineups cache, $skipped_base_lineups base)${RESET}" >&2
    else
        echo -e "${CYAN}📊 Market Summary: $total_processed processed, $total_skipped skipped${RESET}" >&2
    fi
}

process_all_markets_sequentially_fast() {
    local force_refresh="$1"
    local total_markets="$2"
    local recovery_choice="$3"
    local market_safety_buffer="${4:-2}"  # CHANGE 1: Add safety buffer parameter
    
    echo -e "${CYAN}📊 Processing $total_markets markets sequentially${RESET}" >&2
    
    > "$CACHE_DIR/temp_user_stations.tmp"
    local markets_processed=0
    local markets_failed=0
    local markets_successful=0
    local markets_skipped=0
    
    # Get list of completed markets if resuming
    local completed_markets=()
    if [[ "$recovery_choice" == "resume" ]]; then
        # Load completed markets from progress file
        while IFS= read -r market; do
            [[ -n "$market" ]] && completed_markets+=("$market")
        done < <(get_completed_markets_from_progress "user_caching" "$market_safety_buffer")  # CHANGE 2: Add safety buffer parameter
        
        local completed_count=${#completed_markets[@]}
        if [[ $completed_count -gt 0 ]]; then
            echo -e "${GREEN}🔄 Found $completed_count safely completed markets (with $market_safety_buffer market safety buffer)${RESET}" >&2  # CHANGE 2: Update message
        else
            echo -e "${CYAN}🔄 Applying $market_safety_buffer market safety buffer - reprocessing recent markets${RESET}" >&2  # CHANGE 2: Add else clause
        fi
    fi
    
    while IFS=, read -r country zip; do
        [[ "$country" == "Country" ]] && continue
        ((markets_processed++))
        
        # Check if this market was already completed (for resume)
        local market_key="$country,$zip"
        local already_completed=false
        
        if [[ "$recovery_choice" == "resume" ]]; then
            for completed_market in "${completed_markets[@]}"; do
                if [[ "$completed_market" == "$market_key" ]]; then
                    already_completed=true
                    break
                fi
            done
        fi
        
        if [[ "$already_completed" == "true" ]]; then
            # Skip already completed market
            ((markets_skipped++))
            echo -e "${GREEN}✅ Skipping completed: $country/$zip${RESET}" >&2
            continue
        fi
        
        # Update progress before processing market
        update_progress "market_processing" "$market_key" "$markets_processed"
        
        # Process the market (using existing logic)
        if process_single_market_for_user_cache "$country" "$zip" "$markets_processed" "$total_markets"; then
            ((markets_successful++))
            
            # Mark market as completed in progress tracking
            mark_market_completed "user_caching" "$market_key"
        else
            ((markets_failed++))
            
            # Mark market as failed in progress tracking  
            mark_market_failed "user_caching" "$market_key"
        fi
        
    done < "$CSV_FILE"
    
    echo >&2  # Clear progress line
    
    # Enhanced summary with resume information
    echo -e "\n${BOLD}${GREEN}✅ Market Processing Summary:${RESET}" >&2
    
    if [[ "$recovery_choice" == "resume" ]] && [[ $markets_skipped -gt 0 ]]; then
        echo -e "${GREEN}Markets skipped (safely completed): $markets_skipped${RESET}" >&2  # CHANGE 3: Update message
    fi
    
    echo -e "${GREEN}Markets successful: $markets_successful${RESET}" >&2
    echo -e "${YELLOW}Markets failed: $markets_failed${RESET}" >&2
    echo -e "${CYAN}Total processed: $markets_processed${RESET}" >&2
    
    if [[ $markets_failed -gt 0 ]]; then
        echo -e "${CYAN}💡 Failed markets may have invalid postcodes - check output above${RESET}" >&2
    fi
    
    # Convert to array format and smart deduplicate before enhancement
    if [[ -s "$CACHE_DIR/temp_user_stations.tmp" ]]; then
        echo -e "${CYAN}🔄 Converting and smart deduplicating collected stations...${RESET}" >&2
        
        # First convert to array
        jq -s '.' "$CACHE_DIR/temp_user_stations.tmp" > "$CACHE_DIR/temp_user_stations_raw.json"
        
        if [[ $? -eq 0 ]]; then
            # Smart deduplicate with country consolidation
            smart_deduplicate_stations_before_enhancement \
                "$CACHE_DIR/temp_user_stations_raw.json" \
                "$CACHE_DIR/temp_user_stations.json"
            
            # Clean up intermediate file
            rm -f "$CACHE_DIR/temp_user_stations_raw.json"
            
            if [[ $? -eq 0 ]]; then
                echo "$CACHE_DIR/temp_user_stations.json"
                return 0
            else
                echo -e "${RED}❌ Failed to deduplicate stations${RESET}" >&2
                return 1
            fi
        else
            echo -e "${RED}❌ Failed to create consolidated stations array${RESET}" >&2
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️  No stations collected${RESET}" >&2
        return 1
    fi
}

smart_deduplicate_stations_before_enhancement() {
    local input_file="$1"
    local output_file="$2"
    
    echo -e "${CYAN}🔄 Smart deduplicating stations before enhancement (first trace only)...${RESET}" >&2
    
    local original_count=$(jq 'length' "$input_file" 2>/dev/null || echo "0")
    echo -e "${CYAN}📊 Original stations: $original_count${RESET}" >&2
    
    # SIMPLIFIED LOGIC: Keep only the first lineup trace per station
    jq '
      # Group by stationId and smart merge
      group_by(.stationId) | map(
        if length == 1 then
          # Single station - keep only first lineup trace
          .[0] as $station |
          if $station.lineupTracing and ($station.lineupTracing | length > 0) then
            # Simple: keep only the first lineup trace
            (if ($station.lineupTracing | length) > 0 then
              [($station.lineupTracing[0] + {discoveredOrder: 1, isPrimary: true})]
            else
              []
            end) as $final_traces |
            
            # Keep station with single optimized trace
            $station + {lineupTracing: $final_traces}
          else
            # No lineup tracing - keep as is
            $station
          end
        else
          # Multiple stations with same ID - smart merge with single trace
          .[0] as $primary |
          
          # STEP 1: Collect all countries from availableIn arrays (UNCHANGED - preserves data integrity)
          ([.[] | .availableIn[]? // empty] | 
           select(. != null and . != "") | unique | sort) as $all_countries |
          
          # STEP 2: Simple - take the first lineup trace from any station being merged
          (([.[] | .lineupTracing[]? // empty] | .[0]) // null) as $first_trace |
          (if $first_trace then
            [$first_trace + {discoveredOrder: 1, isPrimary: true}]
          else
            []
          end) as $final_traces |
          
          # STEP 3: Create final merged station (UNCHANGED - preserves data integrity)
          $primary + {
            availableIn: $all_countries,
            multiCountry: ($all_countries | length > 1),
            lineupTracing: $final_traces,
            source: (if ([.[] | .source] | unique | length) > 1 then "combined" else $primary.source end)
          }
        end
      ) | sort_by(.name // "")
    ' "$input_file" > "$output_file"
    
    # Simplified reporting - should always be 1 trace per station now
    local dedupe_count=$(jq 'length' "$output_file" 2>/dev/null || echo "0")
    local removed_count=$((original_count - dedupe_count))
    local multi_country_count=$(jq '[.[] | select(.multiCountry == true)] | length' "$output_file" 2>/dev/null || echo "0")
    
    # Simplified trace reporting - should always be 1 trace per station now
    local total_traces=$(jq '[.[] | .lineupTracing[]?] | length' "$output_file" 2>/dev/null || echo "0")
    
    echo -e "${GREEN}✅ Smart deduplication complete${RESET}" >&2
    echo -e "${CYAN}📊 Unique stations: $dedupe_count${RESET}" >&2
    echo -e "${YELLOW}📊 Duplicates merged: $removed_count${RESET}" >&2
    echo -e "${PURPLE}📊 Multi-country stations: $multi_country_count${RESET}" >&2
    echo -e "${BLUE}📊 Lineup traces: $total_traces (1 per station)${RESET}" >&2
    
    return 0
}

# Updated enhance_stations_with_granular_resume function
enhance_stations_with_granular_resume() {
    local start_time="$1"
    local stations_file="$2"
    local operation="${3:-user_caching}"
    local safety_buffer="${4:-50}"  # Allow customizable safety buffer
    
    echo -e "${CYAN}🔄 Starting station data enhancement process with resume capability...${RESET}" >&2
    
    # Get resume information with safety buffer
    local resume_info
    resume_info=$(get_enhancement_resume_point "$operation" "$safety_buffer")
    local start_index=$(echo "$resume_info" | cut -d' ' -f1)
    local enhanced_from_api=$(echo "$resume_info" | cut -d' ' -f2)
    
    if [[ $start_index -gt 0 ]]; then
        echo -e "${GREEN}📊 Resuming from station $start_index with safety buffer of $safety_buffer stations${RESET}" >&2
        echo -e "${GREEN}📊 Estimated previously enhanced: $enhanced_from_api stations${RESET}" >&2
    fi
    
    local tmp_json="$CACHE_DIR/enhancement_tmp_$(date +%s).json"

    # Check if stations file exists and has content
    if [ ! -f "$stations_file" ]; then
        echo -e "${RED}❌ Stations file not found: $stations_file${RESET}" >&2
        echo "0"
        return 1
    fi

    local total_stations
    total_stations=$(jq 'length' "$stations_file" 2>/dev/null)
    if [ -z "$total_stations" ] || [ "$total_stations" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No stations found in file: $stations_file${RESET}" >&2
        echo "0"
        return 0
    fi

    # Initialize progress tracking
    start_fresh_enhancement_tracking "$operation" "$stations_file"

    # Load stations into array
    mapfile -t stations < <(jq -c '.[]' "$stations_file")
    local actual_stations=${#stations[@]}

    echo -e "${CYAN}📊 Processing $actual_stations stations for enhancement (starting from $start_index)...${RESET}" >&2
    
    # Create array to collect enhanced stations
    local enhanced_stations=()
    
    # Handle resume: add already processed stations first
    if [[ $start_index -gt 0 ]]; then
        echo -e "${CYAN}🔄 Adding previously processed stations 0-$((start_index-1))...${RESET}" >&2
        
        for ((j = 0; j < start_index; j++)); do
            enhanced_stations+=("${stations[$j]}")
        done
        
        echo -e "${GREEN}✅ Added $start_index previously processed stations${RESET}" >&2
    fi
    
    # Process stations starting from start_index
    for ((i = start_index; i < actual_stations; i++)); do
        local station="${stations[$i]}"
        local current=$((i + 1))
        local percent=$((current * 100 / actual_stations))
        
        # Show progress bar BEFORE processing (only if more than 10 stations)
        if [ "$actual_stations" -gt 10 ]; then
            show_progress_bar "$current" "$actual_stations" "$percent" "$start_time"
        fi

        # ORIGINAL ENHANCEMENT LOGIC
        local callSign=$(echo "$station" | jq -r '.callSign // empty')
        local name=$(echo "$station" | jq -r '.name // empty')
        
        # Only enhance if station has callsign but missing name AND server is configured
        if [[ -n "$callSign" && "$callSign" != "null" && ( -z "$name" || "$name" == "null" ) && -n "${CHANNELS_URL:-}" ]]; then
            local api_response=$(curl -s --connect-timeout $QUICK_TIMEOUT "$CHANNELS_URL/tms/stations/$callSign" 2>/dev/null)
            local current_station_id=$(echo "$station" | jq -r '.stationId')
            local station_info=$(echo "$api_response" | jq -c --arg id "$current_station_id" '.[] | select(.stationId == $id) // empty' 2>/dev/null)
            
            if [[ -n "$station_info" && "$station_info" != "null" && "$station_info" != "{}" ]]; then
                if echo "$station_info" | jq empty 2>/dev/null; then
                    # Selectively merge only specific fields to avoid type conflicts
                    local enhanced_name=$(echo "$station_info" | jq -r '.name // ""')
                    if [[ -n "$enhanced_name" && "$enhanced_name" != "null" ]]; then
                        station=$(echo "$station" | jq --arg new_name "$enhanced_name" '. + {name: $new_name}')
                        ((enhanced_from_api++))
                    fi
                fi
            fi
            
            # Add small delay to prevent API rate limiting
            sleep 0.05
        fi

        # Add processed station to array
        enhanced_stations+=("$station")
        
        # Update progress every 25 stations
        if [[ $((current % 25)) -eq 0 ]]; then
            update_enhancement_progress_simple "$operation" "$current" "$enhanced_from_api"
        fi
    done
    
    # Clear progress line only if it was shown
    if [ "$actual_stations" -gt 10 ]; then
        echo >&2
    fi
    
    echo -e "${GREEN}✅ Station enhancement completed successfully${RESET}" >&2
    echo -e "${CYAN}📊 Enhanced $enhanced_from_api stations via API lookup${RESET}" >&2
    
    # Convert array to proper JSON array and save
    echo -e "${CYAN}💾 Finalizing enhanced station data...${RESET}" >&2
    
    if printf '%s\n' "${enhanced_stations[@]}" | jq -s '.' > "$tmp_json"; then
        # Validate the output is a proper JSON array
        if [[ "$(jq 'type' "$tmp_json" 2>/dev/null)" == '"array"' ]]; then
            mv "$tmp_json" "$stations_file"
            echo -e "${GREEN}✅ Enhanced station data saved as proper JSON array${RESET}" >&2
        else
            echo -e "${RED}❌ Failed to create proper JSON array${RESET}" >&2
            rm -f "$tmp_json"
            return 1
        fi
    else
        echo -e "${RED}❌ Station Enhancement: Failed to save enhanced data${RESET}" >&2
        echo -e "${CYAN}💡 Check disk space and file permissions${RESET}" >&2
        rm -f "$tmp_json"
        return 1
    fi

    # Mark as completed
    mark_enhancement_completed "$operation"

    # Return only the API enhancement count (clean number only)
    echo "$enhanced_from_api"
}

finalize_user_cache_update() {
  local temp_stations_file="$1"
  local start_time="$2"
  local post_dedup_stations="$3"
  local dup_stations_removed="$4"
  local will_process="$5"
  local already_cached="$6"
  local base_cache_skipped="$7"
  local enhanced_count="$8"
  local lineups_skipped_base="$9"
  local lineups_skipped_user="${10}"
  
  # APPEND to existing USER database
  echo -e "\n${BOLD}${BLUE}Phase 7: Incremental User Database Integration${RESET}"
  echo -e "${CYAN}💾 Appending new stations to existing user database...${RESET}"
  
  if add_stations_to_user_cache "$temp_stations_file"; then
    echo -e "${GREEN}✅ User database updated successfully${RESET}"
    echo -e "${CYAN}📊 Added $post_dedup_stations new stations to user database${RESET}"
  else
    echo -e "${RED}❌ Failed to update user database${RESET}"
    rm -f "$temp_stations_file"
    return 1
  fi

  # Calculate duration and show summary
  local end_time=$(date +%s)
  local duration=$((end_time - ${start_time%%.*}))
  local human_duration=$(printf '%02dh %02dm %02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

  # Show incremental summary
  show_incremental_caching_summary "$will_process" "$already_cached" "$base_cache_skipped" "$post_dedup_stations" "$dup_stations_removed" "$human_duration" "$enhanced_count" "$lineups_skipped_base" "$lineups_skipped_user"
  
  # Rebuild combined cache as final step
  if [ "$post_dedup_stations" -gt 0 ]; then
    echo -e "\n${BOLD}${BLUE}Final Step: Rebuilding Combined Cache${RESET}"
    echo -e "${CYAN}🔄 Updating combined cache with new stations...${RESET}"
    
    # Force invalidate and rebuild
    invalidate_combined_cache
    
    if build_combined_cache_with_progress >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Combined cache rebuilt successfully${RESET}"
    else
      echo -e "${YELLOW}⚠️  Combined cache rebuild failed - will rebuild on next search${RESET}"
    fi
  else
    echo -e "\n${CYAN}💡 No new stations added - combined cache unchanged${RESET}"
  fi

  # Clean up temporary files
  rm -f "$temp_stations_file"
  
  return 0
}

# ============================================================================
# PROGRESS TRACKING HELPER FUNCTIONS FOR MARKET PROCESSING
# ============================================================================
# Note: get_completed_markets_from_progress() is now provided by progress_tracker.sh

# Mark a market as completed
mark_market_completed() {
    local operation="$1"
    local market_key="$2"
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    # Add market to completed_markets array and increment processed_markets
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --arg market "$market_key" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '. + {
         completed_markets: (.completed_markets + [$market] | unique),
         processed_markets: (.processed_markets + 1),
         last_update: $timestamp
       }' "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
}

# Mark a market as failed
mark_market_failed() {
    local operation="$1" 
    local market_key="$2"
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    # Add market to failed_markets array and increment processed_markets
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --arg market "$market_key" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '. + {
         failed_markets: (.failed_markets + [$market] | unique),
         processed_markets: (.processed_markets + 1),
         last_update: $timestamp
       }' "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
}

# ============================================================================
# ENHANCED STATION ENHANCEMENT WITH GRANULAR PROGRESS TRACKING
# Add these functions to cache.sh and update progress_tracker.sh
# ============================================================================

# Initialize enhancement progress tracking
init_enhancement_progress() {
    local operation="$1"
    local stations_file="$2"
    
    if ! init_progress_context "$operation"; then
        return 0  # Fallback to regular enhancement
    fi
    
    # Count total stations
    local total_stations=$(jq 'length' "$stations_file" 2>/dev/null || echo "0")
    
    # Check if enhancement is already in progress
    if [[ -f "$PROGRESS_FILE" ]]; then
        local enhancement_status=$(jq -r '.phase_progress.station_enhancement.status // "not_started"' "$PROGRESS_FILE" 2>/dev/null)
        local temp_enhanced_file=$(jq -r '.phase_progress.station_enhancement.temp_enhanced_file // null' "$PROGRESS_FILE" 2>/dev/null)
        local enhanced_count=$(jq -r '.phase_progress.station_enhancement.enhanced_stations // 0' "$PROGRESS_FILE" 2>/dev/null)
        
        if [[ "$enhancement_status" == "completed" ]]; then
            return 2  # Already completed
        elif [[ "$enhancement_status" == "in_progress" && "$temp_enhanced_file" != "null" && -f "$temp_enhanced_file" ]]; then
            return 1  # Resume from progress
        fi
    fi
    
    # Initialize fresh enhancement tracking
    local temp_enhanced_file="$CACHE_DIR/temp_enhanced_stations.json"
    echo '[]' > "$temp_enhanced_file"
    
    # Update progress file with enhancement initialization
    if [[ -f "$PROGRESS_FILE" ]]; then
        local temp_file="${PROGRESS_FILE}.tmp.$$"
        jq --arg temp_file "$temp_enhanced_file" \
           --arg total "$total_stations" \
           --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '.phase_progress.station_enhancement += {
             status: "in_progress",
             temp_enhanced_file: $temp_file,
             total_stations: ($total | tonumber),
             enhanced_stations: 0,
             current_station_index: 0
           } |
           .current_phase = "station_enhancement" |
           .last_update = $timestamp' \
           "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
    fi
    
    return 0  # Fresh start
}

# Resume station enhancement from previous progress
resume_station_enhancement() {
    local operation="$1"
    local stations_file="$2"
    
    if ! init_progress_context "$operation"; then
        return 1
    fi
    
    # Get progress info
    local temp_enhanced_file=$(jq -r '.phase_progress.station_enhancement.temp_enhanced_file' "$PROGRESS_FILE" 2>/dev/null)
    local enhanced_count=$(jq -r '.phase_progress.station_enhancement.enhanced_stations // 0' "$PROGRESS_FILE" 2>/dev/null)
    local total_stations=$(jq -r '.phase_progress.station_enhancement.total_stations // 0' "$PROGRESS_FILE" 2>/dev/null)
    local current_index=$(jq -r '.phase_progress.station_enhancement.current_station_index // 0' "$PROGRESS_FILE" 2>/dev/null)
    
    echo -e "${GREEN}📊 Resuming enhancement: $enhanced_count/$total_stations stations completed${RESET}" >&2
    echo -e "${CYAN}📊 Starting from station index: $current_index${RESET}" >&2
    
    # Continue enhancement from where we left off
    continue_station_enhancement "$stations_file" "$temp_enhanced_file" "$current_index" "$enhanced_count" "$total_stations"
    local result=$?
    
    # Update final status
    if [[ $result -eq 0 ]]; then
        mark_enhancement_completed "$operation"
        echo "$enhanced_count"
    fi
    
    return $result
}

# Start fresh station enhancement
start_fresh_enhancement() {
    local operation="$1"
    local stations_file="$2"
    
    # Get temp enhanced file from progress
    local temp_enhanced_file="$CACHE_DIR/temp_enhanced_stations.json"
    if [[ -f "$PROGRESS_FILE" ]]; then
        temp_enhanced_file=$(jq -r '.phase_progress.station_enhancement.temp_enhanced_file' "$PROGRESS_FILE" 2>/dev/null)
    fi
    
    local total_stations=$(jq 'length' "$stations_file" 2>/dev/null || echo "0")
    
    echo -e "${CYAN}📊 Enhancing $total_stations stations...${RESET}" >&2
    
    # Start enhancement from beginning
    continue_station_enhancement "$stations_file" "$temp_enhanced_file" 0 0 "$total_stations"
    local result=$?
    
    # Update final status
    if [[ $result -eq 0 ]]; then
        mark_enhancement_completed "$operation"
        local final_count=$(jq 'length' "$temp_enhanced_file" 2>/dev/null || echo "0")
        echo "$final_count"
    fi
    
    return $result
}

# Continue station enhancement from specific index
continue_station_enhancement() {
    local stations_file="$1"
    local temp_enhanced_file="$2"
    local start_index="$3"
    local enhanced_from_api="$4"
    local total_stations="$5"
    
    local current_index="$start_index"
    local actual_stations="$total_stations"
    
    # Process stations starting from start_index
    while IFS= read -r station; do
        # Skip already processed stations
        if [[ $current_index -lt $start_index ]]; then
            ((current_index++))
            continue
        fi
        
        ((current_index++))
        
        # Show progress for every 10th station or less frequently for large datasets
        local progress_interval=10
        if [[ $actual_stations -gt 100 ]]; then
            progress_interval=25
        elif [[ $actual_stations -gt 500 ]]; then
            progress_interval=50
        fi
        
        if [[ $((current_index % progress_interval)) -eq 0 ]] || [[ $current_index -eq $actual_stations ]]; then
            local percent=$((current_index * 100 / actual_stations))
            echo -ne "\r${CYAN}🔄 [$percent%] ($current_index/$actual_stations) Enhancing stations...${RESET}" >&2
        fi
        
        # Get station ID for API lookup
        local station_id=$(echo "$station" | jq -r '.stationId // empty' 2>/dev/null)
        
        # Enhance station if it has a valid station ID
        if [[ -n "$station_id" && "$station_id" != "null" && "$station_id" != "empty" ]]; then
            # API call for station enhancement
            local api_url="$CHANNELS_URL/tms/stations/$station_id"
            local station_info=$(curl -s --connect-timeout $QUICK_TIMEOUT --max-time $STANDARD_TIMEOUT "$api_url" 2>/dev/null)
            
            # Check if we got valid response
            if [[ -n "$station_info" && "$station_info" != "null" && "$station_info" != "{}" ]]; then
                if echo "$station_info" | jq empty 2>/dev/null; then
                    # Selectively merge only specific fields to avoid type conflicts
                    local enhanced_name=$(echo "$station_info" | jq -r '.name // ""')
                    if [[ -n "$enhanced_name" && "$enhanced_name" != "null" ]]; then
                        station=$(echo "$station" | jq --arg new_name "$enhanced_name" '. + {name: $new_name}')
                        ((enhanced_from_api++))
                    fi
                fi
            fi
        fi
        
        # Add enhanced station to temp file
        echo "$station" >> "$temp_enhanced_file"
        
        # Update progress every 25 stations or on interruption points
        if [[ $((current_index % 25)) -eq 0 ]]; then
            update_enhancement_progress "$current_index" "$enhanced_from_api"
        fi
        
    done < <(jq -c '.[]' "$stations_file" 2>/dev/null | tail -n +$((start_index + 1)))
    
    # Clear progress line if it was shown
    if [[ $actual_stations -gt 10 ]]; then
        echo >&2
    fi
    
    echo -e "${GREEN}✅ Station enhancement completed successfully${RESET}" >&2
    echo -e "${CYAN}📊 Enhanced $enhanced_from_api stations via API lookup${RESET}" >&2
    
    # Convert temp JSONL to proper JSON array and replace original file
    echo -e "${CYAN}💾 Finalizing enhanced station data...${RESET}" >&2
    
    # If we have a temp enhanced file with data, convert it to proper JSON array
    if [[ -s "$temp_enhanced_file" ]]; then
        # Read all lines and create JSON array
        jq -s '.' "$temp_enhanced_file" > "${stations_file}.enhanced.tmp"
        if [[ $? -eq 0 ]]; then
            mv "${stations_file}.enhanced.tmp" "$stations_file"
            echo -e "${GREEN}✅ Enhanced station data saved successfully${RESET}" >&2
        else
            echo -e "${RED}❌ Station Enhancement: Failed to save enhanced data${RESET}" >&2
            echo -e "${CYAN}💡 Check disk space and file permissions${RESET}" >&2
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️  No enhanced data to save${RESET}" >&2
    fi
    
    return 0
}

# Update enhancement progress in progress file
update_enhancement_progress() {
    local current_index="$1"
    local enhanced_count="$2"
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 1
    fi
    
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --arg index "$current_index" \
       --arg count "$enhanced_count" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.phase_progress.station_enhancement += {
         current_station_index: ($index | tonumber),
         enhanced_stations: ($count | tonumber)
       } |
       .last_update = $timestamp' \
       "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
}

# Mark enhancement as completed
mark_enhancement_completed() {
    local operation="$1"
    
    if ! init_progress_context "$operation"; then
        return 0
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0
    fi
    
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.phase_progress.station_enhancement.status = "completed" |
        .last_update = $timestamp' \
       "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
}

# Get completed enhancement count
get_completed_enhancement_count() {
    local operation="$1"
    
    if ! init_progress_context "$operation"; then
        echo "0"
        return 1
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "0"
        return 1
    fi
    
    jq -r '.phase_progress.station_enhancement.enhanced_stations // 0' "$PROGRESS_FILE" 2>/dev/null || echo "0"
}

# Start fresh enhancement tracking
start_fresh_enhancement_tracking() {
    local operation="$1"
    local stations_file="$2"
    
    if ! init_progress_context "$operation"; then
        return 0  # Skip tracking if no progress context
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0  # Skip tracking if no progress file
    fi
    
    # Count total stations
    local total_stations=$(jq 'length' "$stations_file" 2>/dev/null || echo "0")
    
    # Update progress file with enhancement initialization
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --arg temp_file "$stations_file" \
       --arg total "$total_stations" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.phase_progress.station_enhancement += {
         status: "in_progress",
         temp_stations_file: $temp_file,
         total_stations: ($total | tonumber),
         enhanced_stations: 0
       } |
       .current_phase = "station_enhancement" |
       .last_update = $timestamp' \
       "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
}

# Mark enhancement as completed (preserves original count)
mark_enhancement_completed() {
    local operation="$1"
    
    if ! init_progress_context "$operation"; then
        return 0  # Skip tracking if no progress context
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0  # Skip tracking if no progress file
    fi
    
    # We don't know the exact enhanced count since original function handles it
    # Just mark as completed
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.phase_progress.station_enhancement.status = "completed" |
        .last_update = $timestamp' \
       "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
}

# Simple progress update helper
update_enhancement_progress_simple() {
    local operation="$1"
    local current_index="$2"
    local enhanced_count="$3"
    
    if ! init_progress_context "$operation"; then
        return 0
    fi
    
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0
    fi
    
    local temp_file="${PROGRESS_FILE}.tmp.$$"
    jq --arg index "$current_index" \
       --arg count "$enhanced_count" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.phase_progress.station_enhancement += {
         current_station_index: ($index | tonumber),
         enhanced_stations: ($count | tonumber)
       } |
       .last_update = $timestamp' \
       "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"
}

# ============================================================================
# USER DATABASE EXPANSION - ORCHESTRATOR FUNCTION
# ============================================================================

perform_user_database_expansion() {
  local force_refresh="${1:-false}"  # Optional parameter: false=incremental, true=complete refresh
  
  # Check if CDVR is configured before proceeding
  if ! check_integration_requirement "Channels DVR" "is_cdvr_configured" "configure_cdvr_integration" "User Database Expansion"; then
    return 1
  fi
  
  # RECOVERY PHASE: CHECK FOR INTERRUPTED SESSION AND HANDLE RECOVERY
  local recovery_choice=""
  check_for_interrupted_session "user_caching"
  local recovery_result=$?

  case "$recovery_result" in
      0) 
          recovery_choice="resume"
          echo -e "${CYAN}🔄 Resuming interrupted user_caching session...${RESET}"
          ;;
      1) 
          echo -e "${YELLOW}Operation cancelled by user${RESET}"
          return 0
          ;;
      2) 
          recovery_choice="fresh"  # No interrupted session or start fresh
          ;;
      *) 
          recovery_choice="fresh"  # Default
          ;;
  esac
  
  # PHASE 0: VALIDATE PREREQUISITES AND INITIALIZE CACHING ENVIRONMENT
  if ! validate_caching_prerequisites "$force_refresh"; then
    return 1
  fi
  
  # PROGRESS TRACKING: INITIALIZE OR RESUME PROGRESS TRACKING
  local total_markets=$(tail -n +2 "$CSV_FILE" | wc -l)
  local resume_phase="market_processing"  # Default
  
  if [[ "$recovery_choice" == "resume" ]]; then
    # Resume existing session
    if ! resume_progress_tracking "user_caching"; then
      echo -e "${RED}❌ Failed to resume session - starting fresh${RESET}"
      recovery_choice="fresh"
    else
      # Restore session state from progress file
      restore_session_state_from_progress "user_caching"
      
      # Determine which phase to resume from
      resume_phase=$(determine_resume_phase "user_caching")
      echo -e "${CYAN}📊 Will resume from phase: $resume_phase${RESET}"
      
      # Handle completed operation
      if [[ "$resume_phase" == "completed" ]]; then
        echo -e "${GREEN}✅ All phases already completed!${RESET}"
        finalize_progress_tracking "user_caching" "completed"
        return 0
      fi
    fi
  fi
  
  if [[ "$recovery_choice" == "fresh" ]]; then
    # Initialize fresh progress tracking
    echo -e "${CYAN}🆕 Starting fresh user database expansion session...${RESET}"
    if ! init_progress_tracking "user_caching" "$total_markets" "$force_refresh" "$CSV_FILE"; then
      echo -e "${RED}❌ Failed to initialize progress tracking${RESET}"
      return 1
    fi
    resume_phase="market_processing"
  fi
  
  # PHASE 1: ANALYZE WHICH MARKETS NEED PROCESSING (RESUME-AWARE)
  local markets_to_process_output
  local temp_stations_file
  local post_dedup_stations=0
  local already_cached=0
  local base_cache_skipped=0
  local will_process=0
  
  # CONDITIONAL PHASE EXECUTION BASED ON RESUME POINT
  
  # === MARKET PROCESSING PHASE ===
  if [[ "$resume_phase" == "market_processing" ]]; then
    echo -e "\n${CYAN}🔍 Analyzing markets for processing...${RESET}"
    
    if [[ "$recovery_choice" == "resume" ]]; then
      # Get remaining markets from progress file
      markets_to_process_output=$(get_remaining_markets_from_progress "user_caching")
      local analysis_result=$?
    else
      # Fresh analysis (preserving original typo: NNEED)
      markets_to_process_output=$(analyze_markets_for_processing "$force_refresh")
      local analysis_result=$?
    fi
    
    # Early exit if no processing needed
    if [[ $analysis_result -ne 0 ]]; then
      if [[ "$recovery_choice" == "resume" ]]; then
        echo -e "${GREEN}✅ Market processing already completed${RESET}"
        mark_phase_completed "market_processing"
        resume_phase="station_enhancement"  # Move to next phase
      else
        return 0
      fi
    fi
    
    # Process markets if we have any
    if [[ $analysis_result -eq 0 ]]; then
      # Convert output back to array
      local markets_to_process=()
      while IFS= read -r line; do
        [[ -n "$line" ]] && markets_to_process+=("$line")
      done <<< "$markets_to_process_output"
      
      will_process=${#markets_to_process[@]}
      
      if [[ "$recovery_choice" == "resume" ]]; then
        echo -e "${GREEN}📊 Found $will_process markets remaining to process${RESET}"
      fi
      
      # Setup caching environment and get start time
      local start_time
      if [[ "$recovery_choice" == "resume" ]]; then
        # Preserve original start time from progress file
        start_time=$(get_original_start_time_from_progress "user_caching")
      else
        start_time=$(setup_caching_environment)
      fi

      # PHASE 2: MARKET BY MARKET PROCESSING
      echo -e "\n${BOLD}${BLUE}Phase 2: Market-by-Market Processing${RESET}"
      
      # Update progress phase
      update_progress "market_processing" "" 0
      
      temp_stations_file=$(process_all_markets_sequentially_fast "$force_refresh" "$total_markets" "$recovery_choice")
      local processing_result=$?
      
      if [[ $processing_result -ne 0 ]] || [[ -z "$temp_stations_file" ]]; then
        echo -e "${YELLOW}⚠️  No new stations collected${RESET}" >&2
        finalize_progress_tracking "user_caching" "no_new_stations"
        return 0
      fi
      
      # Mark market processing as completed
      mark_phase_completed "market_processing"
      
      # Get station counts for summary
      post_dedup_stations=$(jq 'length' "$temp_stations_file" 2>/dev/null || echo "0")
    fi
  fi
  
  # === STATION ENHANCEMENT PHASE ===
  if [[ "$resume_phase" == "station_enhancement" ]] || [[ "$resume_phase" == "market_processing" && -n "$temp_stations_file" ]]; then
    
    # If resuming enhancement, get temp file from progress
    if [[ "$resume_phase" == "station_enhancement" ]]; then
      temp_stations_file=$(get_temp_stations_file_from_progress "user_caching")
      if [[ -z "$temp_stations_file" ]] || [[ ! -f "$temp_stations_file" ]]; then
        echo -e "${RED}❌ Cannot resume station enhancement - temp file missing${RESET}"
        echo -e "${CYAN}💡 Starting fresh...${RESET}"
        finalize_progress_tracking "user_caching" "restart_needed"
        return 1
      fi
      echo -e "${CYAN}🔄 Resuming station enhancement from: $temp_stations_file${RESET}"
      post_dedup_stations=$(jq 'length' "$temp_stations_file" 2>/dev/null || echo "0")
    fi
    
    # PHASE 3: STATION DATA ENHANCEMENT (NAME INJECTION FROM API)
    echo -e "\n${BOLD}${BLUE}Phase 3: Station Data Enhancement${RESET}"
    echo -e "${CYAN}🔄 Enhancing station information...${RESET}"
    
    # Update progress phase with temp file info
    update_progress "station_enhancement" "$temp_stations_file" "$post_dedup_stations"
    
    local enhanced_count
    enhanced_count=$(enhance_stations_with_granular_resume "$(date +%s.%N)" "$temp_stations_file")
    
    # Mark enhancement as completed
    mark_phase_completed "station_enhancement"
  fi

  # === CACHE FINALIZATION PHASE ===
  if [[ "$resume_phase" == "cache_finalization" ]] || [[ -n "$temp_stations_file" ]]; then
    
    # If resuming finalization, get temp file from progress
    if [[ "$resume_phase" == "cache_finalization" ]]; then
      temp_stations_file=$(get_temp_stations_file_from_progress "user_caching")
      if [[ -z "$temp_stations_file" ]] || [[ ! -f "$temp_stations_file" ]]; then
        echo -e "${RED}❌ Cannot resume cache finalization - temp file missing${RESET}"
        finalize_progress_tracking "user_caching" "restart_needed" 
        return 1
      fi
      echo -e "${CYAN}🔄 Resuming cache finalization${RESET}"
      post_dedup_stations=$(jq 'length' "$temp_stations_file" 2>/dev/null || echo "0")
      enhanced_count=0  # We don't track this for resume
    fi
    
    # Get analysis stats for summary (these were calculated earlier but need to be preserved)
    if [[ "$recovery_choice" != "resume" ]] || [[ "$resume_phase" == "market_processing" ]]; then
      # Re-analyze to get exact counts for summary (quick pass)
      while IFS=, read -r country zip; do
        [[ "$country" == "Country" ]] && continue
        if [[ "$force_refresh" != "true" ]]; then
          if is_market_cached "$country" "$zip"; then
            ((already_cached++))
          elif is_market_in_base_cache "$country" "$zip"; then
            ((base_cache_skipped++))
          fi
        fi
      done < "$CSV_FILE"
    fi

    # PHASE 4: FINALIZE USER DATABASE UPDATE
    update_progress "cache_finalization" "" 0
    
    # Get start time for summary (convert to Unix timestamp if needed)
    if [[ -z "$start_time" ]]; then
      local iso_start_time=$(get_original_start_time_from_progress "user_caching")
      # Convert ISO timestamp to Unix timestamp for duration calculation
      start_time=$(date -d "$iso_start_time" +%s 2>/dev/null || echo "$(date +%s)")
    fi
    
    finalize_user_cache_update "$temp_stations_file" "$start_time" "$post_dedup_stations" "0" "$will_process" "$already_cached" "$base_cache_skipped" "${enhanced_count:-0}" "0" "0"
    
    # Mark finalization as completed
    mark_phase_completed "cache_finalization"
  fi
  
  # COMPLETION: FINALIZE PROGRESS TRACKING
  finalize_progress_tracking "user_caching" "completed"
}