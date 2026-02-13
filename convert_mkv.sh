#!/bin/bash

# --- Configuration ---
HOST=$(hostname -s)
EXT_VIDEO=("mp4" "m4v")
EXT_OUT=".mkv"
SOURCE_DIR="/mnt/media/torrent/${HOST}"
CONVERTMKV_DIR="${SOURCE_DIR}/convertmkv"
OUTPUT_DIR="/mnt/media/torrent/completed/"
FINISHED_DIR="/mnt/media/torrent/finished/"
LOG_FILE="/mnt/media/torrent/${HOST}.log"
# LOG_LEVEL="debug" # Uncomment this line to enable verbose logging
POLL_INTERVAL=30

mkdir -p "$SOURCE_DIR" "$CONVERTMKV_DIR" "$OUTPUT_DIR" "$FINISHED_DIR"

log() {
    echo "$(date +'%H:%M'): ($0) $1" | tee -a "$LOG_FILE"
}

# --- Dependencies ---
for dep in "HandBrakeCLI" "mkvmerge" "jq" "mkvpropedit" "rename"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        log "Installing '$dep'..."
        sudo apt-get update && sudo apt-get install -y "${dep%-*}"
    fi
done

log "$0 started (Processing: ${EXT_VIDEO[*]})"

while true; do
    # 1. Standardize filenames (spaces to underscores)
    if [[ $LOG_LEVEL = "debug" ]]; then
        log "Renaming input files (spaces -> underscores)"
    fi
    rename 's/ /_/g' "${CONVERTMKV_DIR}/"* 2>/dev/null

    # 2. Loop through files
    for FULL_PATH in "${CONVERTMKV_DIR}/"*; do
        [[ -e "$FULL_PATH" ]] || continue
        [[ -d "$FULL_PATH" ]] && continue 

        FULL_FILE_NAME="${FULL_PATH##*/}"
        FILE_NAME="${FULL_FILE_NAME%.*}"
        FILE_EXT="${FULL_FILE_NAME##*.}"

        # 3. Check Extension Match
        MATCH=false
        for EXT in "${EXT_VIDEO[@]}"; do
            if [[ "$FILE_EXT" == "$EXT" ]]; then MATCH=true; break; fi
        done

        if [ "$MATCH" = true ]; then
            
            # --- OVERWRITE CHECK ---
            # Check if file with spaces or underscores already exists in output
            CLEAN_NAME=$(echo "$FILE_NAME" | tr '_' ' ')
            if [[ -f "${OUTPUT_DIR}${FILE_NAME}${EXT_OUT}" ]] || [[ -f "${OUTPUT_DIR}${CLEAN_NAME}${EXT_OUT}" ]]; then
                log "Skipping $FULL_FILE_NAME: Output file already exists in completed folder."
                continue
            fi

            # --- STABILITY CHECK ---
            SIZE1=$(stat -c%s "$FULL_PATH")
            sleep 5
            SIZE2=$(stat -c%s "$FULL_PATH")

            if [ "$SIZE1" -ne "$SIZE2" ]; then
                if [[ $LOG_LEVEL = "debug" ]]; then
                    log "Skipping $FULL_FILE_NAME (File size is changing; still downloading?)"
                fi
                continue
            fi

            # 4. Conversion Process
            OUTPUT_FILE="${OUTPUT_DIR}${FILE_NAME}${EXT_OUT}"
            if [[ $LOG_LEVEL = "debug" ]]; then
                log "Processing: ${FULL_FILE_NAME} -> ${EXT_OUT}"
            fi
            
            mkvmerge -o "${OUTPUT_FILE}" "${FULL_PATH}" > /dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                if [[ $LOG_LEVEL = "debug" ]]; then
                    log "Success. Moving original to finished."
                fi
                mv "$FULL_PATH" "${FINISHED_DIR}${FULL_FILE_NAME}"
            else
                log "❌ Error converting ${FULL_FILE_NAME}"
            fi
        fi
    done

    # 5. Clean up output names (underscores back to spaces)
    if [[ $LOG_LEVEL = "debug" ]]; then
         log " Renaming output files (underscores -> spaces)"
    fi
    rename 's/_/ /g' "${OUTPUT_DIR}"/*${EXT_OUT} 2>/dev/null

    sleep "$POLL_INTERVAL"
done
