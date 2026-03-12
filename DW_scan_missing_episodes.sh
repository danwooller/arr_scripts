#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

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

log_start "$TARGET_DIR"

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
        seerr_sync_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "${MANUAL_MAPS[$series_name]}"
    else
        # If NO episodes are missing, we call the NEW surgical resolver
        [[ $LOG_LEVEL == "debug" ]] && log "✨ Nothing missing for $series_name. Checking for Seerr issues to resolve..."
        
        # We need to loop through the seasons found to resolve them individually
        # because Seerr issues are season-specific.
        find "$series_path" -maxdepth 1 -type d -name "Season*" | while read -r season_folder; do
             seerr_resolve_issue "$season_folder"
        done
    fi

done

log_end "$TARGET_DIR"
