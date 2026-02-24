#!/bin/bash

# --- Setup & Includes ---
source "/usr/local/bin/common_functions.sh"

# 1. Setup Environment
TARGET_DIR="/mnt/media/torrent/${HOST}/concat"
INPUT_LIST="${TARGET_DIR}/inputs.txt"

# Move to directory
cd "$TARGET_DIR" || { log "Error: Could not enter $TARGET_DIR"; exit 1; }

# 2. Dynamic Naming Logic
# Grab the first mp4 file found in the directory
FIRST_FILE=$(ls *.mp4 | head -n 1)

if [[ -z "$FIRST_FILE" ]]; then
    log "Error: No MP4 files found in $TARGET_DIR"
    exit 1
fi

# Remove extension (.mp4)
BASE_NAME="${FIRST_FILE%.*}"

# Remove the last number (and any spaces/hyphens/underscores preceding it)
# This regex-like expansion [0-9]* matches trailing digits
# The [[:space:]_-]* matches common separators before the number
CLEAN_NAME=$(echo "$BASE_NAME" | sed 's/[[:space:]_-]*[0-9]\+$//')

OUTPUT_FILE="${TARGET_DIR}/${CLEAN_NAME}.mp4"

# 3. Pre-flight Checks
check_dependencies ffmpeg

log "Starting concatenation process for: $CLEAN_NAME"

# 4. Generate the Input List
log "Generating input list..."
# Using printf to ensure filenames with spaces are handled correctly
printf "file '%s'\n" *.mp4 > "$INPUT_LIST"

# 5. Run FFmpeg Concat
log "Running FFmpeg stream copy to $OUTPUT_FILE..."
ffmpeg -f concat -safe 0 -i "$INPUT_LIST" -c copy "$OUTPUT_FILE" -y >> "$LOG_FILE" 2>&1

# 6. Finalize
if [ $? -eq 0 ]; then
    log "Success! Combined file created at $OUTPUT_FILE"
    rm "$INPUT_LIST"
else
    log "Error: FFmpeg concatenation failed. Check $LOG_FILE"
    exit 1
fi
