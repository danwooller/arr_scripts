#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
LOCK_FILE="/tmp/sorttv_running.lock"
CHECK_INTERVAL="300" # Sleep for 5 minutes (300 seconds)
#LOG_LEVEL="debug"

# --- Ensure dependencies exist (Metric check: jq for API parsing) ---
check_dependencies "curl" "jq"

log_start

# --- Ensure mounts are active (CIFS/TrueNAS) ---
mount -a 2>/dev/null

# --- Ensure the directory exists ---
if [ ! -d "$DIR_MEDIA_COMPLETED" ]; then
    log "❌ Error: Directory $DIR_MEDIA_COMPLETED does not exist."
    exit 1
fi

# --- Cleanup stale locks on start ---
rm -f "$LOCK_FILE"
# --- Grab the latest config ---
cp ~/arr_scripts/sorttv.conf /opt/sorttv

while true; do
    # --- Check if SortTV is already running ---
    if [ -f "$LOCK_FILE" ]; then
        [[ "$LOG_LEVEL" == "debug" ]] && log "⚠️ SortTV is still running from a previous check. Skipping..."
    else
        # --- Look for any .mkv files (Case-insensitive) ---
        MATCHES=$(find "$DIR_MEDIA_COMPLETED" -maxdepth 2 -type f -iname "*.mkv" -print -quit)

        if [ -n "$MATCHES" ]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "📂 MKV files detected. Starting SortTV..."
            touch "$LOCK_FILE"

            # --- EXECUTION BLOCK ---
            set -o pipefail
            OUTPUT=$(/usr/bin/perl /opt/sorttv/sorttv.pl 2>&1 | tee /dev/stderr)
            EXIT_CODE=$?

            SERIES_NAME=$(echo "$OUTPUT" | grep -oP '(?<=trying to move ).*(?= season)' | head -n 1)

            if [ $EXIT_CODE -eq 0 ] && [ -z "$(echo "$OUTPUT" | grep "WARN: Error sorting")" ]; then
                log "✅ SortTV ran successfully."
                
                if [ -n "$SERIES_NAME" ]; then
                    # Map to your TV root
                    #SERIES_FOLDER="/mnt/media/TV/$SERIES_NAME"
                    SERIES_FOLDER=$(echo "$OUTPUT" | grep -oP '(?<=--to--> ).*?(?=/Season)' | head -n 1)
                    log "📂 Detected move for: $SERIES_NAME"
                    
                    # Notify Sonarr with specific path
                    curl -s -H "X-Api-Key: $SONARR_API_KEY" \
                         -H "Content-Type: application/json" \
                         -X POST -d "{\"name\": \"DownloadedEpisodesScan\", \"path\": \"$SERIES_FOLDER\"}" \
                         "$SONARR_URL/api/v3/command" > /dev/null
            
                    SHOW_NAME_ONLY=$(basename "$SERIES_FOLDER")
                    sleep 5
                    synology_tv_show_sync "$SHOW_NAME_ONLY"
                    notify_sonarr_targeted_rename "$SHOW_NAME_ONLY"
                    plex_library_update "PLEX24_TV_SRC" "PLEX24_TV_NAME"
                fi
            else
                log "⚠️ SortTV encountered an error. The file might be locked by the torrent client."
                # Optional: If you want to force a scan anyway, keep notify_media_managers here
            fi
            # --- Always remove lock ---
            rm -f "$LOCK_FILE"
        fi
    fi
    # --- Wait for next poll ---
    sleep "$CHECK_INTERVAL"
done
