#!/bin/bash

# --- Setup & Includes ---
source "/usr/local/bin/DW_common_functions.sh"

# --- Variables ---
DB_CONTAINER="seerr-db"
DB_NAME="seerr_db"
USER_SECRET="/opt/docker/secrets/db_user.txt"
MOUNT_ROOT="/mnt/media"
BACKUP_DIR="/mnt/media/backup/databases"  # Your CIFS mount point
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/seerr_backup_${TIMESTAMP}.sql"

# --- Safety Check: Check the ROOT mount ---
if ! findmnt -M "$MOUNT_ROOT" > /dev/null 2>&1; then
    logger -t backup-seerr "❌ Backup failed: $MOUNT_ROOT is not mounted. TrueNAS down."
    echo "❌ Error: $MOUNT_ROOT is not mounted."
    exit 1
fi

# --- Execution ---

# 1. Extract username from secret
if [ -f "$USER_SECRET" ]; then
    DB_USER=$(cat "$USER_SECRET")
else
    log "❌ Database secret not found at $USER_SECRET"
    exit 1
fi

# 2. Perform the dump
# Using -t for compatibility with automated shells
if docker exec -t "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$BACKUP_FILE"; then
    log "✅ Seerr database backed up to $BACKUP_FILE"
    # Optional: Prune older backups on the TrueNAS share
    find "$BACKUP_DIR" -name "seerr_backup_*.sql" -mtime +14 -delete
else
    log "❌ pg_dump failed for $DB_NAME"
    rm -f "$BACKUP_FILE" # Don't leave partial/broken files on the share
    exit 1
fi
