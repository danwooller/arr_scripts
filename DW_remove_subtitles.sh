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

# For a manual run, you might want to set this to 0
POLL_INTERVAL=30
MIN_FILE_AGE=0 # Set to 0 to catch everything immediately during testing

log "Scanning: $SOURCE_DIR"

while true; do
    # Removed -maxdepth 1 so it finds files in Season folders
    # Using -type f to ensure we only grab files
    find "$SOURCE_DIR" -type f -iname "*.mkv" -mmin +"$MIN_FILE_AGE" | while read -r FILE; do
        FILENAME=$(basename "$FILE")
        FILE_DIR=$(dirname "$FILE")
        TEMP_FILE="$FILE_DIR/processing_$FILENAME"
        MODIFIED=false
        
        log "Checking file: $FILENAME"

        # Identify English, non-forced subtitles
        REMOVABLE_IDS=$(mkvmerge --identify "$FILE" --identification-format json | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == false) | .id' | tr '\n' ',' | sed 's/,$//')

        if [ -n "$REMOVABLE_IDS" ]; then
            log "Match found ($REMOVABLE_IDS). Remuxing..."
            
            if mkvmerge -o "$TEMP_FILE" --subtitles "!$REMOVABLE_IDS" "$FILE"; then
                # In place update:
                if [ -n "$CUSTOM_SOURCE" ]; then
                    mv "$TEMP_FILE" "$FILE"
                else
                    mv "$TEMP_FILE" "$DEST_DIR/$FILENAME"
                    rm "$FILE"
                fi
                
                log "Action complete for $FILENAME"
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
                # This is likely what you see (or don't see) now
                log "No non-forced English subs in $FILENAME. Skipping."
            fi
        fi

        if [ "$MODIFIED" = true ] && [ -n "$CUSTOM_SOURCE" ]; then
            log "Triggering Plex update for $PLEX_NAME..."
            plex_library_update "$PLEX_SRC" "$PLEX_NAME"
        fi
    done

    # If running a one-off manual clean, you might want to 'exit 0' here instead of sleep
    log "Cycle complete. Sleeping for $POLL_INTERVAL seconds..."
    sleep "$POLL_INTERVAL"
done
