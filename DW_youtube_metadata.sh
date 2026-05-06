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

        echo "🔍 Querying DB for: $CHANNEL_NAME..."

        # Query for both URL and Description
        # We use | as a separator to split the results later
        DB_DATA=$(sudo sqlite3 "$HOST_DB_PATH" "
            SELECT original_url, description FROM sources 
            WHERE LOWER(custom_name) LIKE LOWER('%$CHANNEL_NAME%') 
               OR LOWER(original_url) LIKE LOWER('%$CHANNEL_NAME%') 
            LIMIT 1;")

        if [ -n "$DB_DATA" ]; then
            CHANNEL_URL=$(echo "$DB_DATA" | cut -d'|' -f1)
            CHANNEL_DESC=$(echo "$DB_DATA" | cut -d'|' -f2)
            
            # Fallback if description is empty
            [ -z "$CHANNEL_DESC" ] && CHANNEL_DESC="YouTube content for $CHANNEL_NAME."

            echo "🎯 Found Match: $CHANNEL_URL"
            
            # 1. Download Poster via Docker
            sudo docker exec -i "$CONTAINER_NAME" yt-dlp --write-thumbnail --skip-download --playlist-items 0 \
                -o "$INTERNAL_ROOT/$CHANNEL_NAME/poster" "$CHANNEL_URL"

            # 2. Convert/Rename to JPG
            for ext in webp png; do
                [ -f "${CHANNEL_DIR}poster.$ext" ] && mv "${CHANNEL_DIR}poster.$ext" "${CHANNEL_DIR}poster.jpg"
            done

            # 3. Create .plexmatch with REAL description
            cat <<EOF > "${CHANNEL_DIR}.plexmatch"
Title: $CHANNEL_NAME
Summary: $CHANNEL_DESC
EOF

            # 4. Permissions
            chmod 644 "${CHANNEL_DIR}poster.jpg" "${CHANNEL_DIR}.plexmatch"
            echo "✅ Success: $CHANNEL_NAME"
        else
            echo "❌ No DB match for '$CHANNEL_NAME'."
        fi
    done
done

echo "✨ Auto-scan complete."
