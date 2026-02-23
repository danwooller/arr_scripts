#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# --- Load External Configuration ---
CONFIG_FILE="/mnt/media/torrent/ubuntu9_sonarr.txt"
if [[ -f "$CONFIG_FILE" ]]; then
    # Source the file, but strip any trailing Windows CR characters on the fly
    source <(sed 's/\r$//' "$CONFIG_FILE")
else
    log "WARN: Config file $CONFIG_FILE not found."
    EXCLUDE_DIRS=()
    declare -A MANUAL_MAPS
fi

check_dependencies "curl" "jq" "sed" "grep"

TARGET_DIR="${1:-/mnt/media/TV}"
LOG_LEVEL="debug"

sync_seerr_status() {
    local series_name="$1"
    local missing_episodes="$2"
    local media_id=""

    # 1. Get Seerr Media ID (Quoted check for associative array)
    if [[ ${MANUAL_MAPS["$series_name"]+_} ]]; then
        media_id="${MANUAL_MAPS["$series_name"]}"
    else
        local search_term=$(echo "$series_name" | sed -E 's/\([0-9]{4}\)//g; s/[._]/ /g')
        local encoded_query=$(echo "$search_term" | jq -Rr @uri)
        local search_results=$(curl -s -X GET "$SEERR_URL/api/v1/search?query=$encoded_query" \
            -H "X-Api-Key: $SEERR_API_KEY")
        media_id=$(echo "$search_results" | jq -r '.results[] | select(.mediaType == "tv").mediaInfo.id // empty' | head -n 1)
    fi

    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        [[ $LOG_LEVEL == "debug" ]] && log "⚠️  Skipping $series_name: Not found in Seerr."
        return 1
    fi

    # 2. Check for existing Open Issue
    local existing_issues=$(curl -s -X GET "$SEERR_URL/api/v1/issue?take=100&filter=open" -H "X-Api-Key: $SEERR_API_KEY")
    local existing_data=$(echo "$existing_issues" | jq -r --arg mid "$media_id" \
        '.results[] | select(.media.id == ($mid|tonumber) and .issueType == 1) | "\(.id)|\(.message)"' | head -n 1)
    
    local issue_id=$(echo "$existing_data" | cut -d'|' -f1)
    local old_msg=$(echo "$existing_data" | cut -d'|' -f2)

    # 3. Decision Matrix
    if [[ -z "$missing_episodes" ]]; then
        if [[ -n "$issue_id" ]]; then
            log "✅ Closing issue #$issue_id for $series_name (Library complete)."
            curl -s -X DELETE "$SEERR_URL/api/v1/issue/$issue_id" -H "X-Api-Key: $SEERR_API_KEY"
        fi
        return 0
    fi

    if [[ -n "$issue_id" ]]; then
        local norm_old=$(echo "$old_msg" | grep -oE "[0-9]+x[0-9]+" | sort | xargs)
        local norm_new=$(echo "$missing_episodes" | grep -oE "[0-9]+x[0-9]+" | sort | xargs)

        if [[ "$norm_old" == "$norm_new" ]]; then
            [[ $LOG_LEVEL == "debug" ]] && log "😴 Issue #$issue_id is already accurate for $series_name."
            return 0
        else
            log "🔄 Change detected for $series_name. Refreshing issue #$issue_id."
            curl -s -X DELETE "$SEERR_URL/api/v1/issue/$issue_id" -H "X-Api-Key: $SEERR_API_KEY"
        fi
    fi

    local new_msg="Missing Episode(s): $missing_episodes"
    local json_payload=$(jq -n --arg mt "1" --arg msg "$new_msg" --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')

    curl -s -o /dev/null -X POST "$SEERR_URL/api/v1/issue" \
        -H "X-Api-Key: $SEERR_API_KEY" -H "Content-Type: application/json" -d "$json_payload"
    
    log "🚀 Seerr Issue created for $series_name: $missing_episodes"
    trigger_sonarr_search "$series_name"
}

trigger_sonarr_search() {
    local series_name="$1"
    local sonarr_series=$(curl -s -X GET "$SONARR_URL/api/v3/series" -H "X-Api-Key: $SONARR_API_KEY")
    local sonarr_data=$(echo "$sonarr_series" | jq -r --arg name "$series_name" \
        '.[] | select(.title == $name or .path == $name) | "\(.id)|\(.monitored)"' | head -n 1)

    if [[ -n "$sonarr_data" ]]; then
        local s_id=$(echo "$sonarr_data" | cut -d'|' -f1)
        local s_monitored=$(echo "$sonarr_data" | cut -d'|' -f2)
        if [[ "$s_monitored" == "true" ]]; then
            log "🔍 Triggering Sonarr Search for $series_name..."
            local payload=$(jq -n --arg id "$s_id" '{name: "SeriesSearch", seriesId: ($id|tonumber)}')
            curl -s -o /dev/null -X POST "$SONARR_URL/api/v3/command" -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" -d "$payload"
        fi
    fi
}

[[ $LOG_LEVEL == "debug" ]] && log "Starting scan in $TARGET_DIR..."

find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d | while read -r series_path; do
    series_name=$(basename "$series_path")
    
    for exclude in "${EXCLUDE_DIRS[@]}"; do
        [[ "$series_name" == "$exclude" ]] && continue 2
    done
    
    mapfile -t ep_list < <(find "$series_path" -type f -not -path "*Specials*" -not -path "*Season 00*" \
        -name "*[0-9]x[0-9]*" | grep -oE "[0-9]+x[0-9]+(-[0-9]+)?" | sort -V | uniq)

    missing_in_series=""
    if [[ ${#ep_list[@]} -ge 2 ]]; then
        prev_s=-1; prev_e=-1
        for ep in "${ep_list[@]}"; do
            curr_s=$(echo "$ep" | cut -d'x' -f1)
            range=$(echo "$ep" | cut -d'x' -f2)
            start_e=$(echo "$range" | cut -d'-' -f1 | sed 's/^0//'); end_e=$(echo "$range" | cut -d'-' -f2 | sed 's/^0//')
            if [[ "$curr_s" -eq "$prev_s" ]]; then
                expected=$((prev_e + 1))
                [[ "$start_e" -gt "$expected" ]] && for ((i=expected; i<start_e; i++)); do missing_in_series+="${curr_s}x$(printf "%02d" $i) "; done
            fi
            prev_s=$curr_s; prev_e=$end_e
        done
    fi

    sync_seerr_status "$series_name" "${missing_in_series% }"
done

[[ $LOG_LEVEL == "debug" ]] && log "✅ Scan complete."
