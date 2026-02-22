#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# Ensure dependencies
check_dependencies "curl" "jq" "sed"

# Use provided argument or default TV path
TARGET_DIR="${1:-/mnt/media/TV}"

# --- Function to Report to Seerr ---
report_missing_seerr() {
    local series_name="$1"
    local missing_episodes="$2"
    
    local search_term=$(echo "$series_name" | sed -E 's/\([0-9]{4}\)//g; s/[._]/ /g')
    local encoded_query=$(echo "$search_term" | jq -Rr @uri)
    
    local search_results=$(curl -s -X GET "$SEERR_URL/api/v1/search?query=$encoded_query" \
        -H "X-Api-Key: $SEERR_API_KEY")
    
    local media_id=$(echo "$search_results" | jq -r '.results[] | select(.mediaType == "tv").mediaInfo.id // empty' | head -n 1)

    if [ -z "$media_id" ] || [ "$media_id" == "null" ]; then
        log "WARN: Could not link $series_name to Seerr."
        return 1
    fi

    local json_payload=$(jq -n \
        --arg mt "1" \
        --arg msg "Missing Episode Gap: $missing_episodes" \
        --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')

    curl -s -o /dev/null -X POST "$SEERR_URL/api/v1/issue" \
        -H "X-Api-Key: $SEERR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload"
    
    log "Seerr Issue created for $series_name: Missing $missing_episodes"
}

log "Starting gap scan in $TARGET_DIR..."

find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d | while read -r series_path; do
    series_name=$(basename "$series_path")
    
    # 1. Capture patterns like 1x01 or 1x01-02
    mapfile -t ep_list < <(find "$series_path" -type f -not -path "*Specials*" -not -path "*Season 00*" \
        -name "*[0-9]x[0-9]*" | grep -oE "[0-9]+x[0-9]+(-[0-9]+)?" | sort -V | uniq)

    if [ ${#ep_list[@]} -lt 2 ]; then continue; fi

    missing_in_series=""
    prev_s=-1
    prev_e=-1

    for ep in "${ep_list[@]}"; do
        # Extract Season
        curr_s=$(echo "$ep" | cut -d'x' -f1)
        
        # Extract Episode Range
        # If ep is "1x01-02", range is "01-02". If "1x01", range is "01".
        range=$(echo "$ep" | cut -d'x' -f2)
        
        # Start of the range (e.g., 01)
        start_e=$(echo "$range" | cut -d'-' -f1 | sed 's/^0//')
        
        # End of the range (e.g., 02 or 01)
        end_e=$(echo "$range" | cut -d'-' -f2 | sed 's/^0//')

        if [ "$curr_s" -eq "$prev_s" ]; then
            expected=$((prev_e + 1))
            if [ "$start_e" -gt "$expected" ]; then
                for ((i=expected; i<start_e; i++)); do
                    missing_in_series+="${curr_s}x$(printf "%02d" $i) "
                done
            fi
        fi
        
        prev_s=$curr_s
        # Crucial: set previous episode to the END of the range
        prev_e=$end_e
    done

    if [ -n "$missing_in_series" ]; then
        report_missing_seerr "$series_name" "$missing_in_series"
    fi
done

log "Gap scan complete."
