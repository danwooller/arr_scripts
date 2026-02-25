#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# Update your declarations to look like this:
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
#LOG_LEVEL="debug"

# --- 1. Cleanup Excluded Directories (Silent & Prioritized) ---
for excluded_name in "${EXCLUDE_DIRS[@]}"; do
    ex_id=""

    # Check Manual Maps first
    if [[ -n "${MANUAL_MAPS[$excluded_name]}" ]]; then
        ex_id="${MANUAL_MAPS[$excluded_name]}"
        [[ $LOG_LEVEL == "debug" ]] && log "Exclusion: Using Manual Map ID $ex_id for '$excluded_name'"
    else
        # Fallback to search only if no manual map exists
        ex_search=$(echo "$excluded_name" | sed -E 's/\.[^.]*$//; s/[0-9]+x[0-9]+.*//i; s/\([0-9]{4}\)//g; s/[._]/ /g; s/ +/ /g')
        ex_query=$(echo "$ex_search" | jq -Rr @uri)
        ex_results=$(curl -s -X GET "$SEERR_API_BASE/search?query=$ex_query" -H "X-Api-Key: $SEERR_API_KEY")
        ex_id=$(echo "$ex_results" | jq -r '.results // [] | .[] | select(.mediaType == "tv").mediaInfo.id // empty' | head -n 1)
    fi

    # Only attempt resolution if we have a valid ID
    if [[ -n "$ex_id" && "$ex_id" != "null" ]]; then
        # Force resolution by passing an empty message
        sync_seerr_issue "$excluded_name" "tv" "" "$ex_id"
    fi
done

[[ $LOG_LEVEL == "debug" ]] && log "Starting scan in $TARGET_DIR..."

# --- 2. Identify Target Folders ---
if ls "$TARGET_DIR" | grep -qi "^Season "; then
    targets=("$TARGET_DIR")
else
    mapfile -t targets < <(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d)
fi

# --- 3. Process Each Series ---
for series_path in "${targets[@]}"; do
    series_name=$(basename "$series_path")
    
    # Skip items in EXCLUDE_DIRS
    for exclude in "${EXCLUDE_DIRS[@]}"; do
        [[ "$series_name" == "$exclude" ]] && continue 2
    done
    
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

    # --- 4. Sync & Trigger Search ---
    # Passing the manual map ID here ensures Seerr finds the right show even if naming is tricky
    if [[ -n "$missing_in_series" ]]; then
        sync_seerr_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "${MANUAL_MAPS[$series_name]}"
    else
        sync_seerr_issue "$series_name" "tv" "" "${MANUAL_MAPS[$series_name]}"
    fi
done

[[ $LOG_LEVEL == "debug" ]] && log "✅ Scan complete."
