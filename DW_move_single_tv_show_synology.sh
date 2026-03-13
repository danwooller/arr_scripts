#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# === Configuration ===
LOG_LEVEL="debug"
# Set to "true" for a dry run.
DRY_RUN=true

# --- Argument Check ---
if [[ -z "$1" ]]; then
    echo "Usage: $0 <show_folder_name>"
    exit 1
fi

SHOW_NAME="$1"
DEST_SHOW_PATH="$DIR_SYNOLOGY_TV/$SHOW_NAME"
SOURCE_SHOW_PATH="$DIR_MEDIA_TV/$SHOW_NAME"

# --- Run Dependency Check ---
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

# Configure rsync options
if $DRY_RUN; then
    log "DRY RUN ENABLED."
    RSYNC_OPTS="-avhn"
else
    [[ "$LOG_LEVEL" == "debug" ]] && log "PRODUCTION RUN. Moving files..."
    RSYNC_OPTS="-avh --remove-source-files"
fi

# === Main Execution ===

log "--- Manual TV Show Sync Started for: $SHOW_NAME ---"

# Check if the destination show folder exists on Synology
if [[ ! -d "$DEST_SHOW_PATH" ]]; then
    log "Error: Destination folder '$SHOW_NAME' does not exist in $DIR_SYNOLOGY_TV"
    exit 1
fi

# Check if matching show folder exists in the source (TrueNAS)
if [[ -d "$SOURCE_SHOW_PATH" ]]; then
    [[ "$LOG_LEVEL" == "debug" ]] && log "Match found: '$SHOW_NAME'. Syncing..."

    # Execute rsync
    if [[ $LOG_LEVEL = "debug" ]]; then
        rsync $RSYNC_OPTS "$SOURCE_SHOW_PATH/" "$DEST_SHOW_PATH" >> "$LOG_FILE" 2>&1
    else
        rsync $RSYNC_OPTS "$SOURCE_SHOW_PATH/" "$DEST_SHOW_PATH"
    fi
    # Tell Sonarr to update
    sonarr_targeted_rename "$show_name"
    # Update Plex server
#delete update_plex_library "$PLEX_MOVIES_SRC" "$PLEX_MOVIES_NAME"
    plex_library_update "$PLEX_TV_SRC" "$PLEX_TV_NAME"
    # Check rsync exit status
    if [[ $? -eq 0 ]]; then
        log "✅ Sync completed for '$SHOW_NAME'"

        if ! $DRY_RUN; then
            # Clean up empty sub-directories (Seasons, etc.)
            find "$SOURCE_SHOW_PATH" -mindepth 1 -type d -empty -delete
            
            # Remove the show folder if it's completely empty
            if [[ -d "$SOURCE_SHOW_PATH" ]] && [[ -z "$(ls -A "$SOURCE_SHOW_PATH")" ]]; then
                rmdir "$SOURCE_SHOW_PATH"
                [[ "$LOG_LEVEL" == "debug" ]] && log "Removed empty source folder: $SHOW_NAME"
            fi
        fi
    else
        log "[ERROR] rsync failed for '$SHOW_NAME'. Check log for details."
        exit 1
    fi
else
    log "No source files found for '$SHOW_NAME' in $DIR_MEDIA_TV. Nothing to do."
fi
