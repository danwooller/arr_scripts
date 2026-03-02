#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"
source "/usr/local/bin/DW_common_seerr_issue.sh"

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

log_start "Duplicate Check: $TARGET_DIR"

# 1. Iterate through each TV Show folder
find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d | while read -r series_path; do
    series_name=$(basename "$series_path")
    
    # Skip excluded directories
    for exclude in "${EXCLUDE_DIRS[@]}"; do
        [[ "$series_name" == "$exclude" ]] && continue 2
    done
    
    # 2. Extract every SxE pattern found in the series folder
    # We don't use 'uniq' yet because we WANT to see duplicates
    mapfile -t all_eps < <(find "$series_path" -type f -not -path "*Specials*" -not -path "*Season 00*" \
        -name "*[0-9]x[0-9]*" | grep -oE "[0-9]+x[0-9]+" | sort -V)

    # 3. Use uniq -d to find only the patterns that appear 2+ times
    mapfile -t duplicates < <(printf "%s\n" "${all_eps[@]}" | uniq -d)

    if [[ ${#duplicates[@]} -gt 0 ]]; then
        # Format the list for logging/Seerr (e.g., "1x01 1x05")
        dup_list=$(printf "%s " "${duplicates[@]}")
        
        log "⚠️ Duplicate detected in $series_name: $dup_list"
        
        # 4. Sync to Seerr as an 'issue' so you can see it in the UI
        sync_seerr_issue "$series_name" "tv" "Duplicate Episode(s): $dup_list" "${MANUAL_MAPS[$series_name]}"
        
        # Optional: Trigger a Sonarr Rename/Rescan for the series to see if it self-heals
        # trigger_sonarr_rename "$series_name" 
    else
        [[ $LOG_LEVEL == "debug" ]] && log "✨ No duplicates for $series_name."
        
        # If NO duplicates, resolve existing Seerr issues for this show
        find "$series_path" -maxdepth 1 -type d -name "Season*" | while read -r season_folder; do
             resolve_seerr_issue "$season_folder"
        done
    fi

done

log_end "Duplicate Check: $TARGET_DIR"
