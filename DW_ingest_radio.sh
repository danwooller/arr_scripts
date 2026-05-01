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

OVERWRITE_FLAG="-n"
if [[ "${1,,}" == "y" ]]; then
    log "🚀 Manual Overwrite Enabled (using -y)"
    OVERWRITE_FLAG="-y"
fi

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
        # We clean the strings to remove non-alphanumeric chars for the comparison
        # This bypasses the apostrophe and case issues
        CLEAN_SHOW=$(echo "$SHOW_NAME" | tr -d "[:punct:] " | tr '[:upper:]' '[:lower:]')
        CLEAN_TARGET=$(echo "$show" | tr -d "[:punct:] " | tr '[:upper:]' '[:lower:]')

        if [[ "$CLEAN_SHOW" == *"$CLEAN_TARGET"* ]]; then
            USE_GUESTS=true
            break
        fi
    done

    # 3. Apply Metadata Logic
    if [ "$USE_GUESTS" = true ] && [ -n "$RAW_COMMENT" ]; then
        # This regex cuts everything from the first instance of these phrases:
        # " at ", " return", " with ", " play "
        FINAL_TITLE=$(echo "$RAW_COMMENT" | sed -E 's/( at | return| with | play ).*//I' | sed 's/\.$//')
        
        case "${SHOW_NAME,,}" in
            *"unbelievable truth"*)     FINAL_ARTIST="David Mitchell" ;;
            *"haven't a clue"*)         FINAL_ARTIST="Jack Dee" ;;
            *"just a minute"*)          FINAL_ARTIST="Sue Perkins" ;;
            *)                          FINAL_ARTIST="BBC Radio" ;;
        esac
    else
        # Standard fallback
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

    if ffmpeg -i "$FILE" $OVERWRITE_FLAG -loglevel error -codec copy \
        -metadata title="$FINAL_TITLE" \
        -metadata artist="$FINAL_ARTIST" \
        -metadata album_artist="$FINAL_ARTIST" \
        -metadata album="$RAW_ALBUM" \
        -metadata track="$TRACK_RAW" \
        -metadata date="$DATE" \
        "$FINAL_PATH" < /dev/null; then
        
        # If FFmpeg succeeded (either new file created or forced overwrite)
        rm "$FILE"
    else
        # If FFmpeg failed (likely because -n saw an existing file)
        log "⚠️  Output exists. Moving source to hold: $(basename "$FILE")"
        mkdir -p "$DIR_MEDIA_HOLD"
        mv "$FILE" "$DIR_MEDIA_HOLD/"
    fi
done
