#!/bin/bash

# Monitors the tv shows folder on the secondary server (synology) and
# checks the primary (truenas) for duplicate show folders
# (indicating a REPACK or new episodes) and moves them

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# === Configuration ===
HOST_NAME=$(hostname)
SYNOLOGY_DIR="/mnt/synology/TV"
MEDIA_DIR="/mnt/media/TV"
#LOG_LEVEL="debug"
SLEEP_INTERVAL=60

# Set to "true" for a dry run.
DRY_RUN=false

# --- Run Dependency Check using the shared function ---
check_dependencies "rsync"

# --- Safety Checks ---
if [[ ! -d "$SYNOLOGY_DIR" ]]; then
    log "Error: Synology TV directory not found: $SYNOLOGY_DIR"
    exit 1
fi

if [[ ! -d "$MEDIA_DIR" ]]; then
    log "Error: Media TV directory not found: $MEDIA_DIR"
    exit 1
fi

log "--- TV Show Sync Service Started ---"
log "Monitoring: $MEDIA_DIR"

# Configure rsync options
if $DRY_RUN; then
    log "DRY RUN ENABLED."
    RSYNC_OPTS="-avhn"
else
    if [[ $LOG_LEVEL = "debug" ]]; then
        log "PRODUCTION RUN. Moving files..."
    fi
    RSYNC_OPTS="-avh --remove-source-files"
fi

# === Main Service Loop ===
while true; do
#    log "Starting TV folder scan..."

    # Loop through each directory in the SYNOLOGY_DIR
    for dest_show_path in "$SYNOLOGY_DIR"/*/; do

        if [[ -d "$dest_show_path" ]]; then
            show_name=$(basename "$dest_show_path")
            source_show_path="$MEDIA_DIR/$show_name"
            
            # Check if matching show folder exists in the source
            if [[ -d "$source_show_path" ]]; then
                if [[ $LOG_LEVEL = "debug" ]]; then
                    log "Match found: '$show_name'. Syncing..."
                fi

                if [[ $LOG_LEVEL = "debug" ]]; then
                    rsync $RSYNC_OPTS "$source_show_path/" "$dest_show_path" >> "$LOG_FILE" 2>&1
                else
                    # Execute rsync - capture detailed output to log file
                    rsync $RSYNC_OPTS "$source_show_path/" "$dest_show_path"
                fi
                
                if [[ $? -eq 0 ]]; then
                    if [[ $LOG_LEVEL = "debug" ]]; then
                        log "[SUCCESS] Sync completed for '$show_name'"
                    fi
                    
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
