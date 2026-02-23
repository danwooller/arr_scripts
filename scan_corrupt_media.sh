#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# Run dependency check from shared library
# Ensure 'ffmpeg' and 'findutils' are in your check_deps list
check_dependencies "ffmpeg" "find" "curl" "jq"

# Use the first argument if provided; otherwise, use the default path
TARGET_DIR="${1:-/mnt/media/Movies}"
HOLD_DIR="/mnt/media/torrent/hold"

# Display help if requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Usage: $0 [target_directory]"
    echo "Example: $0 /mnt/media/TV_Shows"
    echo "Default: /mnt/media/Movies"
    exit 0
fi

# --- Validation ---
if [ ! -d "$TARGET_DIR" ]; then
    log "Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

log "Starting integrity check on $TARGET_DIR..."
#echo "------------------------------------------"

# Find video files and execute ffmpeg check
# Supported extensions: mkv, mp4, avi, mov, m4v
find "$TARGET_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" \) -print0 | while IFS= read -r -d '' file; do
    # Capture the full output of ffmpeg
    # We use -max_muxing_queue_size to prevent buffer issues on network drives
    #error_msg=$(ffmpeg -v error -n -i "$file" -f null - 2>&1 < /dev/null)
    error_msg=$(ffmpeg -v error -n -i "$file" -c copy -f null - 2>&1 < /dev/null)
    exit_status=$?

    if [ $exit_status -ne 0 ]; then
        media_type="movie"; [[ "$TARGET_DIR" =~ [Tt][Vv] ]] && media_type="tv"
        issue_msg="Integrity Check: $(basename "$file") moved to hold. Error: $error_msg"
        
        # Report, Clean up Seerr, and Search for replacement
        sync_seerr_issue "$(basename "$file")" "$media_type" "$issue_msg"
        
        mv --backup=numbered "$file" "$HOLD_DIR/"
    fi
done

log "Completed integrity check on $TARGET_DIR..."
