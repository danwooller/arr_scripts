#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
CONVERT_DIR="/mnt/media/torrent/${HOST}_convert"
SLEEP_INTERVAL=60

# Ensure script exits immediately if any command fails (except for handled errors)
set -e

log "--- Starting Media Renamer Script (Continuous Mode) ---"

# Check if the directories exist
if [[ ! -d "$CONVERT_DIR" ]]; then
    log "Error: Video directory not found: $CONVERT_DIR" >&2
    exit 1
fi
if [[ ! -d "$DIR_MEDIA_NZB" ]]; then
    log "Error: Metadata directory not found: $DIR_MEDIA_NZB" >&2
    exit 1
fi

# Main infinite loop for continuous monitoring
while true; do
    # Use find to locate all .mp4 and .mkv files
    # Note: Removed 'set -e' requirement for the find loop to prevent crash on minor read errors
    find "$CONVERT_DIR" -type f \( -iname "*.mp4" -o -iname "*.mkv" \) -print0 | while IFS= read -r -d $'\0' FULL_PATH; do
        # Extract file info
        FILENAME_WITH_EXT=$(basename "$FULL_PATH")
        BASE_NAME="${FILENAME_WITH_EXT%.*}"
        EXTENSION="${FILENAME_WITH_EXT##*.}"
        # --- 1. Filtering ---
        if [[ "$BASE_NAME" =~ [._] ]]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ Filename contains a period (.) or an underscore (_)."
            continue
        fi
        # --- 2. Search for metadata match ---
        METADATA_FILE=$(grep -r -l -F "<meta type=\"title\">$FILENAME_WITH_EXT</meta>" "$DIR_MEDIA_NZB" 2>/dev/null | head -n 1)
        if [[ -n "$METADATA_FILE" ]]; then
            # Extract the new filename
            NEW_NAME_RAW=$(grep -oP '(?<=<meta type="name">).*?(?=</meta>)' "$METADATA_FILE" | head -n 1)
            if [[ -n "$NEW_NAME_RAW" ]]; then
                # --- 3. Sanitize the new name ---
                NEW_NAME_CLEAN=$(echo "$NEW_NAME_RAW" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d '\n\r' | sed 's/[^a-zA-Z0-9 -]/_/g')
                # Define the new full path
                NEW_FULL_PATH_WITH_EXT="$CONVERT_DIR/$NEW_NAME_CLEAN.$EXTENSION"

                if [[ "$FULL_PATH" != "$NEW_FULL_PATH_WITH_EXT" ]]; then
                    [[ "$LOG_LEVEL" == "debug" ]] && log "  -> RENAMING: '$FILENAME_WITH_EXT' to '$NEW_NAME_CLEAN.$EXTENSION'"
                    
                    # Use 'mv -n' to prevent overwriting
                    if mv -n "$FULL_PATH" "$NEW_FULL_PATH_WITH_EXT"; then
                        [[ "$LOG_LEVEL" == "debug" ]] && log "🏁 File renamed."
                    else
                        log "❌ Failed to rename file (perhaps destination exists)." >&2
                    fi
                else
                    [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ File already matches the new standardised name."
                fi
            else
                log "⚠️ Metadata file found, but could not extract <meta type=\"name\"> content."
            fi
        fi
    done
    sleep "$SLEEP_INTERVAL"
done
