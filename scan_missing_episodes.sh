#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# Seerr API configuration
export SEERR_API_SEARCH="http://wooller.com:5055/api/v3"
export SEERR_API_ISSUES="http://wooller.com:5055/api/v1"
export SEERR_API_KEY="MTc0MDQ5NzU0MjYyOWRhZjA1MjhmLTg2Y2YtNDZmOS1hODkxLThlMzBlMWNmNzZmOQ=="

# --- Load External Configuration ---
CONFIG_FILE="/mnt/media/torrent/ubuntu24_sonarr_mapping.txt"
if [[ -f "$CONFIG_FILE" ]]; then
    source <(sed 's/\r$//' "$CONFIG_FILE")
else
    log "WARN: Config file $CONFIG_FILE not found."
    EXCLUDE_DIRS=()
    declare -A MANUAL_MAPS
fi

check_dependencies "curl" "jq" "sed" "grep"

TARGET_DIR="${1:-/mnt/media/TV}"
LOG_LEVEL=${LOG_LEVEL:-"info"}

# --- 1. Identify Target Folders ---
if ls "$TARGET_DIR" | grep -qi "^Season "; then
    targets=("$TARGET_DIR")
else
    mapfile -t targets < <(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d)
fi

[[ $LOG_LEVEL == "debug" ]] && log "Starting scan in $TARGET_DIR..."

# --- 2. Process Each Series ---
for series_path in "${targets[@]}"; do
    series_name=$(basename "$series_path")

    # --- Exclusion Logic (Now with Seerr Ticket Resolution) ---
    if [[ " ${EXCLUDE_DIRS[@]} " =~ " ${series_name} " ]]; then
        [[ $LOG_LEVEL == "debug" ]] && log "Exclusion: Skipping '$series_name' (listed in EXCLUDE_DIRS)."
        
        # This will find any open issue and resolve it with the comment
        sync_seerr_issue "$series_name" "tv" "Added to exclusion list" "${MANUAL_MAPS[$series_name]}" "3"
        continue
    fi
    
    # Get existing episodes
    mapfile -t ep_list < <(find "$series_path" -type f -not -path "*Specials*" -not -path "*Season 00*" \
        -name "*[0-9]x[0-9]*" | grep -oE "[0-9]+x[0-9]+(-[0-9]+)?" | sort -V | uniq)

    missing_in_series=""
    if [[ ${#ep_list[@]} -ge 1 ]]; then
        prev_s=-1; prev_e=-1
        
        for ep in "${ep_list[@]}"; do
            curr_s=$(echo "$ep" | cut -d'x' -f1 | sed 's/^0//')
            range=$(echo "$ep" | cut -d'x' -f2)
            start_e=$(echo "$range" | cut -d'-' -f1 | sed 's/^0//')
            end_e=$(echo "$range" | cut -d'-' -f2 | sed 's/^0//')

            # Detect Gap at Start of Season
            if [[ "$curr_s" -ne "$prev_s" ]]; then
                if [[ "$start_e" -gt 1 ]]; then
                    for ((i=1; i<start_e; i++)); do 
                        missing_in_series+="${curr_s}x$(printf "%02d" $i) "
                    done
                fi
            # Detect Gap Between Episodes
            elif [[ "$curr_s" -eq "$prev_s" ]]; then
                expected=$((prev_e + 1))
                if [[ "$start_e" -gt "$expected" ]]; then
                    for ((i=expected; i<start_e; i++)); do 
                        missing_in_series+="${curr_s}x$(printf "%02d" $i) "
                    done
                fi
            fi
            
            prev_s=$curr_s; prev_e=$end_e
        done
    fi

    # --- 3. Sync & Trigger Search ---
    if [[ -n "$missing_in_series" ]]; then
        sync_seerr_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "${MANUAL_MAPS[$series_name]}"
    else
        sync_seerr_issue "$series_name" "tv" "" "${MANUAL_MAPS[$series_name]}"
    fi
done

[[ $LOG_LEVEL == "debug" ]] || log "✅ Scan complete."
