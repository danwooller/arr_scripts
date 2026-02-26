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
    
    # 1. Integrity Check
    error_msg=$(ffmpeg -v error -n -i "$file" -c copy -f null - 2>&1 < /dev/null)
    exit_status=$?

    # 2. Determine Media Type and Title
    media_type="movie"; [[ "$TARGET_DIR" =~ [Tt][Vv] ]] && media_type="tv"
    
    # Get the folder name (The Movie/Show Title)
    # /mnt/media/Movies/The Rip (2026)/The Rip.mkv -> The Rip (2026)
    media_title=$(basename "$(dirname "$file")")
    file_name=$(basename "$file")

    if [ $exit_status -ne 0 ]; then
        log "❌ CORRUPT: $file_name ($error_msg)"
        
        issue_msg="Corruption detected in $file_name. File moved to hold. Error: $error_msg"
        
        # 3. Handle Seerr Issue (Pass the Title, not the filename)
        sync_seerr_issue "$media_title" "$media_type" "$issue_msg"
        
        # 4. Move to hold
        mv --backup=numbered "$file" "$HOLD_DIR/"

        # 5. TRIGGER ARR SEARCH (Add this function call)
        trigger_arr_search "$media_title" "$media_type" "$file"
        
    else
        # Optional: Resolve if found healthy (though corruption rarely "heals" itself)
        # sync_seerr_issue "$media_title" "$media_type" ""
        log "✅ HEALTHY: $file_name"
    fi
done

log "Completed integrity check on $TARGET_DIR..."
