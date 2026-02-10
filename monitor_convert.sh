#!/bin/bash

# Monitors a folder looking for unconverted Linux ISOs, copies them to a local folder,
# determines whether the file is 1080p or 4K and converts the file using HandBrakeCLI
# before copying back to the network for further sorting.

# --- Configuration ---
HOST=$(hostname -s)
SOURCE_DIR="/mnt/media/torrent/${HOST}_convert"
if [[ $HOST == "pi"* ]]; then
    HOME_DIR="/home/pi"
else
    HOME_DIR="/home/dan"
fi
CONVERT_DIR="$HOME/convert"
WORKING_DIR="$HOME/${HOST}_done"
SUBTITLE_DIR="/mnt/media/backup/subtitles"
FINISHED_DIR="/mnt/media/torrent/finished"
COMPLETED_DIR="/mnt/media/torrent/completed"
LOG_FILE="/mnt/media/torrent/${HOST}.log"
#LOG_LEVEL="debug"
TIMESTAMP=$(date +"%H-%M")

# HandBrake Presets (Using system presets)
PRESET_4K="H.265 MKV 2160p60"
PRESET_1080P="Very Fast 1080p30"
PRESET_1080P_X265="H.265 MKV 1080p30"
PRESET_720p="Very Fast 720p30"
PRESET_576p="Very Fast 576p25"
PRESET_SD="Very Fast 480p30"

# File types to process (no variable needed when using -iname)
POLL_INTERVAL=30
MIN_FILE_AGE=5 

# --- Logging Function ---
log() {
#    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    echo "$(date +'%H:%M'): $1" | tee -a "$LOG_FILE"
}

# --- Setup Directories ---
mkdir -p "$SOURCE_DIR" "$CONVERT_DIR" "$WORKING_DIR" "$SUBTITLE_DIR" "$FINISHED_DIR"

# Check if 'HandBrakeCLI' command is already available
if command -v HandBrakeCLI >/dev/null 2>&1; then
    log "✅ 'HandBrakeCLI' is already installed. Proceeding."
    return 0
else
    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing 'HandBrakeCLI' via apt-get..."
        sudo apt-get update && sudo apt-get install -y handbrake-cli
    fi
fi

# Check if 'mkvmerge' command is already available
if command -v mkvmerge >/dev/null 2>&1; then
    log "✅ 'mkvmerge' is already installed. Proceeding."
    return 0
else
    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing 'mkvmerge' via apt-get..."
        sudo apt-get update && sudo apt-get install -y mkvmerge
    fi
fi

# Check if 'jq' command is already available
if command -v jq >/dev/null 2>&1; then
    log "✅ 'jq' is already installed. Proceeding with JSON processing."
    return 0
else
    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing 'jq' via apt-get..."
        sudo apt-get update && sudo apt-get install -y jq
    fi
fi

log "--- HandBrake Converter started ---"

