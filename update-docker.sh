#!/bin/bash

# --- Path Configuration ---
# Point these to the exact location of your binaries in /opt
DOCKER="/usr/bin/docker"

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# 1. Update System
# Standard package maintenance
sudo apt update
sudo apt full-upgrade -y
sudo apt autoremove -y

# 2. Stop Containers for Backup
# Using -q (quiet) to get IDs, which is more reliable for stopping
log "Stopping containers for backup..."
$DOCKER stop $($DOCKER ps -q)

# 3. Sync /opt to Backup Destination
# -a: archive mode (preserves permissions/symlinks)
# -v: verbose
# -h: human-readable (shows sizes in MB/GB)
# --delete: removes files in destination that no longer exist in source
log "Backing up /opt to $BACKUP_DEST..."
sudo rsync -avh /opt/ "$BACKUP_DEST" --delete

# 4. Restart and Update Docker
log "Restarting and updating containers..."
$DOCKER start $($DOCKER ps -a -q)
# This loop finds every directory in /opt that contains a docker-compose.yml
for dir in /opt/*/ ; do
    if [ -f "${dir}docker-compose.yml" ] || [ -f "${dir}docker-compose.yaml" ]; then
        log "Updating project in $dir..."
        cd "$dir"
        $DOCKER compose pull
        $DOCKER compose up -d
    fi
done

# 5. Cleanup
# Removes unused images and volumes to free up disk space
$DOCKER image prune -af
$DOCKER volume prune -f

log "Maintenance complete."
