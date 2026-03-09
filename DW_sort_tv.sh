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
LOG_LEVEL="debug"

# --- Ensure dependencies exist (Metric check: jq for API parsing) ---
check_dependencies "jq" "curl"

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
cp ~/arr_scripts/sorttv.conf /opt

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
            # Capture output and display to stderr simultaneously
            # PIPESTATUS[0] catches the Perl script, PIPESTATUS[1] catches tee
            #OUTPUT=$(/usr/bin/perl /opt/sorttv/sorttv.pl 2>&1 | tee /dev/stderr)
            OUTPUT=$(/usr/bin/perl /opt/sorttv/sorttv.pl /opt/sorttv/sorttv.conf 2>&1 | tee /dev/stderr)
            SORTTV_EXIT_CODE=${PIPESTATUS[0]} 
            # 3. Check for specific "Error sorting" string or a hard crash
            if [[ "$OUTPUT" == *"Error sorting"* ]] || [ "$SORTTV_EXIT_CODE" -ne 0 ]; then
                [[ "$LOG_LEVEL" == "debug" ]] && log "⚠️ SortTV failed to process some files (Exit Code: $SORTTV_EXIT_CODE)."
                [[ "$LOG_LEVEL" == "debug" ]] && log "📡 Falling back to general Sonarr scan for $DIR_MEDIA_COMPLETED..."
                # Fallback: Tell Sonarr to handle what SortTV couldn't (Colbert/Daily Show)
                curl -s -H "X-Api-Key: $SONARR_API_KEY" \
                     -H "Content-Type: application/json" \
                     -X POST -d "{\"name\": \"DownloadedEpisodesScan\", \"path\": \"$DIR_MEDIA_COMPLETED\"}" \
                     "$SONARR_URL/api/v3/command" > /dev/null
                notify_media_managers
            else
                # --- SUCCESS PATH: SortTV moved the file ---
                [[ "$LOG_LEVEL" == "debug" ]] && log "✅ SortTV ran successfully."
                # Extract the Series Folder from SortTV output
                SERIES_FOLDER=$(echo "$OUTPUT" | grep -oP '(?<=--to--> ).*(?=/Season)' | head -n 1)
                if [ -n "$SERIES_FOLDER" ]; then
                    [[ "$LOG_LEVEL" == "debug" ]] && log "📂 Detected move to: $SERIES_FOLDER"
                    # --- Notify Sonarr of the specific path ---
                    curl -s -H "X-Api-Key: $SONARR_API_KEY" \
                         -H "Content-Type: application/json" \
                         -X POST -d "{\"name\": \"DownloadedEpisodesScan\", \"path\": \"$SERIES_FOLDER\"}" \
                         "$SONARR_URL/api/v3/command" > /dev/null

                    SHOW_NAME_ONLY=$(basename "$SERIES_FOLDER")
                    [[ $LOG_LEVEL == "debug" ]] && log "Starting Sync for $SHOW_NAME_ONLY..."
                    # --- Metric-safe sync to Synology ---
#delete                    sync_tv_show_synology "$SHOW_NAME_ONLY"
                    synology_tv_show_sync "$SHOW_NAME_ONLY"
                    notify_sonarr_targeted_rename "$SHOW_NAME_ONLY"
#delete                    update_plex_library "$PLEX24_TV_SRC" "$PLEX24_TV_NAME"
                    plex_library_update "$PLEX24_TV_SRC" "$PLEX24_TV_NAME"
                else
                    [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ Files moved, but no specific show path parsed. Running general notification."
                    notify_media_managers
                fi
            fi
            # --- Always remove lock ---
            rm -f "$LOCK_FILE"
        fi
    fi
    # --- Wait for next poll ---
    sleep "$CHECK_INTERVAL"
done
