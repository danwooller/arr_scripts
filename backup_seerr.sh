#!/bin/bash

# --- Setup & Includes ---
source "/usr/local/bin/common_functions.sh"

# --- Variables ---
DB_CONTAINER="seerr-db"
DB_NAME="seerr_db"
USER_SECRET="/opt/docker/secrets/db_user.txt"
BACKUP_DIR="/mnt/media/backup/databases"  # Your CIFS mount point
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/seerr_backup_${TIMESTAMP}.sql"

# --- Safety Check: Ensure CIFS Share is Mounted ---
# This checks if the directory is an active mount point
if ! mountpoint -q "$BACKUP_DIR"; then
    # Fallback: Log to the local OS system log because TrueNAS is unreachable
    logger -t backup-seerr "❌ Backup failed: $BACKUP_DIR not mounted. TrueNAS server down."
    # Also attempt to print to terminal in case of manual run
    echo "❌ Backup failed: $BACKUP_DIR not mounted. TrueNAS server down."
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
