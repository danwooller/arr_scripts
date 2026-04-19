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

# Map TYPE to Plex variables
case "$TYPE" in
    "tv")       PLEX_SRC="$PLEX_TV_SRC"; PLEX_NAME="$PLEX_TV_NAME" ;;
    "movies")   PLEX_SRC="$PLEX_MOVIES_SRC"; PLEX_NAME="$PLEX_MOVIES_NAME" ;;
    "4ktv")     PLEX_SRC="$PLEX_4KTV_SRC"; PLEX_NAME="$PLEX_4KTV_NAME" ;;
    "4kmovies") PLEX_SRC="$PLEX_4KMOVIES_SRC"; PLEX_NAME="$PLEX_4KMOVIES_NAME" ;;
    *)          log_error "Unknown type: $TYPE. Plex update may fail.";;
esac

mkdir -p "$SOURCE_DIR"
mkdir -p "$DEST_DIR"

POLL_INTERVAL=30
MIN_FILE_AGE=5 

log "$SOURCE_DIR"

while true; do
    find "$SOURCE_DIR" -maxdepth 1 -iname "*.mkv" -mmin +"$MIN_FILE_AGE" | while read -r FILE; do
        FILENAME=$(basename "$FILE")
        TEMP_FILE="$SOURCE_DIR/processing_$FILENAME"
        MODIFIED=false
        
        # Identify English, non-forced subtitles
        REMOVABLE_IDS=$(mkvmerge --identify "$FILE" --identification-format json | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == false) | .id' | tr '\n' ',' | sed 's/,$//')

        if [ -n "$REMOVABLE_IDS" ]; then
            log "Match found ($REMOVABLE_IDS). Remuxing $FILENAME..."
            
            if mkvmerge -o "$TEMP_FILE" --subtitles "!$REMOVABLE_IDS" "$FILE"; then
                TARGET_FINAL="${CUSTOM_SOURCE:+$SOURCE_DIR/}$FILENAME"
                [ -z "$CUSTOM_SOURCE" ] && TARGET_FINAL="$DEST_DIR/$FILENAME"

                mv "$TEMP_FILE" "$TARGET_FINAL"
                [ "$FILE" != "$TARGET_FINAL" ] && rm "$FILE"
                
                log "Action complete: $FILENAME -> $TARGET_FINAL"
                MODIFIED=true
            else
                log "Remux failed for $FILENAME"
                rm -f "$TEMP_FILE"
            fi
        else
            if [ -z "$CUSTOM_SOURCE" ]; then
                log "No changes for $FILENAME, moving to ingest folder."
                mv "$FILE" "$DEST_DIR/$FILENAME"
            else
                log "No changes for $FILENAME. Leaving in place."
            fi
        fi

        # Trigger Plex update ONLY if $2 was set AND we actually changed something
        if [ "$MODIFIED" = true ] && [ -n "$CUSTOM_SOURCE" ]; then
            log "Triggering Plex update for $PLEX_NAME (Section $PLEX_SRC)..."
            plex_library_update "$PLEX_SRC" "$PLEX_NAME"
        fi
    done

    sleep "$POLL_INTERVAL"
done
