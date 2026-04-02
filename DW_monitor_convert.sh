#!/bin/bash

# Monitors a folder looking for unconverted Linux ISOs, copies them to a local folder,
# determines whether the file is 1080p or 4K and converts the file using HandBrakeCLI
# before copying back to the network for further sorting.

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
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
#LOG_LEVEL="debug"

# File types to process (no variable needed when using -iname)
POLL_INTERVAL=30
MIN_FILE_AGE=5

# --- Setup Directories ---
mkdir -p "$SOURCE_DIR" "$CONVERT_DIR" "$WORKING_DIR" "$DIR_MEDIA_SUBTITLES" "$DIR_MEDIA_FINISHED"

# --- copy common_keys.txt ---
cp $DIR_MEDIA_BACKUP/ubuntu24/arr_scripts/common_keys.txt /usr/local/bin

# --- Run Dependency Check using the shared function ---
check_dependencies "HandBrakeCLI" "jq" "mkvpropedit" "mkvmerge"

#log "ℹ️ HandBrake Converter started"
log_start "$SOURCE_DIR"

# --- Main Monitoring Loop (Polling) ---
while true; do
    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Polling $SOURCE_DIR for video files..."
    TIMESTAMP=$(date +"%H-%M")
    rm -f $CONVERT_DIR/*
    rm -f $WORKING_DIR/*

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

        # 2. Extract and CONVERT Subtitles to True SRT
        # We use ffmpeg instead of mkvextract to force the format change from ASS to SRT
        SUB_TRACK_ID=$(mkvmerge -J "$FILE_TO_PROCESS" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)

        HAS_SUBTITLES=false
        if [[ -n "$SUB_TRACK_ID" ]]; then
            log "ℹ️ Converting Forced Subtitle (ID: $SUB_TRACK_ID) to SRT..."
            ffmpeg -i "$FILE_TO_PROCESS" -map 0:"$SUB_TRACK_ID" -c:s srt "$SUB_FILE" -y -loglevel error
            if [[ $? -eq 0 ]]; then
                log "✅ SRT Conversion Successful."
                HAS_SUBTITLES=true
            fi
        fi

        # 3. Determine Preset
        LOWER_FILENAME=$(echo "$FILENAME" | tr '[:upper:]' '[:lower:]')
        if [[ "$LOWER_FILENAME" =~ "2160p" ]]; then PRESET="$PRESET_4K"
        elif [[ "$LOWER_FILENAME" =~ "1080p.x265" ]]; then PRESET="$PRESET_1080P_X265"
        elif [[ "$LOWER_FILENAME" =~ "1080p" ]]; then PRESET="$PRESET_1080P"
        elif [[ "$LOWER_FILENAME" =~ "720p" ]]; then PRESET="$PRESET_720P"
        else PRESET="$PRESET_SD"; fi

        # 4. Transcode Video/Audio ONLY (Ignore internal subs)
        log "ℹ️ Transcoding with HandBrake (Ignoring internal subs)..."
        HandBrakeCLI \
            --preset "$PRESET" \
            -q 24.0 \
            -i "$FILE_TO_PROCESS" \
            -o "$TEMP_OUTPUT" \
            --audio-lang-list eng \
            --aencoder ac3 \
            --ab 640 \
            --mixdown 5point1 \
            --subtitle none \
            --optimize < /dev/null

        # 5. Final Remux: Combine Video/Audio with the CLEAN SRT
        if [[ -f "$TEMP_OUTPUT" ]]; then
            if [ "$HAS_SUBTITLES" = true ]; then
                log "ℹ️ Remuxing clean SRT into final container..."
                # --no-subtitles ignores anything HandBrake might have snuck in
                mkvmerge -o "$FINAL_OUTPUT" \
                    --no-subtitles "$TEMP_OUTPUT" \
                    --language 0:eng --track-name 0:"Forced" --forced-track 0:yes --default-track 0:yes "$SUB_FILE"
            else
                mv "$TEMP_OUTPUT" "$FINAL_OUTPUT"
            fi
        fi

        # 6. Post-Processing & Cleanup
        if [[ -f "$FINAL_OUTPUT" ]]; then
            log "✅ Completed $FILENAME"
            rm -f "$FILE_TO_PROCESS" "$TEMP_OUTPUT"
            
            # Run your existing Sonos fix
            sonos_audio_fix "$FINAL_OUTPUT"
            
            mv "$FINAL_OUTPUT" "$DIR_MEDIA_COMPLETED_TV/"
            mv "$SOURCE_FILE" "$DIR_MEDIA_FINISHED/$BASE_NAME-$TIMESTAMP.$EXTENSION"
            manage_remote_torrent "delete" "$BASE_NAME"
        else
            log "❌ Conversion failed for $FILENAME"
            rm -f "$TEMP_OUTPUT" "$FINAL_OUTPUT"
        fi
    done
    # --- Wait for the next poll cycle ---
    [[ $LOG_LEVEL == "debug" ]] && log "Sleeping for $POLL_INTERVAL seconds"
    sleep "$POLL_INTERVAL"
done
