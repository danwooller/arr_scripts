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
        if [[ -n "$SUB_TRACK_ID" && "$SUB_TRACK_ID" != "null" ]]; then
            log "ℹ️ Converting Forced Subtitle (ID: $SUB_TRACK_ID) to SRT..."
            ffmpeg -i "$FILE_TO_PROCESS" -map 0:"$SUB_TRACK_ID" -c:s srt "$SUB_FILE" -y -loglevel error
            [[ $? -eq 0 ]] && HAS_SUBTITLES=true
        fi

        # 3. Audio Track Detection (Mapping mkvmerge IDs to HandBrake Indices)
        TRACK_JSON=$(mkvmerge -J "$FILE_TO_PROCESS")
        
        # Get list of all audio track IDs in order of appearance
        AUDIO_IDS=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "audio") | .id')

        # Helper to convert mkvmerge ID to HandBrake Index (1-based)
        get_hb_index() {
            local search_id=$1
            local count=1
            for id in $AUDIO_IDS; do
                if [[ "$id" == "$search_id" ]]; then
                    echo "$count"
                    return
                fi
                ((count++))
            done
        }

        # Find Main English Audio ID (Exclude tracks titled "Commentary")
        MAIN_ID=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "audio" and .properties.language == "eng" and (.properties.track_name // "" | test("Commentary"; "i") | not)) | .id' | head -n 1)
        
        # Fallback for Main: If no specific match, take the first audio track ID
        if [[ -z "$MAIN_ID" || "$MAIN_ID" == "null" ]]; then
            MAIN_ID=$(echo "$AUDIO_IDS" | head -n 1)
        fi

        # Find Commentary ID (English + titled "Commentary")
        COMM_ID=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "audio" and .properties.language == "eng" and (.properties.track_name // "" | test("Commentary"; "i"))) | .id' | head -n 1)

        # Resolve Final HandBrake Indices
        HB_MAIN=$(get_hb_index "$MAIN_ID")
        HB_COMM=$(get_hb_index "$COMM_ID")

        if [[ -n "$HB_COMM" && "$HB_COMM" != "$HB_MAIN" ]]; then
            # Both Tracks: Main (5.1) + Commentary (Stereo)
            AUDIO_PARAMS="--audio $HB_MAIN,$HB_COMM --aencoder ac3,ac3 --ab 640,192 --mixdown 5point1,stereo --aname Main,Commentary"
            log "ℹ️ Identified: Main (Track $HB_MAIN) and Commentary (Track $HB_COMM)"
        else
            # Only Main Track
            AUDIO_PARAMS="--audio $HB_MAIN --aencoder ac3 --ab 640 --mixdown 5point1 --aname Main"
            log "ℹ️ Identified: Main (Track $HB_MAIN). No commentary detected."
        fi

        # 4. Determine Video Preset
        LOWER_FILENAME=$(echo "$FILENAME" | tr '[:upper:]' '[:lower:]')
        if [[ "$LOWER_FILENAME" =~ "2160p" ]]; then PRESET="$PRESET_4K"
        elif [[ "$LOWER_FILENAME" =~ "1080p.x265" ]]; then PRESET="$PRESET_1080P_X265"
        elif [[ "$LOWER_FILENAME" =~ "1080p" ]]; then PRESET="$PRESET_1080P"
        elif [[ "$LOWER_FILENAME" =~ "720p" ]]; then PRESET="$PRESET_720P"
        else PRESET="$PRESET_SD"; fi

        # 5. Transcode with HandBrake
        HandBrakeCLI \
            --preset "$PRESET" \
            -q 24.0 \
            -i "$FILE_TO_PROCESS" \
            -o "$TEMP_OUTPUT" \
            $AUDIO_PARAMS \
            --subtitle none \
            --optimize < /dev/null

        # 6. Final Remux: Combine with SRT if available
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
