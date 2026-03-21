#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

check_dependencies "find" "grep" "sed"

INPUT_PATH=$(realpath "${1:-$DIR_MEDIA_TV}")

# --- Hybrid Path Detection ---
if find "$INPUT_PATH" -maxdepth 1 -type d -name "Season*" | grep -q .; then
    SERIES_LIST=("${INPUT_PATH%/}")
else
    mapfile -t SERIES_LIST < <(find "$INPUT_PATH" -maxdepth 1 -mindepth 1 -type d)
fi

log_start "Rename Scan: $INPUT_PATH"

for series_path in "${SERIES_LIST[@]}"; do
    # Strip trailing slash
    series_path="${series_path%/}"
    series_name=$(basename "$series_path")
    
    # Exclusion check
    for exclude in "${EXCLUDE_DIRS[@]}"; do
        [[ "$series_name" == "$exclude" ]] && continue 2
    done

    # --- Detection Logic ---
    # Look for the specific malformed MKV patterns
    found_mismatches=$(find "$series_path" -type f \( -name "* .mkv" -o -name "*_.mkv" \))

    if [[ -n "$found_mismatches" ]]; then
        log "Match found in $series_name. Triggering Sonarr via Title..."

        # --- Strip everything but the Folder Name ---
        # This ensures Sonarr receives "Young Sherlock (2026)" instead of the full path
        SONARR_TARGET_TITLE=$(basename "$series_path")
        
        # Log the stripped name for verification
        log "Mapping Title: '$SONARR_TARGET_TITLE'"
        
        # Trigger the rename using the Title
        sonarr_targeted_rename "$SONARR_TARGET_TITLE"
    else
        [[ $LOG_LEVEL == "debug" ]] && log "No malformed filenames found for $series_name."
    fi
done

log_end "Rename Scan: $INPUT_PATH"
