#!/bin/bash

# Run on ubuntu9 to sync backup db

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# Safety check: Don't run during a ZFS scrub
if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub currently in progress on $BASE_HOST6. Exiting sync."
    exit 0
fi

check_dependencies "gzip" "docker"

# Configuration & Defaults
BACKUP_DIR="${1:-/mnt/media/backup/databases}"
TARGET_DB="${2:-wooller}"
CONTAINER_NAME="mysql-$TARGET_DB"

# 1. Check if directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    log "❌ Error: Directory $BACKUP_DIR does not exist."
    exit 1
fi

# 2. Automatically find the newest backup file
# Sorts by time (-t) and takes the top result
LATEST_FILE=$(ls -t "$BACKUP_DIR/${TARGET_DB}"_*.sql.gz 2>/dev/null | head -1)

if [ -z "$LATEST_FILE" ]; then
    log "❌ Error: No backup files found for $TARGET_DB in $BACKUP_DIR"
    exit 1
fi

log "🔄 Found latest backup: $(basename "$LATEST_FILE")"
log "🔄 Starting auto-restore to $CONTAINER_NAME..."

# 3. Dynamic Credential Mapping
UPPER_DB=$(echo "$TARGET_DB" | tr '[:lower:]' '[:upper:]')
PASS_VAR="MYSQL_${UPPER_DB}_PASS"
USER_VAR="MYSQL_${UPPER_DB}_USER"

DB_PASS="${!PASS_VAR}"
DB_USER="${!USER_VAR:-root}"

# 4. Unzip and Pipe directly to Docker
# Using -e MYSQL_PWD to keep the logs clean and suppress the password warning
zcat "$LATEST_FILE" | sudo docker exec -e MYSQL_PWD="$DB_PASS" -i "$CONTAINER_NAME" \
    mysql -u "$DB_USER" "$TARGET_DB" 2>/dev/null

if [ ${PIPESTATUS[1]} -eq 0 ]; then
    log "✅ Success: $TARGET_DB restored from $(basename "$LATEST_FILE")"
else
    log "❌ Error: Restore failed for $TARGET_DB."
    exit 1
fi

# --- Verification Step ---
log "🔍 Starting cross-server verification (Docker to Docker)..."

# Determine who is remote based on where we are
if [ "$HOST" == "ubuntu24" ]; then
    REMOTE_HOST="ubuntu9"
    REMOTE_LABEL="ubuntu9"
elif [ "$HOST" == "ubuntu9" ]; then
    REMOTE_HOST="ubuntu24"
    REMOTE_LABEL="ubuntu24"
else
    echo "Unknown host: $CURRENT_HOST"
    exit 1
fi

# Standardized dump command to ensure hash consistency
DUMP_CMD="mysqldump -u $DB_USER --single-transaction --set-gtid-purged=OFF --routines --triggers --skip-comments --skip-extended-insert $TARGET_DB"

log "🔍 Comparing Local ($LOCAL_LABEL) to Remote ($REMOTE_LABEL)..."

# --- Get Hash from Remote ---
REMOTE_HASH=$(ssh -o ConnectTimeout=5 "$REMOTE_HOST" \
  "sudo docker exec -e MYSQL_PWD='$DB_PASS' $CONTAINER_NAME $DUMP_CMD 2>/dev/null | md5sum" | awk '{print $1}')

# --- Get Hash from Local ---
LOCAL_HASH=$(sudo docker exec -e MYSQL_PWD="$DB_PASS" "$CONTAINER_NAME" \
  $DUMP_CMD 2>/dev/null | md5sum | awk '{print $1}')

# --- Compare ---
if [ -n "$REMOTE_HASH" ] && [ "$REMOTE_HASH" == "$LOCAL_HASH" ]; then
    log "✨ Verification Passed: Both containers match ($LOCAL_HASH)"
else
    log "❌ Verification FAILED!"
    log "   Local  ($LOCAL_LABEL): $LOCAL_HASH"
    log "   Remote ($REMOTE_LABEL): ${REMOTE_HASH:-CONNECTION_ERROR}"
fi
