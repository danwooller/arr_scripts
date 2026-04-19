#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
TYPE="${1:-"tv"}"
CUSTOM_SOURCE="$2"
SOURCE_DIR="${CUSTOM_SOURCE:-$DIR_MEDIA_TORRENT/$HOST/subtitles/remove/$TYPE}"
DEST_DIR="$DIR_MEDIA_TORRENT/completed-$TYPE"

case "$TYPE" in
    "tv")       PLEX_SRC="$PLEX_TV_SRC"; PLEX_NAME="$PLEX_TV_NAME" ;;
    "movies")   PLEX_SRC="$PLEX_MOVIES_SRC"; PLEX_NAME="$PLEX_MOVIES_NAME" ;;
    "4ktv")     PLEX_SRC="$PLEX_4KTV_SRC"; PLEX_NAME="$PLEX_4KTV_NAME" ;;
    "4kmovies") PLEX_SRC="$PLEX_4KMOVIES_SRC"; PLEX_NAME="$PLEX_4KMOVIES_NAME" ;;
    *)          log "Unknown type: $TYPE. Plex update may fail.";;
esac

mkdir -p "$SOURCE_DIR"
mkdir -p "$DEST_DIR"

POLL_INTERVAL=30
MIN_FILE_AGE=0 

log "Scanning: $SOURCE_DIR"

while true; do
    # Flag to track if any changes happened in this specific loop cycle
    NEEDS_UPDATE=false

    # find -print0 handles spaces in filenames
    while IFS= read -r -d '' FILE; do
        FILENAME=$(basename "$FILE")
        FILE_DIR=$(dirname "$FILE")
        TEMP_FILE="$FILE_DIR/processing_$FILENAME"
        
        log "Checking file: $FILENAME"

        # Identify English, non-forced subtitles
        REMOVABLE_IDS=$(mkvmerge --identify "$FILE" --identification-format json | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == false) | .id' | tr '\n' ',' | sed 's/,$//')

        if [ -n "$REMOVABLE_IDS" ]; then
            log "Match found ($REMOVABLE_IDS). Remuxing..."
            
            if mkvmerge -o "$TEMP_FILE" --subtitle-tracks "!$REMOVABLE_IDS" "$FILE"; then
                if [ -n "$CUSTOM_SOURCE" ]; then
                    mv "$TEMP_FILE" "$FILE"
                    NEEDS_UPDATE=true
                else
                    mv "$TEMP_FILE" "$DEST_DIR/$FILENAME"
                    rm "$FILE"
                fi
                log "Action complete: $FILENAME"
            else
                log "Remux failed for $FILENAME"
                rm -f "$TEMP_FILE"
            fi
        else
            if [ -z "$CUSTOM_SOURCE" ]; then
                log "No changes, moving to ingest: $FILENAME"
                mv "$FILE" "$DEST_DIR/$FILENAME"
            else
                log "No changes for $FILENAME. Skipping."
            fi
        fi
    done < <(find "$SOURCE_DIR" -type f -iname "*.mkv" -mmin +"$MIN_FILE_AGE" -print0)

    # Trigger Plex update ONCE at the end of the scan if changes were made in manual mode
    if [ "$NEEDS_UPDATE" = true ]; then
        log "Finished batch. Triggering Plex update for $PLEX_NAME..."
        plex_library_update "$PLEX_SRC" "$PLEX_NAME"
    fi

    log "Cycle complete. Sleeping for $POLL_INTERVAL seconds..."
    sleep "$POLL_INTERVAL"
done
