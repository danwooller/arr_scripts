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
DATE=$(date +%Y%m%d)

# 1. Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# 2. Find all running containers starting with "mysql-"
containers=$(sudo docker ps --format '{{.Names}}' | grep '^mysql-')

if [ -z "$containers" ]; then
    log "No running containers found matching 'mysql-*'."
    exit 1
fi

for CONTAINER in $containers; do
    # Extract DB name (assumes naming convention mysql-DBNAME)
    DB_NAME="${CONTAINER#mysql-}"
    
    # Define credentials (using your shared variables pattern)
    # This dynamically builds the variable name, e.g., MYSQL_WOOLLER_PASS
    UPPER_DB=$(echo "$DB_NAME" | tr '[:lower:]' '[:upper:]')
    PASS_VAR="MYSQL_${UPPER_DB}_PASS"
    USER_VAR="MYSQL_${UPPER_DB}_USER"
    
    DB_PASS="${!PASS_VAR}"
    DB_USER="${!USER_VAR:-root}"

    BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_${DATE}.sql.gz"

    log "Starting backup for $DB_NAME ($CONTAINER)..."

    # 3. Execute mysqldump and pipe to gzip
    # --single-transaction is used to avoid locking tables (good for InnoDB)
    sudo docker exec "$CONTAINER" mysqldump -u "$DB_USER" -p"$DB_PASS" --single-transaction "$DB_NAME" | gzip > "$BACKUP_FILE"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log "✅ Backup successful: $BACKUP_FILE"
        # Optional: Remove backups older than 30 days
        find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -mtime +90 -delete
    else
        log "❌ Backup failed for $DB_NAME"
        rm -f "$BACKUP_FILE" # Remove partial file on failure
    fi
done
