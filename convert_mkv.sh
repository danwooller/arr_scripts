#!/bin/bash

# --- Configuration ---
HOST=$(hostname -s)
EXT_VIDEO=("mp4" "m4v")
EXT_OUT=".mkv"

# Directories to monitor recursively
WATCH_DIRS=(
    "/mnt/media/torrent/completed"
    "/mnt/media/torrent/completed-movies"
)

OUTPUT_DIR="/mnt/media/torrent/completed"
FINISHED_DIR="/mnt/media/torrent/finished/"
LOG_FILE="/mnt/media/torrent/${HOST}.log"
# LOG_LEVEL="debug"
POLL_INTERVAL=30

mkdir -p "$OUTPUT_DIR" "$FINISHED_DIR"

# --- Logging Function ---
log() {
    echo "$(date +'%H:%M'): (${0##*/}) $1" | tee -a "$LOG_FILE"
}

# --- Dependencies ---
for dep in "HandBrakeCLI" "mkvmerge" "jq" "mkvpropedit" "rename"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        log "Installing '$dep'..."
        sudo apt-get update && sudo apt-get install -y "${dep%-*}"
    fi
done

log "--- (${0##*/}) started ---"

while true; do
    for TARGET_DIR in "${WATCH_DIRS[@]}"; do
        [[ -d "$TARGET_DIR" ]] || continue

        # 1. Standardize filenames recursively (spaces -> underscores)
        # Using find to catch files in subfolders
        find "$TARGET_DIR" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

        # 2. Find and process matching video files recursively
        # This builds a list of files matching our extensions in any subfolder
        FIND_ARGS=()
        for EXT in "${EXT_VIDEO[@]}"; do
            FIND_ARGS+=("-name" "*.$EXT" "-o")
        done
        unset 'FIND_ARGS[${#FIND_ARGS[@]}-1]' # Remove trailing "-o"

        # Read results into an array
        mapfile -t FILE_LIST < <(find "$TARGET_DIR" -type f \( "${FIND_ARGS[@]}" \))

        for FULL_PATH in "${FILE_LIST[@]}"; do
            [[ -e "$FULL_PATH" ]] || continue

            FULL_FILE_NAME=$(basename "$FULL_PATH")
            FILE_EXT="${FULL_FILE_NAME##*.}"
            FILE_NAME="${FULL_FILE_NAME%.*}"

            if [ -n "$FILE_NAME" ]; then
                
                FINAL_OUTPUT="${OUTPUT_DIR}/${FILE_NAME}${EXT_OUT}"
                
                # --- OVERWRITE CHECK ---
                if [[ -f "$FINAL_OUTPUT" ]]; then
                    if [[ $LOG_LEVEL = "debug" ]]; then
                        log "Skipping $FULL_FILE_NAME: Output exists in $OUTPUT_DIR."
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

                # 3. Conversion Process
                log "Converting: ${FULL_FILE_NAME} (from subfolder) -> ${FILE_NAME}${EXT_OUT}"
                
                mkvmerge -o "${FINAL_OUTPUT}" "${FULL_PATH}" > /dev/null 2>&1
                
                if [ $? -eq 0 ]; then
                    log "✅ Success. Moving ${FULL_FILE_NAME} to finished."
                    # Moves original to finished, preserving its name (but loses subfolder structure in finished)
                    mv "$FULL_PATH" "${FINISHED_DIR}${FULL_FILE_NAME}"
                else
                    log "❌ Error converting ${FULL_FILE_NAME}"
                    rm -f "$FINAL_OUTPUT"
                fi
            fi
        done
    done

    # 4. Clean up output names in the central folder
    rename 's/_/ /g' "${OUTPUT_DIR}/"*${EXT_OUT} 2>/dev/null

    sleep "$POLL_INTERVAL"
done
