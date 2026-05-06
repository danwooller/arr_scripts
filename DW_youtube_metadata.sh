#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"

# Configuration
CONTAINER_NAME="pinchflat"
DB_PATH="/config/db/pinchflat.db" # Standard path inside Pinchflat container

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
        
        # Skip if metadata exists
        if [ -f "${CHANNEL_DIR}poster.jpg" ] && [ -f "${CHANNEL_DIR}.plexmatch" ]; then
            echo "⏩ Skipping $CHANNEL_NAME (Metadata exists)"
            continue
        fi

        echo "🔍 Querying Pinchflat for: $CHANNEL_NAME..."

        # Query the Pinchflat DB for the URL where custom_name matches the folder
        # The table is usually 'sources' and the column is 'custom_name' or 'name'
        CHANNEL_URL=$(docker exec "$CONTAINER_NAME" sqlite3 "$DB_PATH" \
            "SELECT url FROM sources WHERE custom_name='$CHANNEL_NAME' OR name='$CHANNEL_NAME' LIMIT 1;")

        if [[ "$CHANNEL_URL" == http* ]]; then
            echo "🎯 Found Match: $CHANNEL_URL"
            
            # 1. Download Poster
            docker exec "$CONTAINER_NAME" yt-dlp --write-thumbnail --skip-download --playlist-items 0 \
                -o "$INTERNAL_ROOT/$CHANNEL_NAME/poster" "$CHANNEL_URL"

            # 2. Convert to JPG
            for ext in webp png; do
                [ -f "${CHANNEL_DIR}poster.$ext" ] && mv "${CHANNEL_DIR}poster.$ext" "${CHANNEL_DIR}poster.jpg"
            done

            # 3. Create .plexmatch
            echo -e "Title: $CHANNEL_NAME\nSummary: YouTube content for $CHANNEL_NAME." > "${CHANNEL_DIR}.plexmatch"

            # 4. Set Permissions
            chmod 644 "${CHANNEL_DIR}poster.jpg" "${CHANNEL_DIR}.plexmatch"
            echo "✅ Assets created for $CHANNEL_NAME"
        else
            echo "❌ No matching source found in Pinchflat for '$CHANNEL_NAME'."
        fi
    done
done

echo "✨ Auto-scan complete."
