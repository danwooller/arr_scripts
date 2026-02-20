#!/bin/bash

# --- Setup & Includes ---
# Ensure this path is correct for your environment
source "//usr/local/bin/common_functions.sh"

# --- Variables ---
DB_CONTAINER="seerr-db"
DB_NAME="seerr_db"
USER_SECRET="/opt/docker/secrets/db_user.txt"
BACKUP_DIR="/mnt/media/backup/databases"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/seerr_backup_${TIMESTAMP}.sql"

# --- Execution ---

# 1. Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# 2. Perform the dump
# We pull the username from the secret file directly
DB_USER=$(cat "$USER_SECRET")

if docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$BACKUP_FILE"; then
    # 3. Log success (assuming your common_functions.sh has a 'log' or 'log_entry' function)
    # Adjust the function name below to match yours (e.g., log_info, write_log)
    log "✅ Seerr database backed up to ${BACKUP_FILE}"
    
    # Optional: Keep only the last 30 days of backups to save space
    find "$BACKUP_DIR" -name "seerr_backup_*.sql" -mtime +30 -delete
else
    log "❌ Seerr database backup failed!"
    exit 1
fi
