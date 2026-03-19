#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

echo "Starting FLAC monitor service..."

# Infinite loop for service persistence
while true; do
    # Create hold directory if it doesn't exist
    mkdir -p "$DIR_MEDIA_HOLD"

    # Find all .flac files
    # Added -maxdepth to avoid infinite recursion if HOLD is inside MUSIC
    find "$DIR_MEDIA_MUSIC" -type f -name "*.flac" | while read -r flac_file; do
        
        # Determine relative path to preserve directory structure
        rel_path="${flac_file#$DIR_MEDIA_MUSIC/}"
        rel_dir=$(dirname "$rel_path")
        
        # Define output mp3 filename
        mp3_file="${flac_file%.flac}.mp3"
        
        # Skip if conversion already happened but original hasn't moved yet
        if [ -f "$mp3_file" ] && [ -f "$DIR_MEDIA_HOLD/$rel_path" ]; then
            continue
        fi

        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Converting: $rel_path"
        
        # Convert to MP3 (-n skips if the mp3 already exists)
        ffmpeg -v error -i "$flac_file" -qscale:a 2 -n "$mp3_file" </dev/null
        
        if [ $? -eq 0 ]; then
            echo "Success. Moving original to hold..."
            mkdir -p "$DIR_MEDIA_HOLD/$rel_dir"
            mv "$flac_file" "$DIR_MEDIA_HOLD/$rel_path"
        else
            echo "Error converting $flac_file. Skipping move."
        fi
    done

    # Sleep interval (e.g., 300 seconds / 5 minutes) to prevent high CPU usage
    sleep "$CHECK_INTERVAL"
done
