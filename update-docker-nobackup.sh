#!/bin/bash

# --- Path Configuration ---
# Point these to the exact location of your binaries in /opt
DOCKER="/usr/bin/docker"

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# 1. Update system (Standard Debian/Ubuntu maintenance)
sudo apt update
sudo apt full-upgrade -y
sudo apt autoremove -y

# 2. Restart and Update Docker
log "Updating containers..."
# This loop finds every directory in /opt that contains a docker-compose.yml
for dir in /opt/*/ ; do
    if [ -f "${dir}docker-compose.yml" ] || [ -f "${dir}docker-compose.yaml" ]; then
        echo "Updating project in $dir..."
        cd "$dir"
        $DOCKER compose pull
        $DOCKER compose up -d
    fi
done

# 3. Cleanup
# Removes unused images and volumes to free up disk space
# Cleanup: Removing unused data to save disk space (measured in GB/MB)
$DOCKER image prune -af
$DOCKER volume prune -f

# 4. Optional: Stop and remove all containers (currently commented out)
# $DOCKER_BIN stop $($DOCKER_BIN ps --format '{{.Names}}')
# $DOCKER_BIN rm $($DOCKER_BIN ps --format '{{.Names}}')
