#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# Run dependency check from shared library
# Ensure 'ffmpeg' and 'findutils' are in your check_deps list
check_dependencies "ffmpeg" "find" "curl" "jq"

# Use the first argument if provided; otherwise, use the default path
TARGET_DIR="${1:-/mnt/media/Movies}"
HOLD_DIR="/mnt/media/torrent/hold"
OVERSEERR_URL="http://wooller.com:5055" # Update with your IP/Port
OVERSEERR_API_KEY="MTc0MDQ5NzU0MjYyOWRhZjA1MjhmLTg2Y2YtNDZmOS1hODkxLThlMzBlMWNmNzZmOQ=="

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

# --- Function to Report Issue to Overseerr ---
report_overseerr_issue() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    # Clean filename for search
    local search_term=$(echo "$filename" | sed 's/\.[^.]*$//' | sed 's/(.*)//')

    # 1. Search for the media ID
    local search_results=$(curl -s -X GET "$OVERSEERR_URL/api/v1/search?query=$(echo "$search_term" | jq -rr @uri)" \
        -H "X-Api-Key: $OVERSEERR_API_KEY")

    # 2. Extract the mediaId
    local media_id=$(echo "$search_results" | jq -r '.results[0].mediaInfo.id // empty')

    if [ -n "$media_id" ] && [ "$media_id" != "null" ]; then
        # 3. Create Video Issue (Type 3)
        curl -s -X POST "$OVERSEERR_URL/api/v1/issue" \
            -H "X-Api-Key: $OVERSEERR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"issueType\": 3,
                \"message\": \"Automated Integrity Check: File moved to hold due to corruption. Path: $file_path\",
                \"mediaId\": $media_id
            }" > /dev/null
        log "Overseerr Issue created for $filename"
    else
        log "WARN: Could not link $filename to an Overseerr Media ID."
    fi
}

log "Starting integrity check on $TARGET_DIR..."
#echo "------------------------------------------"

# Find video files and execute ffmpeg check
# Supported extensions: mkv, mp4, avi, mov, m4v
find "$TARGET_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" \) -print0 | while IFS= read -r -d '' file; do
    #echo -n "Checking: $(basename "$file")... "

    # Run ffmpeg integrity check
    # -v error: only show actual errors
    # -i: input file
    # -f null -: decode but don't save output
    #if ! ffmpeg -v error -n -i "$file" -f null - > /dev/null 2>&1; then
    #if ! ffmpeg -v fatal -err_detect ignore_err -i "$file" -f null - > /dev/null 2>&1; then
    if ! ffmpeg -v fatal -n -i "$file" -f null - < /dev/null 2>&1; then
        # 1. Report to Overseerr
        report_overseerr_issue "$file"
        # 2. Record in log
        log "CORRUPT: $file"
        # 3. Move to Hold (using --backup=numbered in case of duplicate filenames)
        mv --backup=numbered "$file" "$HOLD_DIR/"
        log "MOVED: $(basename "$file") to $HOLD_DIR"
    fi
done

log "Completed integrity check on $TARGET_DIR..."
