#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# scans a direcory and writes the audio codec to a txt file for each media file
TARGET_DIR="/mnt/media/TV"

# Check for dependencies
for cmd in mkvmerge jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

echo "Scanning: $TARGET_DIR"
echo "------------------------------------------------"

find "$TARGET_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) | while read -r file; do
    
    filename=$(basename "$file")
    
    # Extract audio codecs using jq
    # This looks inside 'tracks', filters for type == 'audio', and grabs the 'codec' field
    codecs=$(mkvmerge --identify "$file" --identification-format json | \
             jq -r '.tracks[] | select(.type == "audio") | .codec' | tr '\n' ',' | sed 's/,$//')

    if [ -n "$codecs" ]; then
        echo "$filename: [$codecs]"
    else
        echo "$filename: No audio tracks found"
    fi
done
