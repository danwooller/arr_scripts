#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
EXT_VIDEO=("mp4" "m4v")
EXT_OUT=".mkv"

# Directories to monitor recursively
WATCH_DIRS=(
    "$DIR_MEDIA_COMPLETED_4KMOVIES"
    "$DIR_MEDIA_COMPLETED_4KTV"
    "$DIR_MEDIA_COMPLETED_MOVIES"
    "$DIR_MEDIA_COMPLETED_TV"
)

# Note: OUTPUT_DIR is now used as a fallback or temp if needed, 
# but we will prioritize the source subfolder.
POLL_INTERVAL=30

# --- Run Dependency Check ---
check_dependencies "HandBrakeCLI" "jq" "mkvmerge" "mkvpropedit" "rename"

log_start

while true; do
    for TARGET_DIR in "${WATCH_DIRS[@]}"; do
        [[ -d "$TARGET_DIR" ]] || continue

        # 1. Find and process matching video files recursively
        FIND_ARGS=()
        for EXT in "${EXT_VIDEO[@]}"; do
            FIND_ARGS+=("-name" "*.$EXT" "-o")
        done
        unset 'FIND_ARGS[${#FIND_ARGS[@]}-1]' 

        mapfile -t FILE_LIST < <(find "$TARGET_DIR" -type f \( "${FIND_ARGS[@]}" \))

        for FULL_PATH in "${FILE_LIST[@]}"; do
            [[ -e "$FULL_PATH" ]] || continue

            # Get the directory and filename details
            PARENT_DIR=$(dirname "$FULL_PATH")
            FULL_FILE_NAME=$(basename "$FULL_PATH")
            FILE_NAME="${FULL_FILE_NAME%.*}"

            if [ -n "$FILE_NAME" ]; then
                
                # --- NEW LOGIC: Set output to the same directory as the source ---
                FINAL_OUTPUT="${PARENT_DIR}/${FILE_NAME}${EXT_OUT}"
                
                # --- OVERWRITE CHECK ---
                if [[ -f "$FINAL_OUTPUT" ]]; then
                    if [[ $LOG_LEVEL = "debug" ]]; then
                        log "Skipping $FULL_FILE_NAME: Output already exists in $PARENT_DIR."
                    fi
                    continue
                fi

                # --- STABILITY CHECK ---
                SIZE1=$(stat -c%s "$FULL_PATH")
                sleep 5
                SIZE2=$(stat -c%s "$FULL_PATH")

                if [ "$SIZE1" -ne "$SIZE2" ]; then
                    continue
                fi

                # 2. Conversion Process
                log "ℹ️ Converting: ${FULL_FILE_NAME} -> ${FILE_NAME}${EXT_OUT} in ${PARENT_DIR}"
                
                mkvmerge -o "${FINAL_OUTPUT}" \
                    --language 0:und \
                    --language 1:eng \
                    --track-name 1:"English" \
                    "${FULL_PATH}" > /dev/null 2>&1

                if [ $? -eq 0 ]; then
                    log "ℹ️ Success. Moving original ${FULL_FILE_NAME} to finished."
                    mv "$FULL_PATH" "${DIR_MEDIA_FINISHED}/${FULL_FILE_NAME}"

                    log "ℹ️ Removing torrent: $FILE_NAME"
                    manage_remote_torrent "delete" "$FILE_NAME"
                else
                    log "⚠️ Error: mkvmerge failed on ${FULL_FILE_NAME}"
                fi
            fi
        done
    done

    sleep "$POLL_INTERVAL"
done
