#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"

# Configuration
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" == *"pi"* ]]; then
    REAL_USER="pi"
    SERVICE_USER="pi"
else
    REAL_USER="dan"
    SERVICE_USER="root"
fi
DEST_DIR="/home/$REAL_USER/arr_scripts"
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

# 3. Always update DW_common_functions.sh
if [ -f "$DEST_DIR/DW_common_functions.sh" ]; then
    echo "Updating /usr/local/bin/DW_common_functions.sh..."
    sudo cp "$DEST_DIR/DW_common_functions.sh" "/usr/local/bin/"
    sudo chmod +x "/usr/local/bin/DW_common_functions.sh"
    sudo chown root:root "/usr/local/bin/DW_common_functions.sh"
fi

# 4. Sync back to system bin if requested
if [ -n "$FILENAME" ]; then
    echo "Updating /usr/local/bin/$FILENAME..."
    sudo cp "$DEST_DIR/$FILENAME" "/usr/local/bin/"
    sudo chmod +x "/usr/local/bin/$FILENAME"
    sudo chown root:root "/usr/local/bin/$FILENAME"
fi

log "✅ Pull complete for $FILENAME"
echo "✅ Sync complete."
