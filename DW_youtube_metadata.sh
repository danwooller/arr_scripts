#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"

# Configuration
CONTAINER_NAME="pinchflat"
DB_PATH="/opt/docker/pinchflat/config/db/pinchflat.db" # Standard path inside Pinchflat container

# Map host paths to internal container paths
declare -A PATH_MAP=(
    ["$DIR_MEDIA_YOUTUBE"]="/downloads"
    ["$DIR_SYNOLOGY_YOUTUBE"]="/synology"
)

echo "🕵️ Starting YouTube Metadata Auto-Scan (via Pinchflat DB)..."

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

        # Query the DB directly on the host
        # Using LIKE to handle case-sensitivity and @ handles
        CHANNEL_URL=$(sqlite3 "$HOST_DB_PATH" "SELECT url FROM sources WHERE custom_name LIKE '$CHANNEL_NAME' OR name LIKE '$CHANNEL_NAME' OR url LIKE '%/$CHANNEL_NAME' OR url LIKE '%/@$CHANNEL_NAME' LIMIT 1;")

        if [[ "$CHANNEL_URL" == http* ]]; then
            echo "🎯 Found Match: $CHANNEL_URL"
            
            # Use the container ONLY for the yt-dlp download part
            docker exec -i "$CONTAINER_NAME" yt-dlp --write-thumbnail --skip-download --playlist-items 0 \
                -o "$INTERNAL_ROOT/$CHANNEL_NAME/poster" "$CHANNEL_URL"

            # Rename/Clean up
            for ext in webp png; do
                [ -f "${CHANNEL_DIR}poster.$ext" ] && mv "${CHANNEL_DIR}poster.$ext" "${CHANNEL_DIR}poster.jpg"
            done

            # Create .plexmatch
            echo -e "Title: $CHANNEL_NAME\nSummary: YouTube content for $CHANNEL_NAME." > "${CHANNEL_DIR}.plexmatch"
            chmod 644 "${CHANNEL_DIR}poster.jpg" "${CHANNEL_DIR}.plexmatch"
            echo "✅ Success for $CHANNEL_NAME"
        else
            echo "❌ No DB match for '$CHANNEL_NAME'. Check if name matches Pinchflat exactly."
        fi
    done
done
echo "✨ Auto-scan complete."