# --- Main Monitoring Loop (Polling) ---
while true; do
    if [[ $LOG_LEVEL = "debug" ]]; then
        log "Polling $SOURCE_DIR for video files (age > ${MIN_FILE_AGE}m)..."
    fi

    # --- Cleanup local Directories ---
    rm -f $CONVERT_DIR/*
    rm -f $WORKING_DIR/*

    # Use 'find' with -name filters
    find "$SOURCE_DIR" -type f \
        -mmin +$MIN_FILE_AGE \
        \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.flv" -o -iname "*.webm" \) \
        -print0 | while IFS= read -r -d $'\0' SOURCE_FILE; do
        
        # Get filename and base name
        FILENAME=$(basename "$SOURCE_FILE")
        BASE_NAME="${FILENAME%.*}"
        EXTENSION="${FILENAME##*.}"
        
        #if [[ $LOG_LEVEL = "debug" ]]; then
            log "✅ Detected video file: $FILENAME"
        #fi

        # --- 1. Extract English Forced Subtitles and copy to $SUBTITLE_DIR ---
        SUB_FILE="$SUBTITLE_DIR/$BASE_NAME.srt"
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "   -> Checking for English forced subtitles..."
        fi
        TRACK_INFO=$(mkvmerge -J "$SOURCE_FILE" 2>/dev/null)
        SUB_TRACK_ID=$(echo "$TRACK_INFO" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)
        echo "Extracted Forced Track ID: $SUB_TRACK_ID"

        if [[ -n "$SUB_TRACK_ID" ]]; then
            #if [[ $LOG_LEVEL = "debug" ]]; then
                #log "   -> English Forced subtitle track found (ID: $SUB_TRACK_ID). Extracting to $SUB_FILE..."
                log "   -> Forced subtitles (ID: $SUB_TRACK_ID): $BASE_NAME..."
            #fi
            mkvextract tracks "$SOURCE_FILE" "$SUB_TRACK_ID:$SUB_FILE"
            if [[ $? -eq 0 ]]; then
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Subtitles extracted successfully."
            fi
                SUB_FILE_EXTRACTED=true
            else
                if [[ $LOG_LEVEL = "debug" ]]; then
                    log "   -> WARNING: Subtitle extraction failed. Will NOT embed subtitles."
                fi
            fi
        else
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> No suitable English forced subtitle track found in the source file."
            fi
        fi
        
        # --- 2. Copy the file to the conversion folder ---
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Copying to $CONVERT_DIR..."
            fi

        #Copying to local directory.
        cp "$SOURCE_FILE" "$CONVERT_DIR/"
        
        FILE_TO_PROCESS="$CONVERT_DIR/$FILENAME"
        OUTPUT_FILE="$WORKING_DIR/$BASE_NAME.mkv"
        
        # *** Robust Check to prevent HandBrake Exit Code 3 ***
        if [[ ! -f "$FILE_TO_PROCESS" ]]; then
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> 🛑 FATAL ERROR: Local copy file $FILE_TO_PROCESS does not exist after rsync. Skipping."
            fi
            continue 
        fi
        if [[ ! -r "$FILE_TO_PROCESS" ]]; then
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> 🛑 FATAL ERROR: Local copy file $FILE_TO_PROCESS is not readable by script user. Skipping."
            fi
            continue 
        fi
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Local copy confirmed and readable."
            fi
        
        # Reset HandBrake subtitle argument.
        HANDBRAKE_SUB_ARGS=""
        SUB_FILE_EXTRACTED=false

        # --- 3. Extract English Forced Subtitles and copy to $SUBTITLE_DIR ---
        SUB_FILE="$SUBTITLE_DIR/$BASE_NAME.srt"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Checking for English forced subtitles..."
            fi
        
        TRACK_INFO=$(mkvmerge -J "$FILE_TO_PROCESS" 2>/dev/null)
        SUB_TRACK_ID=$(echo "$TRACK_INFO" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)
        echo "Extracted Forced Track ID: $SUB_TRACK_ID"

        if [[ -n "$SUB_TRACK_ID" ]]; then
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> English Forced subtitle track found (ID: $SUB_TRACK_ID). Extracting to $SUB_FILE..."
            fi
            mkvextract tracks "$FILE_TO_PROCESS" "$SUB_TRACK_ID:$SUB_FILE"
            
            if [[ $? -eq 0 ]]; then
                if [[ $LOG_LEVEL = "debug" ]]; then
                    log "   -> Subtitles extracted successfully."
                fi
                HANDBRAKE_SUB_ARGS="--srt-file \"$SUB_FILE\" --srt-codeset UTF-8 --native-language eng --subtitle-default 1 --subtitle-forced 1 --subname "Forced""
                SUB_FILE_EXTRACTED=true
            else
                if [[ $LOG_LEVEL = "debug" ]]; then
                    log "   -> WARNING: Subtitle extraction failed. Will NOT embed subtitles."
                fi
            fi
        else
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> No suitable English forced subtitle track found in the source file."
            fi
        fi

        if [[ $LOG_LEVEL = "debug" ]]; then
            log "   -> Determining preset based on filename content..."
        fi
        
        # Convert filename to lowercase for case-insensitive check
        LOWER_FILENAME=$(echo "$FILENAME" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$LOWER_FILENAME" =~ "2160p" ]]; then
            PRESET="$PRESET_4K"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Filename contains '2160p'. Using preset: $PRESET_4K"
            fi
        elif [[ "$LOWER_FILENAME" =~ "1080p.x265" ]]; then
            PRESET="$PRESET_1080P_X265"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Filename contains '1080p.x265'. Using preset: $PRESET_1080P_X265"
            fi
        elif [[ "$LOWER_FILENAME" =~ "1080p" ]]; then
            PRESET="$PRESET_1080P"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Filename contains '1080p'. Using preset: $PRESET_1080P"
            fi
        elif [[ "$LOWER_FILENAME" =~ "720p" ]]; then
            PRESET="$PRESET_720P"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Filename contains '720p'. Using preset: $PRESET_720P"
            fi
        elif [[ "$LOWER_FILENAME" =~ "576p" ]]; then
            PRESET="$PRESET_576P"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Filename contains '576p'. Using preset: $PRESET_576P"
            fi
        else
            PRESET="$PRESET_SD"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Filename does not contain '2160p', '1080p', '720p' or '576p'. Using preset: $PRESET_SD"
            fi
        fi

        # --- 5. Convert with HandBrakeCLI ---
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "   -> Starting HandBrake conversion with preset: $PRESET..."
        fi

        HandBrakeCLI \
            --preset "$PRESET" \
            -q 24.0 \
            -i "$FILE_TO_PROCESS" \
            -o "$OUTPUT_FILE" \
            --audio-lang-list eng \
            --aencoder copy --audio-copy-mask aac,ac3,eac3,truehd,dts,dtshd,mp3,flac \
            --audio-fallback aac \
            --optimize \
            $HANDBRAKE_SUB_ARGS 

        #Set the subtitle name.
        if [[ -n "$HANDBRAKE_SUB_ARGS" ]]; then
            mkvpropedit "$OUTPUT_FILE" --edit track:s1 --set name="Forced" --set language=eng
        fi

        CONVERSION_EXIT_CODE=$?

        # --- 6. Post-Conversion Cleanup and Move ---
        if [[ $CONVERSION_EXIT_CODE -eq 0 ]]; then
            #if [[ $LOG_LEVEL = "debug" ]]; then
                #log "   -> Conversion completed successfully. Output file: $OUTPUT_FILE"
                log "   -> Conversion complete: $FILENAME"
            #fi
            
            # Move the completed file to the completed folder
            mv "$OUTPUT_FILE" "$COMPLETED_DIR/"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Moved completed file to $COMPLETED_DIR."
            fi

            # Cleanup only if conversion was successful
            rm -f "$FILE_TO_PROCESS"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Deleted temporary copy in $CONVERT_DIR."
            fi

            # Move the original file to the finished folder
            mv "$SOURCE_FILE" "$FINISHED_DIR/$BASE_NAME-$TIMESTAMP.$EXTENSION"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Moved original file to $FINISHED_DIR/$BASE_NAME_$TIMESTAMP.$EXTENSION."
            fi
            
        else
            log "   -> 🛑 ERROR: HandBrake conversion failed with exit code $CONVERSION_EXIT_CODE for $FILENAME."
            # Clean up working file if conversion failed
            rm -f "$OUTPUT_FILE"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "   -> Cleaned up failed output file."
            fi
        fi
            
    done
    
    # Wait for the next poll cycle
    sleep "$POLL_INTERVAL"
done
