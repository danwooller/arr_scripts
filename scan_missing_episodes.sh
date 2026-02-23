#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# Ensure dependencies
check_dependencies "curl" "jq" "sed"

# Target directory
TARGET_DIR="${1:-/mnt/media/TV}"

# --- Manual Mappings ---
declare -A MANUAL_MAPS
# If 'National Theatre at Home' isn't on Seerr, you can't create an issue.
# If you find it later, put the ID here.
MANUAL_MAPS["National Theatre at Home"]="" 

report_missing_seerr() {
    local series_name="$1"
    local missing_episodes="$2"
    local new_msg="Missing Episode(s): $missing_episodes"
    local media_id=""

    # 1. Get Media ID
    if [[ -n "${MANUAL_MAPS[$series_name]}" ]]; then
        media_id="${MANUAL_MAPS[$series_name]}"
    else
        local search_term=$(echo "$series_name" | sed -E 's/\([0-9]{4}\)//g; s/[._]/ /g')
        local encoded_query=$(echo "$search_term" | jq -Rr @uri)
        local search_results=$(curl -s -X GET "$SEERR_URL/api/v1/search?query=$encoded_query" \
            -H "X-Api-Key: $SEERR_API_KEY")
        media_id=$(echo "$search_results" | jq -r '.results[] | select(.mediaType == "tv").mediaInfo.id // empty' | head -n 1)
    fi

    if [ -z "$media_id" ] || [ "$media_id" == "null" ]; then
        log "⚠️  Skipping $series_name: Not found in Seerr database (Check Sonarr instead)."
        return 1
    fi

    # 2. Advanced Deduplication (Normalize all whitespace)
    local existing_issues=$(curl -s -X GET "$SEERR_URL/api/v1/issue?take=50&filter=open" \
        -H "X-Api-Key: $SEERR_API_KEY")

    local existing_data=$(echo "$existing_issues" | jq -r --arg mid "$media_id" \
        '.results[] | select(.media.id == ($mid|tonumber) and .issueType == 1) | "\(.id)|\(.message)"' | head -n 1)

    if [ -n "$existing_data" ]; then
        local old_issue_id=$(echo "$existing_data" | cut -d'|' -f1)
        local raw_old_msg=$(echo "$existing_data" | cut -d'|' -f2)

        # Remove ALL whitespace from both strings for a 100% "data-only" comparison
        local norm_old=$(echo "$raw_old_msg" | tr -d '[:space:]')
        local norm_new=$(echo "$new_msg" | tr -d '[:space:]')

        if [ "$norm_old" == "$norm_new" ]; then
            log "✅ Issue already exists for $series_name. Skipping."
            return 0
        else
            log "🔄 Change detected for $series_name. Cleaning up #$old_issue_id."
            curl -s -X DELETE "$SEERR_URL/api/v1/issue/$old_issue_id" -H "X-Api-Key: $SEERR_API_KEY"
        fi
    fi

    # 3. Create Issue
    local json_payload=$(jq -n --arg mt "1" --arg msg "$new_msg" --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')

    curl -s -o /dev/null -X POST "$SEERR_URL/api/v1/issue" \
        -H "X-Api-Key: $SEERR_API_KEY" -H "Content-Type: application/json" -d "$json_payload"
    
    log "🚀 Seerr Issue created for $series_name: $missing_episodes"
}

log "Starting scan in $TARGET_DIR..."

find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d | while read -r series_path; do
    series_name=$(basename "$series_path")
    
    mapfile -t ep_list < <(find "$series_path" -type f -not -path "*Specials*" -not -path "*Season 00*" \
        -name "*[0-9]x[0-9]*" | grep -oE "[0-9]+x[0-9]+(-[0-9]+)?" | sort -V | uniq)

    if [ ${#ep_list[@]} -lt 2 ]; then continue; fi

    missing_in_series=""
    prev_s=-1
    prev_e=-1

    for ep in "${ep_list[@]}"; do
        curr_s=$(echo "$ep" | cut -d'x' -f1)
        range=$(echo "$ep" | cut -d'x' -f2)
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

    [[ -n "$missing_in_series" ]] && report_missing_seerr "$series_name" "${missing_in_series% }"
done

log "✅ Scan complete."
