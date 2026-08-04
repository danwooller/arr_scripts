#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

log_start

# --- Helper Function to find Compose files ---
find_compose() {
    local target="$1"
    local cname="$2"

    # 1. Try label inspection if container name provided
    if [ -n "$cname" ]; then
        local label_file
        label_file=$($DOCKER inspect -f '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' "$cname" 2>/dev/null)
        if [ -n "$label_file" ] && [ -f "$label_file" ]; then
            echo "$label_file"
            return
        fi
    fi

    # 2. Search folder up to 3 levels deep inside /opt/docker
    if [ -d "$target" ] && [ "$target" != "/opt" ]; then
        sudo find "$target" -maxdepth 3 \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) 2>/dev/null | head -n 1
    fi
}

# --- Configuration ---
DOCKER="/usr/bin/docker"
DOCKER_DIR="/opt/docker"
BACKUP_DEST="$DIR_MEDIA_BACKUP/${HOSTNAME}/opt"
REQUIRED_SPACE_MB=5000
LOG_LEVEL="debug"

# --- Gather Running Containers via Docker Inspect ---
RUNNING_IDS=$($DOCKER ps -q)
CONTAINER_NAMES=()
COMPOSE_TARGETS=()

if [ -n "$RUNNING_IDS" ]; then
    while IFS= read -r cname; do
        CLEAN_NAME="${cname#/}"
        if [ -n "$CLEAN_NAME" ]; then
            CONTAINER_NAMES+=("$CLEAN_NAME")

            # Direct match under /opt/docker/container_name
            if [ -d "$DOCKER_DIR/$CLEAN_NAME" ]; then
                COMPOSE_TARGETS+=("$DOCKER_DIR/$CLEAN_NAME")
            else
                FOUND_DIR=$(sudo find "$DOCKER_DIR" -maxdepth 2 -type d -name "$CLEAN_NAME" 2>/dev/null | head -n 1)
                if [ -n "$FOUND_DIR" ]; then
                    COMPOSE_TARGETS+=("$FOUND_DIR")
                else
                    PROJ_DIR=$($DOCKER inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$CLEAN_NAME" 2>/dev/null)
                    # Enforce that paths do not fallback higher than /opt/docker
                    if [ -z "$PROJ_DIR" ] || [ "$PROJ_DIR" == "/opt" ] || [ "$PROJ_DIR" == "/" ]; then
                        COMPOSE_TARGETS+=("$DOCKER_DIR/$CLEAN_NAME")
                    else
                        COMPOSE_TARGETS+=("$PROJ_DIR")
                    fi
                fi
            fi
        fi
    done < <($DOCKER inspect -f '{{.Name}}' $RUNNING_IDS 2>/dev/null | sort -u)
fi

if [ ${#CONTAINER_NAMES[@]} -eq 0 ]; then
    echo "⚠️ No running Docker containers detected."
    exit 1
fi

# --- Flag Handling & Interactive Menu ---
SKIP_BACKUP=false
SKIP_UPDATE=false
TARGET_DIR="" # Empty means process ALL
TARGET_CONTAINER=""

# 1. Selection Scope & Single Target Option

echo ""
echo "Select Update Scope:"
echo "  1) All Running Containers (Default)"
echo "  2) Single Service"
read -t 30 -p "Choice (1/2) [1]: " SCOPE_CHOICE
SCOPE_CHOICE=${SCOPE_CHOICE:-1}

if [ "$SCOPE_CHOICE" -eq 2 ]; then
    echo ""
    echo "📋 Running Docker Services:"


#    for i in "${!CONTAINER_NAMES[@]}"; do
#        echo "  $((i+1))) ${CONTAINER_NAMES[$i]}"
#    done

for i in "${!CONTAINER_NAMES[@]}"; do
    echo "$((i+1))) ${CONTAINER_NAMES[$i]}"
done | pr -3 -t -T


    read -t 30 -p "Select a target (1-${#CONTAINER_NAMES[@]}): " CHOICE
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#CONTAINER_NAMES[@]}" ]; then
        TARGET_CONTAINER="${CONTAINER_NAMES[$((CHOICE-1))]}"
        TARGET_DIR="${COMPOSE_TARGETS[$((CHOICE-1))]}"
        log "ℹ️ Selected single target: $TARGET_CONTAINER [$TARGET_DIR]"
    else
        echo "❌ Invalid selection or timeout reached. Exiting."
        exit 1
    fi
fi
echo ""

# 2. Safety Checks
if ! mountpoint -q "$MOUNT_ROOT"; then
    log "❌ $MOUNT_ROOT is not mounted!"
    exit 1
fi

# 3. Pre-fetch Images
PULL_LIST=()
PULL_NAMES=()

if [ -n "$TARGET_DIR" ]; then
    PULL_LIST=("$TARGET_DIR")
    PULL_NAMES=("$TARGET_CONTAINER")
else
    mapfile -t PULL_LIST < <(printf "%s\n" "${COMPOSE_TARGETS[@]}" | sort -u)
    PULL_NAMES=("${CONTAINER_NAMES[@]}")
fi

for i in "${!PULL_LIST[@]}"; do
    path="${PULL_LIST[$i]}"
    cname="${PULL_NAMES[$i]}"
    COMPOSE_FILE=$(find_compose "$path" "$cname")
    DIR_NAME=$(basename "$path")

    if [ -n "$COMPOSE_FILE" ]; then
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Pre-pulling image for $cname using: $COMPOSE_FILE"

        CURRENT_SPACE_MB=$(df -m "$path" | awk 'NR==2 {print $4}')
        if [ "$CURRENT_SPACE_MB" -lt "$REQUIRED_SPACE_MB" ]; then
            log "⚠️ Skipping pull for $DIR_NAME. Low space: ${CURRENT_SPACE_MB}MB (Required: ${REQUIRED_SPACE_MB}MB)"
            continue
        fi

        # Target specific container name if single mode is set to avoid pulling entire root stacks
        if [ -n "$TARGET_CONTAINER" ]; then
            PULL_ERR=$(sudo timeout 600s $DOCKER compose -f "$COMPOSE_FILE" pull "$TARGET_CONTAINER" 2>&1)
        else
            PULL_ERR=$(sudo timeout 600s $DOCKER compose -f "$COMPOSE_FILE" pull 2>&1)
        fi
        
        PULL_RESULT=$?

        if [ $PULL_RESULT -eq 124 ]; then
            log "❌ Pull TIMED OUT (600s) for $DIR_NAME"
        elif [ $PULL_RESULT -ne 0 ]; then
            log "❌ Pull FAILED for $DIR_NAME: $PULL_ERR"
        else
            [[ $LOG_LEVEL == "debug" ]] && log "✅ Pull successful for $DIR_NAME"
        fi
    else
        log "⚠️ No compose file found in $path for $DIR_NAME. Skipping image pull."
    fi
done

# Check Tautulli Plex Activity
if [ "$SKIP_BACKUP" = false ] && { [ -z "$TARGET_CONTAINER" ] || [ "$TARGET_CONTAINER" == "plex" ]; }; then
    if [ -n "$TAUTULLI_URL" ] && [ -n "$TAUTULLI_API_KEY" ]; then
        log "ℹ️ Checking Plex activity via Tautulli..."
        MAX_RETRIES=${MAX_RETRIES:-3}
        WAIT_TIME=${WAIT_TIME:-900}
        
        for (( i=1; i<=$MAX_RETRIES; i++ )); do
            STREAMS=$(curl -s "$TAUTULLI_URL/api/v2?apikey=$TAUTULLI_API_KEY&cmd=get_activity" | grep -oP '"stream_count":\s*"\K[0-9]+')
            STREAMS=${STREAMS:-0}

            if [ "$STREAMS" -eq 0 ]; then
                log "✅ No active streams detected. Proceeding..."
                break
            else
                if [ $i -eq $MAX_RETRIES ]; then
                    log "⚠️ Max retries reached. Users are still watching, but proceeding with backup anyway."
                else
                    log "⏳ $STREAMS stream(s) active. Waiting 15m (Attempt $i/$MAX_RETRIES)..."
                    sleep $WAIT_TIME
                fi
            fi
        done
    fi
fi

# 4. Stop Containers
COMPOSE_FILE=$(find_compose "$TARGET_DIR" "$TARGET_CONTAINER")
if [ -n "$COMPOSE_FILE" ]; then
    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Stopping target compose service: $TARGET_CONTAINER..."
    $DOCKER compose -f "$COMPOSE_FILE" stop "$TARGET_CONTAINER"
else
    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Stopping target container directly: $TARGET_CONTAINER..."
    $DOCKER stop "$TARGET_CONTAINER" >/dev/null 2>&1
fi

# 5. Restart Containers
[[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Restarting containers..."

EXECUTE_LIST=("$TARGET_DIR")
EXECUTE_NAMES=("$TARGET_CONTAINER")

for i in "${!EXECUTE_LIST[@]}"; do
    path="${EXECUTE_LIST[$i]}"
    cname="${EXECUTE_NAMES[$i]}"
    DIR_NAME=$(basename "$path")
    COMPOSE_FILE=$(find_compose "$path" "$cname")
    
    if [ -n "$COMPOSE_FILE" ]; then
        if [ -n "$TARGET_CONTAINER" ]; then
            $DOCKER compose -f "$COMPOSE_FILE" up -d --build "$TARGET_CONTAINER"
        else
            $DOCKER compose -f "$COMPOSE_FILE" down >/dev/null 2>&1
            $DOCKER compose -f "$COMPOSE_FILE" up -d --build
        fi
        
        if [ $? -eq 0 ]; then
            [[ $LOG_LEVEL = "debug" ]] && log "✅ $DIR_NAME ($cname) is online."
        else
            log "❌ $DIR_NAME ($cname) failed to start via compose."
        fi
    else
        log "⚠️ Could not locate compose file for $DIR_NAME in $path."
        if [ -n "$cname" ]; then
            $DOCKER start "$cname" >/dev/null 2>&1
            [[ $LOG_LEVEL == "debug" ]] && log "⚠️ $cname started directly (container restart, no image pull applied)."
        fi
    fi
done

# 6. Cleanup & Reboot Check
[[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Pruning unused resources..."
$DOCKER image prune -f

if [ -f /var/run/reboot-required ]; then
    log "⚠️ reboot required"
else
    log "ℹ️ no reboot required"
fi

log_end
