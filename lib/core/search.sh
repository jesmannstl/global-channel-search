#!/bin/bash
# lib/core/search.sh - Search and filtering utilities for Radio Garden Cache
# Part of modular refactor - contains pure utility functions for search operations

# Module: Search Utilities
# Purpose: Pure utility functions for building search filters and extracting data
# Dependencies: None (utilities only)
# Usage: Source this file and call search_* functions

# ============================================================================
# SEARCH FILTER BUILDERS
# ============================================================================

# Build jq filter for video resolution filtering
# Args: $1 - Optional runtime resolution override
# Returns: jq filter string for resolution matching
search_build_resolution_filter() {
  local runtime_resolution="${1:-}"  # Optional runtime override
  
  # Use runtime resolution if provided, otherwise use configured filter
  if [[ -n "$runtime_resolution" ]]; then
    echo "and (.videoQuality.videoType // \"\" | . == \"$runtime_resolution\")"
  elif [ "$FILTER_BY_RESOLUTION" = "true" ]; then
    local filter_conditions=""
    IFS=',' read -ra RESOLUTIONS <<< "$ENABLED_RESOLUTIONS"
    for res in "${RESOLUTIONS[@]}"; do
      if [ -n "$filter_conditions" ]; then
        filter_conditions+=" or "
      fi
      filter_conditions+="(.videoQuality.videoType // \"\" | . == \"$res\")"
    done
    echo "and ($filter_conditions)"
  else
    echo ""
  fi
}

# Build jq filter for country filtering
# Args: $1 - Optional runtime country override
# Returns: jq filter string for country matching
search_build_country_filter() {
  local runtime_country="${1:-}"  # Optional runtime override
  
  # Use runtime country if provided, otherwise use configured filter
  if [[ -n "$runtime_country" ]]; then
    echo "and (.availableIn[]? // \"\" | . == \"$runtime_country\")"
  elif [ "$FILTER_BY_COUNTRY" = "true" ] && [ -n "$ENABLED_COUNTRIES" ]; then
    local filter_conditions=""
    IFS=',' read -ra COUNTRIES <<< "$ENABLED_COUNTRIES"
    for country in "${COUNTRIES[@]}"; do
      if [ -n "$filter_conditions" ]; then
        filter_conditions+=" or "
      fi
      filter_conditions+="(.availableIn[]? // \"\" | . == \"$country\")"
    done
    echo "and ($filter_conditions)"
  else
    echo ""
  fi
}

# ============================================================================
# MAIN SEARCH FUNCTION
# ============================================================================

