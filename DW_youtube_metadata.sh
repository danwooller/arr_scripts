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
CHANNEL_NAME=$1
CHANNEL_URL=$2

# Ensure arguments are provided
if [ -z "$CHANNEL_NAME" ] || [ -z "$CHANNEL_URL" ]; then
    echo "Usage: ./fix_yt.sh [ChannelName] [URL]"
    exit 1
fi

# --- Mapping Host Paths to Container Internal Paths ---
# Key = Host Directory | Value = Internal Docker Directory
declare -A PATH_MAP
PATH_MAP=(
    ["$DIR_MEDIA_YOUTUBE"]="/downloads"
    ["$DIR_SYNOLOGY_YOUTUBE"]="/synology"
)

# --- Logic: Find the Channel & Download ---
MATCHED_HOST=""
MATCHED_INTERNAL=""

for host_path in "${!PATH_MAP[@]}"; do
    if [ -d "$host_path/$CHANNEL_NAME" ]; then
        MATCHED_HOST="$host_path"
        MATCHED_INTERNAL="${PATH_MAP[$host_path]}"
        break
    fi
done

if [ -z "$MATCHED_HOST" ]; then
    echo "❌ Folder '$CHANNEL_NAME' not found in your YouTube directories."
    exit 1
fi

echo "✅ Found $CHANNEL_NAME at $MATCHED_HOST"
echo "🚀 Using Pinchflat to grab poster for $CHANNEL_NAME..."

# 1. Download thumbnail via Docker
# Using -o to force filename to 'poster' regardless of extension
docker exec $CONTAINER_NAME yt-dlp --write-thumbnail --skip-download --playlist-items 0 \
    -o "$MATCHED_INTERNAL/$CHANNEL_NAME/poster" "$CHANNEL_URL"

# 2. Convert and Rename
# yt-dlp might download .webp, .png, or .jpg. Plex prefers .jpg.
for ext in webp png; do
    if [ -f "$MATCHED_HOST/$CHANNEL_NAME/poster.$ext" ]; then
        mv "$MATCHED_HOST/$CHANNEL_NAME/poster.$ext" "$MATCHED_HOST/$CHANNEL_NAME/poster.jpg"
    fi
done

# 3. Create .plexmatch (Optional but recommended for title/summary)
cat <<EOF > "$MATCHED_HOST/$CHANNEL_NAME/.plexmatch"
Title: $CHANNEL_NAME
Summary: YouTube content for $CHANNEL_NAME.
EOF

# 4. Standardize Permissions
chmod 644 "$MATCHED_HOST/$CHANNEL_NAME/poster.jpg"
chmod 644 "$MATCHED_HOST/$CHANNEL_NAME/.plexmatch"

echo "✨ Success! Refresh metadata in Plex for $CHANNEL_NAME."
