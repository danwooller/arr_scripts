#!/bin/bash

# Monitors a folder looking for video files and extracts any forced subtitle.

# --- Configuration ---
HOST=$(hostname -s)
#SOURCE_DIR="/mnt/media/torrent/${HOST}_convert"
SOURCE_DIR="/mnt/media/TV/PLUR1BUS/Season 1/"
#SOURCE_DIR="/mnt/media/torrent/finished"
#CONVERT_DIR="/home/pi/convert"
#WORKING_DIR="/home/pi/${HOST}_done" 
SUBTITLE_DIR="/mnt/media/backup/subtitles"
#FINISHED_DIR="/mnt/media/torrent/finished"
#COMPLETED_DIR="/mnt/media/torrent/completed"
LOG_FILE="/home/pi/handbrake_subtitles.log"

# File types to process (no variable needed when using -iname)
POLL_INTERVAL=30
MIN_FILE_AGE=5 

# --- Logging Function ---
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

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
#        SUB_TRACK_ID=$(echo "$TRACK_INFO" | grep -E "Track ID [0-9]+: subtitles.*language:eng.*forced" | head -n 1 | awk '{print $3}' | sed 's/://')
#        SUB_TRACK_ID=$(echo "$TRACK_INFO" | grep -E "Track ID [0-9]+: subtitles.*language:eng.*forced track" | head -n 1 | awk '{print $3}' | sed 's/://')
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
