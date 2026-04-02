#!/bin/bash

# Monitors a folder looking for video files and extracts any forced subtitle.

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
SOURCE_DIR="$DIR_MEDIA_TORRENT/${HOST}/subtitles/extract/tv"

mkdir -p "$SOURCE_DIR"

# File types to process (no variable needed when using -iname)
POLL_INTERVAL=30
MIN_FILE_AGE=5 

log_start "$SOURCE_DIR"

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
        
        [[ $LOG_LEVEL == "debug" ]] && log "✅ Detected video file: $FILENAME"

        # Reset HandBrake subtitle argument.
        HANDBRAKE_SUB_ARGS=""
        SUB_FILE_EXTRACTED=false

        # --- 3. Extract English Forced Subtitles and copy to $DIR_MEDIA_SUBTITLES ---
        SUB_FILE="$DIR_MEDIA_SUBTITLES/$BASE_NAME.srt"
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Checking for English forced subtitles..."
        TRACK_INFO=$(mkvmerge -J "$SOURCE_FILE" 2>/dev/null)
        SUB_TRACK_ID=$(echo "$TRACK_INFO" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)
        echo "Extracted Forced Track ID: $SUB_TRACK_ID"

        if [[ -n "$SUB_TRACK_ID" ]]; then
            [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ English Forced subtitle track found (ID: $SUB_TRACK_ID). Extracting to $SUB_FILE..."
            mkvextract tracks "$SOURCE_FILE" "$SUB_TRACK_ID:$SUB_FILE"
        else
            [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ No suitable English forced subtitle track found in the source file."
        fi
        mv "$SOURCE_FILE" "$DIR_MEDIA_COMPLETED_TV/"
    done
    
    # Wait for the next poll cycle
    sleep "$POLL_INTERVAL"
done

log_end "$SOURCE_DIR"
