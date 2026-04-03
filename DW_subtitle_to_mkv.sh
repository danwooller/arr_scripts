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
    
    # Extract parts: Hijack_1x06_Comply_Slowly.srt
    # BASH_REMATCH[1] = Hijack
    # BASH_REMATCH[2] = 1
    # BASH_REMATCH[3] = 06
    if [[ $SRT_FILE =~ ^(.*)_([0-9]+)x([0-9]+)_(.*)\.srt$ ]]; then
        RAW_SHOW_NAME="${BASH_REMATCH[1]}"
        # Replace underscores with spaces for the show name search
        CLEAN_SHOW_NAME="${RAW_SHOW_NAME//_/ }"
        
        SEASON="${BASH_REMATCH[2]}"
        EPISODE="${BASH_REMATCH[3]}"
        
        # Define the two most common episode formats
        S_CODE="${SEASON}x${EPISODE}"               # e.g., 1x06
        E_CODE=$(printf "S%02dE%02d" "$SEASON" "$EPISODE") # e.g., S01E06

        MATCH_FOUND=false
        
        for BASE_TV_DIR in "${DIR_SDTV[@]}"; do
            # 1. Find all MKVs in the directory
            # 2. Filter for the episode code (1x06 or S01E06)
            # 3. Filter for the Show Name (Hijack)
            # We use -i for case-insensitive to be safe
            MKV_PATH=$(find "$BASE_TV_DIR" -type f -name "*.mkv" | \
                grep -iE "$S_CODE|$E_CODE" | \
                grep -iE "$RAW_SHOW_NAME|$CLEAN_SHOW_NAME" | head -n 1)

            if [ -n "$MKV_PATH" ]; then
                # Check for existing forced subtitle track
                HAS_FORCED=$(ffprobe -v error -select_streams s -show_entries stream_disposition=forced -of csv=p=0 "$MKV_PATH" | grep -c "1")

                if [ "$HAS_FORCED" -gt 0 ]; then
                    log "⏭️ SKIPPING: $(basename "$MKV_PATH") already has forced subs."
                    MATCH_FOUND=true
                    break
                fi

                log "✅ MATCH: $(basename "$MKV_PATH")"
                
                cp "$SRT_PATH" "$STAGING_DIR/"
                mv "$MKV_PATH" "$STAGING_DIR/"
                
                MATCH_FOUND=true
                break
            fi
        done

        if [ "$MATCH_FOUND" = false ]; then
            log "❌ NOT FOUND: $SRT_FILE (Looked for '$S_CODE'/'$E_CODE' + '$CLEAN_SHOW_NAME' in ${DIR_SDTV[*]})"
        fi
    fi
done

log "🏁 Restoration staging complete."
exit 0
