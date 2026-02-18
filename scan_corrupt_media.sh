#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# Run dependency check from shared library
# Ensure 'ffmpeg' and 'findutils' are in your check_deps list
check_dependencies "ffmpeg" "find"

# Use the first argument if provided; otherwise, use the default path
TARGET_DIR="${1:-/mnt/media/Movies}"

# Display help if requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Usage: $0 [target_directory]"
    echo "Example: $0 /mnt/media/TV_Shows"
    echo "Default: /mnt/media/Movies"
    exit 0
fi

# --- Validation ---
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

log "Starting integrity check in $TARGET_DIR..."
#echo "------------------------------------------"

# Find video files and execute ffmpeg check
# Supported extensions: mkv, mp4, avi, mov, m4v
find "$TARGET_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" \) | while read -r file; do
    #echo -n "Checking: $(basename "$file")... "

    # Run ffmpeg integrity check
    # -v error: only show actual errors
    # -i: input file
    # -f null -: decode but don't save output
    if ! ffmpeg -v error -i "$file" -f null - > /dev/null 2>&1; then
        log "CORRUPT: $file"
    fi
done

#echo "------------------------------------------"
#echo "Check complete. Failures logged to corrupt_files.txt (if any)."
