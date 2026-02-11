#!/bin/bash

# --- Configuration ---
HOST_NAME=$(hostname)
CONVERT_DIR="/mnt/media/torrent/${HOST_NAME}_convert"
NZB_DIR="/mnt/media/torrent/nzb-get/nzb"
LOG_FILE="/mnt/media/torrent/${HOST_NAME}.log"
SLEEP_INTERVAL=60

# --- Logging Function ---
log() {
    # Outputs to terminal and appends to the log file with a timestamp
    echo "$(date +'%H:%M'): $1" | tee -a "$LOG_FILE"
}

# Ensure script exits immediately if any command fails (except for handled errors)
set -e

log "--- Starting Media Renamer Script (Continuous Mode) ---"
#log "Target Video Directory: $CONVERT_DIR"
#log "Metadata Directory: $NZB_DIR"
#log "Log File: $LOG_FILE"
#log "-------------------------------------------------------"

# Check if the directories exist
if [[ ! -d "$CONVERT_DIR" ]]; then
    log "Error: Video directory not found: $CONVERT_DIR" >&2
    exit 1
fi
if [[ ! -d "$NZB_DIR" ]]; then
    log "Error: Metadata directory not found: $NZB_DIR" >&2
    exit 1
fi

# Main infinite loop for continuous monitoring
while true; do
    
#    log "--- Starting scan ---"
    
    # Use find to locate all .mp4 and .mkv files
    # Note: Removed 'set -e' requirement for the find loop to prevent crash on minor read errors
    find "$CONVERT_DIR" -type f \( -iname "*.mp4" -o -iname "*.mkv" \) -print0 | while IFS= read -r -d $'\0' FULL_PATH; do
        
        # Extract file info
        FILENAME_WITH_EXT=$(basename "$FULL_PATH")
        BASE_NAME="${FILENAME_WITH_EXT%.*}"
        EXTENSION="${FILENAME_WITH_EXT##*.}"

#        log "Processing: $FILENAME_WITH_EXT"

        # --- 1. Filtering ---
        if [[ "$BASE_NAME" =~ [._] ]]; then
            log "  -> SKIPPING: Filename contains a period (.) or an underscore (_)."
            continue
        fi
        
#        log "  -> Passed filter. Searching for metadata..."

        # --- 2. Search for metadata match ---
        METADATA_FILE=$(grep -r -l -F "<meta type=\"title\">$FILENAME_WITH_EXT</meta>" "$NZB_DIR" 2>/dev/null | head -n 1)

        if [[ -n "$METADATA_FILE" ]]; then
#            log "  -> MATCH FOUND in $METADATA_FILE"
            
            # Extract the new filename
            NEW_NAME_RAW=$(grep -oP '(?<=<meta type="name">).*?(?=</meta>)' "$METADATA_FILE" | head -n 1)

            if [[ -n "$NEW_NAME_RAW" ]]; then
                
                # --- 3. Sanitize the new name ---
                NEW_NAME_CLEAN=$(echo "$NEW_NAME_RAW" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d '\n\r' | sed 's/[^a-zA-Z0-9 -]/_/g')

                # Define the new full path
                NEW_FULL_PATH_WITH_EXT="$CONVERT_DIR/$NEW_NAME_CLEAN.$EXTENSION"

                if [[ "$FULL_PATH" != "$NEW_FULL_PATH_WITH_EXT" ]]; then
                    log "  -> RENAMING: '$FILENAME_WITH_EXT' to '$NEW_NAME_CLEAN.$EXTENSION'"
                    
                    # Use 'mv -n' to prevent overwriting
                    if mv -n "$FULL_PATH" "$NEW_FULL_PATH_WITH_EXT"; then
                        log "  -> SUCCESS: File renamed."
                    else
                        log "  -> ERROR: Failed to rename file (perhaps destination exists)." >&2
                    fi
                else
                    log "  -> NO CHANGE: File already matches the new standardized name."
                fi
            else
                log "  -> WARNING: Metadata file found, but could not extract <meta type=\"name\"> content."
            fi
#        else
#            log "  -> No metadata match found in $NZB_DIR"
        fi
#        log "-------------------------------------"

    done

#    log "--- Scan completed. Sleeping for ${SLEEP_INTERVAL}s... ---"
    sleep "$SLEEP_INTERVAL"
done
