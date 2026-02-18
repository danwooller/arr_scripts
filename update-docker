#!/bin/bash

# --- Path Configuration ---
# Point these to the exact location of your binaries in /opt
DOCKER_BIN="/opt/docker"
DOCKER_COMPOSE_BIN="/opt/docker-compose"

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
$DOCKER_BIN stop $($DOCKER ps -q)

# 3. Sync /opt to Backup Destination
# -a: archive mode (preserves permissions/symlinks)
# -v: verbose
# -h: human-readable (shows sizes in MB/GB)
# --delete: removes files in destination that no longer exist in source
log "Backing up /opt to $BACKUP_DEST..."
sudo rsync -avh /opt/ "$BACKUP_DEST" --delete

# 4. Restart and Update Docker
log "Restarting and updating containers..."
$DOCKER_BIN start $($DOCKER ps -a -q)
$DOCKER_COMPOSE_BIN pull
$DOCKER_COMPOSE_BIN up -d

# 5. Cleanup
# Removes unused images and volumes to free up disk space
$DOCKER_BIN image prune -af
$DOCKER_BIN volume prune -f

log "Maintenance complete."
