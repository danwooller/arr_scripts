#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# --- Configuration ---
DOCKER="/usr/bin/docker"
BACKUP_DEST="${MOUNT_ROOT}/backup/${HOSTNAME}/opt"
REQUIRED_SPACE_MB=5000 

# 1. System Updates
if [[ $LOG_LEVEL = "debug" ]]; then
    log "--- Starting Maintenance Cycle ---"
fi
sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y

# 2. & 3. Safety Checks
if ! mountpoint -q "$MOUNT_ROOT"; then
    log "❌ FATAL: $MOUNT_ROOT is not mounted!"
    exit 1
fi

AVAILABLE_SPACE_MB=$(df -m "$MOUNT_ROOT" | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_SPACE_MB" -lt "$REQUIRED_SPACE_MB" ]; then
    log "❌ FATAL: Insufficient space (${AVAILABLE_SPACE_MB}MB)."
    exit 1
fi

# --- Helper Function to find Compose files ---
# This ensures we don't repeat the 'find' logic 3 times
find_compose() {
    sudo find "$1" -maxdepth 1 \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \) 2>/dev/null | head -n 1
}

# 4. Pre-fetch Images
if [[ $LOG_LEVEL = "debug" ]]; then
    log "Pre-pulling images..."
fi
# Check root /opt/ first
ROOT_COMPOSE=$(find_compose "/opt")
if [ -n "$ROOT_COMPOSE" ]; then
    $DOCKER compose -f "$ROOT_COMPOSE" pull -q
fi
# Then check subdirectories
for dir in /opt/*/ ; do
    COMPOSE_FILE=$(find_compose "$dir")
    [ -n "$COMPOSE_FILE" ] && $DOCKER compose -f "$COMPOSE_FILE" pull -q
done

# 5. Stop Containers & Wait
if [[ $LOG_LEVEL = "debug" ]]; then
    log "Stopping all containers..."
fi
RUNNING_CONTAINERS=$($DOCKER ps -q)
if [ -n "$RUNNING_CONTAINERS" ]; then
    $DOCKER stop -t 20 $RUNNING_CONTAINERS >/dev/null 2>&1
    
    COUNT=0
    while [ -n "$($DOCKER ps -q)" ] && [ $COUNT -lt 10 ]; do
        sleep 3
        ((COUNT++))
    done

    STUCK=$($DOCKER ps -q)
    if [ -n "$STUCK" ]; then
        log "⚠️ Killing stuck processes (Exit 137 imminent)..."
        $DOCKER kill $STUCK >/dev/null 2>&1
        sleep 5 
    fi
fi

# 6. Backup Data
if [[ $LOG_LEVEL = "debug" ]]; then
    log "Syncing /opt to $BACKUP_DEST..."
fi
sudo rsync -avh /opt/ "$BACKUP_DEST" --delete --quiet

# 7. Restart
if [[ $LOG_LEVEL = "debug" ]]; then
    log "Restarting containers..."
fi

# A simple list of paths to check: /opt itself, then all subfolders
PATHS_TO_CHECK=("/opt" /opt/*/)

for path in "${PATHS_TO_CHECK[@]}"; do
    # Remove trailing slash for logging
    CLEAN_PATH="${path%/}"
    DIR_NAME=$(basename "$CLEAN_PATH")
    
    COMPOSE_FILE=$(find_compose "$path")
    
    if [ -n "$COMPOSE_FILE" ]; then
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "Recreating project: $DIR_NAME (File: $(basename "$COMPOSE_FILE"))"
        fi
        
        # Clean up Exit 137 states
        $DOCKER compose -f "$COMPOSE_FILE" --project-directory "$CLEAN_PATH" down >/dev/null 2>&1
        $DOCKER compose -f "$COMPOSE_FILE" --project-directory "$CLEAN_PATH" up -d
        
        if [ $? -eq 0 ]; then
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "✅ $DIR_NAME is online."
            fi
        else
            log "❌ ERROR: $DIR_NAME failed to start."
        fi
    fi
done

# 8. Cleanup
if [[ $LOG_LEVEL = "debug" ]]; then
    log "Pruning unused resources..."
fi
$DOCKER image prune -f

log "✅ Maintenance and backup complete."
