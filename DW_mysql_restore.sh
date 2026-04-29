#!/bin/bash

# Fix audio for Sonos Playbar
# for dir in /mnt/media/TV/A*/; do sudo LOG_LEVEL=debug ./DW_sonos_audio_fix.sh "$dir"; done

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# Safety check: Don't run during a ZFS scrub
if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub currently in progress on $BASE_HOST6. Exiting to protect disks."
    exit 0
fi

check_dependencies "gunzip"

# Configuration & Defaults
BACKUP_DIR="${1:-/mnt/media/backup/databases}"
TARGET_DB="${2:-wooller}"
CONTAINER_NAME="mysql-$TARGET_DB"

# 1. Check if directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    echo "Error: Directory $BACKUP_DIR does not exist."
    exit 1
fi

# 2. Filter and list files
cd "$BACKUP_DIR" || exit
files=(${TARGET_DB}_*.sql.gz)

# Check if the first element actually exists as a file
if [ ! -f "${files[0]}" ]; then
    echo "No files found matching pattern: ${TARGET_DB}_*.sql.gz in $BACKUP_DIR"
    exit 1
fi

echo "Available backups for database: $TARGET_DB"
PS3="Please select a backup to restore (or type 'q' to quit): "

select file in "${files[@]}"; do
    if [[ $REPLY == "q" ]]; then
        echo "Exiting."
        exit 0
    elif [ -n "$file" ]; then
        echo "Selected: $file"
        echo "Starting restore to container: $CONTAINER_NAME..."

        # 3. Unzip and Pipe directly to Docker
        # 'zcat' reads the compressed file and pipes the text directly
        zcat "$file" | sudo docker exec -i "$CONTAINER_NAME" mysql -u "$MYSQL_WOOLLER_USER" -p"$MYSQL_WOOLLER_PASS" "$TARGET_DB"

        if [ $? -eq 0 ]; then
            echo "-------------------------------------------"
            echo "Success: $file restored to $TARGET_DB"
        else
            echo "-------------------------------------------"
            echo "Error: Restore failed."
        fi
        break
    else
        echo "Invalid selection."
    fi
done
