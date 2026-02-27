#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# Configuration
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" == *"pi"* ]]; then
    REAL_USER="pi"
else
    REAL_USER="root"
fi
DEST_DIR="/home/$REAL_USER/arr_scripts"
FILENAME=$1
SERVICE_FILE="$FILENAME.service"
SERVICE_DIR="/etc/systemd/system/"

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

    # 5. Handle Service File (Template & Extension Aware)
    # Strip .sh from the filename to find the service (e.g., monitor_convert)
    BASE_NAME="${FILENAME%.sh}"
    
    # Define possible service file names
    SERVICE_TEMPLATE="${BASE_NAME}@.service"
    SERVICE_STANDARD="${BASE_NAME}.service"

    # Determine which one exists (check repo first, then system)
    SELECTED_SERVICE=""
    if [ -f "$DEST_DIR/$SERVICE_TEMPLATE" ] || [ -f "$SERVICE_DIR$SERVICE_TEMPLATE" ]; then
        SELECTED_SERVICE="$SERVICE_TEMPLATE"
    elif [ -f "$DEST_DIR/$SERVICE_STANDARD" ] || [ -f "$SERVICE_DIR$SERVICE_STANDARD" ]; then
        SELECTED_SERVICE="$SERVICE_STANDARD"
    fi

    if [ -n "$SELECTED_SERVICE" ]; then
        echo "Service file detected: $SELECTED_SERVICE. Processing..."

        # 5a. Sync from repo to system if it exists in repo
        if [ -f "$DEST_DIR/$SELECTED_SERVICE" ]; then
            sudo cp "$DEST_DIR/$SELECTED_SERVICE" "$SERVICE_DIR"
            sudo chown root:root "$SERVICE_DIR$SELECTED_SERVICE"
            sudo chmod 644 "$SERVICE_DIR$SELECTED_SERVICE"
            sudo systemctl daemon-reload
        fi

        # 5b. Determine Active Instance Name
        if [[ "$SELECTED_SERVICE" == *"@"* ]]; then
            # Instance name becomes: monitor_convert@dan.service
            ACTIVE_NAME="${SELECTED_SERVICE%.service}$REAL_USER.service"
            echo "Template detected. Using instance: $ACTIVE_NAME"
        else
            ACTIVE_NAME="$SELECTED_SERVICE"
        fi

        # 5c. Enable and Restart
        echo "Restarting $ACTIVE_NAME..."
        sudo systemctl enable "$ACTIVE_NAME"
        sudo systemctl restart "$ACTIVE_NAME"
        
        systemctl is-active --quiet "$ACTIVE_NAME" && echo "Service is running." || echo "Service failed to start."
    else
        echo "No service file (standard or @template) found for $BASE_NAME. Skipping."
    fi
fi

log "✅ Pull and service install complete for $FILENAME"
echo "✅ Sync complete."
