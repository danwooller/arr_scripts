#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# --- Configuration ---
HOST=$(hostname)
BASE_DIR="/mnt/media/torrent/${HOST}_convert"
TARGET_DIR="$BASE_DIR"

SEARCH_DEPTH_MIN=2
SEARCH_DEPTH_MAX=3
SLEEP_INTERVAL=60 # Seconds to wait between full scans

# Function to safely clean up a filename
clean_filename() {
    local filename="$1"
    local name_without_ext="${filename%.*}"
    local extension="${filename##*.}"
    local cleaned_name=$(echo "$name_without_ext" | tr '[:upper:]' '[:lower:]')
    cleaned_name=$(echo "$cleaned_name" | sed -E 's/[. ]+/_/g')
    cleaned_name=$(echo "$cleaned_name" | sed -E 's/[^a-z0-9_-]//g')
    cleaned_name=$(echo "$cleaned_name" | sed -E 's/_+/-/g')
    echo "${cleaned_name}.${extension}"
}

# --- Service Execution ---

log "Service started. Monitoring: $BASE_DIR"

# Ensure the base directory exists
if [ ! -d "$BASE_DIR" ]; then
    log "Error: Base directory $BASE_DIR does not exist. Creating it..."
    mkdir -p "$BASE_DIR"
fi

while true; do
    # Find all .mkv and .mp4 files
    # We process all found files in one batch, then sleep.
    find "$BASE_DIR" -mindepth $SEARCH_DEPTH_MIN -maxdepth $SEARCH_DEPTH_MAX -type f \( -name "*.mkv" -o -name "*.mp4" \) | while IFS= read -r full_path; do
        
        if [ ! -f "$full_path" ]; then continue; fi
        
        original_filename=$(basename -- "$full_path")
        new_filename=$(clean_filename "$original_filename")
        destination_path="$TARGET_DIR/$new_filename"
        
        log "Processing: $original_filename"
        
        # Check for collisions
        if [ -f "$destination_path" ]; then
            log "[SKIP] Destination already exists: $new_filename"
            continue
        fi

        # Execute move
        if mv "$full_path" "$destination_path"; then
            log "[SUCCESS] Moved to: $new_filename"
        else
            log "[ERROR] Failed to move $original_filename"
        fi
    done

    # Optional: Clean up empty directories
    # Only removes directories inside BASE_DIR, not BASE_DIR itself.
    find "$BASE_DIR" -mindepth 1 -depth -type d -empty -not -path "$BASE_DIR" -exec rmdir {} \; 2>/dev/null

    # Wait for the next cycle
    sleep "$SLEEP_INTERVAL"
done
