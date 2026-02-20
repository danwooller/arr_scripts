#!/bin/bash

# --- Setup & Includes ---
source "/usr/local/bin/common_functions.sh"

# --- Variables ---
DB_CONTAINER="seerr-db"
APP_CONTAINER="seerr"
DB_NAME="seerr_db"
USER_SECRET="/opt/docker/secrets/db_user.txt"
BACKUP_DIR="/mnt/media/backup/databases"

# --- Argument Check ---
if [ -z "$1" ]; then
    echo "Usage: restore-seerr <backup_filename.sql>"
    echo "Example: restore-seerr seerr_backup_20240101_120000.sql"
    exit 1
fi

BACKUP_FILE="${BACKUP_DIR}/$1"

# --- Safety Checks ---

# 1. Check if Backup File exists
if [ ! -f "$BACKUP_FILE" ]; then
    log "❌ Restore failed: Backup file not found at $BACKUP_FILE"
    exit 1
fi

# 2. Extract username
if [ -f "$USER_SECRET" ]; then
    DB_USER=$(cat "$USER_SECRET")
else
    log "❌ Restore failed: Secret $USER_SECRET not found."
    exit 1
fi

# 3. Final Warning
echo "⚠️ WARNING: This will WIPE the current database and restore from $1"
read -p "Are you sure you want to continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "🚫 Restore cancelled by user."
    exit 1
fi

# --- Execution ---

log "🔄 Starting restore process..."

# 1. Stop the application to prevent data corruption
docker stop "$APP_CONTAINER"

# 2. Drop and Re-create the database (Ensures a clean import)
log "🧹 Dropping existing database..."
docker exec -t "$DB_CONTAINER" dropdb -U "$DB_USER" "$DB_NAME"
docker exec -t "$DB_CONTAINER" createdb -U "$DB_USER" "$DB_NAME"

# 3. Import the SQL file
log "📥 Importing backup data..."
if cat "$BACKUP_FILE" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME"; then
    log "✅ Restore successful!"
else
    log "❌ Restore failed during SQL import!"
fi

# 4. Start the application back up
log "🚀 Starting $APP_CONTAINER..."
docker start "$APP_CONTAINER"
