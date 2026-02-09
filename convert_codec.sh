#!/bin/bash

# Configuration
SOURCE_DIR="/mnt/media/TV/Dr. Horrible's Sing-Along Blog"
DEST_DIR="/mnt/media/torrent/completed"

# Ensure destination exists
mkdir -p "$DEST_DIR"

# Enable recursive globbing
shopt -s globstar

for file in "$SOURCE_DIR"/**/*.mkv; do
    # Skip if not a file
    [ -e "$file" ] || continue

    # Check if the file contains a DTS audio stream
    if ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file" | grep -qi "dts"; then
        echo "Processing: $file"
        
        # Define output path (flattens structure to DEST_DIR)
        filename=$(basename "$file")
        output="$DEST_DIR/$filename"

        # Convert DTS to EAC3, copy video/subtitles without re-encoding
        ffmpeg -i "$file" -map 0 -c:v copy -c:s copy -c:a eac3 -b:a 640k "$output" -y
    else
        echo "Skipping (No DTS): $file"
    fi
done
