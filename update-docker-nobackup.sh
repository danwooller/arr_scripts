#!/bin/bash

# --- Path Configuration ---
# Point these to the exact location of your binaries in /opt
DOCKER="/opt/docker"

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# 1. Update system (Standard Debian/Ubuntu maintenance)
sudo apt update
sudo apt full-upgrade -y
sudo apt autoremove -y

# 2. Restart and Update Docker
log "Updating containers..."
$DOCKER compose pull
$DOCKER compose up -d

# 3. Cleanup
# Removes unused images and volumes to free up disk space
# Cleanup: Removing unused data to save disk space (measured in GB/MB)
$DOCKER image prune -af
$DOCKER volume prune -f

# 4. Optional: Stop and remove all containers (currently commented out)
# $DOCKER_BIN stop $($DOCKER_BIN ps --format '{{.Names}}')
# $DOCKER_BIN rm $($DOCKER_BIN ps --format '{{.Names}}')
