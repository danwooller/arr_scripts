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
    # 1. Standardize spacing to avoid path errors
    find "$DIR_MEDIA_COMPLETED_MOVIES" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Find MKVs: Ignore files already containing a year in parentheses to prevent re-processing
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -maxdepth 1 -type f -iname "*.mkv" ! -regex ".*([0-9][0-9][0-9][0-9]).*" -print0 | while IFS= read -r -d $'\0' file; do        
        
        ORIGINAL_FILENAME=$(basename "$file")
        FILE_NAME_BASE="${ORIGINAL_FILENAME%.*}"
        
        # Stability Check
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        log "🎬 Processing: $ORIGINAL_FILENAME"

        # Step A: Sonos Audio Fix
        sonos_audio_fix "$file"

        # Step B: Identify tracks and apply UID-based English fix
        metadata=$(mkvmerge --identify "$file" --identification-format json)
        read -r audio_id audio_uid audio_lang <<< $(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and (.properties.language=="eng" or .properties.language=="und" or .properties.language==null)) | "\(.id) \(.properties.uid) \(.properties.language)"' | head -n 1)

        # Apply Language Fix if needed
        if [ -n "$audio_id" ] && ([ "$audio_lang" == "und" ] || [ "$audio_lang" == "null" ]); then
             mkvpropedit "$file" --edit "track:=$audio_uid" --set language=eng --set language-ietf=en >/dev/null 2>&1
             metadata=$(mkvmerge --identify "$file" --identification-format json)
        fi

        # Step C: Subtitle Logic
        forced_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id] | join(",")')
        if [ -n "$forced_ids" ]; then
            primary_forced=$(echo "$forced_ids" | cut -d',' -f1)
            mkvextract tracks "$file" "$primary_forced:$DIR_MEDIA_SUBTITLES/${FILE_NAME_BASE}.srt" >/dev/null 2>&1
            TRACK_OPTS="--video-tracks 0 --audio-tracks $audio_id --subtitle-tracks $forced_ids"
            NEEDS_PROPEDIT=true
        else
            TRACK_OPTS="--video-tracks 0 --audio-tracks $audio_id --no-subtitles"
            NEEDS_PROPEDIT=false
        fi

        # Step D: Naming Logic (Extract year for Radarr)
        year=$(echo "$ORIGINAL_FILENAME" | grep -oP '\d{4}' | head -n 1)
        clean_title=$(echo "$FILE_NAME_BASE" | sed -E "s/([0-9]{3,4}p|BluRay|BDRip|WEB-DL|x26[45]|LAMA|${year:-0000}).*//i" | tr '._' ' ' | xargs)
        final_title=$(echo "$clean_title" | sed -E 's/ [pP]$//g' | xargs)
        
        TARGET_FILENAME="${final_title} (${year}).mkv"
        TARGET_PATH="$DIR_MEDIA_COMPLETED_MOVIES/$TARGET_FILENAME"
        TEMP_FILE="${file}.processing.tmp"

        # Step E: Merge & Archive
        mv "$file" "$TEMP_FILE"
        if mkvmerge -q -o "$TARGET_PATH" $TRACK_OPTS "$TEMP_FILE"; then
            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$TARGET_PATH" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "✅ Processed: $TARGET_FILENAME"
            if mv "$TEMP_FILE" "$DIR_MEDIA_FINISHED/"; then
                manage_remote_torrent "delete" "$FILE_NAME_BASE"
                radarr_ingest "$DIR_MEDIA_COMPLETED_MOVIES"
            fi
        else
            log "❌ Merge failed. Resuming..."
            mv "$TEMP_FILE" "$file"
            manage_remote_torrent "resume" "$FILE_NAME_BASE"
        fi
    done

    sleep "$SLEEP_INTERVAL"
done
