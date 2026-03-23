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
        log "❌ SKIP: $CURRENT_DIR is not available (Check mount/network)."
        continue
    fi
log "Current: $CURRENT_DIR"
    # 2. Check if the directory is empty (common sign of a dropped mount)
    if [ -z "$(ls -A "$CURRENT_DIR" 2>/dev/null)" ]; then
        log "⚠️ WARNING: $CURRENT_DIR appears empty. Skipping to prevent data loss/errors."
        continue
    fi

    [[ "$LOG_LEVEL" == "debug" ]] && log "🔍 Processing: $CURRENT_DIR"
    
    # 1. Integrity Check
    error_msg=$(ffmpeg -v error -n -i "$file" -c copy -f null - 2>&1 < /dev/null)
    exit_status=$?

    # 2. Determine Media Type and Title
    media_type="movie"; [[ "$TARGET_DIR" =~ [Tt][Vv] ]] && media_type="tv"
    
    # Get the folder name (The Movie/Show Title)
    # /mnt/media/Movies/The Rip (2026)/The Rip.mkv -> The Rip (2026)
    media_title=$(basename "$(dirname "$file")")
    file_name=$(basename "$file")
    media_name=$(basename "$1")

    if [[ "$media_type" == "tv" ]]; then
        if [[ "$media_name" =~ ^Season|^Specials|^S[0-9]+ ]]; then
            media_name=$(basename "$(dirname "$1")")
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

    log "✅ Completed scan for $CURRENT_DIR"
done

[[ "$LOG_LEVEL" == "debug" ]] && log "🏁 Tasks finished."
exit 0
