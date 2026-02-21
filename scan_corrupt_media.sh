#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

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

# --- Function to Report Issue to Seerr ---
report_seerr_issue() {
    local file_path="$1"
    local error_details="$2"
    local filename=$(basename "$file_path")
    
    # Clean filename: remove extension and common year patterns like (2023)
    local search_term=$(echo "$filename" | sed -E 's/\.[^.]*$//; s/\([0-9]{4}\)//g; s/[._]/ /g')

    log "Searching Seerr for: $search_term"

    # 1. Search with URL encoding
    local search_results=$(curl -s -X GET "$SEERR_URL/api/v1/search?query=$(echo "$search_term" | jq -rr @uri)" \
        -H "X-Api-Key: $SEERR_API_KEY")

    # 2. Extract the ID of the first result. 
    # Note: Seerr 'issues' usually link to the mediaId (internal DB), 
    # but the API often requires the tmdbId or specific mediaId.
    local media_id=$(echo "$search_results" | jq -r '.results[0].mediaInfo.id // empty')

    if [ -z "$media_id" ] || [ "$media_id" == "null" ]; then
        log "WARN: Could not find $filename in Seerr library (no mediaInfo found)."
        return 1
    fi

    # 3. Create Issue
    local response=$(curl -s -w "%{http_code}" -X POST "$SEERR_URL/api/v1/issue" \
        -H "X-Api-Key: $SEERR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"issueType\": 3,
            \"message\": \"Automated Integrity Check: Corruption detected. Path: $file_path. Error: $error_details\",
            \"mediaId\": $media_id
        }")

    local http_code="${response: -3}"
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        log "Seerr Issue created for $filename (ID: $media_id)"
    else
        log "ERROR: Seerr API returned $http_code for $filename"
    fi
}

log "Starting integrity check on $TARGET_DIR..."
#echo "------------------------------------------"

# Find video files and execute ffmpeg check
# Supported extensions: mkv, mp4, avi, mov, m4v
find "$TARGET_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" \) -print0 | while IFS= read -r -d '' file; do
    # Capture the full output of ffmpeg
    # We use -max_muxing_queue_size to prevent buffer issues on network drives
    error_msg=$(ffmpeg -v error -n -i "$file" -f null - 2>&1 < /dev/null)
    exit_status=$?

    if [ $exit_status -ne 0 ]; then
        # Filter out the common "Output file does not contain any stream" noise 
        # if there's a more relevant error above it.
        clean_error=$(echo "$error_msg" | grep -v "Output file does not contain any stream" | tail -n 2)
      
        # 1. Report to Seerr (includes the error in the message)
        report_seerr_issue "$file" "$error_msg"
        
        # 2. Record in log
        log "$file | ${clean_error:-$error_msg}"

        # 3. Move to Hold
        mv --backup=numbered "$file" "$HOLD_DIR/"
        log "MOVED: $(basename "$file") to $HOLD_DIR"
    fi
done

log "Completed integrity check on $TARGET_DIR..."
