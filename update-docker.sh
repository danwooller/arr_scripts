#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# --- Configuration ---
DOCKER="/usr/bin/docker"
BACKUP_DEST="$MOUNT_ROOT/backup/$HOSTNAME/opt"

# 1. Update System Packages
log "Starting System Updates..."
sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y

# 2. Safety Check: Is the backup drive there?
if ! mountpoint -q "$MOUNT_ROOT"; then
    log "❌ $MOUNT_ROOT is not mounted! Aborting to protect OS drive."
    exit 1
fi

# 3. Pre-fetch Docker Images (Zero Downtime during this step)
log "Pre-pulling Docker updates..."
for dir in /opt/*/ ; do
    if [ -f "${dir}docker-compose.yml" ] || [ -f "${dir}docker-compose.yaml" ]; then
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "Pulling latest images in $dir..."
        fi
        cd "$dir" && $DOCKER compose pull -q
    fi
done

# 4. Stop Containers & Backup
if [[ $LOG_LEVEL = "debug" ]]; then
    log "Stopping containers for backup..."
fi
$DOCKER stop $($DOCKER ps -q)

if [[ $LOG_LEVEL = "debug" ]]; then
    log "Syncing /opt to $BACKUP_DEST..."
fi
sudo rsync -avh /opt/ "$BACKUP_DEST" --delete

# 5. Restart & Apply Updates
if [[ $LOG_LEVEL = "debug" ]]; then
    log "Restarting and applying updates..."
fi
for dir in /opt/*/ ; do
    if [ -f "${dir}docker-compose.yml" ] || [ -f "${dir}docker-compose.yaml" ]; then
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "Recreating containers in $dir..."
        fi
        cd "$dir" && $DOCKER compose up -d
    fi
done

# 6. Cleanup
# -f only removes dangling images; -af removes all unused. 
# Sticking to -f is safer if you have "on-demand" containers.
$DOCKER image prune -f
$DOCKER volume prune -f

log "✅ Docker update complete."
