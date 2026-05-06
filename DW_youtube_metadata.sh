#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"

# --- CONFIGURATION ---
HOST_DB_PATH="/opt/docker/pinchflat/config/db/pinchflat.db" 
CONTAINER_NAME="pinchflat"
TEMP_DIR="/tmp/yt_metadata"

# Ensure temp directory exists
mkdir -p "$TEMP_DIR"

declare -A PATH_MAP=(
    ["$DIR_MEDIA_YOUTUBE"]="/downloads"
    ["$DIR_SYNOLOGY_YOUTUBE"]="/synology"
)

echo "🕵️ Starting YouTube Metadata Auto-Scan..."

for HOST_ROOT in "${!PATH_MAP[@]}"; do
    INTERNAL_ROOT="${PATH_MAP[$HOST_ROOT]}"
    
    for CHANNEL_DIR in "$HOST_ROOT"/*/; do
        [ -d "$CHANNEL_DIR" ] || continue
        CHANNEL_NAME=$(basename "$CHANNEL_DIR")
        
        if [ -f "${CHANNEL_DIR}poster.jpg" ] && [ -f "${CHANNEL_DIR}.plexmatch" ]; then
            echo "⏩ Skipping $CHANNEL_NAME"
            continue
        fi

        echo "🔍 Querying DB for: $CHANNEL_NAME..."

        # Query for URL and Description
        CHANNEL_URL=$(sudo sqlite3 "$HOST_DB_PATH" "SELECT original_url FROM sources WHERE LOWER(custom_name) LIKE LOWER('%$CHANNEL_NAME%') OR LOWER(original_url) LIKE LOWER('%$CHANNEL_NAME%') LIMIT 1;" | tr -d '\r\n')
        CHANNEL_DESC=$(sudo sqlite3 "$HOST_DB_PATH" "SELECT description FROM sources WHERE LOWER(custom_name) LIKE LOWER('%$CHANNEL_NAME%') OR LOWER(original_url) LIKE LOWER('%$CHANNEL_NAME%') LIMIT 1;")

        if [[ "$CHANNEL_URL" == http* ]]; then
            echo "🎯 Found Match: $CHANNEL_URL"
            
            # 1. Download to LOCAL /tmp first to avoid mount issues
            # We use the container to download, but we output it to a bind-mounted temp path
            # (Assuming /tmp is shared or we just use the container's stdout)
            
            echo "📥 Downloading poster to local storage..."
            sudo docker exec -i "$CONTAINER_NAME" yt-dlp --write-thumbnail --skip-download \
                --playlist-items 0 --no-playlist --convert-thumbnails jpg \
                -o "/tmp/poster" "$CHANNEL_URL" > /dev/null 2>&1

            # 2. Extract the file FROM the container to the host
            # This is the most reliable way to get a file out of a container
            sudo docker cp "$CONTAINER_NAME:/tmp/poster.jpg" "${CHANNEL_DIR}poster.jpg" 2>/dev/null
            
            # 3. Clean up the container's temp file
            sudo docker exec -i "$CONTAINER_NAME" rm -f /tmp/poster.jpg

            # 4. Create .plexmatch
            [ -z "$CHANNEL_DESC" ] && CHANNEL_DESC="YouTube content for $CHANNEL_NAME."
            cat <<EOF > "${CHANNEL_DIR}.plexmatch"
Title: $CHANNEL_NAME
Summary: $CHANNEL_DESC
EOF

            # 5. Force permissions and sync
            sync
            if [ -f "${CHANNEL_DIR}poster.jpg" ]; then
                chmod 644 "${CHANNEL_DIR}poster.jpg"
                chmod 644 "${CHANNEL_DIR}.plexmatch"
                echo "✅ Success: $CHANNEL_NAME"
            else
                echo "⚠️ Poster copy failed. Trying fallback move..."
                # Fallback: Check if it actually landed in the Synology path despite the error
                find "$CHANNEL_DIR" -name "poster*" -exec mv {} "${CHANNEL_DIR}poster.jpg" \; 2>/dev/null
            fi
        else
            echo "❌ No DB match for '$CHANNEL_NAME'."
        fi
    done
done

echo "✨ Auto-scan complete."
