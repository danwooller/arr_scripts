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
    echo "Processing: $FILE"

    # 1. Extract Metadata using ffprobe and jq
    METADATA=$(ffprobe -v quiet -print_format json -show_format "$FILE")
    
    # Extract guests for the title
    GUESTS=$(echo "$METADATA" | jq -r '.format.tags.comment // empty' | sed 's/ play The Unbelievable Truth.*//g' | sed 's/\.$//')

    if [ -z "$GUESTS" ]; then
        FINAL_TITLE=$(echo "$METADATA" | jq -r '.format.tags.title // "Unknown Episode"')
    else
        FINAL_TITLE="$GUESTS"
    fi

    # 2. Parse Series and Track
    RAW_ALBUM=$(echo "$METADATA" | jq -r '.format.tags.album // empty')
    SERIES_NUM=$(echo "$RAW_ALBUM" | grep -oP 'Series \K\d+')
    
    # Ensure we have a show name for the path
    SHOW_NAME="The Unbelievable Truth"
    
    TRACK_RAW=$(echo "$METADATA" | jq -r '.format.tags.track // "1"' | cut -d'/' -f1)
    printf -v TRACK_PAD "%02d" "$TRACK_RAW"

    # 3. Define Paths
    TARGET_FOLDER="$DIR_MEDIA_RADIO/$SHOW_NAME/Season $SERIES_NUM"
    NEW_FILENAME="$TRACK_PAD $FINAL_TITLE.mp3"
    FINAL_PATH="$TARGET_FOLDER/$NEW_FILENAME"

    echo "    Moving to: $FINAL_PATH"

    # 4. Create directory if it doesn't exist
    mkdir -p "$TARGET_FOLDER"

    # 5. Move and Fix Metadata
    # Changed $TITLE to $FINAL_TITLE
    ffmpeg -i "$FILE" -n -loglevel error -codec copy \
        -metadata title="$FINAL_TITLE" \
        -metadata artist="David Mitchell" \
        -metadata album_artist="David Mitchell" \
        -metadata album="$SHOW_NAME: Series $SERIES_NUM" \
        -metadata track="$TRACK_RAW" \
        -metadata date="$(echo "$METADATA" | jq -r '.format.tags.date')" \
        "$FINAL_PATH" && rm "$FILE"
done
