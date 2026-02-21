#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# --- Configuration ---
DOCKER="/usr/bin/docker"
SERVICE_NAME=$1
COMPOSE_DIR="/opt/docker/$SERVICE_NAME"

# The physical mount point to check for safety
MOUNT_ROOT="/mnt/media"
# Specific backup path as requested
BACKUP_DEST="$MOUNT_ROOT/backup/$HOSTNAME/opt/docker/$SERVICE_NAME"

# --- 1. Validation Checks ---
if [ -z "$SERVICE_NAME" ]; then
    log "Error: No service name provided. Usage: ./update.sh <service_name>"
    exit 1
fi

# Check if the physical drive is mounted to prevent filling the OS drive
if ! mountpoint -q "$MOUNT_ROOT"; then
    log "CRITICAL: $MOUNT_ROOT is not mounted! Aborting update/backup."
    exit 1
fi

# Ensure the project directory exists
if [ ! -d "$COMPOSE_DIR" ]; then
    log "Error: Source directory $COMPOSE_DIR not found."
    exit 1
fi

# --- 2. Update and Backup Workflow ---
cd "$COMPOSE_DIR" || exit 1

log "Starting update for $SERVICE_NAME..."

# Pull new image first to minimize downtime
$DOCKER compose pull "$SERVICE_NAME"

# Stop service for a 'cold' backup (ensures data integrity)
log "Stopping $SERVICE_NAME..."
$DOCKER compose stop "$SERVICE_NAME"

# Perform Rsync
# mkdir -p ensures the path exists on the backup drive
mkdir -p "$BACKUP_DEST"
log "Syncing $COMPOSE_DIR to $BACKUP_DEST..."
sudo rsync -avh "$COMPOSE_DIR/" "$BACKUP_DEST/" --delete

# Bring the service back up (recreates the container with the new image)
log "Starting $SERVICE_NAME..."
$DOCKER compose up -d "$SERVICE_NAME"

# --- 3. Cleanup ---
# Removes old image layers that are no longer being used
$DOCKER image prune -f

log "Successfully updated and backed up $SERVICE_NAME."
