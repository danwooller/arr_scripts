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
            OUTPUT=$(/usr/bin/perl /opt/sorttv/sorttv.pl 2>&1 | tee /dev/stderr)
            
            if [ $? -eq 0 ]; then
                log "✅ SortTV ran successfully."
                # 3. Extract the Series Folder from SortTV output
                # It looks for the path after '--to-->' and stops before '/Season'
                SERIES_FOLDER=$(echo "$OUTPUT" | grep -oP '(?<=--to--> ).*(?=/Season)' | head -n 1)
                if [ -n "$SERIES_FOLDER" ]; then
                    log "📂 Detected move to: $SERIES_FOLDER"
                    log "📡 Notifying Sonarr via DownloadedEpisodesScan..."
                    # Direct API call with the specific path for immediate import
                    curl -s -H "X-Api-Key: $SONARR_API_KEY" \
                         -H "Content-Type: application/json" \
                         -X POST -d "{\"name\": \"DownloadedEpisodesScan\", \"path\": \"$SERIES_FOLDER\"}" \
                         "$SONARR_URL/api/v3/command" > /dev/null
                    # Strip the path to get just the folder name
                    SHOW_NAME_ONLY=$(basename "$SERIES_FOLDER")
                    [[ $LOG_LEVEL == "debug" ]] && log "Starting Sync for $SHOW_NAME_ONLY..."
                    synology_tv_show_sync "$SHOW_NAME_ONLY"
                    [[ $LOG_LEVEL == "debug" ]] && log "Sync process ended. Now notifying Sonarr..."
                    notify_sonarr_targeted_rename "$SHOW_NAME_ONLY"
                    plex_library_update "PLEX24_TV_SRC" "PLEX24_TV_NAME"
                else
                    # Fallback to your shared function if no specific path was parsed
                    log "ℹ️ No specific show path parsed. Running general notification."
                    notify_media_managers
                fi
            else
                log "⚠️ SortTV encountered an error during execution."
            fi

            
            # --- Always remove lock ---
            rm -f "$LOCK_FILE"
        fi
    fi
    # --- Wait for next poll ---
    sleep "$CHECK_INTERVAL"
done
