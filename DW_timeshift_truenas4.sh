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
SSD_DEVICE="/dev/sda"
SSD_MOUNT="/mnt/ssd_recovery"
NAS_PATH="/mnt/backup/$HOST"
MOUNT_POINT="/mnt/truenas4_backup"
SSD_SNAPSHOTS="$SSD_MOUNT/timeshift/snapshots/"
trap 'sudo umount -l $MOUNT_POINT $SSD_MOUNT 2>/dev/null' EXIT

# 1. Prepare local SSD mount
sudo mkdir -p $SSD_MOUNT
sudo mount $SSD_DEVICE $SSD_MOUNT

# 2. PRE-FLIGHT CHECK: Is the NAS even awake?
if ! ping -c 1 -W 2 "$BASE_HOST4" > /dev/null; then
    log "ℹ️ $BASE_HOST4 is not responding, skipping backup."
    # Clean up the SSD mount since we're exiting
    sudo umount -l "$SSD_MOUNT" || true
    exit 0
fi

# 3. Mount TrueNAS (Now we know it's awake)
sudo mkdir -p $MOUNT_POINT
echo "Mounting TrueNAS..."
sudo mount -t nfs -o soft,timeo=50,retrans=2 $BASE_HOST4:$NAS_PATH $MOUNT_POINT

if mountpoint -q "$MOUNT_POINT" && mountpoint -q "$SSD_MOUNT"; then
    [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ Drives ready, starting sync..."
    
    # --timeout=180: If no data moves for 3 mins (NAS went to sleep), rsync kills itself
    # --partial: Keeps what it got so far to save time tomorrow
    sudo rsync -aH --delete --timeout=180 "$SSD_SNAPSHOTS" "$MOUNT_POINT/"
    
    log "🏁 Sync complete, cleaning up..."
    # -l (Lazy) is key here. If the drive is already "gone" (asleep), 
    # a standard umount will hang, but a lazy one detaches the ghost mount.
    sudo umount -l "$MOUNT_POINT"
    sudo umount -l "$SSD_MOUNT"
else
    log "❌ One or more drives failed to mount."
    sudo umount -l "$MOUNT_POINT" || true
    sudo umount -l "$SSD_MOUNT" || true
    exit 1
fi
