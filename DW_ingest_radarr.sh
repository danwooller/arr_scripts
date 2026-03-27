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
    # 0. Flatten: Move media from sub-folders to parent
    find "$DIR_MEDIA_COMPLETED_MOVIES" -mindepth 2 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.ts" \) -exec mv -t "$DIR_MEDIA_COMPLETED_MOVIES" {} +
    
    # 1. Standardize spacing (Now includes files just moved)
    find "$DIR_MEDIA_COMPLETED_MOVIES" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Processing Loop
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.ts" \) \
        ! -name "*.tmp" \
        ! -regex ".*/.* ([0-9][0-9][0-9][0-9])\.mkv$" -print0 | while IFS= read -r -d $'\0' file; do
        
        # Skip if it already matches the "Final" format to prevent loops
        if [[ "$file" =~ \([0-9]{4}\)\.mkv$ ]]; then
            continue
        fi

        ORIGINAL_FILENAME=$(basename "$file")
        
        # Stability Check
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        log "🎬 Processing: $ORIGINAL_FILENAME"

        # --- Sonos Fix & Audio ID Selection ---
        sonos_audio_fix "$file"

         # --- Subtitle processing ---
        subtitle_opts "$file"
        
        # --- Naming & Duplicate Protection ---
        # --- Naming & Duplicate Protection ---
        year=$(echo "$ORIGINAL_FILENAME" | grep -oP '\d{4}' | head -n 1)

        # 1. Strip common scene tags and resolution
        # We move the year-strip to a separate step to avoid wiping the whole title
        clean_title=$(echo "$FILE_NAME_BASE" | sed -E "s/([0-9]{3,4}p|BluRay|BDRip|WEB-DL|x26[45]|LAMA)//gi")

        # 2. Specifically strip the year if it's preceded by a separator
        if [ -n "$year" ]; then
            clean_title=$(echo "$clean_title" | sed -E "s/[._(-]${year}[._)-].*//g")
        fi

        # 3. Clean up separators and trim whitespace
        final_title=$(echo "$clean_title" | tr '._' ' ' | sed -E 's/ +/ /g' | xargs)

        # Fallback: If title became empty (rare), use the original base name
        if [ -z "$final_title" ]; then
            final_title="$FILE_NAME_BASE"
        fi

        TARGET_FILENAME="${final_title} (${year:-0000}).mkv"
        TARGET_PATH="$DIR_MEDIA_COMPLETED_MOVIES/$TARGET_FILENAME"

        if [ -f "$TARGET_PATH" ]; then
            log "⚠️ $TARGET_FILENAME already exists. Skipping."
            continue
        fi

        # --- Execute Remux ---
        TEMP_FILE="${file}.processing.tmp"
        mv "$file" "$TEMP_FILE"
        
        log "🔨 Merging into: $TARGET_FILENAME"
        if mkvmerge -q -o "$TARGET_PATH" $TRACK_OPTS "$TEMP_FILE"; then
            
            # Only run mkvpropedit if subtitles were actually merged
            if [ "$NEEDS_PROPEDIT" = true ]; then
                log "🏷️ Setting Forced flags on subtitle track..."
                mkvpropedit "$TARGET_PATH" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "✅ Remux successful. Archiving original..."
            sync

            # Final Move to Finished and trigger Radarr
            if mv "$TEMP_FILE" "$DIR_MEDIA_FINISHED/$ORIGINAL_FILENAME"; then
                manage_remote_torrent "delete" "$FILE_NAME_BASE"
                radarr_ingest "$DIR_MEDIA_COMPLETED_MOVIES"
            fi
        else
            log "❌ Merge failed for $ORIGINAL_FILENAME"
            mv "$TEMP_FILE" "$file"
            manage_remote_torrent "resume" "$FILE_NAME_BASE"
        fi
    done

    # Clean up empty folders left behind
    find "$DIR_MEDIA_COMPLETED_MOVIES" -type d -empty -delete 2>/dev/null

    sleep "$SLEEP_INTERVAL"
done
