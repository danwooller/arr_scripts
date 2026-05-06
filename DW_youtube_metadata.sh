#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"

# --- CONFIGURATION ---
HOST_DB_PATH="/opt/docker/pinchflat/config/db/pinchflat.db" 
CONTAINER_NAME="pinchflat"

declare -A PATH_MAP=(
    ["$DIR_MEDIA_YOUTUBE"]="/downloads"
    ["$DIR_SYNOLOGY_YOUTUBE"]="/synology"
)

# 1. Verify DB Access
if [ ! -f "$HOST_DB_PATH" ]; then
    echo "❌ DB not found at $HOST_DB_PATH."
    exit 1
fi

echo "🕵️ Starting YouTube Metadata Auto-Scan..."

for HOST_ROOT in "${!PATH_MAP[@]}"; do
    INTERNAL_ROOT="${PATH_MAP[$HOST_ROOT]}"
    
    for CHANNEL_DIR in "$HOST_ROOT"/*/; do
        [ -d "$CHANNEL_DIR" ] || continue
        CHANNEL_NAME=$(basename "$CHANNEL_DIR")
        
        # Skip if assets already exist
        if [ -f "${CHANNEL_DIR}poster.jpg" ] && [ -f "${CHANNEL_DIR}.plexmatch" ]; then
            echo "⏩ Skipping $CHANNEL_NAME"
            continue
        fi

        echo "🔍 Querying DB for folder: $CHANNEL_NAME..."

        # Query using LOWER() and LIKE for maximum flexibility
        # This matches if the folder name is anywhere in the URL, name, or custom_name
        CHANNEL_URL=$(sudo sqlite3 "$HOST_DB_PATH" "
            SELECT url FROM sources 
            WHERE LOWER(custom_name) LIKE LOWER('%$CHANNEL_NAME%') 
               OR LOWER(name) LIKE LOWER('%$CHANNEL_NAME%') 
               OR LOWER(url) LIKE LOWER('%$CHANNEL_NAME%') 
            LIMIT 1;")

        if [[ "$CHANNEL_URL" == http* ]]; then
            echo "🎯 Found Match: $CHANNEL_URL"
            
            # Download via Docker
            sudo docker exec -i "$CONTAINER_NAME" yt-dlp --write-thumbnail --skip-download --playlist-items 0 \
                -o "$INTERNAL_ROOT/$CHANNEL_NAME/poster" "$CHANNEL_URL"

            # Rename/Clean up
            for ext in webp png; do
                if [ -f "${CHANNEL_DIR}poster.$ext" ]; then
                    mv "${CHANNEL_DIR}poster.$ext" "${CHANNEL_DIR}poster.jpg"
                fi
            done

            # Create .plexmatch
            echo -e "Title: $CHANNEL_NAME\nSummary: YouTube content for $CHANNEL_NAME." > "${CHANNEL_DIR}.plexmatch"
            
            # Permissions
            chmod 644 "${CHANNEL_DIR}poster.jpg" "${CHANNEL_DIR}.plexmatch"
            echo "✅ Created poster and .plexmatch for $CHANNEL_NAME"
        else
            echo "❌ No DB match for '$CHANNEL_NAME'. Double check the name in Pinchflat."
        fi
    done
done

echo "✨ Auto-scan complete."
