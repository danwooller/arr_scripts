#!/bin/bash

# --- Setup & Includes ---
source "/usr/local/bin/common_functions.sh"

# Configuration
SOURCE_DIR="/mnt/media/TV/"

# Enable recursive globbing
shopt -s globstar

check_dependencies "jq"

for file in "$SOURCE_DIR"/**/*.mkv; do
    [[ -e "$file" ]] || continue
    
    echo "Scanning: $(basename "$file")"

    # Get track info in JSON format
    json_info=$(mkvmerge -J "$file")

    # Build the mkvpropedit command string
    cmd_args=()

    # 1. Identify Audio tracks where language is 'und'
    # '.[0]' refers to the first track type found, etc. 
    # This loop finds the track ID (not the track number) for mkvpropedit
    while read -r track_id; do
        if [[ -n "$track_id" ]]; then
            cmd_args+=("--edit" "track:=$track_id" "--set" "language=eng")
        fi
    done < <(echo "$json_info" | jq -r '.tracks[] | select(.type=="audio" and (.properties.language=="und" or .properties.language==null)) | .id')

    # 2. Identify ALL Subtitle tracks to set to English
    while read -r track_id; do
        if [[ -n "$track_id" ]]; then
            cmd_args+=("--edit" "track:=$track_id" "--set" "language=eng")
        fi
    done < <(echo "$json_info" | jq -r '.tracks[] | select(.type=="subtitles") | .id')

    # Execute if we found tracks to update
    if [ ${#cmd_args[@]} -gt 0 ]; then
        echo "Updating metadata for tracks: ${cmd_args[*]}"
        mkvpropedit "$file" "${cmd_args[@]}"
    else
        echo "No 'und' audio or missing subtitle tags found. Skipping."
    fi

    echo "---"
done

echo "Batch processing complete."
