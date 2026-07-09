#!/usr/bin/env bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

FSTAB_FILE="/etc/fstab"
MOUNT_POINT="/mnt/media"
PING_TIMEOUT=2
MAX_ATTEMPTS=30
WAIT_INTERVAL=10

log "Starting dynamic TrueNAS boot mount sequence..."

# 1. Parse fstab to extract unique hostnames mapping to /mnt/media
# This regex strips leading '#' and grabs the hostname/IP from the '//hostname/share' format
TRUENAS_HOSTS=($(awk -v mp="$MOUNT_POINT" '$2 == mp || $3 == mp { 
    gsub(/^#+/, ""); 
    if ($1 ~ /^\/\//) { 
        split($1, parts, "/"); 
        print parts[3] 
    } 
}' "$FSTAB_FILE" | sort -u))

if [ ${#TRUENAS_HOSTS[@]} -eq 0 ]; then
    log "ERROR: No TrueNAS hosts found in $FSTAB_FILE targeting $MOUNT_POINT."
    exit 1
fi

log "Found candidate hosts in fstab: ${TRUENAS_HOSTS[*]}"

# 2. Wait for one of the discovered TrueNAS hosts to become available
ACTIVE_HOST=""
attempt=0

while [ $attempt -lt $MAX_ATTEMPTS ]; do
    for host in "${TRUENAS_HOSTS[@]}"; do
        if ping -c 1 -W $PING_TIMEOUT "$host" >/dev/null 2>&1; then
            log "Success: Active TrueNAS detected at $host"
            ACTIVE_HOST=$host
            break 2
        fi
    done
    
    attempt=$((attempt + 1))
    log "No target TrueNAS online yet. Attempt $attempt/$MAX_ATTEMPTS. Retrying in ${WAIT_INTERVAL}s..."
    sleep $WAIT_INTERVAL
done

if [ -z "$ACTIVE_HOST" ]; then
    log "ERROR: None of the hosts (${TRUENAS_HOSTS[*]}) responded. Exiting."
    exit 1
fi

# 3. Ensure /mnt/media is completely disconnected
log "Ensuring $MOUNT_POINT is unmounted..."
if mountpoint -q "$MOUNT_POINT"; then
    log "$MOUNT_POINT is currently mounted. Unmounting forcefully..."
    umount -l "$MOUNT_POINT"
    sleep 2
else
    umount -f "$MOUNT_POINT" >/dev/null 2>&1
fi

# 4. Clean up spurious directories/files inside the mount point
if [ -d "$MOUNT_POINT" ]; then
    log "Cleaning up any leftover artifacts in $MOUNT_POINT..."
    if ! mountpoint -q "$MOUNT_POINT"; then
        rm -rf "${MOUNT_POINT:?}"/* "${MOUNT_POINT:?}"/.* 2>/dev/null || true
    else
        log "CRITICAL: Mount point still active! Skipping directory cleanup."
        exit 1
    fi
else
    mkdir -p "$MOUNT_POINT"
fi

# 5. Mount using the specific active host configuration from fstab
log "Mounting live server ($ACTIVE_HOST)..."

# Extract the exact fstab line corresponding to the active host (ignoring the comment symbol)
FSTAB_LINE=$(grep -E "^#?//${ACTIVE_HOST}/" "$FSTAB_FILE" | head -n 1 | sed 's/^#//')

if [ -z "$FSTAB_LINE" ]; then
    log "ERROR: Could not reconstruct fstab line for $ACTIVE_HOST"
    exit 1
fi

# Execute the mount directly using the parsed arguments from that line
# This preserves all your specific cifs tokens (credentials, forceuid, vers=3.0, etc.)
SHARE=$(echo "$FSTAB_LINE" | awk '{print $1}')
OPTIONS=$(echo "$FSTAB_LINE" | awk '{print $4}')

if mount -t cifs -o "$OPTIONS" "$SHARE" "$MOUNT_POINT"; then
    log "SUCCESS: $SHARE successfully mounted to $MOUNT_POINT."
else
    log "ERROR: Mount command failed for $SHARE."
    exit 1
fi
