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
SOURCE_DIR="${CUSTOM_SOURCE:-$DIR_MEDIA_TORRENT/$HOST/subtitles/extract/$TYPE}"
# Destination for the video file if in Auto mode
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
MIN_FILE_AGE=5 

log "Scanning for extraction: $SOURCE_DIR"

while true; do
    NEEDS_UPDATE=false

    # find -print0 handles spaces; process substitution keeps variables in scope
    while IFS= read -r -d '' SOURCE_FILE; do
        FILENAME=$(basename "$SOURCE_FILE")
        BASE_NAME="${FILENAME%.*}"
        
        # Determine subtitle destination: 
        # If manual ($2), keep it with the file. If auto, move to your sub directory.
        if [ -n "$CUSTOM_SOURCE" ]; then
            SUB_FILE="$(dirname "$SOURCE_FILE")/$BASE_NAME.srt"
        else
            SUB_FILE="$DIR_MEDIA_SUBTITLES/$BASE_NAME.srt"
        fi

        log "Checking for forced subs: $FILENAME"

        # Identify English AND Forced subtitles
        SUB_TRACK_ID=$(mkvmerge -J "$SOURCE_FILE" 2>/dev/null | jq -r '.tracks[] | select(.type == "subtitles" and .properties.language == "eng" and .properties.forced_track == true) | .id' | head -n 1)

        if [ -n "$SUB_TRACK_ID" ]; then
            log "English Forced found (ID: $SUB_TRACK_ID). Extracting to $SUB_FILE..."
            
            if mkvextract tracks "$SOURCE_FILE" "$SUB_TRACK_ID:$SUB_FILE"; then
                log "Extraction successful."
                [ -n "$CUSTOM_SOURCE" ] && NEEDS_UPDATE=true
            else
                log "Extraction failed for $FILENAME"
            fi
        else
            log "No English forced subtitles found."
        fi

        # Ingest Logic: If NO custom source was provided, move the video file to completed
        if [ -z "$CUSTOM_SOURCE" ]; then
            log "Moving video to ingest folder: $DEST_DIR"
            mv "$SOURCE_FILE" "$DEST_DIR/"
        fi

    done < <(find "$SOURCE_DIR" -type f \( -iname "*.mkv" -o -iname "*.mp4" \) -mmin +$MIN_FILE_AGE -print0)

    # Trigger Plex scan only if we added subs to a library folder ($2)
    if [ "$NEEDS_UPDATE" = true ]; then
        log "Finished batch. Triggering Plex update for $PLEX_NAME..."
        plex_library_update "$PLEX_SRC" "$PLEX_NAME"
    fi

    # Exit vs Sleep logic
    if [ -n "$CUSTOM_SOURCE" ]; then
        log "Manual extraction complete. Exiting."
        exit 0
    else
        log "Cycle complete. Sleeping for $POLL_INTERVAL seconds..."
        sleep "$POLL_INTERVAL"
    fi
done
