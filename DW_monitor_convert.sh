#!/bin/bash

# Monitors a folder for unconverted video files, converts them using HandBrakeCLI
# (Sonos-safe AC3 5.1/2.0), and handles English commentary and forced subtitles.

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
HOST=$(hostname -s)
SOURCE_DIR="$DIR_MEDIA_TORRENT/${HOST}_convert"
if [[ $HOST == "pi"* ]]; then
    HOME_DIR="/home/pi"
else
    HOME_DIR="/home/dan"
fi
CONVERT_DIR="$HOME_DIR/convert"
WORKING_DIR="$HOME_DIR/${HOST}_done"

POLL_INTERVAL=30
MIN_FILE_AGE=5

# --- Setup Directories ---
mkdir -p "$SOURCE_DIR" "$CONVERT_DIR" "$WORKING_DIR" "$DIR_MEDIA_SUBTITLES" "$DIR_MEDIA_FINISHED"

# --- Run Dependency Check ---
check_dependencies "HandBrakeCLI" "jq" "mkvpropedit" "mkvmerge" "ffprobe"

log_start "$SOURCE_DIR"

# --- Main Monitoring Loop (Polling) ---
while true; do
    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Polling $SOURCE_DIR for video files..."
    TIMESTAMP=$(date +"%H-%M")
    rm -f $CONVERT_DIR/*
    rm -f $WORKING_DIR/*
    
    # Process Sonarr weekly shows if function exists
    sonarr_weekly_shows
    
    find "$SOURCE_DIR" -type f \
        -mmin +$MIN_FILE_AGE \
        \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.flv" -o -iname "*.webm" \) \
        -print0 | while IFS= read -r -d $'\0' SOURCE_FILE; do
        
        FILENAME=$(basename "$SOURCE_FILE")
        BASE_NAME="${FILENAME%.*}"
        EXTENSION="${FILENAME##*.}"
        
        # 1. Prepare Paths
        cp "$SOURCE_FILE" "$CONVERT_DIR/"
        FILE_TO_PROCESS="$CONVERT_DIR/$FILENAME"
        TEMP_OUTPUT="$WORKING_DIR/${BASE_NAME}_temp.mkv"
        FINAL_OUTPUT="$WORKING_DIR/$BASE_NAME.mkv"
        SUB_FILE="$DIR_MEDIA_SUBTITLES/$BASE_NAME.srt"

        # 2. Extract Forced Subtitles
        # Using mkvmerge -J to find English forced tracks
        SUB_TRACK_ID=$(mkvmerge -J "$FILE_TO_PROCESS" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)
        HAS_SUBTITLES=false
        if [[ -n "$SUB_TRACK_ID" ]]; then
            log "ℹ️ Converting Forced Subtitle (ID: $SUB_TRACK_ID) to SRT..."
            ffmpeg -i "$FILE_TO_PROCESS" -map 0:"$SUB_TRACK_ID" -c:s srt "$SUB_FILE" -y -loglevel error
            [[ $? -eq 0 ]] && HAS_SUBTITLES=true
        fi

        # 3. Audio Track Detection (MKVToolNix Logic)
        TRACK_JSON=$(mkvmerge -J "$FILE_TO_PROCESS")

        # Find Main English Audio (Excluding tracks named "Commentary")
        MAIN_ID=$(echo "$TRACK_JSON" | jq -r '
            .tracks[] | 
            select(.type == "audio" and .properties.language == "eng" and 
            (.properties.track_name // "" | test("Commentary"; "i") | not)) | 
            .id' | head -n 1)

        # Fallback: If no English non-commentary track found, take the first audio track
        [[ -z "$MAIN_ID" ]] && MAIN_ID=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "audio") | .id' | head -n 1)

        # Find Commentary (English track named "Commentary")
        COMM_ID=$(echo "$TRACK_JSON" | jq -r '
            .tracks[] | 
            select(.type == "audio" and .properties.language == "eng" and 
            (.properties.track_name // "" | test("Commentary"; "i"))) | 
            .id' | head -n 1)

        # HandBrake uses 1-based indexing (mkvmerge ID + 1)
        HB_MAIN=$((MAIN_ID + 1))
        
        if [[ -n "$COMM_ID" && "$COMM_ID" != "$MAIN_ID" ]]; then
            HB_COMM=$((COMM_ID + 1))
            # Encode both: 5.1 Main + Stereo Commentary (AC3 for Sonos)
            AUDIO_PARAMS="--audio $HB_MAIN,$HB_COMM --aencoder ac3,ac3 --ab 640,192 --mixdown 5point1,stereo --aname Main,Commentary"
            log "ℹ️ Found Tracks: Main ($HB_MAIN
