#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
SLEEP_INTERVAL=120
mkdir -p "$DIR_MEDIA_COMPLETED_MOVIES" "$DIR_MEDIA_FINISHED" "$DIR_MEDIA_SUBTITLES"
check_dependencies "lsof" "mkvmerge" "jq" "mkvpropedit" "rename"

log_start "$DIR_MEDIA_COMPLETED_MOVIES"

while true; do
    # --- 0. Flatten & Cleanup ---
    # Move files from subfolders to root, then delete empty folders and junk files
    find "$DIR_MEDIA_COMPLETED_MOVIES" -mindepth 2 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.ts" \) -exec mv -t "$DIR_MEDIA_COMPLETED_MOVIES" {} +
    find "$DIR_MEDIA_COMPLETED_MOVIES" -mindepth 1 -type d -empty -delete 2>/dev/null
    find "$DIR_MEDIA_COMPLETED_MOVIES" -type f \( -name "*.nfo" -o -name "*.txt" -o -name "*.jpg" -o -name "*.png" -o -name "*.url" \) -delete 2>/dev/null

    # --- 1. Processing Loop ---
    # Regex updated to ignore ANY file ending in (YYYY).mkv regardless of space or underscore
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.ts" \) \
    ! -name "*.tmp" \
    ! -regex ".*([0-9][0-9][0-9][0-9])\.mkv$" -print0 | while IFS= read -r -d $'\0' file; do
        
        ORIGINAL_FILENAME=$(basename "$file")
        FILE_NAME_BASE="${ORIGINAL_FILENAME%.*}"
        
        # Check if file is still being written
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        # --- 2. Robust Naming Logic ---
        year=$(echo "$ORIGINAL_FILENAME" | grep -oP '\d{4}' | head -n 1)
        
        # Kill everything in square brackets [YTS.BZ] etc.
        # Convert dots, underscores, dashes to spaces
        clean_name=$(echo "$FILE_NAME_BASE" | sed 's/\[[^]]*\]//g' | tr '._-' ' ')

        # Strip the year specifically (if found)
        if [ -n "$year" ]; then
            clean_name=$(echo "$clean_name" | sed -E "s/\b$year\b//gi")
        fi

        # Strip global junk tags
        # We add a trailing space to the replacement to ensure words don't "smush"
        for junk in "${MEDIA_JUNK_TAGS[@]}"; do
            clean_name=$(echo "$clean_name" | sed -E "s/\b$junk\b/ /gi")
        done

        # Capitalize the first letter of every word BEFORE final space cleanup
        # This helps sed 'see' the word boundaries better
        final_title=$(echo "$clean_name" | sed -E 's/\b([a-z])/\U\1/g')

        # FINAL CLEANUP:
        # 1. Remove empty parentheses
        # 2. Collapse multiple spaces into one
        # 3. Trim leading/trailing whitespace
        final_title=$(echo "$final_title" | sed -E 's/\(\)//g' | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

        # Fallback if title becomes empty
        if [ -z "$final_title" ]; then final_title="$FILE_NAME_BASE"; fi

        # Construct target name
        TARGET_FILENAME="${final_title} (${year:-0000}).mkv"
        TARGET_PATH="$DIR_MEDIA_COMPLETED_MOVIES/$TARGET_FILENAME"

        log "🎬 Processing: $TARGET_FILENAME"

        # --- 3. Remux Logic ---
        #sonos_audio_fix "$file"
        #subtitle_opts "$file"

        if [ -f "$TARGET_PATH" ]; then
            log "⚠️ $TARGET_FILENAME already exists. Skipping."
            continue
        fi

        TEMP_FILE="${file}.processing.tmp"
        mv "$file" "$TEMP_FILE"
        
        if mkvmerge -q -o "$TARGET_PATH" $TRACK_OPTS "$TEMP_FILE"; then
            if [ "$NEEDS_PROPEDIT" = true ]; then
                log "🏷️ Setting Forced flags..."
                mkvpropedit "$TARGET_PATH" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "✅ Remux successful."
#            sync
            sleep 2

            if mv "$TEMP_FILE" "$DIR_MEDIA_FINISHED/$ORIGINAL_FILENAME"; then
                manage_remote_torrent "delete" "$FILE_NAME_BASE"
                radarr_ingest "$DIR_MEDIA_COMPLETED_MOVIES"
            else
                log "❌ Failed to move original file!"
            fi
        else
            log "❌ Merge failed for $ORIGINAL_FILENAME"
            mv "$TEMP_FILE" "$file"
            ha_notification "⚠️ Ingest Failed" "mkvmerge failed for: $ORIGINAL_FILENAME."
            manage_remote_torrent "resume" "$FILE_NAME_BASE"
        fi
    done

    sleep "$SLEEP_INTERVAL"
done
