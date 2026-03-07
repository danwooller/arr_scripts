#!/bin/bash

# Monitors the tv shows folder on the secondary server (synology) and
# checks the primary (truenas) for duplicate show folders
# (indicating a REPACK or new episodes) and moves them

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
#LOG_LEVEL="debug"
SLEEP_INTERVAL=60

# Set to "true" for a dry run.
DRY_RUN=false

# --- Run Dependency Check using the shared function ---
check_dependencies "rsync"

# --- Safety Checks ---
if [[ ! -d "$DIR_SYNOLOGY_TV" ]]; then
    log "Error: Synology TV directory not found: $DIR_SYNOLOGY_TV"
    exit 1
fi

if [[ ! -d "$DIR_MEDIA_TV" ]]; then
    log "Error: Media TV directory not found: $DIR_MEDIA_TV"
    exit 1
fi

log "--- TV Show Sync Service Started ---"
log "Monitoring: $DIR_MEDIA_TV"

# Configure rsync options
if $DRY_RUN; then
    log "DRY RUN ENABLED."
    #RSYNC_OPTS="-avhn"
    RSYNC_OPTS="-rlptDvn"
else
    [[ $LOG_LEVEL == "debug" ]] && log "PRODUCTION RUN. Moving files..."
    #RSYNC_OPTS="-avh --remove-source-files"
    RSYNC_OPTS="-avh --remove-source-files --no-p --no-g --no-o"
fi

# === Main Service Loop ===
while true; do
#    log "Starting TV folder scan..."

    # Loop through each directory in the SYNOLOGY_DIR
    for dest_show_path in "$DIR_SYNOLOGY_TV"/*/; do

        if [[ -d "$dest_show_path" ]]; then
            show_name=$(basename "$dest_show_path")
            source_show_path="$DIR_MEDIA_TV/$show_name"
            
            # Check if matching show folder exists in the source
            if [[ -d "$source_show_path" ]]; then
                [[ $LOG_LEVEL == "debug" ]] && log "Match found: '$show_name'. Syncing..."
                if [[ $LOG_LEVEL = "debug" ]]; then
                    rsync $RSYNC_OPTS "$source_show_path/" "$dest_show_path" >> "$LOG_FILE" 2>&1
                else
                    # Execute rsync - capture detailed output to log file
                    rsync $RSYNC_OPTS "$source_show_path/" "$dest_show_path"
                fi
                # Tell Sonarr to update
                notify_sonarr_targeted_rename "$show_name"
                # Update Plex server
                update_plex_library "$PLEX_TV_SRC" "$PLEX_TV_NAME"
                #if [[ $? -eq 0 ]]; then
                if [[ $RSYNC_EXIT -eq 0 || $RSYNC_EXIT -eq 23 || $RSYNC_EXIT -eq 24 ]]; then
                    log "✅ Sync completed for '$show_name'"

                    if ! $DRY_RUN; then
                        # Clean up empty sub-directories (Seasons, etc.)
                        find "$source_show_path" -mindepth 1 -type d -empty -delete
                        
                        # Remove the show folder if it's completely empty
                        if [[ -d "$source_show_path" ]] && [[ -z "$(ls -A "$source_show_path")" ]]; then
                            rmdir "$source_show_path"
                            if [[ $LOG_LEVEL = "debug" ]]; then
                                log "Removed empty source folder: $show_name"
                            fi
                        fi
                    fi
                else
                    log "[ERROR] rsync failed for '$show_name'. Check log for details."
                fi
            fi
        fi
    done

#    log "Scan complete. Waiting ${SLEEP_INTERVAL}s..."
    sleep "$SLEEP_INTERVAL"
done
