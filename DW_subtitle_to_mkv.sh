#!/bin/bash

# scan through the subtitles backup and then looks for the corresponding
# episode and check whether the forced subtitle is present.
# If not the files are copied/moved for processing by DW_merge_forced_subtitles.sh

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# Safety check: Don't run during a ZFS scrub
if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub currently in progress on $BASE_HOST6. Exiting to protect disks."
    exit 0
fi

# Define staging area
STAGING_DIR="$DIR_MEDIA_TORRENT/${HOST}/subtitles/forced"
mkdir -p "$STAGING_DIR"

log "🚀 Starting full library sync and restoration..."

# Loop through SRT files
find "$DIR_MEDIA_SUBTITLES/forced/tv" -name "*.srt" | while read -r SRT_PATH; do
    SRT_DIR=$(dirname "$SRT_PATH")
    SRT_FILE=$(basename "$SRT_PATH")
    
    # Extract parts: SHOW_1x01_EPISODE.srt
    if [[ $SRT_FILE =~ ^(.*)_([0-9]+)x([0-9]+)_(.*)\.srt$ ]]; then
        RAW_SHOW_NAME="${BASH_REMATCH[1]}"
        FUZZY_SHOW_NAME=$(echo "$RAW_SHOW_NAME" | sed 's/[-_ ]//g' | tr '[:upper:]' '[:lower:]')
        
        S_CODE="${BASH_REMATCH[2]}x${BASH_REMATCH[3]}"
        E_CODE=$(printf "S%02dE%02d" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")

        MATCH_FOUND=false
        
        for BASE_TV_DIR in "${DIR_SDTV[@]}"; do
            # Find candidate MKVs using fuzzy matching
            MKV_PATH=$(find "$BASE_TV_DIR" -type f -iname "*.mkv" | grep -Ei "$S_CODE|$E_CODE" | while read -r candidate; do
                FUZZY_CANDIDATE=$(basename "$candidate" | sed 's/[-_ ]//g' | tr '[:upper:]' '[:lower:]')
                if [[ "$FUZZY_CANDIDATE" == *"$FUZZY_SHOW_NAME"* ]]; then
                    echo "$candidate"
                    break
                fi
            done | head -n 1)

            if [ -n "$MKV_PATH" ]; then
                # 1. PERMANENT RENAME AT SOURCE
                # Define the new name based on the video file found
                MKV_FILENAME=$(basename "$MKV_PATH")
                SYNCED_SRT_NAME="${MKV_FILENAME%.mkv}.srt"
                NEW_SRT_PATH="$SRT_DIR/$SYNCED_SRT_NAME"

                if [ "$SRT_FILE" != "$SYNCED_SRT_NAME" ]; then
                    log "📝 Syncing filename: $SRT_FILE -> $SYNCED_SRT_NAME"
                    mv "$SRT_PATH" "$NEW_SRT_PATH"
                    # Update variable for the rest of this loop iteration
                    CURRENT_SRT_PATH="$NEW_SRT_PATH"
                else
                    CURRENT_SRT_PATH="$SRT_PATH"
                fi

                # 2. CHECK FORCED STATUS (STAGING ONLY)
                HAS_FORCED=$(ffprobe -v error -select_streams s -show_entries stream_disposition=forced -of csv=p=0 "$MKV_PATH" | grep -c "1")
                
                if [ "$HAS_FORCED" -gt 0 ]; then
                    log "⏭️  SKIPPING STAGING: $(basename "$MKV_PATH") already fixed."
                    MATCH_FOUND=true
                    break
                fi

                # 3. STAGE FOR PROCESSING
                log "✅ MATCH FOUND: Staging $MKV_FILENAME"
                cp "$CURRENT_SRT_PATH" "$STAGING_DIR/"
                mv "$MKV_PATH" "$STAGING_DIR/"
                
                MATCH_FOUND=true
                break
            fi
        done

        if [ "$MATCH_FOUND" = false ]; then
            log "❌ NOT FOUND: $SRT_FILE"
        fi
    fi
done

log "🏁 Task complete. Subtitle library synced and missing files staged."
exit 0
