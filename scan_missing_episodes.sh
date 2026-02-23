#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# Ensure dependencies
check_dependencies "curl" "jq" "sed" "grep"

# Target directory
TARGET_DIR="${1:-/mnt/media/TV}"

# --- Configuration ---
# Folders to skip entirely (Exact folder names)
EXCLUDE_DIRS=("National Theatre at Home" "National Theatre Live")

# Manual Mappings (Folder Name -> Seerr Media ID)
declare -A MANUAL_MAPS
MANUAL_MAPS["Example Show"]="12345"

report_missing_seerr() {
    local series_name="$1"
    local missing_episodes="$2"
    local new_msg="Missing Episode(s): $missing_episodes"
    local media_id=""

    # 1. Get Seerr Media ID
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
        log "⚠️  Skipping $series_name: Not found in Seerr database."
        return 1
    fi

    # 2. Seerr Deduplication (Only proceed if no issue exists)
    local existing_issues=$(curl -s -X GET "$SEERR_URL/api/v1/issue?take=100&filter=open" \
        -H "X-Api-Key: $SEERR_API_KEY")

    local exists=$(echo "$existing_issues" | jq -r --arg mid "$media_id" \
        '.results[] | select(.media.id == ($mid|tonumber) and .issueType == 1) | .id' | head -n 1)

    if [ -n "$exists" ]; then
        log "✅ Issue #$exists already exists for $series_name. Skipping."
        return 0
    fi

    # 3. Create Seerr Issue
    local json_payload=$(jq -n --arg mt "1" --arg msg "$new_msg" --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')

    curl -s -o /dev/null -X POST "$SEERR_URL/api/v1/issue" \
        -H "X-Api-Key: $SEERR_API_KEY" -H "Content-Type: application/json" -d "$json_payload"
    
    log "🚀 Seerr Issue created for $series_name."

    # --- 4. Sonarr Search (Monitored Check) ---
    local sonarr_series=$(curl -s -X GET "$SONARR_URL/api/v3/series" -H "X-Api-Key: $SONARR_API_KEY")
    
    # Extract ID and Monitored status
    local sonarr_data=$(echo "$sonarr_series" | jq -r --arg name "$series_name" \
        '.[] | select(.title == $name or .path == $name) | "\(.id)|\(.monitored)"' | head -n 1)

    if [ -n "$sonarr_data" ]; then
        local s_id=$(echo "$sonarr_data" | cut -d'|' -f1)
        local s_monitored=$(echo "$sonarr_data" | cut -d'|' -f2)

        if [ "$s_monitored" == "true" ]; then
            log "🔍 Triggering Sonarr Search (ID: $s_id) for $series_name..."
            local search_payload=$(jq -n --arg id "$s_id" '{name: "SeriesSearch", seriesId: ($id|tonumber)}')
            curl -s -o /dev/null -X POST "$SONARR_URL/api/v3/command" \
                -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" -d "$search_payload"
        else
            log "⏸️  Sonarr match found for $series_name, but it is NOT monitored. Skipping search."
        fi
    else
        log "⚠️  Could not find matching Series in Sonarr for $series_name."
    fi
}

log "Starting scan in $TARGET_DIR..."

find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d | while read -r series_path; do
    series_name=$(basename "$series_path")
    
    for exclude in "${EXCLUDE_DIRS[@]}"; do
        if [[ "$series_name" == "$exclude" ]]; then
            log "🚫 Skipping excluded directory: $series_name"
            continue 2
        fi
    done
    
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
