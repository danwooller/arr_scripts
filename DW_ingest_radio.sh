#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# Safety check for ZFS maintenance
if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub in progress on $BASE_HOST6. Skipping."
    exit 0
fi

check_dependencies "ffprobe" "jq" "ffmpeg"

FILES_PROCESSED=0
OVERWRITE_FLAG="-n"

# Check if overwrite is requested via $1 (e.g., ./script.sh y)
if [[ "${1,,}" == "y" ]]; then
    log "🚀 Manual Overwrite Enabled (using -y)"
    OVERWRITE_FLAG="-y"
fi

# Use Process Substitution (< <(find...)) to keep variable scope inside the loop
while read -r FILE; do
    # Reset variables for each iteration
    SHOW_NAME=""
    SERIES_NUM="0"
    FINAL_TITLE=""
    FINAL_ARTIST=""
    TRACK_PAD=""

    # Extract existing metadata
    METADATA=$(ffprobe -v quiet -print_format json -show_format "$FILE")
    
    RAW_ALBUM=$(echo "$METADATA" | jq -r '.format.tags.album // empty')
    RAW_TITLE=$(echo "$METADATA" | jq -r '.format.tags.title // empty')
    RAW_COMMENT=$(echo "$METADATA" | jq -r '.format.tags.comment // empty')
    TRACK_RAW=$(echo "$METADATA" | jq -r '.format.tags.track // "1"' | cut -d'/' -f1)
    DATE=$(echo "$METADATA" | jq -r '.format.tags.date // empty')

    # 1. Determine Show Name and Series
    SHOW_NAME=$(echo "$RAW_ALBUM" | sed -E 's/:? Series.*//I' | sed 's/:$//')
    SERIES_NUM=$(echo "$RAW_ALBUM" | grep -oP 'Series \K\d+')
    
    # Fallback for empty album tags
    [ -z "$SHOW_NAME" ] && SHOW_NAME="Unknown Show"
    [ -z "$SERIES_NUM" ] && SERIES_NUM="0"

    # 2. Case-Insensitive Array Check for Guest Shows
    USE_GUESTS=false
    for show in "${RADIO_GUEST[@]}"; do
        CLEAN_SHOW=$(echo "$SHOW_NAME" | tr -d "[:punct:] " | tr '[:upper:]' '[:lower:]')
        CLEAN_TARGET=$(echo "$show" | tr -d "[:punct:] " | tr '[:upper:]' '[:lower:]')

        if [[ "$CLEAN_SHOW" == *"$CLEAN_TARGET"* ]]; then
            USE_GUESTS=true
            break
        fi
    done

    # 3. Apply Metadata Logic
    if [ "$USE_GUESTS" = true ] && [ -n "$RAW_COMMENT" ]; then
        # Extract guests from comment, stripping filler phrases
        FINAL_TITLE=$(echo "$RAW_COMMENT" | sed -E 's/( at | return| with | play ).*//I' | sed 's/\.$//')
        
        case "${SHOW_NAME,,}" in
            *"unbelievable truth"*)     FINAL_ARTIST="David Mitchell" ;;
            *"haven't a clue"*)         FINAL_ARTIST="Jack Dee" ;;
            *"just a minute"*)          FINAL_ARTIST="Sue Perkins" ;;
            *)                          FINAL_ARTIST="BBC Radio" ;;
        esac
    else
        # Standard fallback for scripted shows (Dead Ringers, etc.)
        FINAL_TITLE="$RAW_TITLE"
        FINAL_ARTIST=$(echo "$METADATA" | jq -r '.format.tags.artist // "BBC Radio"')
    fi

    # 4. Define Paths and Format Track Number
    printf -v TRACK_PAD "%02d" "$TRACK_RAW"
    
    TARGET_FOLDER="$DIR_MEDIA_RADIO/$SHOW_NAME/Season $SERIES_NUM"
    NEW_FILENAME="$TRACK_PAD $FINAL_TITLE.mp3"
    NEW_FILENAME=$(echo "$NEW_FILENAME" | tr -d '*?|<>')
    FINAL_PATH="$TARGET_FOLDER/$NEW_FILENAME"

    # 5. Execute with Safety Catch
    # Catch-all for empty metadata to prevent file collisions
    if [[ -z "$SHOW_NAME" || "$SHOW_NAME" == "Unknown Show" ]] && [[ -z "$FINAL_TITLE" || "$FINAL_TITLE" == "Unknown" ]]; then
        log "⚠️  CRITICAL: Missing metadata tags. Moving to HOLD."
        mkdir -p "$DIR_MEDIA_HOLD"
        mv "$FILE" "$DIR_MEDIA_HOLD/"
        continue 
    fi

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
        
        # If successful, remove source and increment counter
        rm "$FILE"
        ((FILES_PROCESSED++))
    else
        # If skip occurred (-n) or error, move to hold
        log "⚠️  Output exists or FFmpeg failed. Moving to hold: $(basename "$FILE")"
        mkdir -p "$DIR_MEDIA_HOLD"
        mv "$FILE" "$DIR_MEDIA_HOLD/"
    fi

done < <(find "$DIR_MEDIA_TORRENT_RADIO" -maxdepth 1 -name "*.mp3")

# --- Finalization ---
if [ "$FILES_PROCESSED" -gt 0 ]; then
    log "✅ Successfully processed $FILES_PROCESSED file(s)."
    if plex_library_update "$PLEX_RADIO_SRC" "$PLEX_RADIO_NAME"; then
        log "ℹ️ Plex update for $PLEX_RADIO_NAME sent."
    fi
else
    log "ℹ️ No files were processed. Skipping Plex library update."
fi

log "🏁 DW_ingest_radio.sh script finished."
