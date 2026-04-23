#!/bin/bash

# Monitors for video files and converts to Sonos-safe AC3.
# Logic: 
# 1. English Main + Forced Subs
# 2. English Main + Commentary + Forced Subs
# 3. No English Audio -> First Audio + First English Subs

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
HOST=$(hostname -s)
SOURCE_DIR="$DIR_MEDIA_TORRENT/${HOST}/${HOST}_convert"
[[ $HOST == "pi"* ]] && HOME_DIR="/home/pi" || HOME_DIR="/home/dan"
CONVERT_DIR="$HOME_DIR/convert"
WORKING_DIR="$HOME_DIR/${HOST}_done"

POLL_INTERVAL=30
MIN_FILE_AGE=5

mkdir -p "$DIR_MEDIA_TORRENT/${HOST}" "$SOURCE_DIR" "$CONVERT_DIR" "$WORKING_DIR" "$DIR_MEDIA_SUBTITLES" "$DIR_MEDIA_FINISHED"
check_dependencies "HandBrakeCLI" "jq" "mkvpropedit" "mkvmerge" "ffprobe"
log_start "$SOURCE_DIR"

while true; do
    rm -f $CONVERT_DIR/* $WORKING_DIR/*
    sonarr_weekly_shows
    find "$SOURCE_DIR" -type f -mmin +$MIN_FILE_AGE \
        \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) \
        -print0 | while IFS= read -r -d $'\0' SOURCE_FILE; do
        FILENAME=$(basename "$SOURCE_FILE")
        BASE_NAME="${FILENAME%.*}"
        EXTENSION="${FILENAME##*.}"
        cp "$SOURCE_FILE" "$CONVERT_DIR/"
        FILE_TO_PROCESS="$CONVERT_DIR/$FILENAME"
        TEMP_OUTPUT="$WORKING_DIR/${BASE_NAME}_temp.mkv"
        FINAL_OUTPUT="$WORKING_DIR/$BASE_NAME.mkv"
        SUB_FILE="$DIR_MEDIA_SUBTITLES/$BASE_NAME.srt"
        # --- Subtitle Logic ---
        TRACK_JSON=$(mkvmerge -J "$FILE_TO_PROCESS")
        # 1. Try Forced English
        SUB_TRACK_ID=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)
        if [[ -n "$SUB_TRACK_ID" && "$SUB_TRACK_ID" != "null" ]]; then
            SUB_NAME="Forced"
        else
            # 2. Check if we need English Audio to decide on Subtitle Fallback
            HAS_ENG_AUDIO=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "audio" and .properties.language == "eng") | .id' | head -n 1)
            
            # 3. If NO English audio exists, Fallback to FIRST English subtitle
            if [[ -z "$HAS_ENG_AUDIO" || "$HAS_ENG_AUDIO" == "null" ]]; then
                SUB_TRACK_ID=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng") | .id' | head -n 1)
                SUB_NAME="English"
            fi
        fi
        
        # 2. Check if we need English Audio to decide on Subtitle Fallback
        HAS_ENG_AUDIO=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "audio" and .properties.language == "eng") | .id' | head -n 1)
        
        # 3. If NO English audio exists, Fallback to FIRST English subtitle
        if [[ -z "$HAS_ENG_AUDIO" || "$HAS_ENG_AUDIO" == "null" ]]; then
            if [[ -z "$SUB_TRACK_ID" || "$SUB_TRACK_ID" == "null" ]]; then
                SUB_TRACK_ID=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng") | .id' | head -n 1)
            fi
        fi

        HAS_SUBTITLES=false
        if [[ -n "$SUB_TRACK_ID" && "$SUB_TRACK_ID" != "null" ]]; then
            log "ℹ️ Extracting English Subtitle (ID: $SUB_TRACK_ID)..."
            ffmpeg -i "$FILE_TO_PROCESS" -map 0:"$SUB_TRACK_ID" -c:s srt "$SUB_FILE" -y -loglevel error
            [[ $? -eq 0 ]] && HAS_SUBTITLES=true
        fi

        # --- Audio Logic ---
        AUDIO_IDS=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "audio") | .id')
        get_hb_index() {
            local search_id=$1; local count=1
            for id in $AUDIO_IDS; do [[ "$id" == "$search_id" ]] && echo "$count" && return; ((count++)); done
        }

        # Find Main English (No Commentary)
        MAIN_ID=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "audio" and .properties.language == "eng" and (.properties.track_name // "" | test("Commentary"; "i") | not)) | .id' | head -n 1)
        
        # Universal Fallback (Option 3)
        if [[ -z "$MAIN_ID" || "$MAIN_ID" == "null" ]]; then
            MAIN_ID=$(echo "$AUDIO_IDS" | head -n 1)
        fi

        # Find Commentary (English only)
        COMM_ID=$(echo "$TRACK_JSON" | jq -r '.tracks[] | select(.type == "audio" and .properties.language == "eng" and (.properties.track_name // "" | test("Commentary"; "i"))) | .id' | head -n 1)

        HB_MAIN=$(get_hb_index "$MAIN_ID")
        HB_COMM=$(get_hb_index "$COMM_ID")

        if [[ -n "$HB_COMM" && "$HB_COMM" != "$HB_MAIN" ]]; then
            AUDIO_PARAMS="--audio $HB_MAIN,$HB_COMM --aencoder ac3,ac3 --ab 640,192 --mixdown 5point1,stereo --aname English,Commentary"
        else
            AUDIO_PARAMS="--audio $HB_MAIN --aencoder ac3 --ab 640 --mixdown 5point1 --aname English"
        fi

        # --- Preset & Transcode ---
        LOWER_FILENAME=$(echo "$FILENAME" | tr '[:upper:]' '[:lower:]')
        if [[ "$LOWER_FILENAME" =~ "2160p" ]]; then PRESET="$PRESET_4K"
        elif [[ "$LOWER_FILENAME" =~ "1080p.x265" ]]; then PRESET="$PRESET_1080P_X265"
        elif [[ "$LOWER_FILENAME" =~ "1080p" ]]; then PRESET="$PRESET_1080P"
        else PRESET="$PRESET_SD"; fi

        HandBrakeCLI --preset "$PRESET" -q 24.0 -i "$FILE_TO_PROCESS" -o "$TEMP_OUTPUT" $AUDIO_PARAMS --subtitle none --optimize < /dev/null

        # --- Remux ---
        if [[ -f "$TEMP_OUTPUT" ]]; then
            if [ "$HAS_SUBTITLES" = true ] && [[ -f "$SUB_FILE" ]]; then
                log "ℹ️ Remuxing forced subtitles into $FILENAME"
                # We use a temporary log to catch mkvmerge errors without stopping the script
                mkvmerge -o "$FINAL_OUTPUT" --no-subtitles "$TEMP_OUTPUT" \
                    --language 0:eng --track-name 0:"$SUB_NAME" \
                    --forced-display 0:"$FORCED_FLAG" --default-track 0:"$FORCED_FLAG" \
                    "$SUB_FILE" > /tmp/mkvmerge_last_run.log 2>&1
                
                # Check if mkvmerge actually created the file
                if [[ ! -f "$FINAL_OUTPUT" ]]; then
                    log "❌ mkvmerge failed (forced subs). Check /tmp/mkvmerge_last_run.log"
                    log "⚠️ Moving original source to HOLD for manual review."
                    mv "$SOURCE_FILE" "$DIR_MEDIA_HOLD/"
                    seerr_sync_issue "$BASE_NAME" "tv"
                    rm -f "$TEMP_OUTPUT" "$FILE_TO_PROCESS"
                    continue # Move to next file in the loop
                fi
            else
                mv "$TEMP_OUTPUT" "$FINAL_OUTPUT"
            fi

            # Audio Normalization
            sonos_audio_fix "$FINAL_OUTPUT"

            # --- The Critical Ingest Move ---
            if [[ -d "$DIR_MEDIA_COMPLETED_TV" ]]; then
                if mv "$FINAL_OUTPUT" "$DIR_MEDIA_COMPLETED_TV/"; then
                    log "✨ Successfully moved: $FILENAME"
                    # Only now do we clear the source and the torrent
                    mv "$SOURCE_FILE" "$DIR_MEDIA_FINISHED/$BASE_NAME-$(date +%H%M).$EXTENSION"
                    manage_remote_torrent "delete" "$BASE_NAME"
                    rm -f "$FILE_TO_PROCESS" "$TEMP_OUTPUT" "$SUB_FILE"
                else
                    log "❌ Move to Ingest FAILED. Sending source to HOLD."
                    mv "$SOURCE_FILE" "$DIR_MEDIA_HOLD/"
                    seerr_sync_issue "$BASE_NAME" "tv"
                    # Clean up working files but keep the source safe in HOLD
                    rm -f "$FILE_TO_PROCESS" "$TEMP_OUTPUT" "$FINAL_OUTPUT"
                fi
            else
                log "🚨 DIR_MEDIA_COMPLETED_TV ($DIR_MEDIA_COMPLETED_TV) NOT FOUND."
                mv "$SOURCE_FILE" "$DIR_MEDIA_HOLD/"
                seerr_sync_issue "$BASE_NAME" "tv"
                rm -f "$FILE_TO_PROCESS" "$TEMP_OUTPUT" "$FINAL_OUTPUT"
            fi
        fi
    done
    sleep "$POLL_INTERVAL"
done
