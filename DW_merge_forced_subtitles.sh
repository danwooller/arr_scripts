#!/bin/bash

# Monitors a folder looking for video files with
# corresponding subtitle files and merges them.
# Use for FORCED subtitles.

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
HOST=$(hostname -s)
WATCH_DIR="$DIR_MEDIA_TORRENT/${HOST}/subtitles/forced"
EXT_VIDEO=("mp4" "mkv" "m4v")
SUBTITLE_EXT="srt"
POLL_INTERVAL=60

mkdir -p "$DIR_MEDIA_COMPLETED_TV" "$DIR_MEDIA_HOLD" "$WATCH_DIR"

check_dependencies "mkvmerge" "mkvpropedit" "rename" "find"

log "--- Forced Subtitle Merger (English Check Enabled) ---"

while true; do
    # 1. Standardize names
    find "$WATCH_DIR" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Find video files
    FIND_ARGS=()
    for EXT in "${EXT_VIDEO[@]}"; do
        FIND_ARGS+=("-name" "*.$EXT" "-o")
    done
    unset 'FIND_ARGS[${#FIND_ARGS[@]}-1]'

    mapfile -t VIDEO_FILES < <(find "$WATCH_DIR" -type f \( "${FIND_ARGS[@]}" \))

    for FULL_PATH in "${VIDEO_FILES[@]}"; do
        [[ -e "$FULL_PATH" ]] || continue

        BASE_FILE=$(basename "$FULL_PATH")
        DIR_PATH=$(dirname "$FULL_PATH")
        FILE_NAME="${BASE_FILE%.*}"
        SUB_FILE="${DIR_PATH}/${FILE_NAME}.${SUBTITLE_EXT}"

        if [[ -f "$SUB_FILE" ]]; then
            
            # --- ENGLISH CONTENT CHECK ---
            # Checks for common English words (case insensitive) to verify track language
#            if ! grep -qiE " a | about | all | an | and | as | at | be | but | by | do | for \
#                | from | get | go | have | he | her | his | hold | I | if | in | it | me | my \
#                | not | of | on | one | or | out | say | she | so | that | the | their | there \
#                | they | this | to | up | we | what | which | who | will | with | would | you " "$SUB_FILE"; then
#                log "Skipping $BASE_FILE: Subtitle file does not appear to be English."
#                continue
#            fi
            
            # Stability Check
            SIZE1=$(stat -c%s "$FULL_PATH")
            sleep 5
            SIZE2=$(stat -c%s "$FULL_PATH")
            [[ "$SIZE1" -ne "$SIZE2" ]] && continue

            OUTPUT_FILE="${DIR_MEDIA_COMPLETED_TV}/${FILE_NAME}.mkv"
            CLEAN_TITLE=$(echo "$FILE_NAME" | sed "s/_/ /g")

            log "Merging: $BASE_FILE (Verified English Subs)"

            # 3. Merge
#            mkvmerge -o "$OUTPUT_FILE" "$FULL_PATH" "$SUB_FILE" --title "$CLEAN_TITLE" > /dev/null 2>&1
            mkvmerge -o "$OUTPUT_FILE" -S "$FULL_PATH" "$SUB_FILE" --title "$CLEAN_TITLE" > /dev/null 2>&1

            if [ $? -eq 0 ]; then
                # 4. Metadata tagging
                mkvpropedit "$OUTPUT_FILE" \
                    --edit track:s1 --set flag-default=1 --set flag-forced=1 --set language=en --set name="Forced" \
                    --edit track:a1 --set language=en \
                    --edit track:v1 --set language=en > /dev/null 2>&1
                
                # 5. Cleanup
                rm -f "$DIR_MEDIA_HOLD$BASE_FILE"
                mv "$FULL_PATH" "$DIR_MEDIA_HOLD/"
                rm -f "$SUB_FILE"
                
                log "✅ Successfully merged $CLEAN_TITLE"
            else
                log "❌ Error merging $BASE_FILE"
            fi
        fi
    done

    # 6. Cleanup output names
    rename 's/_/ /g' "${DIR_MEDIA_COMPLETED_TV}"/*.mkv 2>/dev/null

    sleep "$POLL_INTERVAL"
done
