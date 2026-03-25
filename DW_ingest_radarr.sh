#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

SLEEP_INTERVAL=120
mkdir -p "$DIR_MEDIA_COMPLETED_MOVIES" "$DIR_MEDIA_FINISHED" "$DIR_MEDIA_SUBTITLES"
check_dependencies "lsof" "mkvmerge" "jq" "mkvpropedit" "qbittorrent-cli" "rename"

log_start "$DIR_MEDIA_COMPLETED_MOVIES"

while true; do
    # 1. Clean up spaces in filenames (prevents many bash headaches)
    find "$DIR_MEDIA_COMPLETED_MOVIES" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Process MKVs
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -type f -iname "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do        
        filename=$(basename "$file")
        FILE_NAME="${filename%.*}"
        
        # Stability Check
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        log "🎬 Processing: $filename"

        # --- FIX: Move file to a temporary name immediately ---
        # This prevents the 'find' loop from seeing the same file twice
        working_file="${file}.processing.tmp"
        mv "$file" "$working_file"

        # --- Fix audio for Sonos ---
        sonos_audio_fix "$working_file"

        metadata=$(mkvmerge --identify "$working_file" --identification-format json)
        
        # 1. Identify Target Audio
        read -r audio_id audio_uid audio_lang <<< $(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and (.properties.language=="eng" or .properties.language=="und" or .properties.language==null)) | "\(.id) \(.properties.uid) \(.properties.language)"' | head -n 1)

        if [ -z "$audio_id" ]; then
            log "ℹ️ No English/Und audio found."
            eng_sub_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng") | .id] | join(",")')
            TRACK_OPTS=$([ -n "$eng_sub_ids" ] && echo "--subtitle-tracks $eng_sub_ids" || echo "--no-subtitles")
            NEEDS_PROPEDIT=false
        else
            # 2. Update Undefined
            if [ "$audio_lang" == "und" ] || [ "$audio_lang" == "null" ]; then
                log "Found Undefined audio (UID: $audio_uid). Forcing English..."
                mkvpropedit "$working_file" --edit "track:=$audio_uid" --set language=eng --set language-ietf=en --tags all: >/dev/null 2>&1
                metadata=$(mkvmerge --identify "$working_file" --identification-format json)
            fi

            # 3. Subtitle Logic
            forced_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id] | join(",")')
            if [ -n "$forced_ids" ]; then
                primary_forced=$(echo "$forced_ids" | cut -d',' -f1)
                mkvextract tracks "$working_file" "$primary_forced:$DIR_MEDIA_SUBTITLES/${FILE_NAME}.srt" >/dev/null 2>&1
                TRACK_OPTS="--subtitle-tracks $forced_ids"
                NEEDS_PROPEDIT=true
            else
                TRACK_OPTS="--no-subtitles"
                NEEDS_PROPEDIT=false
            fi
        fi

        # --- EXECUTE MERGE ---
        # Input: working_file, Output: Original location (where Radarr expects it)
        if mkvmerge -q -o "$file" $TRACK_OPTS "$working_file"; then
            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$file" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "✅ Merge Successful. Moving source to FINISHED."
            
            # --- THE CRITICAL FIX ---
            # Move the original (now temp) file to finished so it is GONE from source
            if mv "$working_file" "$DIR_MEDIA_FINISHED/"; then
                log "✨ Cleaning up QBT and Triggering Radarr..."
                manage_remote_torrent "delete" "$FILE_NAME"
                radarr_ingest
            fi
        else
            log "❌ Error: Merge failed. Moving to HOLD..."
            manage_remote_torrent "resume" "$FILE_NAME"
            mv "$working_file" "$DIR_MEDIA_HOLD/$filename"
        fi
    done
    sleep "$SLEEP_INTERVAL"
done
