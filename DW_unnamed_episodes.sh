#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

check_dependencies "find" "grep"

# Canonicalize path to remove trailing slashes
TARGET_DIR=$(realpath "${1:-/mnt/media/TV}")
log_start "Rename Scan: $TARGET_DIR"

# --- SMART PATH DETECTION ---
# If the target dir contains "Season" folders, we treat it as a single Series scan
if find "$TARGET_DIR" -maxdepth 1 -type d -name "Season*" | grep -q .; then
    PROCESS_LIST=("$TARGET_DIR")
    log "Direct series folder detected. Processing: $(basename "$TARGET_DIR")"
else
    # Otherwise, treat it as a library root and list all subdirectories
    mapfile -t PROCESS_LIST < <(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d)
fi

for series_path in "${PROCESS_LIST[@]}"; do
    series_name=$(basename "$series_path")
    
    # Skip if folder name is "Season X" (prevents double-processing or errors)
    [[ "$series_name" =~ ^Season ]] && continue

    for exclude in "${EXCLUDE_DIRS[@]}"; do
        [[ "$series_name" == "$exclude" ]] && continue 2
    done

    # Search for the specific naming patterns
    found_mismatches=$(find "$series_path" -type f \( -name "* .mkv" -o -name "*_.mkv" \))

    if [[ -n "$found_mismatches" ]]; then
        log "Match found in $series_name. Triggering Sonarr Targeted Rename."
        
        # Pass the Series Name to the rename function
        # (Assuming your function looks up ID by folder name or path)
        sonarr_targeted_rename "$series_path"
    else
        [[ $LOG_LEVEL == "debug" ]] && log "No malformed filenames found for $series_name."
    fi
done

log_end "Rename Scan: $TARGET_DIR"
