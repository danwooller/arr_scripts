#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

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
LOG_LEVEL="debug"

[[ $LOG_LEVEL == "debug" ]] && log "Starting scan in $TARGET_DIR..."

# --- 1. Identify Target Folders ---
# Check if the TARGET_DIR contains ANY "Season" folder
if ls "$TARGET_DIR" | grep -qi "^Season "; then
    # It's a single series folder
    targets=("$TARGET_DIR")
else
    # It's a parent directory (like /mnt/media/TV)
    mapfile -t targets < <(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d)
fi

# --- 2. Clean up issues for Excluded Directories ---
if [[ ${#EXCLUDE_DIRS[@]} -gt 0 ]]; then
    [[ $LOG_LEVEL == "debug" ]] && log "Cleaning up Seerr issues for EXCLUDE_DIRS..."
    for excluded_name in "${EXCLUDE_DIRS[@]}"; do
        # We redirect stderr to /dev/null to suppress "Could not link to ID" 
        # for items we know aren't in Seerr anyway.
        sync_seerr_issue "$excluded_name" "tv" "" "${MANUAL_MAPS[$excluded_name]}" 2>/dev/null
    done
fi

# --- 3. Process Each Series ---
for series_path in "${targets[@]}"; do
    series_name=$(basename "$series_path")
    
    for exclude in "${EXCLUDE_DIRS[@]}"; do
        [[ "$series_name" == "$exclude" ]] && continue 2
    done
    
    # Build list of existing episodes
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

            # --- Detect Gap at Start of Season (Episode 01 missing) ---
            if [[ "$curr_s" -ne "$prev_s" ]]; then
                if [[ "$start_e" -gt 1 ]]; then
                    for ((i=1; i<start_e; i++)); do 
                        missing_in_series+="${curr_s}x$(printf "%02d" $i) "
                    done
                fi
            # --- Detect Gap Between Episodes ---
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

    # --- 4. Sync & Trigger ---
    if [[ -n "$missing_in_series" ]]; then
        # sync_seerr_issue now handles Sonarr/Radarr search internally
        sync_seerr_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "${MANUAL_MAPS[$series_name]}"
    else
        # Auto-resolve Seerr issue if list is empty
        sync_seerr_issue "$series_name" "tv" "" "${MANUAL_MAPS[$series_name]}"
    fi
done

[[ $LOG_LEVEL == "debug" ]] && log "✅ Scan complete."
