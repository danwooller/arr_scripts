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
        # 1. Extract the year
        year=$(echo "$ORIGINAL_FILENAME" | grep -oP '\d{4}' | head -n 1)

        # 2. Advanced Clean: Keep everything BEFORE the year or the first resolution tag
        # This regex looks for the year or 1080p/720p/etc and clips the string there
        clean_name=$(echo "$FILE_NAME_BASE" | sed -E "s/([._(-]($year|1080p|720p|2160p|BluRay|BDRip|WEB-DL|x26[45]|LAMA)).*//gi")

        # 3. If the above failed (e.g., year is at the very start), fallback to stripping just the year
        if [ -z "$clean_name" ]; then
            clean_name=$(echo "$FILE_NAME_BASE" | sed "s/$year//g")
        fi

        # 4. Final Polish: Convert separators to spaces and trim
        final_title=$(echo "$clean_name" | tr '._-' ' ' | sed -E 's/ +/ /g' | xargs)

        # 5. Last Resort Fallback
        if [ -z "$final_title" ]; then
            final_title=$(echo "$FILE_NAME_BASE" | tr '._-' ' ' | xargs)
        fi

        TARGET_FILENAME="${final_title} (${year:-0000}).mkv"
        TARGET_PATH="$DIR_MEDIA_COMPLETED_MOVIES/$TARGET_FILENAME"

        log "🎬 Processing: $TARGET_FILENAME"

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
