#!/bin/bash

# --- Configuration ---
# Get the current hostname dynamically
HOST_NAME=$(hostname)

# Directory containing the MP4/MKV files to check
CONVERT_DIR="/mnt/media/torrent/${HOST_NAME}_convert"

# Directory containing the metadata text files (NZB folder)
NZB_DIR="/mnt/media/torrent/nzb"

# Ensure script exits immediately if any command fails
set -e

echo "--- Starting Media Renamer Script (Continuous Mode) ---"
echo "Target Video Directory: $CONVERT_DIR"
echo "Metadata Directory: $NZB_DIR"
echo "Sleep interval: 60 seconds"
echo "-------------------------------------------------------"

# Check if the directories exist outside the loop to avoid repeated checks
if [[ ! -d "$CONVERT_DIR" ]]; then
    echo "Error: Video directory not found: $CONVERT_DIR" >&2
    exit 1
fi
if [[ ! -d "$NZB_DIR" ]]; then
    echo "Error: Metadata directory not found: $NZB_DIR" >&2
    exit 1
fi

# Main infinite loop for continuous monitoring
while true; do
    
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    echo "--- Starting scan at $TIMESTAMP ---"
    
    # Use find to locate all .mp4 and .mkv files in the convert directory recursively.
    # We use -print0 and a while loop to safely handle filenames with spaces or special characters.
    find "$CONVERT_DIR" -type f \( -iname "*.mp4" -o -iname "*.mkv" \) -print0 | while IFS= read -r -d $'\0' FULL_PATH; do
        
        # Extract the full filename (with extension)
        FILENAME_WITH_EXT=$(basename "$FULL_PATH")
        
        # Extract the base filename (without extension)
        BASE_NAME="${FILENAME_WITH_EXT%.*}"
        
        # Extract the file extension
        EXTENSION="${FILENAME_WITH_EXT##*.}"

        echo "Processing: $FILENAME_WITH_EXT"

        # --- 1. Filtering: Check if the base name contains a period (.) or an underscore (_) ---
        # We check the BASE_NAME (without extension) to maintain the original filtering logic.
        if [[ "$BASE_NAME" =~ [._] ]]; then
            echo "  -> SKIPPING: Filename contains a period (.) or an underscore (_)."
            continue
        fi
        
        echo "  -> Passed filter. Searching for metadata..."

        # --- 2. Search for metadata match in NZB_DIR ---
        
        # Use grep -r to search recursively, -l to list matching files, and -F for fixed string matching.
        # The title tag must exactly match the full filename (including extension).
        # We limit results to the first file found using head -n 1.
        METADATA_FILE=$(grep -r -l -F "<meta type=\"title\">$FILENAME_WITH_EXT</meta>" "$NZB_DIR" 2>/dev/null | head -n 1)

        if [[ -n "$METADATA_FILE" ]]; then
            echo "  -> MATCH FOUND in $METADATA_FILE"
            
            # Extract the content (the new filename) found between <meta type="name">...</meta> tags.
            # *** ROBUST FIX: Use grep with PCRE (-oP) for precise, non-greedy tag content extraction. ***
            # This reliably grabs the content even if other tags are on the same line.
            NEW_NAME_RAW=$(grep -oP '(?<=<meta type="name">).*?(?=</meta>)' "$METADATA_FILE" | head -n 1)

            if [[ -n "$NEW_NAME_RAW" ]]; then
                
                # --- 3. Sanitize the new name ---
                # a) Remove leading/trailing whitespace (sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                # b) Remove newlines/carriage returns (tr -d '\n\r')
                # c) Replace any character that isn't a letter, number, space, or hyphen with an underscore
                NEW_NAME_CLEAN=$(echo "$NEW_NAME_RAW" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d '\n\r' | sed 's/[^a-zA-Z0-9 -]/_/g')

                # Define the new full path
                NEW_FULL_PATH_WITH_EXT="$CONVERT_DIR/$NEW_NAME_CLEAN.$EXTENSION"

                if [[ "$FULL_PATH" != "$NEW_FULL_PATH_WITH_EXT" ]]; then
                    echo "  -> RENAMING: '$FILENAME_WITH_EXT' to '$NEW_NAME_CLEAN.$EXTENSION'"
                    
                    # Use 'mv -n' to prevent overwriting existing files
                    mv -n "$FULL_PATH" "$NEW_FULL_PATH_WITH_EXT"
                    
                    if [ $? -eq 0 ]; then
                        echo "  -> SUCCESS: File renamed."
                    else
                        echo "  -> ERROR: Failed to rename file (perhaps a file with the new name already exists)." >&2
                    fi
                else
                    echo "  -> NO CHANGE: File already matches the new standardized name."
                fi
            else
                echo "  -> WARNING: Metadata file found, but could not extract content from <meta type=\"name\"> tag."
            fi
        else
            echo "  -> No metadata match found in $NZB_DIR for the full filename: $FILENAME_WITH_EXT"
        fi
        echo "-------------------------------------"

    done
    
    echo "--- Scan completed. Sleeping for 60 seconds... ---"
    sleep 60
done
