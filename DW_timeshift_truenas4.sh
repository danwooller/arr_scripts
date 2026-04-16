#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

check_dependencies "nfs-common"

# --- CONFIGURATION ---
SSD_DEVICE="/dev/sda"
SSD_MOUNT="/mnt/ssd_recovery"
NAS_PATH="/mnt/backup/$HOST"
MOUNT_POINT="/mnt/truenas4_backup"
SSD_SNAPSHOTS="$SSD_MOUNT/timeshift/snapshots/"

# 1. Prepare local SSD mount
sudo mkdir -p $SSD_MOUNT
echo "Mounting local SSD..."
sudo mount $SSD_DEVICE $SSD_MOUNT

# 2. Mount TrueNAS (Your existing code)
sudo mkdir -p $MOUNT_POINT
echo "Mounting TrueNAS..."
sudo mount -t nfs $BASE_HOST4:$NAS_PATH $MOUNT_POINT

# 3. Check both mounts before Sync
if mountpoint -q $MOUNT_POINT && mountpoint -q $SSD_MOUNT; then
    echo "Both drives ready. Starting Sync..."
    
    sudo rsync -aH --delete "$SSD_SNAPSHOTS" "$MOUNT_POINT/"
    
    echo "Sync Complete. Cleaning up..."
    sudo umount $MOUNT_POINT
    sudo umount $SSD_MOUNT
else
    echo "Error: One or more drives failed to mount."
    # Try to unmount whatever DID work to stay clean
    sudo umount $MOUNT_POINT || true
    sudo umount $SSD_MOUNT || true
    exit 1
fi
