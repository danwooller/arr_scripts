#!/bin/bash

# verify db, $1 specifies

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

# Configuration & Defaults
TARGET_DB="${1:-wooller}"
CONTAINER_NAME="mysql-$TARGET_DB"

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
DUMP_CMD="mysqldump -u $MYSQL_WOOLLER_USER --single-transaction --set-gtid-purged=OFF --routines --triggers --skip-comments --skip-extended-insert --no-tablespaces $TARGET_DB"

log "🔍 Comparing Local ($LOCAL_LABEL) to Remote ($REMOTE_LABEL)..."

# --- Get Hash from Remote ---
REMOTE_HASH=$(ssh -o ConnectTimeout=5 "$REMOTE_HOST" \
  "sudo docker exec -e MYSQL_PWD='$MYSQL_WOOLLER_PASS' $CONTAINER_NAME $DUMP_CMD 2>/dev/null | md5sum" | awk '{print $1}')

# --- Get Hash from Local ---
LOCAL_HASH=$(sudo docker exec -e MYSQL_PWD="$MYSQL_WOOLLER_PASS" "$CONTAINER_NAME" \
  $DUMP_CMD 2>/dev/null | md5sum | awk '{print $1}')

# --- Compare ---
if [ -n "$REMOTE_HASH" ] && [ "$REMOTE_HASH" == "$LOCAL_HASH" ]; then
    log "✨ Verification Passed: Both containers match ($LOCAL_HASH)"
else
    log "❌ Verification FAILED!"
    log "   Local  ($LOCAL_LABEL): $LOCAL_HASH"
    log "   Remote ($REMOTE_LABEL): ${REMOTE_HASH:-CONNECTION_ERROR}"
fi
