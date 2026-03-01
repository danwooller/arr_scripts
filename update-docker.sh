#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"

# --- Flag Handling ---
SKIP_BACKUP=false
SKIP_UPDATE=false
if [[ "$1" == "--no-backup-update" ]]; then
    SKIP_BACKUP=true
    SKIP_UPDATE=true
elif [[ "$1" == "--no-backup" ]]; then
    SKIP_BACKUP=true
elif [[ "$1" == "--no-update" ]]; then
    SKIP_UPDATE=true
elif [ -z "$1" ]; then
    # 2. No flags provided? Enter Interactive Mode with 30s timeout
    echo "❓ No flags detected. Choose your options (Default is 'No' in 30s):"

    # Ask about Backup
    read -t 30 -p "   -> Skip Rsync Backup? (y/N): " RESP_BACKUP
    if [[ "$RESP_BACKUP" =~ ^[Yy]$ ]]; then
        SKIP_BACKUP=true
        log "ℹ️ Choice: Skipping Backup."
    fi

    # Ask about System Updates
    read -t 30 -p "   -> Skip OS apt Updates? (y/N): " RESP_UPDATE
    if [[ "$RESP_UPDATE" =~ ^[Yy]$ ]]; then
        SKIP_UPDATE=true
        log "ℹ️ Choice: Skipping Updates."
    fi
    echo "" # Clean line break
fi

# --- Configuration ---
DOCKER="/usr/bin/docker"
BACKUP_DEST="${MOUNT_ROOT}/backup/${HOSTNAME}/opt"
REQUIRED_SPACE_MB=5000
LOG_LEVEL="debug"

# 1. System Updates
log_start

if [ "$SKIP_UPDATE" = false ]; then
    sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y
fi

# 2. & 3. Safety Checks
if ! mountpoint -q "$MOUNT_ROOT"; then
    log "❌ FATAL: $MOUNT_ROOT is not mounted!"
    exit 1
fi

# Only check space if we are actually backing up
if [ "$SKIP_BACKUP" = false ]; then
    AVAILABLE_SPACE_MB=$(df -m "$MOUNT_ROOT" | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE_MB" -lt "$REQUIRED_SPACE_MB" ]; then
        log "❌ FATAL: Insufficient space for backup (${AVAILABLE_SPACE_MB}MB)."
        exit 1
    fi
fi

# --- Helper Function to find Compose files ---
find_compose() {
    sudo find "$1" -maxdepth 1 \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \) 2>/dev/null | head -n 1
}

# 4. Pre-fetch Images (with Error Logging)
ROOT_COMPOSE=$(find_compose "/opt")
if [ -n "$ROOT_COMPOSE" ]; then
    log "ℹ️ Pre-pulling images for: $ROOT_COMPOSE"

    # --- Pre-Pull Space Check ---
    # Get current available space in MB
    CURRENT_SPACE_MB=$(df -m /opt | awk 'NR==2 {print $4}')
    
    if [ "$CURRENT_SPACE_MB" -lt "$REQUIRED_SPACE_MB" ]; then
        log "⚠️ WARNING: Skipping pull for $DIR_NAME. Low space: ${CURRENT_SPACE_MB}MB (Required: ${REQUIRED_SPACE_MB}MB)"
        continue # Skip to the next folder in /opt/
    fi
    
    # Run timeout and capture the result
    sudo timeout 300s $DOCKER compose -f "$ROOT_COMPOSE" pull -q
    RESULT=$?

    if [ $RESULT -eq 124 ]; then
        log "❌ ERROR: Pull TIMED OUT (300s exceeded) for $ROOT_COMPOSE"
    elif [ $RESULT -ne 0 ]; then
        log "❌ ERROR: Pull FAILED (Exit Code: $RESULT) for $ROOT_COMPOSE"
    else
        [[ $LOG_LEVEL == "debug" ]] && log "✅ Pull successful for $ROOT_COMPOSE"
    fi
fi

for dir in /opt/*/ ; do
    COMPOSE_FILE=$(find_compose "$dir")
    
    if [ -n "$COMPOSE_FILE" ]; then
        DIR_NAME=$(basename "$dir")
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Pre-pulling images for: $DIR_NAME"

        # Run pull with a 10-minute timeout
        # Using -q to keep the overnight logs clean
        sudo timeout 600s $DOCKER compose -f "$COMPOSE_FILE" pull -q
        PULL_RESULT=$?

        if [ $PULL_RESULT -eq 124 ]; then
            log "❌ ERROR: Pull TIMED OUT (600s) for $DIR_NAME"
        elif [ $PULL_RESULT -ne 0 ]; then
            log "❌ ERROR: Pull FAILED (Exit Code: $PULL_RESULT) for $DIR_NAME"
        else
            [[ $LOG_LEVEL == "debug" ]] && log "✅ Pull successful for $DIR_NAME"
        fi
    fi
done

# 5. Stop Containers & Wait
[[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Stopping all containers..."

RUNNING_CONTAINERS=$($DOCKER ps -q)
if [ -n "$RUNNING_CONTAINERS" ]; then
    $DOCKER stop -t 20 $RUNNING_CONTAINERS >/dev/null 2>&1
    
    COUNT=0
    while [ -n "$($DOCKER ps -q)" ] && [ $COUNT -lt 10 ]; do
        sleep 3
        ((COUNT++))
    done

    STUCK=$($DOCKER ps -q)
    if [ -n "$STUCK" ]; then
        log "⚠️ Killing stuck processes (Exit 137 imminent)..."
        $DOCKER kill $STUCK >/dev/null 2>&1
        sleep 5 
    fi
fi

# 6. Backup Data (Conditional)
if [ "$SKIP_BACKUP" = true ]; then
    log "⏩ Skipping rsync backup as requested."
else
    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Syncing /opt to $BACKUP_DEST..."
    sudo rsync -avh /opt/ "$BACKUP_DEST" --delete --quiet
fi

# 7. Restart
[[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Restarting containers..."

PATHS_TO_CHECK=("/opt" /opt/*/)
for path in "${PATHS_TO_CHECK[@]}"; do
    CLEAN_PATH="${path%/}"
    DIR_NAME=$(basename "$CLEAN_PATH")
    COMPOSE_FILE=$(find_compose "$path")
    
    if [ -n "$COMPOSE_FILE" ]; then
        $DOCKER compose -f "$COMPOSE_FILE" --project-directory "$CLEAN_PATH" down >/dev/null 2>&1
        $DOCKER compose -f "$COMPOSE_FILE" --project-directory "$CLEAN_PATH" up -d
        
        if [ $? -eq 0 ]; then
            [[ $LOG_LEVEL = "debug" ]] && log "✅ $DIR_NAME is online."
        else
            log "❌ ERROR: $DIR_NAME failed to start."
        fi
    fi
done

# 8. Cleanup
[[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Pruning unused resources..."
$DOCKER image prune -f

log_end
