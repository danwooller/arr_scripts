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
    # 1. Standardize spacing (Original Logic)
    find "$DIR_MEDIA_COMPLETED_MOVIES" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Find MKVs: Ignore .tmp and ignore "Title (Year)" files to prevent infinite loops
    #find -L "$DIR_MEDIA_COMPLETED_MOVIES" -maxdepth 1 -type f -iname "*.mkv" ! -name "*.tmp" ! -regex ".*([0-9][0-9][0-9][0-9]).*" -print0 | while IFS= read -r -d $'\0' file; do
    # 2. Find MKV, MP4, or TS: Ignore .tmp and ignore "Title (Year)" files
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.ts" \) ! -name "*.tmp" ! -regex ".*([0-9][0-9][0-9][0-9]).*" -print0 | while IFS= read -r -d $'\0' file; do
        
        ORIGINAL_FILENAME=$(basename "$file")
        FILE_NAME_BASE="${ORIGINAL_FILENAME%.*}"
        
        # Stability Check (Ensure qBit is done writing)
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        log "🎬 Processing: $ORIGINAL_FILENAME"

        # --- Step A: Sonos Fix & Audio ID Selection ---
        sonos_audio_fix "$file"
        metadata=$(mkvmerge --identify "$file" --identification-format json)
        
        # Identify Target Audio using your UID logic for precision
        read -r audio_id audio_uid audio_lang <<< $(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and (.properties.language=="eng" or .properties.language=="und" or .properties.language==null)) | "\(.id) \(.properties.uid) \(.properties.language)"' | head -n 1)

        if [ -n "$audio_id" ] && [[ "$audio_lang" == "und" || "$audio_lang" == "null" ]]; then
            log "Found Undefined audio (UID: $audio_uid). Forcing English..."
            mkvpropedit "$file" --edit "track:=$audio_uid" --set language=eng --set language-ietf=en --tags all: >/dev/null 2>&1
            metadata=$(mkvmerge --identify "$file" --identification-format json)
        fi

        # --- Step B: Subtitle Logic ---
        # Reset flag for each file
        NEEDS_PROPEDIT=false
        forced_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id] | join(",")')
        
        if [ -n "$forced_ids" ]; then
            primary_forced=$(echo "$forced_ids" | cut -d',' -f1)
            # Extract to backup dir
            mkvextract tracks "$file" "$primary_forced:$DIR_MEDIA_SUBTITLES/${FILE_NAME_BASE}.srt" >/dev/null 2>&1
            TRACK_OPTS="--video-tracks 0 --audio-tracks $audio_id --subtitle-tracks $forced_ids"
            NEEDS_PROPEDIT=true
        else
            TRACK_OPTS="--video-tracks 0 --audio-tracks $audio_id --no-subtitles"
        fi

        # --- Step C: Naming & Duplicate Protection ---
        year=$(echo "$ORIGINAL_FILENAME" | grep -oP '\d{4}' | head -n 1)
        clean_title=$(echo "$FILE_NAME_BASE" | sed -E "s/([0-9]{3,4}p|BluRay|BDRip|WEB-DL|x26[45]|LAMA|${year:-0000}).*//i" | tr '._' ' ' | xargs)
        final_title=$(echo "$clean_title" | sed -E 's/ [pP]$//g' | xargs)
        
        TARGET_FILENAME="${final_title} (${year}).mkv"
        TARGET_PATH="$DIR_MEDIA_COMPLETED_MOVIES/$TARGET_FILENAME"

        if [ -f "$TARGET_PATH" ]; then
            log "⚠️ $TARGET_FILENAME already exists. Skipping."
            continue
        fi

        # --- Step D: Execute Remux ---
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
