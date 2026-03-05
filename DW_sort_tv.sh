#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

LOCK_FILE="/tmp/sorttv_running.lock"

check_dependencies "jq"

log_start

# Ensure mounts are active
mount -a 2>/dev/null

# Ensure the directory exists
if [ ! -d "$DIR_MEDIA_COMPLETED" ]; then
    echo "Error: Directory $DIR_MEDIA_COMPLETED does not exist."
    exit 1
fi

while true; do
    # 1. Check if SortTV is already running to avoid overlapping processes
    if [ -f "$LOCK_FILE" ]; then
        log "⚠️ SortTV is still running from a previous check. Skipping..."
    else
        # 2. Look for any .mkv files in the directory
        # -iname makes it case-insensitive
        MATCHES=$(find "$DIR_MEDIA_COMPLETED" -type f -iname "*.mkv" -print -quit)

        if [ -n "$MATCHES" ]; then
            log "📂 MKV files detected. Starting SortTV..."
            touch "$LOCK_FILE"
            
            # --- YOUR SORTTV LOGIC START ---
            OUTPUT=$(/usr/bin/perl /opt/sorttv/sorttv.pl 2>&1)
            
            if [ $? -eq 0 ]; then
                log "✅ SortTV ran successfully."
                # ... insert the rest of your Sonarr/Sync logic here ...
            else
                log "⚠️ SortTV encountered an error."
            fi
            # --- YOUR SORTTV LOGIC END ---

            rm "$LOCK_FILE"
        fi
    fi

    # 3. Wait before checking again
    sleep "$CHECK_INTERVAL"
done
