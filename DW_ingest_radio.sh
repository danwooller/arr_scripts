#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# Safety check: Don't run during a ZFS scrub
if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub in progress on $BASE_HOST6. Skipping backup to protect I/O."
    exit 0
fi

check_dependencies "ffprobe" "jq" "ffmpeg"

# Loop through all MP3s in the source
find "$DIR_MEDIA_TORRENT_RADIO" -maxdepth 1 -name "*.mp3" | while read -r FILE; do
    # --- RESET VARIABLES ---
    SHOW_NAME=""
    SERIES_NUM="0"
    FINAL_TITLE=""
    FINAL_ARTIST=""
    # -----------------------

    echo "------------------------------------------------"
    echo "Processing: $(basename "$FILE")"

    # 1. Extract Metadata
    METADATA=$(ffprobe -v quiet -print_format json -show_format "$FILE")
    
    RAW_ALBUM=$(echo "$METADATA" | jq -r '.format.tags.album // empty')
    RAW_TITLE=$(echo "$METADATA" | jq -r '.format.tags.title // empty')
    RAW_COMMENT=$(echo "$METADATA" | jq -r '.format.tags.comment // empty')
    TRACK_RAW=$(echo "$METADATA" | jq -r '.format.tags.track // "1"' | cut -d'/' -f1)
    DATE=$(echo "$METADATA" | jq -r '.format.tags.date // empty')

    # 2. Determine Show Name and Series
    if [ -n "$RAW_ALBUM" ]; then
        SHOW_NAME=$(echo "$RAW_ALBUM" | sed -E 's/:? Series.*//I' | sed 's/:$//')
        SERIES_NUM=$(echo "$RAW_ALBUM" | grep -oP 'Series \K\d+')
    fi

    # Fallback if Album tag is missing or Series not found
    [ -z "$SHOW_NAME" ] && SHOW_NAME="Unknown Show"
    [ -z "$SERIES_NUM" ] && SERIES_NUM="0"

    # 3. Specific Handling for "The Unbelievable Truth"
    if [[ "$SHOW_NAME" == "The Unbelievable Truth" ]]; then
        FINAL_TITLE=$(echo "$RAW_COMMENT" | sed 's/ play The Unbelievable Truth.*//I' | sed 's/\.$//')
        FINAL_ARTIST="David Mitchell"
    else
        FINAL_TITLE="$RAW_TITLE"
        FINAL_ARTIST=$(echo "$METADATA" | jq -r '.format.tags.artist // "BBC Radio"')
    fi

    # 4. Define Paths
    printf -v TRACK_PAD "%02d" "$TRACK_RAW"
    TARGET_FOLDER="$DIR_MEDIA_RADIO/$SHOW_NAME/Season $SERIES_NUM"
    NEW_FILENAME="$TRACK_PAD $FINAL_TITLE.mp3"
    
    # Sanitize filename
    NEW_FILENAME=$(echo "$NEW_FILENAME" | tr -d '*?|<>')
    FINAL_PATH="$TARGET_FOLDER/$NEW_FILENAME"

    echo "    Show: $SHOW_NAME (Series $SERIES_NUM)"
    echo "    Dest: $FINAL_PATH"

    mkdir -p "$TARGET_FOLDER"

    # 5. The Critical Fix: Added < /dev/null to prevent ffmpeg from reading stdin
    ffmpeg -i "$FILE" -n -loglevel error -codec copy \
        -metadata title="$FINAL_TITLE" \
        -metadata artist="$FINAL_ARTIST" \
        -metadata album_artist="$FINAL_ARTIST" \
        -metadata album="$RAW_ALBUM" \
        -metadata track="$TRACK_RAW" \
        -metadata date="$DATE" \
        "$FINAL_PATH" < /dev/null && rm "$FILE"
done
