#!/bin/bash

# === Channel Name Parsing Framework ===
# Comprehensive channel name analysis and parsing for station matching

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Helper function to check if a word exists as a separate word (not part of another word)
word_exists() {
    local text="$1"
    local word="$2"
    # Add spaces around text to simplify boundary checking
    local padded_text=" $text "
    local padded_word=" $word "
    # Check if the padded word exists in the padded text
    [[ "$padded_text" == *"$padded_word"* ]]
}

# Helper function to remove a word safely (only if it's a separate word)
remove_word() {
    local text="$1"
    local word="$2"
    # Remove the word and clean up extra spaces
    echo "$text" | sed -E "s/(^|[[:space:]])$word([[:space:]]|$)/ /g" | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

# ============================================================================
# CORE CHANNEL PARSING FUNCTIONS
# ============================================================================

# Main channel parsing function - returns cleaned name and detected attributes
parse_channel_name() {
    local channel_name="$1"
    local debug_mode="${2:-false}"
    
    # Initialize variables
    local clean_name="$channel_name"
    local detected_country=""
    local detected_resolution=""
    
    # Step 0: Handle special character separators FIRST
    clean_name=$(handle_special_separators "$clean_name")
    
    # Step 1: Country detection
    # Major English-speaking markets (most common)
    if word_exists "$clean_name" "US" || word_exists "$clean_name" "USA" || word_exists "$clean_name" "UNITED STATES"; then
        detected_country="USA"
        clean_name=$(remove_word "$clean_name" "US")
        clean_name=$(remove_word "$clean_name" "USA")
        clean_name=$(remove_word "$clean_name" "UNITED STATES")
    elif word_exists "$clean_name" "UK" || word_exists "$clean_name" "GBR" || word_exists "$clean_name" "BRITAIN" || word_exists "$clean_name" "ENGLAND"; then
        detected_country="GBR"
        clean_name=$(remove_word "$clean_name" "UK")
        clean_name=$(remove_word "$clean_name" "GBR")
        clean_name=$(remove_word "$clean_name" "BRITAIN")
        clean_name=$(remove_word "$clean_name" "ENGLAND")
    elif word_exists "$clean_name" "CA" || word_exists "$clean_name" "CAN" || word_exists "$clean_name" "CANADA"; then
        detected_country="CAN"
        clean_name=$(remove_word "$clean_name" "CA")
        clean_name=$(remove_word "$clean_name" "CAN")
        clean_name=$(remove_word "$clean_name" "CANADA")
    elif word_exists "$clean_name" "AU" || word_exists "$clean_name" "AUS" || word_exists "$clean_name" "AUSTRALIA"; then
        detected_country="AUS"
        clean_name=$(remove_word "$clean_name" "AU")
        clean_name=$(remove_word "$clean_name" "AUS")
        clean_name=$(remove_word "$clean_name" "AUSTRALIA")
    
    # Major European markets
    elif word_exists "$clean_name" "DE" || word_exists "$clean_name" "DEU" || word_exists "$clean_name" "GERMANY" || word_exists "$clean_name" "DEUTSCH"; then
        detected_country="DEU"
        clean_name=$(remove_word "$clean_name" "DE")
        clean_name=$(remove_word "$clean_name" "DEU")
        clean_name=$(remove_word "$clean_name" "GERMANY")
        clean_name=$(remove_word "$clean_name" "DEUTSCH")
    elif word_exists "$clean_name" "FR" || word_exists "$clean_name" "FRA" || word_exists "$clean_name" "FRANCE" || word_exists "$clean_name" "FRENCH"; then
        detected_country="FRA"
        clean_name=$(remove_word "$clean_name" "FR")
        clean_name=$(remove_word "$clean_name" "FRA")
        clean_name=$(remove_word "$clean_name" "FRANCE")
        clean_name=$(remove_word "$clean_name" "FRENCH")
    elif word_exists "$clean_name" "IT" || word_exists "$clean_name" "ITA" || word_exists "$clean_name" "ITALY" || word_exists "$clean_name" "ITALIAN"; then
        detected_country="ITA"
        clean_name=$(remove_word "$clean_name" "IT")
        clean_name=$(remove_word "$clean_name" "ITA")
        clean_name=$(remove_word "$clean_name" "ITALY")
        clean_name=$(remove_word "$clean_name" "ITALIAN")
    elif word_exists "$clean_name" "ES" || word_exists "$clean_name" "ESP" || word_exists "$clean_name" "SPAIN" || word_exists "$clean_name" "SPANISH"; then
        detected_country="ESP"
        clean_name=$(remove_word "$clean_name" "ES")
        clean_name=$(remove_word "$clean_name" "ESP")
        clean_name=$(remove_word "$clean_name" "SPAIN")
        clean_name=$(remove_word "$clean_name" "SPANISH")
    elif word_exists "$clean_name" "NL" || word_exists "$clean_name" "NLD" || word_exists "$clean_name" "NETHERLANDS" || word_exists "$clean_name" "DUTCH"; then
        detected_country="NLD"
        clean_name=$(remove_word "$clean_name" "NL")
        clean_name=$(remove_word "$clean_name" "NLD")
        clean_name=$(remove_word "$clean_name" "NETHERLANDS")
        clean_name=$(remove_word "$clean_name" "DUTCH")
    elif word_exists "$clean_name" "BE" || word_exists "$clean_name" "BEL" || word_exists "$clean_name" "BELGIUM" || word_exists "$clean_name" "BELGIAN"; then
        detected_country="BEL"
        clean_name=$(remove_word "$clean_name" "BE")
        clean_name=$(remove_word "$clean_name" "BEL")
        clean_name=$(remove_word "$clean_name" "BELGIUM")
        clean_name=$(remove_word "$clean_name" "BELGIAN")
    elif word_exists "$clean_name" "CH" || word_exists "$clean_name" "CHE" || word_exists "$clean_name" "SWITZERLAND" || word_exists "$clean_name" "SWISS"; then
        detected_country="CHE"
        clean_name=$(remove_word "$clean_name" "CH")
        clean_name=$(remove_word "$clean_name" "CHE")
        clean_name=$(remove_word "$clean_name" "SWITZERLAND")
        clean_name=$(remove_word "$clean_name" "SWISS")
    elif word_exists "$clean_name" "AT" || word_exists "$clean_name" "AUT" || word_exists "$clean_name" "AUSTRIA" || word_exists "$clean_name" "AUSTRIAN"; then
        detected_country="AUT"
        clean_name=$(remove_word "$clean_name" "AT")
        clean_name=$(remove_word "$clean_name" "AUT")
        clean_name=$(remove_word "$clean_name" "AUSTRIA")
        clean_name=$(remove_word "$clean_name" "AUSTRIAN")
    
    # Nordic countries
    elif word_exists "$clean_name" "SE" || word_exists "$clean_name" "SWE" || word_exists "$clean_name" "SWEDEN" || word_exists "$clean_name" "SWEDISH"; then
        detected_country="SWE"
        clean_name=$(remove_word "$clean_name" "SE")
        clean_name=$(remove_word "$clean_name" "SWE")
        clean_name=$(remove_word "$clean_name" "SWEDEN")
        clean_name=$(remove_word "$clean_name" "SWEDISH")
    elif word_exists "$clean_name" "NO" || word_exists "$clean_name" "NOR" || word_exists "$clean_name" "NORWAY" || word_exists "$clean_name" "NORWEGIAN"; then
        detected_country="NOR"
        clean_name=$(remove_word "$clean_name" "NO")
        clean_name=$(remove_word "$clean_name" "NOR")
        clean_name=$(remove_word "$clean_name" "NORWAY")
        clean_name=$(remove_word "$clean_name" "NORWEGIAN")
    elif word_exists "$clean_name" "DK" || word_exists "$clean_name" "DNK" || word_exists "$clean_name" "DENMARK" || word_exists "$clean_name" "DANISH"; then
        detected_country="DNK"
        clean_name=$(remove_word "$clean_name" "DK")
        clean_name=$(remove_word "$clean_name" "DNK")
        clean_name=$(remove_word "$clean_name" "DENMARK")
        clean_name=$(remove_word "$clean_name" "DANISH")
    elif word_exists "$clean_name" "FI" || word_exists "$clean_name" "FIN" || word_exists "$clean_name" "FINLAND" || word_exists "$clean_name" "FINNISH"; then
        detected_country="FIN"
        clean_name=$(remove_word "$clean_name" "FI")
        clean_name=$(remove_word "$clean_name" "FIN")
        clean_name=$(remove_word "$clean_name" "FINLAND")
        clean_name=$(remove_word "$clean_name" "FINNISH")
    
    # Major Asian markets
    elif word_exists "$clean_name" "JP" || word_exists "$clean_name" "JPN" || word_exists "$clean_name" "JAPAN" || word_exists "$clean_name" "JAPANESE"; then
        detected_country="JPN"
        clean_name=$(remove_word "$clean_name" "JP")
        clean_name=$(remove_word "$clean_name" "JPN")
        clean_name=$(remove_word "$clean_name" "JAPAN")
        clean_name=$(remove_word "$clean_name" "JAPANESE")
    elif word_exists "$clean_name" "KR" || word_exists "$clean_name" "KOR" || word_exists "$clean_name" "KOREA" || word_exists "$clean_name" "KOREAN"; then
        detected_country="KOR"
        clean_name=$(remove_word "$clean_name" "KR")
        clean_name=$(remove_word "$clean_name" "KOR")
        clean_name=$(remove_word "$clean_name" "KOREA")
        clean_name=$(remove_word "$clean_name" "KOREAN")
    elif word_exists "$clean_name" "CN" || word_exists "$clean_name" "CHN" || word_exists "$clean_name" "CHINA" || word_exists "$clean_name" "CHINESE"; then
        detected_country="CHN"
        clean_name=$(remove_word "$clean_name" "CN")
        clean_name=$(remove_word "$clean_name" "CHN")
        clean_name=$(remove_word "$clean_name" "CHINA")
        clean_name=$(remove_word "$clean_name" "CHINESE")
    elif word_exists "$clean_name" "IN" || word_exists "$clean_name" "IND" || word_exists "$clean_name" "INDIA" || word_exists "$clean_name" "INDIAN"; then
        detected_country="IND"
        clean_name=$(remove_word "$clean_name" "IN")
        clean_name=$(remove_word "$clean_name" "IND")
        clean_name=$(remove_word "$clean_name" "INDIA")
        clean_name=$(remove_word "$clean_name" "INDIAN")
    
    # Latin American markets
    elif word_exists "$clean_name" "BR" || word_exists "$clean_name" "BRA" || word_exists "$clean_name" "BRAZIL" || word_exists "$clean_name" "BRAZILIAN"; then
        detected_country="BRA"
        clean_name=$(remove_word "$clean_name" "BR")
        clean_name=$(remove_word "$clean_name" "BRA")
        clean_name=$(remove_word "$clean_name" "BRAZIL")
        clean_name=$(remove_word "$clean_name" "BRAZILIAN")
    elif word_exists "$clean_name" "MX" || word_exists "$clean_name" "MEX" || word_exists "$clean_name" "MEXICO" || word_exists "$clean_name" "MEXICAN"; then
        detected_country="MEX"
        clean_name=$(remove_word "$clean_name" "MX")
        clean_name=$(remove_word "$clean_name" "MEX")
        clean_name=$(remove_word "$clean_name" "MEXICO")
        clean_name=$(remove_word "$clean_name" "MEXICAN")
    elif word_exists "$clean_name" "AR" || word_exists "$clean_name" "ARG" || word_exists "$clean_name" "ARGENTINA" || word_exists "$clean_name" "ARGENTINIAN"; then
        detected_country="ARG"
        clean_name=$(remove_word "$clean_name" "AR")
        clean_name=$(remove_word "$clean_name" "ARG")
        clean_name=$(remove_word "$clean_name" "ARGENTINA")
        clean_name=$(remove_word "$clean_name" "ARGENTINIAN")

    # Major Arabic-speaking markets
    elif word_exists "$clean_name" "EG" || word_exists "$clean_name" "EGY" || word_exists "$clean_name" "EGYPT" || word_exists "$clean_name" "EGYPTIAN"; then
        detected_country="EGY"
        clean_name=$(remove_word "$clean_name" "EG")
        clean_name=$(remove_word "$clean_name" "EGY")
        clean_name=$(remove_word "$clean_name" "EGYPT")
        clean_name=$(remove_word "$clean_name" "EGYPTIAN")
    elif word_exists "$clean_name" "SA" || word_exists "$clean_name" "SAU" || word_exists "$clean_name" "SAUDI" || word_exists "$clean_name" "KSA"; then
        detected_country="SAU"
        clean_name=$(remove_word "$clean_name" "SA")
        clean_name=$(remove_word "$clean_name" "SAU")
        clean_name=$(remove_word "$clean_name" "SAUDI")
        clean_name=$(remove_word "$clean_name" "KSA")
    elif word_exists "$clean_name" "AE" || word_exists "$clean_name" "ARE" || word_exists "$clean_name" "UAE" || word_exists "$clean_name" "EMIRATES"; then
        detected_country="ARE"
        clean_name=$(remove_word "$clean_name" "AE")
        clean_name=$(remove_word "$clean_name" "ARE")
        clean_name=$(remove_word "$clean_name" "UAE")
        clean_name=$(remove_word "$clean_name" "EMIRATES")
    elif word_exists "$clean_name" "IQ" || word_exists "$clean_name" "IRQ" || word_exists "$clean_name" "IRAQ" || word_exists "$clean_name" "IRAQI"; then
        detected_country="IRQ"
        clean_name=$(remove_word "$clean_name" "IQ")
        clean_name=$(remove_word "$clean_name" "IRQ")
        clean_name=$(remove_word "$clean_name" "IRAQ")
        clean_name=$(remove_word "$clean_name" "IRAQI")
    elif word_exists "$clean_name" "MA" || word_exists "$clean_name" "MAR" || word_exists "$clean_name" "MOROCCO" || word_exists "$clean_name" "MOROCCAN"; then
        detected_country="MAR"
        clean_name=$(remove_word "$clean_name" "MA")
        clean_name=$(remove_word "$clean_name" "MAR")
        clean_name=$(remove_word "$clean_name" "MOROCCO")
        clean_name=$(remove_word "$clean_name" "MOROCCAN")
    elif word_exists "$clean_name" "DZ" || word_exists "$clean_name" "DZA" || word_exists "$clean_name" "ALGERIA" || word_exists "$clean_name" "ALGERIAN"; then
        detected_country="DZA"
        clean_name=$(remove_word "$clean_name" "DZ")
        clean_name=$(remove_word "$clean_name" "DZA")
        clean_name=$(remove_word "$clean_name" "ALGERIA")
        clean_name=$(remove_word "$clean_name" "ALGERIAN")
    elif word_exists "$clean_name" "SY" || word_exists "$clean_name" "SYR" || word_exists "$clean_name" "SYRIA" || word_exists "$clean_name" "SYRIAN"; then
        detected_country="SYR"
        clean_name=$(remove_word "$clean_name" "SY")
        clean_name=$(remove_word "$clean_name" "SYR")
        clean_name=$(remove_word "$clean_name" "SYRIA")
        clean_name=$(remove_word "$clean_name" "SYRIAN")
    elif word_exists "$clean_name" "LB" || word_exists "$clean_name" "LBN" || word_exists "$clean_name" "LEBANON" || word_exists "$clean_name" "LEBANESE"; then
        detected_country="LBN"
        clean_name=$(remove_word "$clean_name" "LB")
        clean_name=$(remove_word "$clean_name" "LBN")
        clean_name=$(remove_word "$clean_name" "LEBANON")
        clean_name=$(remove_word "$clean_name" "LEBANESE")
    elif word_exists "$clean_name" "JO" || word_exists "$clean_name" "JOR" || word_exists "$clean_name" "JORDAN" || word_exists "$clean_name" "JORDANIAN"; then
        detected_country="JOR"
        clean_name=$(remove_word "$clean_name" "JO")
        clean_name=$(remove_word "$clean_name" "JOR")
        clean_name=$(remove_word "$clean_name" "JORDAN")
        clean_name=$(remove_word "$clean_name" "JORDANIAN")
    elif word_exists "$clean_name" "TN" || word_exists "$clean_name" "TUN" || word_exists "$clean_name" "TUNISIA" || word_exists "$clean_name" "TUNISIAN"; then
        detected_country="TUN"
        clean_name=$(remove_word "$clean_name" "TN")
        clean_name=$(remove_word "$clean_name" "TUN")
        clean_name=$(remove_word "$clean_name" "TUNISIA")
        clean_name=$(remove_word "$clean_name" "TUNISIAN")
    
    # Additional major markets
    elif word_exists "$clean_name" "RU" || word_exists "$clean_name" "RUS" || word_exists "$clean_name" "RUSSIA" || word_exists "$clean_name" "RUSSIAN"; then
        detected_country="RUS"
        clean_name=$(remove_word "$clean_name" "RU")
        clean_name=$(remove_word "$clean_name" "RUS")
        clean_name=$(remove_word "$clean_name" "RUSSIA")
        clean_name=$(remove_word "$clean_name" "RUSSIAN")
    elif word_exists "$clean_name" "PL" || word_exists "$clean_name" "POL" || word_exists "$clean_name" "POLAND" || word_exists "$clean_name" "POLISH"; then
        detected_country="POL"
        clean_name=$(remove_word "$clean_name" "PL")
        clean_name=$(remove_word "$clean_name" "POL")
        clean_name=$(remove_word "$clean_name" "POLAND")
        clean_name=$(remove_word "$clean_name" "POLISH")
    fi

    # Step 2: Resolution detection patterns (unchanged, but no confidence scoring)
    if word_exists "$clean_name" "4K" || word_exists "$clean_name" "UHD" || word_exists "$clean_name" "UHDTV" || [[ "$clean_name" =~ Ultra[[:space:]]*HD ]]; then
        detected_resolution="UHDTV"
        clean_name=$(remove_word "$clean_name" "4K")
        clean_name=$(remove_word "$clean_name" "UHD") 
        clean_name=$(remove_word "$clean_name" "UHDTV")
        clean_name=$(echo "$clean_name" | sed -E 's/Ultra[[:space:]]*HD/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    elif word_exists "$clean_name" "FHD" || [[ "$clean_name" =~ (^|[[:space:]])(1080[ip]?|720[ip]?)([[:space:]]|$) ]]; then
        detected_resolution="HDTV"
        clean_name=$(remove_word "$clean_name" "FHD")
        clean_name=$(echo "$clean_name" | sed -E 's/(^|[[:space:]])(1080[ip]?|720[ip]?)([[:space:]]|$)/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    elif word_exists "$clean_name" "HD" && ! [[ "$clean_name" =~ [0-9] ]]; then
        detected_resolution="HDTV"
        clean_name=$(remove_word "$clean_name" "HD")
    elif word_exists "$clean_name" "SD" || [[ "$clean_name" =~ (^|[[:space:]])480[ip]?([[:space:]]|$) ]]; then
        detected_resolution="SDTV"
        clean_name=$(remove_word "$clean_name" "SD")
        clean_name=$(echo "$clean_name" | sed -E 's/(^|[[:space:]])480[ip]?([[:space:]]|$)/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    fi
    
    # Step 3: Final cleanup (renumbered from Step 4)
    clean_name=$(perform_general_cleanup "$clean_name")
    
    # SIMPLIFIED: Return format - only 3 fields now
    echo "$clean_name|$detected_country|$detected_resolution"
}

# ============================================================================
# SPECIAL CHARACTER SEPARATOR HANDLING
# ============================================================================

handle_special_separators() {
    local input_name="$1"
    local clean_name="$input_name"
    
    # Replace special character separators with spaces
    # This must happen BEFORE any other parsing to ensure proper separation of tokens
    
    # Check if we have separators to avoid unnecessary processing
    if [[ "$clean_name" =~ [\|★◉:►▶→»≫—–=〉〈⟩⟨◆♦◊⬥●•] ]]; then
        # Replace separators with spaces - handle each type
        clean_name=$(echo "$clean_name" | sed 's/[\|★◉:►▶→»≫—–=〉〈⟩⟨◆♦◊⬥●•]/ /g')
        
        # Normalize spacing after separator replacement
        clean_name=$(echo "$clean_name" | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    fi
    
    echo "$clean_name"
}

# ============================================================================
# GENERAL CLEANUP FUNCTIONS
# ============================================================================

perform_general_cleanup() {
    local input_name="$1"
    local clean_name="$input_name"
    
    # Remove common prefixes and suffixes
    clean_name=$(remove_common_prefixes "$clean_name")
    clean_name=$(remove_common_suffixes "$clean_name")
    clean_name=$(remove_remaining_special_characters "$clean_name")
    clean_name=$(normalize_spacing "$clean_name")
    clean_name=$(remove_generic_terms "$clean_name")
    
    echo "$clean_name"
}

remove_common_prefixes() {
    local name="$1"
    
    # Remove common channel prefixes - use word boundaries
    name=$(echo "$name" | sed -E 's/^(CHANNEL|CH|NETWORK|NET|TV|TELEVISION|DIGITAL|CABLE|SATELLITE|STREAM|LIVE|24\/7|24-7)[[:space:]]+//gi')
    
    echo "$name"
}

remove_common_suffixes() {
    local name="$1"
    
    # Remove common channel suffixes - use word boundaries
    name=$(echo "$name" | sed -E 's/[[:space:]]+(CHANNEL|CH|NETWORK|NET|TV|TELEVISION|DIGITAL|LIVE|STREAM|PLUS|\+|24\/7|24-7)$//gi')
    
    echo "$name"
}

remove_remaining_special_characters() {
    local name="$1"
    
    # Remove or replace remaining special characters (after separator handling)
    # Replace underscores and hyphens with spaces
    name=$(echo "$name" | tr '_-' '  ')
    
    # Remove brackets and parentheses
    name=$(echo "$name" | tr -d '()[]{}<>')
    
    # Remove remaining special symbols
    name=$(echo "$name" | tr -d '#@$%^&*')
    
    # Remove trailing punctuation
    name=$(echo "$name" | sed 's/[[:punct:]]*$//')
    
    echo "$name"
}

normalize_spacing() {
    local name="$1"
    
    # Normalize whitespace
    name=$(echo "$name" | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    echo "$name"
}

remove_generic_terms() {
    local name="$1"
    
    # Remove very generic terms that don't help with matching
    name=$(echo "$name" | sed -E 's/\b(THE|A|AN|AND|OR|OF|IN|ON|AT|TO|FOR|WITH|OFFICIAL|ORIGINAL|PREMIUM|EXCLUSIVE|ONLINE|DIGITAL|STREAMING|BROADCAST)\b/ /gi')
    
    # Final spacing cleanup after term removal
    name=$(normalize_spacing "$name")
    
    echo "$name"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Extract call sign patterns from channel names
extract_call_sign() {
    local channel_name="$1"
    local call_sign=""
    
    # Common call sign patterns
    if [[ "$channel_name" =~ \b([KWCN][A-Z]{2,4})\b ]]; then
        call_sign="${BASH_REMATCH[1]}"
    elif [[ "$channel_name" =~ \b([A-Z]{3,5})[[:space:]]*TV\b ]]; then
        call_sign="${BASH_REMATCH[1]}"
    elif [[ "$channel_name" =~ \b([A-Z]{2,4})[[:space:]]*[0-9]+\b ]]; then
        call_sign="${BASH_REMATCH[1]}"
    fi
    
    echo "$call_sign"
}

# Get parsing confidence level description
get_confidence_description() {
    local confidence="$1"
    
    if [[ $confidence -ge 50 ]]; then
        echo "High"
    elif [[ $confidence -ge 30 ]]; then
        echo "Medium"
    elif [[ $confidence -ge 15 ]]; then
        echo "Low"
    else
        echo "Minimal"
    fi
}

# Test channel parsing with multiple examples including special separators
test_channel_parsing() {
    # Define test categories with their channels
    local -A test_categories=(
        ["Basic Country Detection"]="CNN USA HD|BBC One UK|CBC News CA|Channel 7 AU|ZDF DE HD|TF1 France|RAI 1 Italy|TVE Spain"
        
        ["Special Separators"]="ESPN★USA★4K|Sky Sports|UK|HD|France 24◉French|NHK→Japan→HD|Discovery»Canada»FHD|MTV:USA:1080p|Comedy Central▶UK▶HD"
        
        ["Resolution Edge Cases"]="UK: 4 MORE|Channel 5 HD USA|4K Nature Documentary|ESPN 1080p Sports|News 720p Live|Classic Movies SD|Ultra HD Wildlife|FHD Sports Center"
        
        ["Arabic Markets"]="Al Jazeera EG|MBC 1 Saudi Arabia|Dubai One UAE HD|LBC Lebanon|Jordan TV JOR|Al Arabiya UAE|Nile TV Egypt|Syria TV SYR"
        
        ["Nordic Countries"]="SVT1 Sweden|NRK1 Norway|DR1 Denmark|YLE TV1 Finland|TV2 Norge|SVT HD Swedish|Finnish Broadcasting FI"
        
        ["Asian Markets"]="NHK Japan HD|KBS Korea|CCTV China|Star Plus India|ABS-CBN Philippines|Thai TV Thailand|Vietnam VTV"
        
        ["Latin American"]="Globo Brazil HD|Televisa Mexico|Canal 13 Argentina|TVN Chile|Caracol Colombia|Canal+ Peru|TV Azteca MX"
        
        ["Complex Scenarios"]="UK: BBC 1 (North West) HD|US: HBO★Premium★4K★Sports|Discovery Channel Canada FHD|Comedy Central★USA★1080p|National Geographic 4K UHD"
        
        ["Edge Cases & Bugs"]="MORE 4 UK|5 USA Network|HD Theater|4K Sports Channel|SD Movies Classic|BONUS TV|TRUST Network|MUSIC USA"
        
        ["No Country/Resolution"]="Discovery Channel|Comedy Central|National Geographic|History Channel|Animal Planet|Food Network|HGTV"
    )
    
    # Define category order for consistent pagination
    local category_order=(
        "Basic Country Detection"
        "Special Separators" 
        "Resolution Edge Cases"
        "Arabic Markets"
        "Nordic Countries"
        "Asian Markets"
        "Latin American"
        "Complex Scenarios"
        "Edge Cases & Bugs"
        "No Country/Resolution"
    )
    
    echo -e "${BOLD}${CYAN}=== Channel Parsing Comprehensive Test Suite ===${RESET}"
    echo -e "${YELLOW}Testing parsing logic across multiple categories and edge cases${RESET}"
    echo -e "${CYAN}Press Enter to continue through each category...${RESET}"
    echo
    read -p "" dummy_var
    
    local category_num=1
    local total_categories=${#category_order[@]}
    
    for category in "${category_order[@]}"; do
        clear
        echo -e "${BOLD}${BLUE}=== Category $category_num of $total_categories: $category ===${RESET}"
        echo
        
        # Show category description
        case "$category" in
            "Basic Country Detection")
                echo -e "${CYAN}Tests fundamental country detection across major TV markets${RESET}"
                echo -e "${CYAN}Validates: USA, UK, Canada, Australia, Germany, France, Italy, Spain${RESET}"
                ;;
            "Special Separators")
                echo -e "${CYAN}Tests handling of special characters used as separators in channel names${RESET}"
                echo -e "${CYAN}Validates: ★ ◉ → » : ▶ and other Unicode separators${RESET}"
                ;;
            "Resolution Edge Cases")
                echo -e "${CYAN}Tests resolution detection edge cases and false positive prevention${RESET}"
                echo -e "${CYAN}Validates: Numbers vs quality indicators, specific patterns${RESET}"
                ;;
            "Arabic Markets")
                echo -e "${CYAN}Tests Arabic-speaking market detection${RESET}"
                echo -e "${CYAN}Validates: Egypt, Saudi Arabia, UAE, Lebanon, Jordan, Syria${RESET}"
                ;;
            "Nordic Countries")
                echo -e "${CYAN}Tests Nordic/Scandinavian market detection${RESET}"
                echo -e "${CYAN}Validates: Sweden, Norway, Denmark, Finland${RESET}"
                ;;
            "Asian Markets")
                echo -e "${CYAN}Tests major Asian television markets${RESET}"
                echo -e "${CYAN}Validates: Japan, Korea, China, India, Philippines, Thailand, Vietnam${RESET}"
                ;;
            "Latin American")
                echo -e "${CYAN}Tests Latin American market detection${RESET}"
                echo -e "${CYAN}Validates: Brazil, Mexico, Argentina, Chile, Colombia, Peru${RESET}"
                ;;
            "Complex Scenarios")
                echo -e "${CYAN}Tests real-world complex channel name patterns${RESET}"
                echo -e "${CYAN}Validates: Multiple separators, parentheses, regional indicators${RESET}"
                ;;
            "Edge Cases & Bugs")
                echo -e "${CYAN}Tests known problematic patterns and regression prevention${RESET}"
                echo -e "${CYAN}Validates: False positive prevention, number handling${RESET}"
                ;;
            "No Country/Resolution")
                echo -e "${CYAN}Tests channels that should NOT trigger country/resolution detection${RESET}"
                echo -e "${CYAN}Validates: Generic network names without geographic indicators${RESET}"
                ;;
        esac
        echo
        echo -e "${BOLD}${YELLOW}Test Results:${RESET}"
        echo
        
        # Parse and display results for this category
        IFS='|' read -ra channels <<< "${test_categories[$category]}"
        local channel_num=1
        
        for channel in "${channels[@]}"; do
            echo -e "${BOLD}[$channel_num] Testing:${RESET} '$channel'"
            
            local result=$(parse_channel_name "$channel")
            IFS='|' read -r clean_name country resolution <<< "$result"
            
            # Format results with color coding
            echo -e "    ${CYAN}Clean:${RESET} '$clean_name'"
            
            if [[ -n "$country" ]]; then
                echo -e "    ${GREEN}Country:${RESET} $country"
            else
                echo -e "    ${YELLOW}Country:${RESET} (none detected)"
            fi
            
            if [[ -n "$resolution" ]]; then
                echo -e "    ${GREEN}Resolution:${RESET} $resolution"
            else
                echo -e "    ${YELLOW}Resolution:${RESET} (none detected)"
            fi
            
            # Show raw result for debugging
            echo -e "    ${GRAY}Raw:${RESET} '$result'"
            echo
            
            ((channel_num++))
        done
        
        # Navigation controls
        echo -e "${BOLD}${CYAN}Navigation:${RESET}"
        if [[ $category_num -lt $total_categories ]]; then
            echo -e "${GREEN}Press Enter${RESET} - Next category ($((category_num + 1))/${total_categories})"
        else
            echo -e "${GREEN}Press Enter${RESET} - Complete test suite"
        fi
        echo -e "${YELLOW}Type 'q'${RESET} - Quit test suite"
        echo
        
        read -p "Choice: " nav_choice
        
        case "$nav_choice" in
            q|Q)
                echo -e "${YELLOW}Test suite cancelled${RESET}"
                return 0
                ;;
            *)
                # Continue to next category
                ;;
        esac
        
        ((category_num++))
    done
    
    # Final summary
    clear
    echo -e "${BOLD}${GREEN}=== Test Suite Complete ===${RESET}"
    echo
    echo -e "${CYAN}All $total_categories categories tested successfully!${RESET}"
    echo
    echo -e "${BOLD}Categories Covered:${RESET}"
    for i in "${!category_order[@]}"; do
        echo -e "  $((i+1)). ${category_order[$i]}"
    done
    echo
    echo -e "${YELLOW}Review results above to verify parsing accuracy${RESET}"
    echo -e "${CYAN}Look for any unexpected country/resolution detections${RESET}"
    echo
}

# Add GRAY color if not already defined (add to color definitions section)
GRAY="${ESC}[90m"

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Functions are automatically available when this module is sourced
# No explicit exports needed - sourcing makes all functions available in the calling script

# Optional: Log successful module load
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Module was sourced, not executed directly
    true  # Functions are now available
fi
