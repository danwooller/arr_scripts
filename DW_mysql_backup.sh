#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# Safety check: Don't run during a ZFS scrub
if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub in progress on $BASE_HOST6. Skipping backup to protect I/O."
    exit 0
fi

check_dependencies "gzip" "docker"

# Configuration
BACKUP_DIR="${1:-/mnt/media/backup/databases}"
TARGET_DB="${2:-wooller}"
DATE=$(date +%Y%m%d)

# 1. Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# 2. Determine which containers to back up
if [ -n "$TARGET_DB" ]; then
    # Target only the specific container
    containers="mysql-$TARGET_DB"
    # Verify it exists/is running
    if ! sudo docker ps --format '{{.Names}}' | grep -q "^${containers}$"; then
        log "❌ Error: Container $containers is not running."
        exit 1
    fi
else
    # Find all running containers starting with "mysql-"
    containers=$(sudo docker ps --format '{{.Names}}' | grep '^mysql-')
fi

if [ -z "$containers" ]; then
    log "No running containers found matching 'mysql-*'."
    exit 1
fi

for CONTAINER in $containers; do
    # Extract DB name (assumes naming convention mysql-DBNAME)
    DB_NAME="${CONTAINER#mysql-}"
    
    # Define credentials
    UPPER_DB=$(echo "$DB_NAME" | tr '[:lower:]' '[:upper:]')
    PASS_VAR="MYSQL_${UPPER_DB}_PASS"
    USER_VAR="MYSQL_${UPPER_DB}_USER"
    
    DB_PASS="${!PASS_VAR}"
    DB_USER="${!USER_VAR:-root}"

    BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_${DATE}.sql.gz"

    log "Starting backup for $DB_NAME ($CONTAINER)..."

    # 3. Execute mysqldump and pipe to gzip
    # Added the --set-gtid-purged=OFF and environment variable password handling
    sudo docker exec -e MYSQL_PWD="$DB_PASS" "$CONTAINER" mysqldump -u "$DB_USER" \
          --single-transaction \
          --set-gtid-purged=OFF \
          --routines --triggers \
          "$DB_NAME" 2>/dev/null | gzip > "$BACKUP_FILE"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log "✅ Backup successful: $BACKUP_FILE"
        # Cleanup: Keep 90 days as per your latest edit
        find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -mtime +90 -delete
    else
        log "❌ Backup failed for $DB_NAME"
        rm -f "$BACKUP_FILE" 
    fi
done
