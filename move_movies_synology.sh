#!/bin/bash

# === Configuration ===
HOST_NAME=$(hostname)
SYNOLOGY_DIR="/mnt/synology/Movies"
MEDIA_DIR="/mnt/media/Movies"
LOG_FILE="/mnt/media/torrent/${HOST_NAME}.log"
SLEEP_INTERVAL=300

# Set to "true" for a dry run. No files will be moved.
DRY_RUN=false

# --- Logging Function ---
log() {
    echo "$(date +'%H:%M'): $1" | tee -a "$LOG_FILE"
}

# --- Safety Checks ---
if [ ! -d "$SYNOLOGY_DIR" ]; then
    log "Error: Synology directory not found: $SYNOLOGY_DIR"
    exit 1
fi

if [ ! -d "$MEDIA_DIR" ]; then
    log "Error: Media directory not found: $MEDIA_DIR"
    exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
    log "Error: rsync is not installed. Please install it to use this script."
    exit 1
fi

log "--- Movie Sync Service Started ---"
log "Reference/Destination: $SYNOLOGY_DIR"
log "Source: $MEDIA_DIR"

# Configure rsync options once
if $DRY_RUN; then
    log "DRY RUN ENABLED. No files will be moved."
    RSYNC_OPTS="-avhn" # Removed --progress for cleaner logs in service mode
else
    log "PRODUCTION RUN. Files will be moved."
    RSYNC_OPTS="-avh --remove-source-files"
fi

# === Main Service Loop ===
while true; do
#    log "Starting folder scan..."

    # Loop through each directory in the SYNOLOGY_DIR
    for dest_movie_path in "$SYNOLOGY_DIR"/*/; do

        if [ -d "$dest_movie_path" ]; then
            movie_name=$(basename "$dest_movie_path")
            source_movie_path="$MEDIA_DIR/$movie_name"
            
            # Check if matching folder exists in the source MEDIA_DIR
            if [ -d "$source_movie_path" ]; then
                log "Match found: '$movie_name'. Starting sync..."
                
                # Use rsync to "move-and-merge"
                # Redirecting rsync output to log via the log function can be messy, 
                # so we append it directly to the log file.
                rsync $RSYNC_OPTS "$source_movie_path/" "$dest_movie_path" >> "$LOG_FILE" 2>&1
                
                if [ $? -eq 0 ]; then
                    log "[SUCCESS] Sync completed for '$movie_name'"
                    
                    if ! $DRY_RUN; then
                        # Cleanup empty sub-dirs
                        find "$source_movie_path" -mindepth 1 -type d -empty -delete
                        
                        # Remove parent if now empty
                        if [ -d "$source_movie_path" ] && [ -z "$(ls -A "$source_movie_path")" ]; then
                            rmdir "$source_movie_path"
                            log "Removed empty source directory: $movie_name"
                        fi
                    fi
                else
                    log "[ERROR] rsync failed for '$movie_name'. Check log for details."
                fi
            fi
        fi
    done

#    log "Scan complete. Sleeping for ${SLEEP_INTERVAL}s..."
    sleep "$SLEEP_INTERVAL"
done