# Core station search function  
# Args: search_term, page, output_format, runtime_country, runtime_resolution
# Returns: Search results in specified format
search_stations() {
  local search_term="$1"
  local page="${2:-1}"
  local output_format="${3:-tsv}"     # "tsv", "count", or "full"
  local runtime_country="${4:-}"      # For future channel name parsing
  local runtime_resolution="${5:-}"   # For future channel name parsing
  local results_per_page=$DEFAULT_RESULTS_PER_PAGE
  
  # Log search operation
  local search_context="term='$search_term', page=$page, format=$output_format"
  [[ -n "$runtime_country" ]] && search_context+=", country=$runtime_country"
  [[ -n "$runtime_resolution" ]] && search_context+=", resolution=$runtime_resolution"
  
  if declare -f log_info >/dev/null 2>&1; then
    log_info "search" "Starting station search" "$search_context"
  fi
  
  local start_index=$(( (page - 1) * results_per_page ))
  
  # Get effective stations file (same source for all searches)
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -ne 0 ]; then
    if declare -f log_error >/dev/null 2>&1; then
      log_error "search" "Failed to get effective stations file"
    fi
    if [[ "$output_format" == "count" ]]; then
      echo "0"
    fi
    return 1
  fi
  
  # Escape special regex characters for safety (same as local search)
  local escaped_term=$(echo "$search_term" | sed 's/[[\.*^$()+?{|]/\\&/g')
  
  # Build filters with runtime override capability (for future parsing)
  local resolution_filter=$(search_build_resolution_filter "$runtime_resolution")
  local country_filter=$(search_build_country_filter "$runtime_country")
  
  # Core search logic - identical for all callers
  if [[ "$output_format" == "count" ]]; then
    # Return count only
    jq -r --arg term "$escaped_term" --arg exact_term "$search_term" '
      [.[] | select(
        ((.name // "" | test($term; "i")) or
         (.callSign // "" | test($term; "i")) or
         (.name // "" | . == $exact_term) or
         (.callSign // "" | . == $exact_term))
        '"$resolution_filter"'
        '"$country_filter"'
      )] | length
    ' "$stations_file" 2>/dev/null || echo "0"
  elif [[ "$output_format" == "tsv" ]]; then
    # Return paginated TSV results (for Dispatcharr tables)
    jq -r --arg term "$escaped_term" --arg exact_term "$search_term" --argjson start "$start_index" --argjson limit "$results_per_page" '
      [.[] | select(
        ((.name // "" | test($term; "i")) or
         (.callSign // "" | test($term; "i")) or
         (.name // "" | . == $exact_term) or
         (.callSign // "" | . == $exact_term))
        '"$resolution_filter"'
        '"$country_filter"'
      )] | .[$start:($start + $limit)][] | 
      (.stationId // "") + "\t" + 
        (.name // "") + "\t" + 
        (.callSign // "") + "\t" + 
        (if (.videoQuality.videoType // "") == "" then "Unknown" else .videoQuality.videoType end) + "\t" + 
        ((.availableIn // []) | if length > 1 then join(",") else .[0] // "UNK" end)
    ' "$stations_file" 2>/dev/null
  else
    # Return full JSON results (for local search display)
    jq -r --arg term "$escaped_term" --arg exact_term "$search_term" --argjson start "$start_index" --argjson limit "$results_per_page" '
      [.[] | select(
        ((.name // "" | test($term; "i")) or
         (.callSign // "" | test($term; "i")) or
         (.name // "" | . == $exact_term) or
         (.callSign // "" | . == $exact_term))
        '"$resolution_filter"'
        '"$country_filter"'
      )] | .[$start:($start + $limit)][] | 
      [.name, .callSign, (if (.videoQuality.videoType // "") == "" then "Unknown" else .videoQuality.videoType end), .stationId, ((.availableIn // []) | if length > 1 then join(",") else .[0] // "UNK" end)] | @tsv
    ' "$stations_file" 2>/dev/null
  fi
  
  # Log search completion
  if declare -f log_info >/dev/null 2>&1; then
    log_info "search" "Station search completed" "$search_context"
  fi
}

# ============================================================================
# DATA EXTRACTION UTILITIES  
# ============================================================================

# Extract available countries from station data
# Returns: comma-separated list of countries
search_get_available_countries() {
  local debug_trace=${DEBUG_COUNTRY_FILTER:-false}
  
  if [ "$debug_trace" = true ]; then
    echo -e "${INFO_STYLE}[DEBUG] search_get_available_countries() - extracting from availableIn arrays${RESET}" >&2
  fi
  
  # Get countries from availableIn arrays instead of legacy country field
  local stations_file
  if stations_file=$(get_effective_stations_file 2>/dev/null); then
    if [ "$debug_trace" = true ]; then
      echo -e "${INFO_STYLE}[DEBUG] Using stations file: $stations_file${RESET}" >&2
    fi
    
    local countries
    countries=$(jq -r '[.[] | .availableIn[]? // empty | select(. != "")] | unique | join(",")' "$stations_file" 2>/dev/null)
    
    if [[ -n "$countries" && "$countries" != "null" && "$countries" != "" ]]; then
      if [ "$debug_trace" = true ]; then
        echo -e "${INFO_STYLE}[DEBUG] Found countries from arrays: $countries${RESET}" >&2
      fi
      echo "$countries"
      return 0
    else
      if [ "$debug_trace" = true ]; then
        echo -e "${INFO_STYLE}[DEBUG] No countries found in availableIn arrays${RESET}" >&2
      fi
      echo ""
      return 1
    fi
  else
    if [ "$debug_trace" = true ]; then
      echo -e "${INFO_STYLE}[DEBUG] No effective stations file available${RESET}" >&2
    fi
    echo ""
    return 1
  fi
}

# Get video quality for a specific station ID
# Args: $1 - Station ID to lookup
# Returns: Video quality type or "Unknown"
search_get_station_quality() {
  local station_id="$1"
  
  # Get effective stations file
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -ne 0 ]; then
    echo "Unknown"
    return 1
  fi
  
  # Extract quality for this station
  local quality=$(jq -r --arg id "$station_id" \
    '.[] | select(.stationId == $id) | .videoQuality.videoType // "Unknown"' \
    "$stations_file" 2>/dev/null | head -n 1)
  
  echo "${quality:-Unknown}"
}

# Get logo URL for a specific station ID
# Args: $1 - Station ID to lookup
# Returns: Logo URL or empty string
search_get_station_logo_url() {
  local stid="$1"
  
  # Get effective stations file for logo lookup
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -eq 0 ]; then
    local logo_url=$(jq -r --arg id "$stid" '.[] | select(.stationId == $id) | .preferredImage.uri // empty' "$stations_file" | head -n 1)
    echo "$logo_url"
  fi
}

# ============================================================================
# MODULE VALIDATION
# ============================================================================

# Validate this module loaded correctly
search_module_loaded() {
    echo "search module loaded"
}

# ============================================================================
# LEGACY COMPATIBILITY WRAPPERS - TO DO REMOVE IN FUTURE
# ============================================================================

# Compatibility wrapper - delegates to search module
shared_station_search() {
  search_stations "$@"
}

# Compatibility wrapper - delegates to search module
get_station_quality() {
  search_get_station_quality "$@"
}