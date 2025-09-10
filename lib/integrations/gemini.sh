#!/bin/bash

# ============================================================================
# GEMINI INTEGRATION MODULE
# ============================================================================
# Description: Provides AI-powered search capabilities using the Google Gemini API.
# Version: 1.0.0
# ============================================================================

# Prevent multiple inclusions
if [[ "${GEMINI_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly GEMINI_MODULE_LOADED="true"

# ============================================================================
# LOGGING
# ============================================================================

# Module-specific logging function
_gemini_log() {
    local level="$1"
    local message="$2"

    if declare -f log_${level} >/dev/null 2>&1; then
        log_${level} "gemini" "$message"
    else
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [$level] [GEMINI] $message" >&2
    fi
}

# ============================================================================
# API FUNCTIONS
# ============================================================================

# Test the connection to the Gemini API with the configured key
gemini_test_connection() {
    _gemini_log "info" "Testing Gemini API connection..."

    if [[ -z "${GEMINI_API_KEY:-}" ]]; then
        _gemini_log "error" "Gemini API key is not set."
        return 1
    fi

    local api_url="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    # Simple payload to test the API
    local payload
    payload=$(jq -n \
        --arg text "hello" \
        '{contents: [{parts: [{text: $text}]}]}')

    local response
    response=$(curl -s -w "HTTP_STATUS:%{http_code}" \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -d "$payload" \
        "$api_url" 2>&1)

    local curl_exit_code=$?
    local http_status=$(echo "$response" | sed -n 's/.*HTTP_STATUS://p')
    local response_body=$(echo "$response" | sed 's/HTTP_STATUS:.*//')

    if [[ $curl_exit_code -ne 0 ]]; then
        _gemini_log "error" "curl command failed with exit code $curl_exit_code."
        return 1
    fi

    if [[ "$http_status" -eq 200 ]]; then
        _gemini_log "info" "Gemini API key is valid."
        return 0
    else
        _gemini_log "error" "Gemini API key is invalid or API is unreachable. Status: $http_status"
        _gemini_log "debug" "Response body: $response_body"
        return 1
    fi
}

# Parse a natural language query into structured search parameters using Gemini
gemini_ai_search_parser() {
    local user_query="$1"

    if [[ -z "$user_query" ]]; then
        _gemini_log "error" "AI search parser called with an empty query."
        return 1
    fi

    if ! gemini_test_connection >/dev/null 2>&1; then
        _gemini_log "error" "Gemini connection test failed. Cannot proceed with AI search."
        echo "Error: Gemini connection failed. Check API key and configuration." >&2
        return 1
    fi

    _gemini_log "info" "Sending user query to Gemini AI: '$user_query'"

    # The prompt engineering is key here.
    # We give the model a role, define the exact output format, and provide examples.
    local prompt
    prompt=$(cat <<PROMPT
You are an intelligent search query parser for a television station database. Your task is to analyze a user's natural language query and convert it into a structured JSON object.

The JSON object must contain the following keys:
- "search_term": A string representing the primary search keyword (e.g., "CNN", "ABC News"). This should be your best guess at the channel name or call sign. It can be null if the query is too generic.
- "quality": A string that must be one of the following values: "HDTV", "SDTV", "UHDTV", or null if not specified.
- "country": A string representing the 3-letter ISO country code (e.g., "USA", "CAN", "GBR"), or null if not specified.

Analyze the following user query and return ONLY the raw JSON object, with no other text, explanations, or markdown formatting.

User Query: "$user_query"
PROMPT
)

    local payload
    payload=$(jq -n --arg text "$prompt" '{
        "contents": [{
            "parts": [{"text": $text}]
        }],
        "generationConfig": {
            "responseMimeType": "application/json"
        }
    }')

    local api_url="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    local response
    response=$(curl -s \
        --connect-timeout ${STANDARD_TIMEOUT:-10} \
        --max-time ${EXTENDED_TIMEOUT:-15} \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -d "$payload" \
        "$api_url")

    if [[ -z "$response" ]]; then
        _gemini_log "error" "Received an empty response from Gemini API."
        echo "Error: Received an empty response from Gemini API." >&2
        return 1
    fi

    # Extract the text part which should contain our JSON
    local parsed_json
    parsed_json=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)

    if [[ -z "$parsed_json" || "$parsed_json" == "null" ]]; then
        _gemini_log "error" "Failed to extract valid JSON from Gemini response."
        _gemini_log "debug" "Full response: $response"
        echo "Error: AI failed to generate a valid search query." >&2
        return 1
    fi

    # Validate the JSON structure
    local search_term=$(echo "$parsed_json" | jq -r '.search_term // empty')
    local quality=$(echo "$parsed_json" | jq -r '.quality // empty')
    local country=$(echo "$parsed_json" | jq -r '.country // empty')

    if [[ -z "$search_term" && -z "$quality" && -z "$country" ]]; then
        _gemini_log "warn" "AI returned an empty search structure."
        echo "Warning: AI could not determine any search parameters from your query." >&2
        return 1
    fi

    _gemini_log "info" "AI parsed search: term='$search_term', quality='$quality', country='$country'"

    # Return the clean, validated JSON string
    echo "$parsed_json"
    return 0
}
