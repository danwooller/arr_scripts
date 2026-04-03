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

log "🚀 Starting subtitle restoration scan (Flexible Naming Mode)..."

# Loop through SRT files (Format: SHOW_1x01_EPISODE.srt)
find "$DIR_MEDIA_SUBTITLES/forced/tv" -name "*.srt" | while read -r SRT_PATH; do
    SRT_FILE=$(basename "$SRT_PATH")
    
    # Extract parts: SHOW_1x01_EPISODE.srt
    if [[ $SRT_FILE =~ ^(.*)_([0-9]+)x([0-9]+)_(.*)\.srt$ ]]; then
        # The raw name from the SRT (has underscores)
        RAW_SHOW_NAME="${BASH_REMATCH[1]}"
        # The sanitized name for searching (replace underscores with spaces)
        CLEAN_SHOW_NAME="${RAW_SHOW_NAME//_/ }"
        
        SEASON="${BASH_REMATCH[2]}"
        EPISODE="${BASH_REMATCH[3]}"
        
        # Search patterns
        SEARCH_STR="${SEASON}x${EPISODE}"
        ALT_SEARCH_STR=$(printf "S%02dE%02d" "$SEASON" "$EPISODE")

        MATCH_FOUND=false
        for BASE_TV_DIR in "${DIR_SDTV[@]}"; do
            # 1. We search for the Show Name using either underscores OR spaces
            # 2. We search for the Season/Episode code
            MKV_PATH=$(find "$BASE_TV_DIR" -type f -name "*.mkv" | \
                grep -Ei "($RAW_SHOW_NAME|$CLEAN_SHOW_NAME)" | \
                grep -Ei "($SEARCH_STR|$ALT_SEARCH_STR)" | head -n 1)

            if [ -n "$MKV_PATH" ]; then
                # Check for existing forced subtitle track
                HAS_FORCED=$(ffprobe -v error -select_streams s -show_entries stream_disposition=forced -of csv=p=0 "$MKV_PATH" | grep -c "1")

                if [ "$HAS_FORCED" -gt 0 ]; then
                    log "⏭️ SKIPPING: $(basename "$MKV_PATH") already has a forced subtitle track."
                    MATCH_FOUND=true
                    break
                fi

                log "✅ Match found (Space/Underscore flex): $(basename "$MKV_PATH")"
                
                cp "$SRT_PATH" "$STAGING_DIR/"
                mv "$MKV_PATH" "$STAGING_DIR/"
                
                MATCH_FOUND=true
                break
            fi
        done

        if [ "$MATCH_FOUND" = false ]; then
            log "❌ No MKV match found for: $SRT_FILE (Checked '$CLEAN_SHOW_NAME' and '$RAW_SHOW_NAME')"
        fi
    fi
done

log "🏁 Restoration staging complete."
exit 0
