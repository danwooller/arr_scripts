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
log "----1----"
            if [ $EXIT_CODE -eq 0 ] && [ -z "$(echo "$OUTPUT" | grep "WARN: Error sorting")" ]; then
log "----2----"
                log "✅ SortTV ran successfully."
                
                if [ -n "$SERIES_NAME" ]; then
                    # 1. Clean up the name for searching (e.g., "Paradise 2025")
                    CLEAN_NAME=$(echo "$SERIES_NAME" | sed 's/[^a-zA-Z0-9 ]//g')
                    log "📡 Searching Sonarr for: $CLEAN_NAME"
                
                    # 2. Get the internal Series ID from Sonarr
                    SERIES_ID=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/series" | \
                                jq -r ".[] | select(.title | ascii_downcase == \"${CLEAN_NAME,,}\") | .id")
                
                    if [ -n "$SERIES_ID" ] && [ "$SERIES_ID" != "null" ]; then
                        log "✅ Found ID $SERIES_ID. Triggering targeted Rescan..."
                        curl -s -H "X-Api-Key: $SONARR_API_KEY" \
                             -H "Content-Type: application/json" \
                             -X POST -d "{\"name\": \"RescanSeries\", \"seriesId\": $SERIES_ID}" \
                             "$SONARR_URL/api/v3/command" > /dev/null
                    else
                        log "⚠️ Could not find ID for '$CLEAN_NAME'. Running fallback scan."
                        # Keep the old method as a backup
                        curl -s -H "X-Api-Key: $SONARR_API_KEY" \
                             -H "Content-Type: application/json" \
                             -X POST -d "{\"name\": \"DownloadedEpisodesScan\", \"path\": \"/mnt/media/TV/$SERIES_NAME\"}" \
                             "$SONARR_URL/api/v3/command" > /dev/null
                    fi
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
