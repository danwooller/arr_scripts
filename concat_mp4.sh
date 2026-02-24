#!/bin/bash

# --- Setup & Includes ---
source "/usr/local/bin/common_functions.sh"

# 1. Setup Environment
TARGET_DIR="/mnt/media/torrent/${HOST}/concat"
OUTPUT_DIR="/mnt/media/torrent/completed"
FINISHED_DIR="/mnt/media/torrent/finished/"
INPUT_LIST="${TARGET_DIR}/inputs.txt"

# Move to directory
cd "$TARGET_DIR" || { log "Error: Could not enter $TARGET_DIR"; exit 1; }

# 2. Dynamic Naming Logic
FIRST_FILE=$(ls *.mp4 2>/dev/null | head -n 1)

if [[ -z "$FIRST_FILE" ]]; then
    log "No MP4 files found in $TARGET_DIR. Nothing to do."
    exit 0
fi

BASE_NAME="${FIRST_FILE%.*}"
CLEAN_NAME=$(echo "$BASE_NAME" | sed 's/[[:space:]_-]*[0-9]\+$//')
OUTPUT_FILE="${OUTPUT_DIR}/${CLEAN_NAME}.mp4"

# 3. Pre-flight Checks
check_dependencies ffmpeg

log "Starting concatenation for: $CLEAN_NAME"

# 4. Generate the Input List
log "Generating input list..."
printf "file '%s'\n" *.mp4 > "$INPUT_LIST"

# 5. Run FFmpeg Concat
log "Running FFmpeg stream copy to $OUTPUT_FILE..."
ffmpeg -f concat -safe 0 -i "$INPUT_LIST" -c copy "$OUTPUT_FILE" -y >> "$LOG_FILE" 2>&1

# 6. Finalize & Move Files
if [ $? -eq 0 ]; then
    log "Success! Combined file created at $OUTPUT_FILE"
    
    log "Moving source files to $FINISHED_DIR..."
    # Read the input list we made and move each file mentioned
    while IFS= read -r line; do
        # Extract filename between the single quotes
        FILE_TO_MOVE=$(echo "$line" | cut -d"'" -f2)
        mv "$FILE_TO_MOVE" "$FINISHED_DIR"
    done < "$INPUT_LIST"

else
    log "Error: FFmpeg concatenation failed. Check $LOG_FILE"
    exit 1
fi
