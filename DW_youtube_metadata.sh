#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"

# --- CONFIGURATION ---
HOST_DB_PATH="/opt/docker/pinchflat/config/db/pinchflat.db" 
CONTAINER_NAME="pinchflat"

log "🕵️ Starting YouTube Metadata Auto-Scan..."

NEW_ASSETS=false

for HOST_ROOT in "${!DIR_YOUTUBE[@]}"; do
    INTERNAL_ROOT="${DIR_YOUTUBE[$HOST_ROOT]}"
    
    for CHANNEL_DIR in "$HOST_ROOT"/*/; do
        [ -d "$CHANNEL_DIR" ] || continue
        CHANNEL_NAME=$(basename "$CHANNEL_DIR")
        
        # Skip if assets already exist
        if [ -f "${CHANNEL_DIR}poster.jpg" ] && [ -f "${CHANNEL_DIR}.plexmatch" ]; then
            [[ $LOG_LEVEL == "debug" ]] && log "⏩ Skipping $CHANNEL_NAME"
            continue
        fi

        [[ $LOG_LEVEL == "debug" ]] && log "🔍 Querying DB for: $CHANNEL_NAME..."

        # Query for URL and Description (using original_url for your DB version)
        CHANNEL_URL=$(sudo sqlite3 "$HOST_DB_PATH" "SELECT original_url FROM sources WHERE LOWER(custom_name) LIKE LOWER('%$CHANNEL_NAME%') OR LOWER(original_url) LIKE LOWER('%$CHANNEL_NAME%') LIMIT 1;" | tr -d '\r\n')
        CHANNEL_DESC=$(sudo sqlite3 "$HOST_DB_PATH" "SELECT description FROM sources WHERE LOWER(custom_name) LIKE LOWER('%$CHANNEL_NAME%') OR LOWER(original_url) LIKE LOWER('%$CHANNEL_NAME%') LIMIT 1;")

        if [[ "$CHANNEL_URL" == http* ]]; then
            [[ $LOG_LEVEL == "debug" ]] && log "🎯 Found Match: $CHANNEL_URL"
            
            # 1. Download to container's internal /tmp
            sudo docker exec -i "$CONTAINER_NAME" yt-dlp --write-thumbnail --skip-download \
                --playlist-items 0 --no-playlist --convert-thumbnails jpg \
                -o "/tmp/poster" "$CHANNEL_URL" > /dev/null 2>&1

            # 2. Extract directly to the Synology folder
            sudo docker cp "$CONTAINER_NAME:/tmp/poster.jpg" "${CHANNEL_DIR}poster.jpg" 2>/dev/null
            
            # 3. Clean up container
            sudo docker exec -i "$CONTAINER_NAME" rm -f /tmp/poster.jpg

            # 4. Create .plexmatch
            [ -z "$CHANNEL_DESC" ] && CHANNEL_DESC="YouTube content for $CHANNEL_NAME."
            cat <<EOF > "${CHANNEL_DIR}.plexmatch"
Title: $CHANNEL_NAME
Summary: $CHANNEL_DESC
EOF

            # 5. Finalize
            sync
            if [ -f "${CHANNEL_DIR}poster.jpg" ]; then
                chmod 644 "${CHANNEL_DIR}poster.jpg" "${CHANNEL_DIR}.plexmatch"
                [[ $LOG_LEVEL == "debug" ]] && log "✅ Success: $CHANNEL_NAME"
                NEW_ASSETS=true
            else
                [[ $LOG_LEVEL == "debug" ]] && log "⚠️ Poster download failed for $CHANNEL_NAME"
            fi
        else
            log "❌ No DB match for '$CHANNEL_NAME'."
        fi
    done
done

[ "$NEW_ASSETS" = true ] && [[ $LOG_LEVEL == "debug" ]] && log "🔄 New metadata added. Plex should pick this up on its next scan."
[[ $LOG_LEVEL == "debug" ]] && log "✨ Auto-scan complete."
