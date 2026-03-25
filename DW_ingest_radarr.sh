#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
fi

# --- Configuration ---
SLEEP_INTERVAL=120
mkdir -p "$DIR_MEDIA_COMPLETED_MOVIES" "$DIR_MEDIA_FINISHED" "$DIR_MEDIA_SUBTITLES"

log_start "$DIR_MEDIA_COMPLETED_MOVIES"

while true; do
    # 1. Standardize spacing (Original Logic)
    find "$DIR_MEDIA_COMPLETED_MOVIES" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Find MKVs: Ignore .tmp AND ignore files already in "Title (Year)" format
    # This REGEX is the key to preventing the infinite loop.
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -maxdepth 1 -type f -iname "*.mkv" ! -name "*.tmp" ! -regex ".*([0-9][0-9][0-9][0-9]).*" -print0 | while IFS= read -r -d $'\0' file; do        
        
        ORIGINAL_FILENAME=$(basename "$file")
        FILE_NAME_BASE="${ORIGINAL_FILENAME%.*}"
        
        # Stability Check
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        log "🎬 Processing: $ORIGINAL_FILENAME"

        # Step A: Sonos Fix (Original UID Logic)
        sonos_audio_fix "$file"
        metadata=$(mkvmerge --identify "$file" --identification-format json)
        
        # Extract Audio Data using your UID selector
        read -r audio_id audio_uid audio_lang <<< $(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and (.properties.language=="eng" or .properties.language=="und" or .properties.language==null)) | "\(.id) \(.properties.uid) \(.properties.language)"' | head -n 1)

        if [ -z "$audio_id" ]; then
            log "ℹ️ No English/Und audio found."
            eng_sub_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng") | .id] | join(",")')
            TRACK_OPTS=$([ -n "$eng_sub_ids" ] && echo "--subtitle-tracks $eng_sub_ids" || echo "--no-subtitles")
            NEEDS_PROPEDIT=false
        else
            # Force Undefined to English via UID (Your mkvpropedit fix)
            if [ "$audio_lang" == "und" ] || [ "$audio_lang" == "null" ]; then
                mkvpropedit "$file" --edit "track:=$audio_uid" --set language=eng --set language-ietf=en --tags all: >/dev/null 2>&1
                metadata=$(mkvmerge --identify "$file" --identification-format json)
            fi

            # Subtitle Logic
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
        fi

        # Step B: Naming Logic for TARGET (Keep Year!)
        year=$(echo "$ORIGINAL_FILENAME" | grep -oP '\d{4}' | head -n 1)
        clean_title=$(echo "$FILE_NAME_BASE" | sed -E "s/([0-9]{3,4}p|BluRay|BDRip|WEB-DL|x26[45]|LAMA|${year:-0000}).*//i" | tr '._' ' ' | xargs)
        final_title=$(echo "$clean_title" | sed -E 's/ [pP]$//g' | xargs)
        
        # This name triggers your Step 2 (.movie != null) in radarr_ingest
        TARGET_FILENAME="${final_title} (${year}).mkv"
        TARGET_PATH="$DIR_MEDIA_COMPLETED_MOVIES/$TARGET_FILENAME"
        TEMP_FILE="${file}.processing.tmp"

        # Step C: Execute Merge
        mv "$file" "$TEMP_FILE"
        if mkvmerge -q -o "$TARGET_PATH" $TRACK_OPTS "$TEMP_FILE"; then
            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$TARGET_PATH" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "✅ Finishing: $TARGET_FILENAME"
            # Step D: Move original to Finished and trigger your ingest
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
