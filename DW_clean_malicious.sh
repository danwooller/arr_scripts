#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ Common functions missing."
    exit 1
fi

# Configuration
SLEEP_INTERVAL="5m" # Check every 5 minutes
MONITOR_DIRS=(
    "$DIR_MEDIA_PI14_CONVERT"
    "$DIR_MEDIA_PI16_CONVERT"
    "$DIR_MEDIA_UBUNTU9_CONVERT"
)

log_start

while true; do
    for TARGET_DIR in "${MONITOR_DIRS[@]}"; do
        if [ ! -d "$TARGET_DIR" ]; then
            continue
        fi
        # Scan for junk
        find "$TARGET_DIR" -type f \( -iname "*.exe" -o -iname "*.rar" \) -print0 | while IFS= read -r -d '' FULL_PATH; do            
            FILENAME=$(basename "$FULL_PATH")
            BASE_NAME="${FILENAME%.*}"
            if manage_remote_torrent "delete" "$BASE_NAME" "true"; then
                log "✅ Deleted $BASE_NAME"
                rm -f "$FULL_PATH"
            else
                log "❌ Failed to issue delete for $BASE_NAME"
            fi
        done
    done
    sleep "$SLEEP_INTERVAL"
done

log_end
