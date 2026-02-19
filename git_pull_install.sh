#!/bin/bash

# Configuration
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" == *"pi"* ]]; then
    REAL_USER="pi"
else
    REAL_USER="dan"
fi
DEST_DIR="/home/$REAL_USER/arr_scripts"
FILENAME=$1
SERVICE_FILE="$FILENAME.service"

cd "$DEST_DIR" || exit

# 1. Clean up any stuck lock files and fix ownership
sudo rm -f .git/index.lock
sudo chown -R "$REAL_USER:$REAL_USER" "$DEST_DIR"

# 2. Try a standard pull; if it fails, reset to origin
echo "Pulling latest changes..."
if ! sudo -u "$REAL_USER" git pull origin main; then
    echo "Conflict detected! Forcing local repo to match GitHub..."
    sudo -u "$REAL_USER" git fetch origin
    sudo -u "$REAL_USER" git reset --hard origin/main
fi

# 3. Always update common_functions.sh
if [ -f "$DEST_DIR/common_functions.sh" ]; then
    echo "Updating /usr/local/bin/common_functions.sh..."
    sudo cp "$DEST_DIR/common_functions.sh" "/usr/local/bin/"
    sudo chmod +x "/usr/local/bin/common_functions.sh"
    sudo chown root:root "/usr/local/bin/common_functions.sh"
fi

if [ -n "$FILENAME" ]; then
    # 4. Sync script to system bin
    if [ -f "$DEST_DIR/$FILENAME" ]; then
        echo "Updating /usr/local/bin/$FILENAME..."
        sudo cp "$DEST_DIR/$FILENAME" "/usr/local/bin/"
        sudo chmod +x "/usr/local/bin/$FILENAME"
        sudo chown root:root "/usr/local/bin/$FILENAME"
    else
        echo "Error: Script $FILENAME not found in $DEST_DIR"
    fi

    # 5. Handle Service File (if exists)
    if [ -f "$DEST_DIR/$SERVICE_FILE" ]; then
        echo "Service file detected: $SERVICE_FILE. Installing/Restarting..."
        
        # Copy to systemd directory
        sudo cp "$DEST_DIR/$SERVICE_FILE" "/etc/systemd/system/"
        sudo chown root:root "/etc/systemd/system/$SERVICE_FILE"
        sudo chmod 644 "/etc/systemd/system/$SERVICE_FILE"

        # Reload systemd to recognize changes
        sudo systemctl daemon-reload

        # Enable the service (if not already enabled)
        sudo systemctl enable "$SERVICE_FILE"

        # Restart the service to apply the new script/config
        echo "Restarting $SERVICE_FILE..."
        sudo systemctl restart "$SERVICE_FILE"
        
        # Check status briefly
        systemctl is-active --quiet "$SERVICE_FILE" && echo "Service is running." || echo "Service failed to start."
    else
        echo "No service file found for $FILENAME. Skipping service update."
    fi
fi

echo "Sync complete."
