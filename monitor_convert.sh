#!/bin/bash

# Monitors a folder looking for unconverted Linux ISOs, copies them to a local folder,
# determines whether the file is 1080p or 4K and converts the file using HandBrakeCLI
# before copying back to the network for further sorting.

# --- Configuration ---
HOST=$(hostname -s)
SOURCE_DIR="/mnt/media/torrent/${HOST}_convert"
CONVERT_DIR="/home/pi/convert"
WORKING_DIR="/home/pi/${HOST}_done" 
SUBTITLE_DIR="/mnt/media/backup/subtitles"
FINISHED_DIR="/mnt/media/torrent/finished"
COMPLETED_DIR="/mnt/media/torrent/completed"
LOG_FILE="/mnt/media/torrent/${HOST}_monitor_convert.log"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")

# HandBrake Presets (Using system presets)
PRESET_4K="H.265 MKV 2160p60"
PRESET_1080P="Very Fast 1080p30"

# File types to process (no variable needed when using -iname)
POLL_INTERVAL=30
MIN_FILE_AGE=5 

# --- Setup Directories ---
mkdir -p "$SOURCE_DIR" "$CONVERT_DIR" "$WORKING_DIR" "$SUBTITLE_DIR" "$FINISHED_DIR"

# Check if 'jq' command is already available
if command -v jq >/dev/null 2>&1; then
    echo "✅ 'jq' is already installed. Proceeding with JSON processing."
    return 0
else
    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing 'jq' via apt-get..."
        sudo apt-get update && sudo apt-get install -y jq
    fi
fi

# --- Logging Function ---
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "--- Polling Conversion Monitor Started ---"

# --- Main Monitoring Loop (Polling) ---
while true; do
    log "Polling $SOURCE_DIR for video files (age > ${MIN_FILE_AGE}m)..."

    # --- Cleanup local Directories ---
    rm $CONVERT_DIR/*
    rm $WORKING_DIR/*

    # Use 'find' with -name filters
    find "$SOURCE_DIR" -type f \
        -mmin +$MIN_FILE_AGE \
        \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.flv" -o -iname "*.webm" \) \
        -print0 | while IFS= read -r -d $'\0' SOURCE_FILE; do
        
        # Get filename and base name
        FILENAME=$(basename "$SOURCE_FILE")
        BASE_NAME="${FILENAME%.*}"
        EXTENSION="${FILENAME##*.}"
        
        log "✅ Detected video file: $FILENAME"

        # --- 1.5. Extract English Forced Subtitles and copy to $SUBTITLE_DIR ---
        SUB_FILE="$SUBTITLE_DIR/$BASE_NAME.srt"
        log "   -> Checking for English forced subtitles..."
        TRACK_INFO=$(mkvmerge -J "$SOURCE_FILE" 2>/dev/null)
        SUB_TRACK_ID=$(echo "$TRACK_INFO" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)
        echo "Extracted Forced Track ID: $SUB_TRACK_ID"

        if [[ -n "$SUB_TRACK_ID" ]]; then
            log "   -> English Forced subtitle track found (ID: $SUB_TRACK_ID). Extracting to $SUB_FILE..."
            mkvextract tracks "$SOURCE_FILE" "$SUB_TRACK_ID:$SUB_FILE"
            if [[ $? -eq 0 ]]; then
                log "   -> Subtitles extracted successfully."
                SUB_FILE_EXTRACTED=true
            else
                log "   -> WARNING: Subtitle extraction failed. Will NOT embed subtitles."
            fi
        else
            log "   -> No suitable English forced subtitle track found in the source file."
        fi
        
        # --- 2. Copy the file to the conversion folder ---
        log "   -> Copying to $CONVERT_DIR..."
        #rsync -rPt --chmod=ugo+rwX "$SOURCE_FILE" "$CONVERT_DIR/"
        #RSYNC_EXIT_CODE=$?
        cp "$SOURCE_FILE" "$CONVERT_DIR/"

        #if [[ $RSYNC_EXIT_CODE -ne 0 ]]; then
        #    log "   -> 🛑 FATAL ERROR: rsync failed with exit code $RSYNC_EXIT_CODE. Skipping."
        #    continue # Skip to the next file in the loop
        #fi
        #log "   -> rsync completed successfully."
        
        FILE_TO_PROCESS="$CONVERT_DIR/$FILENAME"
        OUTPUT_FILE="$WORKING_DIR/$BASE_NAME.mkv"
        
        # *** Robust Check to prevent HandBrake Exit Code 3 ***
        if [[ ! -f "$FILE_TO_PROCESS" ]]; then
            log "   -> 🛑 FATAL ERROR: Local copy file $FILE_TO_PROCESS does not exist after rsync. Skipping."
            continue 
        fi
        if [[ ! -r "$FILE_TO_PROCESS" ]]; then
            log "   -> 🛑 FATAL ERROR: Local copy file $FILE_TO_PROCESS is not readable by script user. Skipping."
            continue 
        fi
        log "   -> Local copy confirmed and readable."
        
        # Reset HandBrake subtitle argument.
        HANDBRAKE_SUB_ARGS=""
        SUB_FILE_EXTRACTED=false

        # --- 3. Extract English Forced Subtitles and copy to $SUBTITLE_DIR ---
        SUB_FILE="$SUBTITLE_DIR/$BASE_NAME.srt"
        log "   -> Checking for English forced subtitles..."
        
        TRACK_INFO=$(mkvmerge -J "$FILE_TO_PROCESS" 2>/dev/null)
#        SUB_TRACK_ID=$(echo "$TRACK_INFO" | grep -E "Track ID [0-9]+: subtitles.*language:eng.*forced" | head -n 1 | awk '{print $3}' | sed 's/://')
#        SUB_TRACK_ID=$(echo "$TRACK_INFO" | grep -E "Track ID [0-9]+: subtitles.*language:eng.*forced track" | head -n 1 | awk '{print $3}' | sed 's/://')
        SUB_TRACK_ID=$(echo "$TRACK_INFO" | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)
        echo "Extracted Forced Track ID: $SUB_TRACK_ID"

        if [[ -n "$SUB_TRACK_ID" ]]; then
            log "   -> English Forced subtitle track found (ID: $SUB_TRACK_ID). Extracting to $SUB_FILE..."
            mkvextract tracks "$FILE_TO_PROCESS" "$SUB_TRACK_ID:$SUB_FILE"
            
            if [[ $? -eq 0 ]]; then
                log "   -> Subtitles extracted successfully."
                HANDBRAKE_SUB_ARGS="--srt-file \"$SUB_FILE\" --srt-codeset UTF-8 --native-language eng --subtitle-default 1 --subtitle-forced 1 --subname "Forced""
                SUB_FILE_EXTRACTED=true
            else
                log "   -> WARNING: Subtitle extraction failed. Will NOT embed subtitles."
            fi
        else
            log "   -> No suitable English forced subtitle track found in the source file."
        fi

        # --- 4. Determine Resolution and Preset (FIXED: -P removed) ---
        
#        log "   -> Scanning file resolution..."

        # Capture the scan output without the erroneous -P flag
#        SCAN_OUTPUT=$(HandBrakeCLI --scan -i "$FILE_TO_PROCESS" 2>/dev/null) 

        # Extract height using a robust method
#        VIDEO_HEIGHT=$(echo "$SCAN_OUTPUT" | grep -E 'size: [0-9]+x[0-9]+|height: [0-9]+' | head -n 1 | sed -E 's/.*size: [0-9]+x([0-9]+).*/\1/' | awk -F'height: ' '{print $2}' | tr -d '[:space:]')
        
