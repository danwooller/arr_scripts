#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# Configuration
CONTAINER_NAME="pinchflat"
INTERNAL_PATH="/downloads" # Internal Pinchflat mount

CHANNEL_NAME=$1
CHANNEL_URL=$2

if [ -z "$CHANNEL_NAME" ] || [ -z "$CHANNEL_URL" ]; then
    echo "Usage: ./fix_yt.sh [ChannelName] [URL]"
    exit 1
fi

# --- Find the correct Host Path from the array ---
MATCHED_HOST_PATH=""

for path in "${DIR_YOUTUBE[@]}"; do
    if [ -d "$path/$CHANNEL_NAME" ]; then
        MATCHED_HOST_PATH="$path"
        break
    fi
done

if [ -z "$MATCHED_HOST_PATH" ]; then
    echo "❌ Could not find folder '$CHANNEL_NAME' in any YouTube directories."
    exit 1
fi

echo "✅ Found $CHANNEL_NAME at $MATCHED_HOST_PATH"
echo "🚀 Using Pinchflat container to grab metadata..."

# 1. Grab the thumbnail via the container
# We assume the internal path structure matches the host structure under /downloads
docker exec $CONTAINER_NAME yt-dlp --write-thumbnail --skip-download --playlist-items 0 \
    -o "$INTERNAL_PATH/$CHANNEL_NAME/poster" "$CHANNEL_URL"

# 2. Convert webp to jpg on the host
# Check both potential formats yt-dlp might spit out
for ext in webp png mkv; do
    if [ -f "$MATCHED_HOST_PATH/$CHANNEL_NAME/poster.$ext" ]; then
        mv "$MATCHED_HOST_PATH/$CHANNEL_NAME/poster.$ext" "$MATCHED_HOST_PATH/$CHANNEL_NAME/poster.jpg"
    fi
done

# 3. Create the .plexmatch file
cat <<EOF > "$MATCHED_HOST_PATH/$CHANNEL_NAME/.plexmatch"
Title: $CHANNEL_NAME
Summary: YouTube content for $CHANNEL_NAME.
EOF

# 4. Fix permissions
chmod 644 "$MATCHED_HOST_PATH/$CHANNEL_NAME/poster.jpg"
chmod 644 "$MATCHED_HOST_PATH/$CHANNEL_NAME/.plexmatch"

echo "✨ Done! Refresh Plex metadata for $CHANNEL_NAME."
