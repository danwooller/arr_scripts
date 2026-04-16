#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- CONFIGURATION ---
NAS_PATH="/mnt/backups/$HOST"
MOUNT_POINT="/mnt/truenas4_backup"
SSD_SNAPSHOTS="/run/timeshift/backup/timeshift/snapshots/"

# 1. Create mount point if it doesn't exist
sudo mkdir -p $MOUNT_POINT

# 2. Mount the TrueNAS Share
echo "Mounting TrueNAS..."
sudo mount -t nfs $BASE_HOST4:$NAS_PATH $MOUNT_POINT

# 3. Check if mount was successful
if mountpoint -q $MOUNT_POINT; then
    echo "Mount successful. Starting Sync..."
    
    # 4. Sync the SSD to the NAS
    # -a: Archive mode (preserves everything)
    # -H: Preserves Hard Links (CRITICAL for Timeshift)
    # --delete: Removes old snapshots from NAS that were deleted from SSD
    sudo rsync -aH --delete $SSD_SNAPSHOTS $MOUNT_POINT
    
    echo "Sync Complete. Unmounting NAS."
    sudo umount $MOUNT_POINT
else
    echo "Error: Could not mount TrueNAS. Backup aborted."
    exit 1
fi
