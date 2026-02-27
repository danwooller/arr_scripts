#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# --- Load External Configuration ---
CONFIG_FILE="/mnt/media/torrent/ubuntu24_sonarr_mapping.txt"
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
#LOG_LEVEL="debug"

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

[[ $LOG_LEVEL == "debug" ]] && log_start $TARGET_DIR

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

    if [[ -n "$missing_in_series" ]]; then
        sync_seerr_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "${MANUAL_MAPS[$series_name]}"
    else
        # If NO episodes are missing, we call the NEW surgical resolver
        log "✨ Nothing missing for $series_name. Checking for Seerr issues to resolve..."
        
        # We need to loop through the seasons found to resolve them individually
        # because Seerr issues are season-specific.
        find "$series_path" -maxdepth 1 -type d -name "Season*" | while read -r season_folder; do
             resolve_seerr_issue "$season_folder"
        done
    fi

done

[[ $LOG_LEVEL == "debug" ]] && log_end $TARGET_DIR
