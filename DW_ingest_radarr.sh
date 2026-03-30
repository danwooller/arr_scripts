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
    find "$DIR_MEDIA_COMPLETED_MOVIES" -mindepth 2 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.ts" \) -exec mv -t "$DIR_MEDIA_COMPLETED_MOVIES" {} +
    find "$DIR_MEDIA_COMPLETED_MOVIES" -mindepth 1 -type d -empty -delete 2>/dev/null
    find "$DIR_MEDIA_COMPLETED_MOVIES" -type f \( -name "*.nfo" -o -name "*.txt" -o -name "*.jpg" -o -name "*.png" -o -name "*.url" \) -delete 2>/dev/null

    # --- 1. Standardize Spacing ---
    find "$DIR_MEDIA_COMPLETED_MOVIES" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # --- 2. Processing Loop ---
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.ts" \) \
        ! -name "*.tmp" \
        ! -regex ".*([0-9][0-9][0-9][0-9])\.mkv$" -print0 | while IFS= read -r -d $'\0' file; do
        
        ORIGINAL_FILENAME=$(basename "$file")
        FILE_NAME_BASE="${ORIGINAL_FILENAME%.*}"
        
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        # --- 3. Robust Naming Logic ---
        year=$(echo "$ORIGINAL_FILENAME" | grep -oP '\d{4}' | head -n 1)
        clean_name=$(echo "$FILE_NAME_BASE" | tr '._-' ' ')
        
        # ADD THIS LINE: Specifically remove existing empty parens or double spaces
        clean_name=$(echo "$clean_name" | sed -E 's/\(\)//g' | sed -E 's/ +/ /g')
        
        # Expanded Junk List
        for junk in "$year" "1080p" "720p" "2160p" "4K" "UHD" "HDR" "DV" "IMAX" "BluRay" "BDRip" "BRRip" "RMTeam" "WEB-DL" "WEB" "x264" "x265" "LAMA" "HEVC" "REMUX" "AMZN" "NF" "DSNP" "HMAX"; do
            clean_name=$(echo "$clean_name" | sed -E "s/\b$junk\b//gi")
        done
        
        # Final Clean & Proper Case
        final_title=$(echo "$clean_name" | sed -E 's/ +/ /g' | sed -E 's/\b([a-z])/\U\1/g' | xargs)

        if [ -z "$final_title" ]; then final_title="$FILE_NAME_BASE"; fi

        TARGET_FILENAME="${final_title// /_}_(${year:-0000}).mkv"
        TARGET_PATH="$DIR_MEDIA_COMPLETED_MOVIES/$TARGET_FILENAME"

        log "🎬 Processing: $TARGET_FILENAME"

        # --- 4. Remux Logic ---
        sonos_audio_fix "$file"
        subtitle_opts "$file"

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
            sync

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

    sleep "$SLEEP_INTERVAL"
done
