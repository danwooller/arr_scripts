#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"

# Configuration
CONTAINER_NAME="pinchflat"
# Map host paths to internal container paths (Keys = Host | Values = Docker)
declare -A PATH_MAP=(
    ["$DIR_MEDIA_YOUTUBE"]="/downloads"
    ["$DIR_SYNOLOGY_YOUTUBE"]="/synology"
)

echo "🕵️ Starting YouTube Metadata Auto-Scan..."

for HOST_ROOT in "${!PATH_MAP[@]}"; do
    INTERNAL_ROOT="${PATH_MAP[$HOST_ROOT]}"
    
    # Iterate through each channel folder
    for CHANNEL_DIR in "$HOST_ROOT"/*/; do
        [ -d "$CHANNEL_DIR" ] || continue
        CHANNEL_NAME=$(basename "$CHANNEL_DIR")
        
        # Check if we already have a poster to save resources
        if [ -f "${CHANNEL_DIR}poster.jpg" ] && [ -f "${CHANNEL_DIR}.plexmatch" ]; then
            echo "⏩ Skipping $CHANNEL_NAME (Metadata already exists)"
            continue
        fi

        echo "🔍 Identifying channel for folder: $CHANNEL_NAME..."

        # Find the first video file to extract channel info
        SAMPLE_VIDEO=$(find "$CHANNEL_DIR" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" \) | head -n 1)

        if [ -z "$SAMPLE_VIDEO" ]; then
            echo "⚠️ No videos found in $CHANNEL_NAME, cannot auto-identify."
            continue
        fi

        # Convert Host Video Path to Internal Container Path
        INTERNAL_VIDEO="${SAMPLE_VIDEO/$HOST_ROOT/$INTERNAL_ROOT}"

        # Get Channel URL from video metadata using yt-dlp inside the container
        CHANNEL_URL=$(docker exec "$CONTAINER_NAME" yt-dlp --get-filename -o "%(channel_url)s" "$INTERNAL_VIDEO" 2>/dev/null)

        if [[ "$CHANNEL_URL" == http* ]]; then
            echo "🎯 Found URL: $CHANNEL_URL. Downloading assets..."
            
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
        else
            echo "❌ Failed to extract Channel URL for $CHANNEL_NAME."
        fi
    done
done

echo "✅ Auto-scan complete."
