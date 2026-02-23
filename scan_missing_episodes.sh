#!/bin/bash

# --- Load Shared Functions ---
# Assumes SEERR_URL and SEERR_API_KEY are defined here or exported in environment
source "/usr/local/bin/common_functions.sh"

# Ensure dependencies are available
check_dependencies "curl" "jq" "sed"

# Target directory: Default to /mnt/media/TV but allow override via first argument
TARGET_DIR="${1:-/mnt/media/TV}"

if [ ! -d "$TARGET_DIR" ]; then
    log "❌ $TARGET_DIR does not exist."
    exit 1
fi

# --- Function to Report/Sync with Seerr ---
report_missing_seerr() {
    local series_name="$1"
    local missing_episodes="$2"
    local new_msg="Missing Episode(s): $missing_episodes"
    
    # 1. Search for Series ID in Seerr
    local search_term=$(echo "$series_name" | sed -E 's/\([0-9]{4}\)//g; s/[._]/ /g')
    local encoded_query=$(echo "$search_term" | jq -Rr @uri)
    local search_results=$(curl -s -X GET "$SEERR_URL/api/v1/search?query=$encoded_query" \
        -H "X-Api-Key: $SEERR_API_KEY")
    
    local media_id=$(echo "$search_results" | jq -r '.results[] | select(.mediaType == "tv").mediaInfo.id // empty' | head -n 1)

    if [ -z "$media_id" ] || [ "$media_id" == "null" ]; then
        log "❌ Could not link $series_name to Seerr."
        return 1
    fi

    # 2. Check for existing Open issues to deduplicate
    local existing_issues=$(curl -s -X GET "$SEERR_URL/api/v1/issue?take=50&filter=open" \
        -H "X-Api-Key: $SEERR_API_KEY")

    # Extract ID and Message for this media and Type 1 (Video Issue)
    local existing_data=$(echo "$existing_issues" | jq -r --arg mid "$media_id" \
        '.results[] | select(.media.id == ($mid|tonumber) and .issueType == 1) | "\(.id)|\(.message)"' | head -n 1)

    if [ -n "$existing_data" ]; then
        local old_issue_id=$(echo "$existing_data" | cut -d'|' -f1)
        # Trim leading/trailing whitespace from the old message
        local old_msg=$(echo "$existing_data" | cut -d'|' -f2 | xargs)
        # Trim leading/trailing whitespace from the new message
        local clean_new_msg=$(echo "$new_msg" | xargs)

        if [ "$old_msg" == "$clean_new_msg" ]; then
            log "SKIP: Identical open issue already exists for $series_name."
            return 0
        else
            log "CLEANUP: Removing outdated issue #$old_issue_id for $series_name."
            log "DEBUG: Old: [$old_msg] | New: [$clean_new_msg]" # Temporary debug line
            curl -s -X DELETE "$SEERR_URL/api/v1/issue/$old_issue_id" -H "X-Api-Key: $SEERR_API_KEY"
        fi
    fi

    # 3. Create the New/Updated Issue
    local json_payload=$(jq -n \
        --arg mt "1" \
        --arg msg "$new_msg" \
        --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')

    local response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SEERR_URL/api/v1/issue" \
        -H "X-Api-Key: $SEERR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload")
    
    if [[ "$response" =~ ^20[0-9]$ ]]; then
        log "Seerr Issue created for $series_name: $missing_episodes"
    else
        log "❌ Seerr API failed with HTTP $response for $series_name"
    fi
}

log "Starting Scan in $TARGET_DIR..."

# Iterate through Series folders
find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d | while read -r series_path; do
    series_name=$(basename "$series_path")
    
    # Capture 1x01 or 1x01-02 patterns, excluding Specials/Season 00
    mapfile -t ep_list < <(find "$series_path" -type f -not -path "*Specials*" -not -path "*Season 00*" \
        -name "*[0-9]x[0-9]*" | grep -oE "[0-9]+x[0-9]+(-[0-9]+)?" | sort -V | uniq)

    # Need at least 2 episodes to determine a gap
    if [ ${#ep_list[@]} -lt 2 ]; then continue; fi

    missing_in_series=""
    prev_s=-1
    prev_e=-1

    for ep in "${ep_list[@]}"; do
        curr_s=$(echo "$ep" | cut -d'x' -f1)
        range=$(echo "$ep" | cut -d'x' -f2)
        
        # Parse range (handles 01 as 1-1, and 01-02 as 1-2)
        start_e=$(echo "$range" | cut -d'-' -f1 | sed 's/^0//')
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
        prev_e=$end_e
    done

    if [ -n "$missing_in_series" ]; then
        # Trim trailing space and report
        report_missing_seerr "$series_name" "${missing_in_series% }"
    fi
done

log "✅ Scan complete."
