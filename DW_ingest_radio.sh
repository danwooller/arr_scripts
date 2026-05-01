#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# Safety check
if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub in progress on $BASE_HOST6. Skipping."
    exit 0
fi

check_dependencies "ffprobe" "jq" "ffmpeg"

# Loop through all MP3s
find "$DIR_MEDIA_TORRENT_RADIO" -maxdepth 1 -name "*.mp3" | while read -r FILE; do
    # Reset variables
    SHOW_NAME=""
    SERIES_NUM="0"
    FINAL_TITLE=""
    FINAL_ARTIST=""
    TRACK_PAD=""

    METADATA=$(ffprobe -v quiet -print_format json -show_format "$FILE")
    
    RAW_ALBUM=$(echo "$METADATA" | jq -r '.format.tags.album // empty')
    RAW_TITLE=$(echo "$METADATA" | jq -r '.format.tags.title // empty')
    RAW_COMMENT=$(echo "$METADATA" | jq -r '.format.tags.comment // empty')
    TRACK_RAW=$(echo "$METADATA" | jq -r '.format.tags.track // "1"' | cut -d'/' -f1)
    DATE=$(echo "$METADATA" | jq -r '.format.tags.date // empty')

    # 1. Determine Show Name and Series
    SHOW_NAME=$(echo "$RAW_ALBUM" | sed -E 's/:? Series.*//I' | sed 's/:$//')
    SERIES_NUM=$(echo "$RAW_ALBUM" | grep -oP 'Series \K\d+')
    [ -z "$SHOW_NAME" ] && SHOW_NAME="Unknown Show"
    [ -z "$SERIES_NUM" ] && SERIES_NUM="0"

    # 2. Case-Insensitive Array Check
    USE_GUESTS=false
    for show in "${RADIO_GUEST[@]}"; do
        if [[ "${SHOW_NAME,,}" == "${show,,}" ]]; then
            USE_GUESTS=true
            break
        fi
    done

    # 3. Apply Metadata Logic
    if [ "$USE_GUESTS" = true ] && [[ "$RAW_COMMENT" =~ " play " ]]; then
        # Extract guests from comment
        FINAL_TITLE=$(echo "$RAW_COMMENT" | sed -E "s/ play $SHOW_NAME.*//I" | sed 's/\.$//')
        
        case "$SHOW_NAME" in
            *"Unbelievable Truth"*)     FINAL_ARTIST="David Mitchell" ;;
            *"Haven't A Clue"*)         FINAL_ARTIST="Jack Dee" ;;
            *"Just a Minute"*)          FINAL_ARTIST="Sue Perkins" ;;
            *)                          FINAL_ARTIST="BBC Radio" ;;
        esac
    else
        FINAL_TITLE="$RAW_TITLE"
        FINAL_ARTIST=$(echo "$METADATA" | jq -r '.format.tags.artist // "BBC Radio"')
    fi

    # 4. Define Paths and ALWAYS set TRACK_PAD
    printf -v TRACK_PAD "%02d" "$TRACK_RAW"
    
    TARGET_FOLDER="$DIR_MEDIA_RADIO/$SHOW_NAME/Season $SERIES_NUM"
    NEW_FILENAME="$TRACK_PAD $FINAL_TITLE.mp3"
    NEW_FILENAME=$(echo "$NEW_FILENAME" | tr -d '*?|<>')
    FINAL_PATH="$TARGET_FOLDER/$NEW_FILENAME"

    # 5. Execute
    mkdir -p "$TARGET_FOLDER"
    log "Processing: $SHOW_NAME - $FINAL_TITLE"

    ffmpeg -i "$FILE" -y -loglevel error -codec copy \
        -metadata title="$FINAL_TITLE" \
        -metadata artist="$FINAL_ARTIST" \
        -metadata album_artist="$FINAL_ARTIST" \
        -metadata album="$RAW_ALBUM" \
        -metadata track="$TRACK_RAW" \
        -metadata date="$DATE" \
        "$FINAL_PATH" < /dev/null && rm "$FILE"
done
