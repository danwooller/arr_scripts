#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"
source "/usr/local/bin/DW_common_seerr_issue.sh"

# --- Load External Configuration ---
CONFIG_FILE="/mnt/media/torrent/ubuntu24_sonarr_mapping.txt"
[[ -f "$CONFIG_FILE" ]] && source <(sed 's/\r$//' "$CONFIG_FILE")

check_dependencies "curl" "jq" "sed" "grep"

INPUT_PATH="${1:-/mnt/media/TV}"

# --- Hybrid Path Detection ---
if find "$INPUT_PATH" -maxdepth 1 -type d -name "Season*" | grep -q .; then
    SERIES_LIST=("$INPUT_PATH")
else
    mapfile -t SERIES_LIST < <(find "$INPUT_PATH" -maxdepth 1 -mindepth 1 -type d)
fi

log_start "Duplicate Check: $INPUT_PATH"

for series_path in "${SERIES_LIST[@]}"; do
    series_name=$(basename "$series_path")
    
    for exclude in "${EXCLUDE_DIRS[@]}"; do
        [[ "$series_name" == "$exclude" ]] && continue 2
    done

    # 1. Find only VIDEO files and count SxE occurrences
    duplicates=$(find "$series_path" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) \
        -not -path "*Specials*" -not -path "*Season 00*" \
        | grep -oE "[0-9]+x[0-9]+" | sort | uniq -c | awk '$1 > 1 {print $2}')

    if [[ -n "$duplicates" ]]; then
        dup_list=$(echo $duplicates | xargs)
        
        # 2. Check Seerr for existing issue to avoid duplicate comments
        # We fetch the current status of the issue for this show
        local existing_issue=$(curl -s -X GET "$SEERR_URL/api/v1/issue?searchTerm=$series_name" -H "Authorization: Bearer $SEERR_API_KEY")
        local current_msg=$(echo "$existing_issue" | jq -r '.results[0].comments[0].message // ""')

        # 3. Only sync if the duplicate list has changed
        if [[ "$current_msg" != "Duplicate Episode(s): $dup_list" ]]; then
            log "⚠️ New/Changed Duplicates in $series_name: $dup_list"
            sync_seerr_issue "$series_name" "tv" "Duplicate Episode(s): $dup_list" "${MANUAL_MAPS[$series_name]}"
        else
            [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Duplicates for $series_name haven't changed. Skipping Seerr comment."
        fi
    else
        [[ $LOG_LEVEL == "debug" ]] && log "✨ No duplicates for $series_name. Checking for issues
