#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# Ensure dependencies
check_dependencies "curl" "jq" "sed"

# Target directory
TARGET_DIR="${1:-/mnt/media/TV}"

# --- Manual Mappings ---
# Add problematic shows here: ["FolderName"]="SeerrMediaID"
declare -A MANUAL_MAPS
MANUAL_MAPS["National Theatre at Home"]="12345" # <-- Replace 12345 with the actual Seerr Media ID

report_missing_seerr() {
    local series_name="$1"
    local missing_episodes="$2"
    local new_msg="Missing Episode(s): $missing_episodes"
    local media_id=""

    # 1. Check Manual Mapping first, then Search
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
        log "❌ Could not link $series_name to Seerr."
        return 1
    fi

    # 2. Deduplication check with whitespace trimming
    local existing_issues=$(curl -s -X GET "$SEERR_URL/api/v1/issue?take=50&filter=open" \
        -H "X-Api-Key: $SEERR_API_KEY")

    local existing_data=$(echo "$existing_issues" | jq -r --arg mid "$media_id" \
        '.results[] | select(.media.id == ($mid|tonumber) and .issueType == 1) | "\(.id)|\(.message)"' | head -n 1)

    if [ -n "$existing_data" ]; then
        local old_issue_id=$(echo "$existing_data" | cut -d'|' -f1)
        # Trim whitespace using xargs for a clean comparison
        local old_msg=$(echo "$existing_data" | cut -d'|' -f2 | xargs)
        local clean_new_msg=$(echo "$new_msg" | xargs)

        if [ "$old_msg" == "$clean_new_msg" ]; then
            log "✅ Identical open issue already exists for $series_name. Skipping."
            return 0
        else
            log "🔄 Gap changed for $series_name. Cleaning up outdated issue #$old_issue_id."
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

log "Starting Gap Scan in $TARGET_DIR..."

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
