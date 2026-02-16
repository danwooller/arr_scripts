#!/bin/bash

# Monitors a folder looking for video files and extracts any forced subtitle.

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# --- Configuration ---
HOST=$(hostname -s)
SOURCE_DIR="/mnt/media/torrent/${HOST}/subtitles/extract"

# File types to process (no variable needed when using -iname)
POLL_INTERVAL=30
MIN_FILE_AGE=5 

log "--- Polling Conversion Monitor Started ---"

# --- Main Monitoring Loop (Polling) ---
while true; do
    log "Polling $SOURCE_DIR for video files (age > ${MIN_FILE_AGE}m)..."

    # Use 'find' with -name filters
    find "$SOURCE_DIR" -type f \
        -mmin +$MIN_FILE_AGE \
        \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.flv" -o -iname "*.webm" \) \
        -print0 | while IFS= read -r -d $'\0' SOURCE_FILE; do
        
        # Get filename and base name
        FILENAME=$(basename "$SOURCE_FILE")
        BASE_NAME="${FILENAME%.*}"
        
        log "✅ Detected video file: $FILENAME"

        # Reset HandBrake subtitle argument.
        HANDBRAKE_SUB_ARGS=""
        SUB_FILE_EXTRACTED=false

        # --- 3. Extract English Forced Subtitles and copy to $SUBTITLE_DIR ---
        SUB_FILE="$SUBTITLE_DIR/$BASE_NAME.srt"
        log "   -> Checking for English forced subtitles..."
        TRACK_INFO=$(mkvmerge -J "$SOURCE_FILE" 2>/dev/null)
        SUB_TRACK_ID=$(echo "$TRACK_INFO" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)
        echo "Extracted Forced Track ID: $SUB_TRACK_ID"

        if [[ -n "$SUB_TRACK_ID" ]]; then
            log "   -> English Forced subtitle track found (ID: $SUB_TRACK_ID). Extracting to $SUB_FILE..."
            mkvextract tracks "$SOURCE_FILE" "$SUB_TRACK_ID:$SUB_FILE"
        else
            log "   -> No suitable English forced subtitle track found in the source file."
        fi
    done
    
    # Wait for the next poll cycle
    sleep "$POLL_INTERVAL"
done
