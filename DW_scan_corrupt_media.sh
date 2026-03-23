#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub currently in progress on $BASE_HOST6. Exiting to protect disks."
    exit 0
fi

# --- Logic: Manual vs Scheduled ---
if [ -n "$1" ]; then
    # If an argument is passed, we only scan that specific path
    log "Manual scan requested for: $1"
    TARGET_PATHS=("$1")
else
    # If no argument, we run the full array (Systemd Timer mode)
    [[ "$LOG_LEVEL" == "debug" ]] && log "Starting scheduled scan of all TV locations..."
    TARGET_PATHS=("${DIR_TV[@]}" "${DIR_MOVIES[@]}")
fi

# --- Execution Loop ---
for CURRENT_DIR in "${TARGET_PATHS[@]}"; do
    
    # 1. Check if the directory actually exists/is mounted
    if [ ! -d "$CURRENT_DIR" ]; then
        log "❌ SKIP: $CURRENT_DIR is not available."
        continue
    fi

    # 2. Check if empty
    if [ -z "$(ls -A "$CURRENT_DIR" 2>/dev/null)" ]; then
        log "⚠️ WARNING: $CURRENT_DIR appears empty. Skipping."
        continue
    fi

    [[ "$LOG_LEVEL" == "debug" ]] && log "🔍 Processing: $CURRENT_DIR"

    # --- NEW: Find video files within the directory ---
    # This finds mkv, mp4, avi, etc., and loops through them
    find "$CURRENT_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) | while read -r file; do
        
        file_name=$(basename "$file")

        # 1. Integrity Check
        error_msg=$(ffmpeg -v error -n -i "$file" -c copy -f null - 2>&1 < /dev/null)
        exit_status=$?

        # 2. Determine Media Type (Look at the full path for 'TV')
        media_type="movie"
        [[ "$file" =~ [Tt][Vv] ]] && media_type="tv"
        
        # 3. Logic for Media Title (Handling Seasons/Specials)
        # We start with the parent folder of the file
        media_name=$(basename "$(dirname "$file")")

        if [[ "$media_type" == "tv" ]]; then
            # If the folder is "Season 01", go up one more level to get the Show Title
            if [[ "$media_name" =~ ^Season|^Specials|^S[0-9]+ ]]; then
                media_name=$(basename "$(dirname "$(dirname "$file")")")
            fi
        fi

        if [ $exit_status -ne 0 ]; then
            log "❌ CORRUPT: $file_name ($error_msg)"
            issue_msg="Corruption detected in $file_name. Error: $error_msg"
            
            seerr_sync_issue "$media_name" "$media_type" "$issue_msg"
            mv --backup=numbered "$file" "$DIR_MEDIA_HOLD/"
        else
            [[ "$LOG_LEVEL" == "debug" ]] && log "✅ HEALTHY: $file_name"
            seerr_resolve_issue "$media_name" "$media_type"
        fi
    done

    log "✅ Completed scan for $CURRENT_DIR"
done

[[ "$LOG_LEVEL" == "debug" ]] && log "🏁 Tasks finished."
exit 0
