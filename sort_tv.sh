#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
#LOG_LEVEL="debug"

# --- Ensure dependencies exist (Metric check: jq for API parsing) ---
check_dependencies "curl" "jq"

log_start

# 1. Ensure mounts are active
mount -a 2>/dev/null

# --- Ensure the directory exists ---
if [ ! -d "$DIR_MEDIA_COMPLETED" ]; then
    log "❌ Error: Directory $DIR_MEDIA_COMPLETED does not exist."
    exit 1
fi

# 2. Check mount point before proceeding
if mountpoint -q /mnt/media; then
    # Capture output and check for success
    # Using 'tee' allows the output to appear in your logs while being captured
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
            sonarr_targeted_rename "$SHOW_NAME_ONLY"
            plex_library_update "PLEX24_TV_SRC" "PLEX24_TV_NAME"
        else
            # Fallback to your shared function if no specific path was parsed
            log "ℹ️ No specific show path parsed. Running general notification."
            notify_media_managers
        fi
    else
        log "⚠️ SortTV encountered an error during execution."
    fi
else
    echo "❌ ERROR: Media mount not found at /mnt/media. Skipping SortTV."
    exit 1
fi

log_end
