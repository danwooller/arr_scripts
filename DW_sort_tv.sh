
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

LOCK_FILE="/tmp/sorttv_service.lock"
CHECK_INTERVAL=300 # 5 minutes

# --- Grab the latest config ---
cp /home/dan/arr_scripts/sorttv.conf /opt/sorttv

# --- Service Loop ---
while true; do
    # 1. Check if mount is active
    if mountpoint -q $DIR_MEDIA; then
        # 2. Prevent overlapping runs
        if [ -f "$LOCK_FILE" ]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "⚠️ Service already running. Skipping."
        else
            touch "$LOCK_FILE"
            # 3. Enable case-insensitive globbing
            shopt -s nocaseglob
            # 4. Define the mapping (Pattern -> Destination)
            declare -A LIBRARY_MAP=(
                ["stephen.colbert"]="$DIR_MEDIA_TV/The Late Show with Stephen Colbert"
                ["stephen-colbert"]="$DIR_MEDIA_TV/The Late Show with Stephen Colbert"
                ["last.week.tonight"]="$DIR_MEDIA_TV/Last Week Tonight with John Oliver"
                ["last-week-tonight"]="$DIR_MEDIA_TV/Last Week Tonight with John Oliver"
                ["daily.show"]="$DIR_MEDIA_TV/The Daily Show"
                ["daily-show"]="$DIR_MEDIA_TV/The Daily Show"
            )
            # 5. Iterate through the mappin
            for pattern in "${!LIBRARY_MAP[@]}"; do
                dest="${LIBRARY_MAP[$pattern]}"
                # Create destination if it doesn't exist (20 meters of files? No problem!)
                mkdir -p "$dest"
                # Use find to locate files case-insensitively
                # -maxdepth 1 limits to current folder; adjust if searching subfolders
                # -iname ensures case is ignored for both the pattern and the filename
                find "$DIR_MEDIA_COMPLETED" -maxdepth 1 -type f -iname "*$pattern*.mkv" -print0 | while IFS= read -r -d '' file; do
                    [[ "$LOG_LEVEL" == "debug" ]] && log "Moving: '$file' -> '$dest/'"
                    mv -v "$file" "$dest/"
                    [[ "$LOG_LEVEL" == "debug" ]] && log "Updating Sonarr for: $dest"
                    sonarr_targeted_rename "$dest"
                    SHOW_NAME="${file##*/}"
                    manage_remote_torrent "delete" "$SHOW_NAME"
                done
            done
            # 6. Cleanup
            shopt -u nocaseglob
            # 7. Run SortTV and capture output
            OUTPUT=$(/usr/bin/perl /opt/sorttv/sorttv.pl 2>&1)
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                [[ "$LOG_LEVEL" == "debug" ]] && log "✅ SortTV ran successfully."
                # 8. Extract folder and trigger Sonarr logic
                SERIES_FOLDER=$(echo "$OUTPUT" | grep -oP '(?<=--to--> ).*?(?=/Season)' | head -n 1)
                MOVIE_FOLDER=$(echo "$OUTPUT" | grep -oP '(?<=--to--> ).*(?=/)' | head -n 1)
                if [ -n "$SERIES_FOLDER" ]; then
                    log "📂 Moved to $SERIES_FOLDER"
                    SHOW_NAME_ONLY=$(basename "$SERIES_FOLDER")
                    synology_tv_show_sync "$SHOW_NAME_ONLY"
                    sleep 10
                    sonarr_targeted_rename "$SHOW_NAME_ONLY"
                    plex_library_update "$PLEX_TV_SRC" "$PLEX_TV_NAME"
                elif [ -n "$MOVIE_FOLDER" ]; then
                    # Extracts "Prisoners (2013)" from "/mnt/media/Movies/Prisoners (2013)"
                    MOVIE_NAME_ONLY=$(basename "$MOVIE_FOLDER")
                    log "🎬 Movie Moved to $MOVIE_FOLDER"
                    # Pass the movie name to your notification function
                    radarr_targeted_scan "$MOVIE_NAME_ONLY"
                    plex_library_update "$PLEX_MOVIES_SRC" "$PLEX_MOVIES_NAME"
                else
                    [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ No specific show path parsed. Running general notification."
                    #notify_media_managers
                fi
            else
                log "⚠️ SortTV encountered an error during execution."
            fi
            rm -f "$LOCK_FILE"
        fi
    else
        log "❌ Media mount not found. Retrying in $CHECK_INTERVAL seconds..."
    fi   
    # --- Wait for next poll ---
    sleep "$CHECK_INTERVAL"
done
