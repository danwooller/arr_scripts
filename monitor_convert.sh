#!/bin/bash

# --- Configuration ---
HOST=$(hostname -s)
SOURCE_DIR="/mnt/media/torrent/${HOST}_convert"

if [[ $HOST == "pi"* ]]; then
    HOME_DIR="/home/pi"
else
    HOME_DIR="/home/dan"
fi

CONVERT_DIR="$HOME_DIR/convert"
WORKING_DIR="$HOME_DIR/${HOST}_done"
SUBTITLE_DIR="/mnt/media/backup/subtitles"
FINISHED_DIR="/mnt/media/torrent/finished"
COMPLETED_DIR="/mnt/media/torrent/completed"
LOG_FILE="/mnt/media/torrent/${HOST}.log"
LOG_LEVEL="debug"

# HandBrake Presets
PRESET_4K="H.265 MKV 2160p60"
PRESET_1080P="Very Fast 1080p30"
PRESET_1080P_X265="H.265 MKV 1080p30"
PRESET_720P="Very Fast 720p30"
PRESET_576P="Very Fast 576p25"
PRESET_SD="Very Fast 480p30"

POLL_INTERVAL=30
MIN_FILE_AGE=5 

# --- Logging Function ---
log() {
    echo "$(date +'%H:%M'): $1" | tee -a "$LOG_FILE"
}

# --- Setup Directories ---
mkdir -p "$SOURCE_DIR" "$CONVERT_DIR" "$WORKING_DIR" "$SUBTITLE_DIR" "$FINISHED_DIR" "$COMPLETED_DIR"

check_dep() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log "Installing '$1' via apt-get..."
        sudo apt-get update && sudo apt-get install -y "$2"
    else
        log "✅ '$1' is ready."
    fi
}

check_dep "HandBrakeCLI" "handbrake-cli"
check_dep "mkvmerge" "mkvtoolnix"
check_dep "jq" "jq"
check_dep "mkvpropedit" "mkvtoolnix"
check_dep "mkvextract" "mkvtoolnix"
check_dep "rsync" "rsync"

log "--- HandBrake Converter started ---"

# --- Main Monitoring Loop ---
while true; do
    if [[ $LOG_LEVEL = "debug" ]]; then
        log "Polling $SOURCE_DIR for files (age > ${MIN_FILE_AGE}m)..."
    fi

    find "$SOURCE_DIR" -maxdepth 1 -type f \
        -mmin +$MIN_FILE_AGE \
        \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.flv" -o -iname "*.webm" \) \
        -print0 | while IFS= read -r -d $'\0' SOURCE_FILE; do
        
        FILENAME=$(basename "$SOURCE_FILE")
        BASE_NAME="${FILENAME%.*}"
        EXTENSION="${FILENAME##*.}"
        TIMESTAMP=$(date +"%H-%M")
        
        log "✅ Detected video file: $FILENAME"

        # --- 1. Copy to local conversion folder (Using rsync for Code 3 fix) ---
        log "   -> Copying to $CONVERT_DIR..."
        rsync -a --fsync "$SOURCE_FILE" "$CONVERT_DIR/$FILENAME"
        sync
        
        FILE_TO_PROCESS="$CONVERT_DIR/$FILENAME"
        OUTPUT_FILE="$WORKING_DIR/$BASE_NAME.mkv"
        
        if [[ ! -f "$FILE_TO_PROCESS" || ! -r "$FILE_TO_PROCESS" ]]; then
            log "   -> 🛑 FATAL ERROR: Local copy $FILENAME failed. Skipping."
            continue 
        fi

        # --- 2. Integrity Check (Specifically for Code 3) ---
        if ! mkvmerge -i "$FILE_TO_PROCESS" >/dev/null 2>&1; then
            log "   -> 🛑 ERROR: File $FILENAME is corrupted or incomplete. Skipping."
            rm -f "$FILE_TO_PROCESS"
            continue
        fi

        # --- 3. Subtitle Extraction ---
        HANDBRAKE_SUB_ARGS=""
        SUB_FILE="$SUBTITLE_DIR/$BASE_NAME.srt"
        
        log "   -> Checking for English forced subtitles..."
        TRACK_INFO=$(mkvmerge -J "$FILE_TO_PROCESS" 2>/dev/null)
        SUB_TRACK_ID=$(echo "$TRACK_INFO" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)

        if [[ -n "$SUB_TRACK_ID" && "$SUB_TRACK_ID" != "null" ]]; then
            log "   -> Forced subtitles found (ID: $SUB_TRACK_ID). Extracting..."
            mkvextract tracks "$FILE_TO_PROCESS" "$SUB_TRACK_ID:$SUB_FILE"
            
            if [[ $? -eq 0 ]]; then
                log "   -> Subtitles extracted successfully."
                HANDBRAKE_SUB_ARGS="--srt-file \"$SUB_FILE\" --srt-codeset UTF-8 --native-language eng --subtitle-default 1 --subtitle-forced 1 --subname Forced"
            else
                log "   -> WARNING: Subtitle extraction failed."
            fi
        fi

        # --- 4. Determine Preset ---
        LOWER_FILENAME=$(echo "$FILENAME" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$LOWER_FILENAME" =~ "2160p" ]]; then
            PRESET="$PRESET_4K"
        elif [[ "$LOWER_FILENAME" =~ "1080p.x265" ]]; then
            PRESET="$PRESET_1080P_X265"
        elif [[ "$LOWER_FILENAME" =~ "1080p" ]]; then
            PRESET="$PRESET_1080P"
        elif [[ "$LOWER_FILENAME" =~ "720p" ]]; then
            PRESET="$PRESET_720P"
        elif [[ "$LOWER_FILENAME" =~ "576p" ]]; then
            PRESET="$PRESET_576P"
        else
            PRESET="$PRESET_SD"
        fi
        log "   -> Using preset: $PRESET"

        # --- 5. Conversion ---
        log "   -> Starting HandBrake conversion..."
        HandBrakeCLI \
            --preset "$PRESET" \
            -q 24.0 \
            -i "$FILE_TO_PROCESS" \
