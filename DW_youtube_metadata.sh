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

        echo "🔍 Querying DB for: $CHANNEL_NAME..."

        # Use -line mode to make parsing easier and more robust
        CHANNEL_URL=$(sudo sqlite3 "$HOST_DB_PATH" "SELECT original_url FROM sources WHERE LOWER(custom_name) LIKE LOWER('%$CHANNEL_NAME%') OR LOWER(original_url) LIKE LOWER('%$CHANNEL_NAME%') LIMIT 1;")
        CHANNEL_DESC=$(sudo sqlite3 "$HOST_DB_PATH" "SELECT description FROM sources WHERE LOWER(custom_name) LIKE LOWER('%$CHANNEL_NAME%') OR LOWER(original_url) LIKE LOWER('%$CHANNEL_NAME%') LIMIT 1;")

        # Clean up the variables (remove potential carriage returns)
        CHANNEL_URL=$(echo "$CHANNEL_URL" | tr -d '\r\n')

        if [[ "$CHANNEL_URL" == http* ]]; then
            echo "🎯 Found Match: $CHANNEL_URL"
            
            # 1. Download Poster via Docker
            # Added --no-cache-dir to ensure we aren't getting old hits
            sudo docker exec -i "$CONTAINER_NAME" yt-dlp --write-thumbnail --skip-download \
                --playlist-items 0 --no-playlist --no-cache-dir \
                --convert-thumbnails jpg \
                -o "$INTERNAL_ROOT/$CHANNEL_NAME/poster" "$CHANNEL_URL"

            # 2. FORCE SYNC
            # This tells Ubuntu to flush all mount buffers and refresh the file list
            sync
            sleep 2 

            # 3. Handle the rename with a broader search
            # We look for anything 'poster' and force it to be 'poster.jpg'
            MATCHED_FILE=$(find "$CHANNEL_DIR" -maxdepth 1 -name "poster*" | head -n 1)

            if [ -n "$MATCHED_FILE" ]; then
                if [[ "$MATCHED_FILE" != *.jpg ]]; then
                    mv "$MATCHED_FILE" "${CHANNEL_DIR}poster.jpg"
                fi
                
                # 4. Create .plexmatch
                [ -z "$CHANNEL_DESC" ] && CHANNEL_DESC="YouTube content for $CHANNEL_NAME."
                cat <<EOF > "${CHANNEL_DIR}.plexmatch"
Title: $CHANNEL_NAME
Summary: $CHANNEL_DESC
EOF

                # 5. Fix Permissions immediately
                chmod 644 "${CHANNEL_DIR}poster.jpg" "${CHANNEL_DIR}.plexmatch"
                echo "✅ Success: $CHANNEL_NAME"
            else
                echo "⚠️ Poster download failed. yt-dlp reported success but $CHANNEL_NAME/poster* is missing on the host."
                echo "Check your Synology NFS/SMB permissions for the Docker user."
            fi
        else
            echo "❌ No DB match for '$CHANNEL_NAME'."
        fi
    done
done

echo "✨ Auto-scan complete."
