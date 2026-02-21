#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# --- Path Configuration ---
# Point these to the exact location of your binaries in /opt
DOCKER="/usr/bin/docker"
BACKUP_DEST="/mnt/media/backup/$HOSTNAME/opt"
BACKUP_SRC="/opt/docker/$1"

# 1. Stop container
$DOCKER stop $1
log "Stop $1 container..."
# 2. Remove container
$DOCKER rm $1
log "Remove $1 container..."
# 3. Backup containers
sudo rsync -avh "$BACKUP_SRC" "$BACKUP_DEST" --delete
log "Backup "$BACKUP_SRC" to "$BACKUP_DEST"..."
# 4. Update containers
$DOCKER compose pull
$DOCKER compose up -d
# 5. Cleanup
# Removes unused images and volumes to free up disk space
$DOCKER image prune -af
$DOCKER volume prune -f
log "Updated container $1"
