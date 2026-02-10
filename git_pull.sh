#!/bin/bash

# Configuration
REAL_USER="pi"
DEST_DIR="/home/pi/arr_scripts"
FILENAME=$1

cd "$DEST_DIR" || exit

# 1. Clean up any stuck lock files and fix ownership
sudo rm -f .git/index.lock
sudo chown -R $REAL_USER:$REAL_USER "$DEST_DIR"

# 2. Try a standard pull; if it fails, reset to origin
echo "Pulling latest changes..."
if ! sudo -u $REAL_USER git pull origin main; then
    echo "Conflict detected! Forcing local repo to match GitHub..."
    sudo -u $REAL_USER git fetch origin
    sudo -u $REAL_USER git reset --hard origin/main
fi

# 3. Sync back to system bin if requested
if [ -n "$FILENAME" ]; then
    echo "Updating /usr/local/bin/$FILENAME..."
    sudo cp "$DEST_DIR/$FILENAME" "/usr/local/bin/"
    sudo chmod +x "/usr/local/bin/$FILENAME"
    sudo chown root:root "/usr/local/bin/$FILENAME"
fi

echo "Sync complete."