#        if ! [[ "$VIDEO_HEIGHT" =~ ^[0-9]+$ ]]; then
#            log "   -> 🛑 WARNING: Failed to extract height. Assuming 1080p for conversion."
#            VIDEO_HEIGHT=1080 # Set a default to ensure the script doesn't crash
#        fi
        
#        if [[ "$VIDEO_HEIGHT" -ge 2160 ]]; then
#            PRESET="$PRESET_4K"
#            log "   -> Detected 4K resolution ($VIDEO_HEIGHT). Using preset: $PRESET_4K"
#        else
#            PRESET="$PRESET_1080P"
#            log "   -> Detected HD/lower resolution ($VIDEO_HEIGHT). Using preset: $PRESET_1080P"
#        fi

        log "   -> Determining preset based on filename content..."
        
        # Convert filename to lowercase for case-insensitive check
        LOWER_FILENAME=$(echo "$FILENAME" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$LOWER_FILENAME" =~ "2160p" ]]; then
            PRESET="$PRESET_4K"
            log "   -> Filename contains '2160p'. Using preset: $PRESET_4K (4K)"
        else
            PRESET="$PRESET_1080P"
            log "   -> Filename does not contain '2160p'. Using preset: $PRESET_1080P (1080p default)"
        fi

        # --- 5. Convert with HandBrakeCLI ---
        log "   -> Starting HandBrake conversion with preset: $PRESET..."

        HandBrakeCLI \
            --preset "$PRESET" \
            -i "$FILE_TO_PROCESS" \
            -o "$OUTPUT_FILE" \
            --aencoder copy --audio-copy-mask aac,ac3,eac3,truehd,dts,dtshd,mp3,flac \
            --audio-fallback aac \
            --optimize \
            $HANDBRAKE_SUB_ARGS 

	    if [[ -n "$HANDBRAKE_SUB_ARGS" ]]; then
	        mkvpropedit "$OUTPUT_FILE" --edit track:s1 --set name="Forced"
	    fi

        CONVERSION_EXIT_CODE=$?

        # --- 6. Post-Conversion Cleanup and Move ---
        if [[ $CONVERSION_EXIT_CODE -eq 0 ]]; then
            log "   -> Conversion completed successfully. Output file: $OUTPUT_FILE"
            
            # Move the completed file to the completed folder
            mv "$OUTPUT_FILE" "$COMPLETED_DIR/"
            log "   -> Moved completed file to $COMPLETED_DIR."

            # Cleanup only if conversion was successful
            rm -f "$FILE_TO_PROCESS"
            log "   -> Deleted temporary copy in $CONVERT_DIR."

            # Delete the temporary .srt file (if it was created)
            if $SUB_FILE_EXTRACTED ; then
                log "   -> Deleting temporary SRT file from working directory: $SUB_FILE"
                rm -f "$SUB_FILE"
            fi

            # Move the original file to the finished folder
#            mv "$SOURCE_FILE" "$FINISHED_DIR/"
#            log "   -> Moved original file to $FINISHED_DIR."
            mv "$SOURCE_FILE" "$FINISHED_DIR/$BASE_NAME-$TIMESTAMP.$EXTENSION"
            log "   -> Moved original file to $FINISHED_DIR/$BASE_NAME_$TIMESTAMP.$EXTENSION."
            
        else
            log "   -> 🛑 ERROR: HandBrake conversion failed with exit code $CONVERSION_EXIT_CODE for $FILENAME."
            # Clean up working file if conversion failed
            rm -f "$OUTPUT_FILE"
            log "   -> Cleaned up failed output file."
        fi
            
    done
    
    # Wait for the next poll cycle
    sleep "$POLL_INTERVAL"
done
