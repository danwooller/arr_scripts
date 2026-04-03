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

log "🚀 Starting subtitle restoration scan (skipping files with existing forced subs)..."

# Loop through SRT files
find "$DIR_MEDIA_SUBTITLES/forced/tv" -name "*.srt" | while read -r SRT_PATH; do
    SRT_FILE=$(basename "$SRT_PATH")
    
    # Extract parts: SHOW_1x01_EPISODE.srt
    if [[ $SRT_FILE =~ ^(.*)_([0-9]+)x([0-9]+)_(.*)\.srt$ ]]; then
        SHOW_NAME="${BASH_REMATCH[1]}"
        SEASON="${BASH_REMATCH[2]}"
        EPISODE="${BASH_REMATCH[3]}"
        
        SEARCH_STR="${SEASON}x${EPISODE}"
        ALT_SEARCH_STR=$(printf "S%02dE%02d" "$SEASON" "$EPISODE")

        MATCH_FOUND=false
        for BASE_TV_DIR in "${DIR_SDTV[@]}"; do
            # Find the candidate mkv
            MKV_PATH=$(find "$BASE_TV_DIR" -type f -name "*.mkv" | grep -i "$SHOW_NAME" | grep -Ei "($SEARCH_STR|$ALT_SEARCH_STR)" | head -n 1)

            if [ -n "$MKV_PATH" ]; then
                # --- NEW CHECK: Check for existing forced subtitle stream ---
                # This returns "1" if a forced subtitle is found, "0" otherwise
                HAS_FORCED=$(ffprobe -v error -select_streams s -show_entries stream_disposition=forced -of csv=p=0 "$MKV_PATH" | grep -c "1")

                if [ "$HAS_FORCED" -gt 0 ]; then
                    log "⏭️ SKIPPING: $(basename "$MKV_PATH") already has a forced subtitle track."
                    MATCH_FOUND=true # Mark as found so we don't log a "not found" error, but we don't move it
                    break
                fi
                # -------------------------------------------------------------

                log "✅ Missing forced sub. Staging: $(basename "$MKV_PATH")"
                
                cp "$SRT_PATH" "$STAGING_DIR/"
                mv "$MKV_PATH" "$STAGING_DIR/"
                
                MATCH_FOUND=true
                break
            fi
        done

        if [ "$MATCH_FOUND" = false ]; then
            log "❌ No MKV match found for: $SRT_FILE"
        fi
    fi
done

log "🏁 Restoration staging complete."
exit 0
