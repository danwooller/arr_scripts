#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# Ensure the required function is available
check_dependencies "find" "grep"

TARGET_DIR="${1:-/mnt/media/TV}"
log_start "Rename Scan: $TARGET_DIR"

# 1. Find all directories (Series) in the target path
find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d | while read -r series_path; do
    series_name=$(basename "$series_path")
    
    # Handle Exclusions (if EXCLUDE_DIRS is populated by your config)
    for exclude in "${EXCLUDE_DIRS[@]}"; do
        [[ "$series_name" == "$exclude" ]] && continue 2
    done

    # 2. Search for the specific naming patterns within the series folder
    # Pattern 1: "* .mkv" (Space before extension)
    # Pattern 2: "*_.mkv" (Underscore before extension)
    # Using -o (OR) logic in find for efficiency
    found_mismatches=$(find "$series_path" -type f \( -name "* .mkv" -o -name "*_.mkv" \))

    if [[ -n "$found_mismatches" ]]; then
        log "Match found in $series_name. Triggering Sonarr Targeted Rename."
        
        # Log the specific files found if in debug mode
        if [[ $LOG_LEVEL == "debug" ]]; then
             echo "$found_mismatches" | while read -r file; do log "Target file: $(basename "$file")"; done
        fi

        # 3. Trigger the specific rename function from your common functions
        # Passing series_path as the likely argument needed for the rename
        sonarr_targetted_rename "$series_path"
    else
        [[ $LOG_LEVEL == "debug" ]] && log "No malformed filenames found for $series_name."
    fi

done

log_end "Rename Scan: $TARGET_DIR"
