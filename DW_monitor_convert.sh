#!/bin/bash

# Monitors a folder looking for unconverted Linux ISOs, copies them to a local folder,
# determines whether the file is 1080p or 4K and converts the file using HandBrakeCLI
# before copying back to the network for further sorting.

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

# --- Main Monitoring Loop ---
while true; do
    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Polling $SOURCE_DIR for video files..."
    TIMESTAMP=$(date +"%H-%M")
    rm -f $CONVERT_DIR/*
    rm -f $WORKING_DIR/*
    
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
        SUB_TRACK_ID=$(mkvmerge -J "$FILE_TO_PROCESS" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)
        HAS_SUBTITLES=false
        if [[ -n "$SUB_TRACK_ID" ]]; then
            log "ℹ️ Converting Forced Subtitle (ID: $SUB_TRACK_ID) to SRT..."
            ffmpeg -i "$FILE_TO_PROCESS" -map 0:"$SUB_TRACK_ID" -c:s srt "$SUB_FILE" -y -loglevel error
            [[ $? -eq 0 ]] && HAS_SUBTITLES=true
        fi

        # 3. Audio Track Detection (Sonos Optimized)
        # Find Main English Audio (Preferably 6ch)
        MAIN_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=index,channels:stream_tags=language -of json "$FILE_TO_PROCESS" | jq -r '.streams[] | select(.tags.language=="eng") | sort_by(.channels) | reverse | .[0].index' | head -n 1)
        
        # Find Commentary (English, title contains "Commentary", and not the main track)
        COMM_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=index,channels:stream_tags=title,language -of json "$FILE_TO_PROCESS" | jq -r ".streams[] | select(.tags.language==\"eng\" and (.tags.title? | strings | test(\"Commentary\"; \"i\"))) | .index" | head -n 1)
        
        # Fallback for Commentary: If no title match, look for a secondary English stereo track
        if [[ -z "$COMM_AUDIO" ]]; then
            COMM_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=index,channels:stream_tags=language -of json "$FILE_TO_PROCESS" | jq -r ".streams[] | select(.tags.language==\"eng\" and .channels==2 and .index != $MAIN_AUDIO) | .index" | head -n 1)
        fi

        # Adjust for HandBrake (HB uses 1-based indexing)
        HB_MAIN=$((MAIN_AUDIO + 1))
        
        if [[ -n "$COMM_AUDIO" && "$COMM_AUDIO" != "$MAIN_AUDIO" ]]; then
            HB_COMM=$((COMM_AUDIO + 1))
            AUDIO_PARAMS="--audio $HB_MAIN,$HB_COMM --aencoder ac3,ac3 --ab 640,192 --mixdown 5point1,stereo --aname Main,Commentary"
            log "ℹ️ Found Main (Track $HB_MAIN) and Commentary (Track $HB_COMM)"
        else
            AUDIO_PARAMS="--audio $HB_MAIN --aencoder ac3 --ab 640 --mixdown 5point1 --aname Main"
            log "ℹ️ Found Main (Track $HB_MAIN). No commentary detected."
        fi

        # 4. Determine Video Preset
        LOWER_FILENAME=$(echo "$FILENAME" | tr '[:upper:]' '[:lower:]')
        if [[ "$LOWER_FILENAME" =~ "2160p" ]]; then PRESET="$PRESET_4K"
        elif [[ "$LOWER_FILENAME" =~ "1080p.x265" ]]; then PRESET="$PRESET_1080P_X265"
        elif [[ "$LOWER_FILENAME" =~ "1080p" ]]; then PRESET="$PRESET_1080P"
        elif [[ "$LOWER_FILENAME" =~ "720p" ]]; then PRESET="$PRESET_720P"
        else PRESET="$PRESET_SD"; fi

        # 5. Transcode
        HandBrakeCLI \
            --preset "$PRESET" \
            -q 24.0 \
            -i "$FILE_TO_PROCESS" \
            -o "$TEMP_OUTPUT" \
            $AUDIO_PARAMS \
            --subtitle none \
            --optimize < /dev/null

        # 6. Final Remux with SRT
        if [[ -f "$TEMP_OUTPUT" ]]; then
            if [ "$HAS_SUBTITLES" = true ]; then
                log "ℹ️ Remuxing clean SRT into final container..."
                mkvmerge -o "$FINAL_OUTPUT" \
                    --no-subtitles "$TEMP_OUTPUT" \
                    --language 0:eng --track-name 0:"Forced" --forced-track 0:yes --default-track 0:yes "$SUB_FILE"
            else
                mv "$TEMP_OUTPUT" "$FINAL_OUTPUT"
            fi
        fi

        # 7. Post-Processing & Cleanup
        if [[ -f "$FINAL_OUTPUT" ]]; then
            log "✅ Completed $FILENAME"
            rm -f "$FILE_TO_PROCESS" "$TEMP_OUTPUT"
            sonos_audio_fix "$FINAL_OUTPUT"  
            mv "$FINAL_OUTPUT" "$DIR_MEDIA_COMPLETED_TV/"
            mv "$SOURCE_FILE" "$DIR_MEDIA_FINISHED/$BASE_NAME-$TIMESTAMP.$EXTENSION"
            manage_remote_torrent "delete" "$BASE_NAME"
        else
            log "❌ Conversion failed for $FILENAME"
            rm -f "$TEMP_OUTPUT" "$FINAL_OUTPUT"
        fi
    done

    sleep "$POLL_INTERVAL"
done
