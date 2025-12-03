#!/bin/bash

# A a bash script for linux that starts in the folder /mnt/media/torrent/$(hostname)_convert,
# looks for subfolders and then looks for mkv and mp4 files one or two folders down
# and renames those files before moving them to /mnt/media/torrent/$(hostname)_convert.
# Processes obfuscated usenet Linux ISOs and renames them to the parent folder.

# --- Configuration ---
# Set the base directory using the current hostname
# Example path: /mnt/media/torrent/myhostname_convert
BASE_DIR="/mnt/media/torrent/$(hostname)_convert"

# Maximum depth for finding files (2 levels deep, e.g., Dir1/Dir2/file.mkv)
# If BASE_DIR is level 0:
# mindepth 2 = BASE_DIR/Subfolder/file
# maxdepth 3 = BASE_DIR/Subfolder/Subfolder/file
SEARCH_DEPTH_MIN=2
SEARCH_DEPTH_MAX=3

# Target directory is the root of the conversion folder
TARGET_DIR="$BASE_DIR"

# --- Functions ---

# Function to safely clean up a filename (removes spaces, special characters, converts to lowercase)
clean_filename() {
    local filename="$1"
    # 1. Remove file extension
    local name_without_ext="${filename%.*}"
    local extension="${filename##*.}"
    
    # 2. Convert to lowercase
    local cleaned_name=$(echo "$name_without_ext" | tr '[:upper:]' '[:lower:]')
    
    # 3. Replace spaces, dots, and common separators with underscores
    cleaned_name=$(echo "$cleaned_name" | sed -E 's/[. ]+/_/g')
    
    # 4. Remove any characters that are not alphanumeric, hyphens, or underscores
    cleaned_name=$(echo "$cleaned_name" | sed -E 's/[^a-z0-9_-]//g')
    
    # 5. Collapse multiple underscores
    cleaned_name=$(echo "$cleaned_name" | sed -E 's/_+/-/g')

    # 6. Reconstruct the full path
    echo "${cleaned_name}.${extension}"
}


# --- Script Execution ---

echo "Starting media organization script..."
echo "Base Directory: $BASE_DIR"

# Check if the base directory exists
if [ ! -d "$BASE_DIR" ]; then
    echo "Error: Base directory $BASE_DIR does not exist. Please create it first."
    exit 1
fi

# Find all .mkv and .mp4 files within the specified depth
# -type f: find files
# \( -name "*.mkv" -o -name "*.mp4" \): find files with either extension
# -mindepth and -maxdepth control the folder structure deep inside $BASE_DIR
# NOTE: -mindepth and -maxdepth are global options and are moved before -type f to silence warnings.
find "$BASE_DIR" -mindepth $SEARCH_DEPTH_MIN -maxdepth $SEARCH_DEPTH_MAX -type f \( -name "*.mkv" -o -name "*.mp4" \) | while IFS= read -r full_path; do
    
    # Check if the file still exists (important if files are moved concurrently)
    if [ ! -f "$full_path" ]; then
        continue
    fi
    
    # Get the original file name and directory
    original_filename=$(basename -- "$full_path")
    original_dir=$(dirname -- "$full_path")
    
    # 1. Generate the cleaned-up target filename
    new_filename=$(clean_filename "$original_filename")
    
    # 2. Define the full path for the destination file
    destination_path="$TARGET_DIR/$new_filename"
    
    echo "Processing: $original_filename in $original_dir"
    echo " -> New Name: $new_filename"
    
    # 3. Execute the move/rename operation
    # Check if the destination file already exists to prevent overwriting
    if [ -f "$destination_path" ]; then
        echo "   [SKIP] Destination file already exists: $destination_path"
    else
        # Use 'mv' to rename and move in one atomic operation
        if mv "$full_path" "$destination_path"; then
            echo "   [SUCCESS] Moved and renamed to: $destination_path"
        else
            echo "   [ERROR] Failed to move $full_path"
        fi
    fi

    # Add a 60-second pause as requested
    echo "   [PAUSE] Pausing for 60 seconds before checking the next file..."
    sleep 60

done

echo "Script completed."
# Optional cleanup: remove empty directories left behind
echo "Cleaning up empty directories..."
find "$BASE_DIR" -depth -type d -empty -exec rmdir {} \; 2>/dev/null
echo "Cleanup finished."
