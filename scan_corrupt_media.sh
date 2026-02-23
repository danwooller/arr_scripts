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

# --- Function to Report Issue to Seerr ---
report_seerr_issue() {
    local file_path="$1"
    local error_details="$2"
    local filename=$(basename "$file_path")
    
# 1. Determine Media Type and Extract 1x02
    local media_type="movie"
    local extra_info=""
    if [[ "$TARGET_DIR" =~ [Tt][Vv] ]]; then
        media_type="tv"
        if [[ "$filename" =~ ([0-9]+)x([0-9]+) ]]; then
            local season="${BASH_REMATCH[1]}"
            local episode="${BASH_REMATCH[2]}"
            extra_info=" [Season $season, Episode $episode]"
        fi
    fi

    # 2. Optimized Search Term: 
    # Remove extension, remove the 1x02 pattern, and remove (Year)
    # This leaves just "The Late Show with Stephen Colbert"
    local search_term=$(echo "$filename" | sed -E 's/\.[^.]*$//; s/[0-9]+x[0-9]+.*//i; s/\([0-9]{4}\)//g; s/[._]/ /g; s/ +/ /g')

    log "Searching Seerr ($media_type) for: $search_term"

    # 3. Search and Extract ID
    local encoded_query=$(echo "$search_term" | jq -Rr @uri)
    local search_results=$(curl -s -X GET "$SEERR_URL/api/v1/search?query=$encoded_query" \
        -H "X-Api-Key: $SEERR_API_KEY")

    local media_id=$(echo "$search_results" | jq -r --arg type "$media_type" \
        '.results[] | select(.mediaType == $type).mediaInfo.id // empty' | head -n 1)

    if [ -z "$media_id" ] || [ "$media_id" == "null" ]; then
        log "WARN: Could not link $filename to a $media_type in Seerr."
        return 1
    fi

    # 4. Build JSON Payload
    # We include the extra_info (Season/Episode) in the message string
    local json_payload=$(jq -n \
        --arg mt "1" \
        --arg msg "Integrity Check: $filename moved to hold.$extra_info Error: $error_details" \
        --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')

    # 5. POST to Seerr
    local response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SEERR_URL/api/v1/issue" \
        -H "X-Api-Key: $SEERR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload")

    if [[ "$response" =~ ^20[0-9]$ ]]; then
        log "Seerr Issue created for $filename$extra_info (ID: $media_id)"
    else
        log "❌ Seerr API returned HTTP $response"
    fi
}

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
