#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"
source "/usr/local/bin/DW_common_seerr_issue.sh"

# --- Load External Configuration ---
CONFIG_FILE="/mnt/media/torrent/ubuntu24_sonarr_mapping.txt"
[[ -f "$CONFIG_FILE" ]] && source <(sed 's/\r$//' "$CONFIG_FILE")

check_dependencies "curl" "jq" "sed" "grep"

# Target directory from argument 1, or default to /mnt/media/TV
INPUT_PATH="${1:-/mnt/media/TV}"

# --- Logic to determine if we are looking at one show or many ---
# If the folder contains "Season " folders, it's a single show.
if find "$INPUT_PATH" -maxdepth 1 -type d -name "Season*" | grep -q .; then
    # We are inside a single show folder
    SERIES_LIST=("$INPUT_PATH")
    BASE_DIR=$(dirname "$INPUT_PATH")
else
    # We are looking at the root /TV folder
    mapfile -t SERIES_LIST < <(find "$INPUT_PATH" -maxdepth 1 -mindepth 1 -type d)
    BASE_DIR="$INPUT_PATH"
fi

log_start "Duplicate Check: $INPUT_PATH"

for series_path in "${SERIES_LIST[@]}"; do
    series_name=$(basename "$series_path")
    
    # Skip excluded directories
    for exclude in "${EXCLUDE_DIRS[@]}"; do
        [[ "$series_name" == "$exclude" ]] && continue 2
    done

    # 1. Find only VIDEO files (.mkv, .mp4, .avi)
    # 2. Extract SxE pattern
    # 3. Count occurrences and filter for counts > 1
    duplicates=$(find "$series_path" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) \
        -not -path "*Specials*" -not -path "*Season 00*" \
        | grep -oE "[0-9]+x[0-9]+" | sort | uniq -c | awk '$1 > 1 {print $2}')

    if [[ -n "$duplicates" ]]; then
        dup_list=$(echo $duplicates | xargs)
        log "⚠️ Duplicate episodes in $series_name: $dup_list"
        
        # Sync to Seerr
        sync_seerr_issue "$series_name" "tv" "Duplicate Episode(s): $dup_list" "${MANUAL_MAPS[$series_name]}"
    else
        [[ $LOG_LEVEL == "debug" ]] && log "✨ No duplicates for $series_name."
        
        # Resolve existing issues
        find "$series_path" -maxdepth 1 -type d -name "Season*" | while read -r season_folder; do
             resolve_seerr_issue "$season_folder"
        done
    fi
done

log_end "Duplicate Check: $INPUT_PATH"
