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
    # find -print0 handles spaces in filenames much better
    find "$SOURCE_DIR" -type f -iname "*.mkv" -mmin +"$MIN_FILE_AGE" -print0 | while IFS= read -r -d '' FILE; do
        FILENAME=$(basename "$FILE")
        FILE_DIR=$(dirname "$FILE")
        TEMP_FILE="$FILE_DIR/processing_$FILENAME"
        MODIFIED=false
        
        log "Checking file: $FILENAME"

        # Identify English, non-forced subtitles
        REMOVABLE_IDS=$(mkvmerge --identify "$FILE" --identification-format json | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == false) | .id' | tr '\n' ',' | sed 's/,$//')

        if [ -n "$REMOVABLE_IDS" ]; then
            log "Match found ($REMOVABLE_IDS). Remuxing..."
            
            # Fixed the execution string to handle spaces and explicit track exclusion
            if mkvmerge -o "$TEMP_FILE" --subtitle-tracks "!$REMOVABLE_IDS" "$FILE"; then
                if [ -n "$CUSTOM_SOURCE" ]; then
                    # Replace original file with the new one
                    mv "$TEMP_FILE" "$FILE"
                else
                    # Move to ingest folder and clean up source
                    mv "$TEMP_FILE" "$DEST_DIR/$FILENAME"
                    rm "$FILE"
                fi
                
                log "Action complete: $FILENAME"
                MODIFIED=true
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

        if [ "$MODIFIED" = true ] && [ -n "$CUSTOM_SOURCE" ]; then
            log "Triggering Plex update for $PLEX_NAME..."
            plex_library_update "$PLEX_SRC" "$PLEX_NAME"
        fi
    done

    log "Cycle complete. Sleeping for $POLL_INTERVAL seconds..."
    sleep "$POLL_INTERVAL"
done
