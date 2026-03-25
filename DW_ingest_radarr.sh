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
mkdir -p "$DIR_MEDIA_COMPLETED_MOVIES" "$DIR_MEDIA_FINISHED" "$DIR_MEDIA_SUBTITLES" "$DIR_MEDIA_HOLD"
check_dependencies "lsof" "mkvmerge" "jq" "mkvpropedit" "rename"

log_start "$DIR_MEDIA_COMPLETED_MOVIES"

while true; do
    # 1. Process all MKVs (Ignoring existing .tmp files)
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -type f -iname "*.mkv" ! -name "*.tmp" -print0 | while IFS= read -r -d $'\0' file; do        
        
        # Stability Check
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        # Capture the EXACT name as it exists right now
        current_full_path="$file"
        current_filename=$(basename "$file")
        FILE_NAME_BASE="${current_filename%.*}"

        log "🎬 Processing: $current_filename"

        # Step A: Create the working .tmp file using the EXACT current path
        working_file="${current_full_path}.processing.tmp"
        if ! mv "$current_full_path" "$working_file"; then
            log "❌ Error: Could not rename $current_filename to .tmp"
            continue
        fi
        sync

        # Step B: Robust Naming Logic (Title Only)
        # We extract the year from the original filename
        release_year=$(echo "$current_filename" | grep -oP '\d{4}' | head -n 1)
        
        # Clean the title: Strip resolution, codec, group, and year
        clean_title=$(echo "$FILE_NAME_BASE" | sed -E "s/([0-9]{3,4}p|BluRay|BDRip|WEB-DL|x26[45]|LAMA|${release_year:-0000}).*//i" | tr '._' ' ' | xargs)
        final_title=$(echo "$clean_title" | sed -E 's/ [pP]$//g' | xargs)
        
        # Destination for the "Clean" file Radarr will take
        target_output="$DIR_MEDIA_COMPLETED_MOVIES/${final_title}.mkv"

        # Step C: Sonos Fix
        sonos_audio_fix "$working_file"

        # Step D: Track Selection
        metadata=$(mkvmerge --identify "$working_file" --identification-format json)
        audio_id=$(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and (.properties.language=="eng" or .properties.language=="und" or .properties.language==null)) | .id' | head -n 1)
        forced_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id] | join(",")')
        
        if [ -n "$forced_ids" ]; then
            primary_forced=$(echo "$forced_ids" | cut -d',' -f1)
            mkvextract tracks "$working_file" "$primary_forced:$DIR_MEDIA_SUBTITLES/${final_title}.srt" >/dev/null 2>&1
            FINAL_TRACK_OPTS="--video-tracks 0 --audio-tracks $audio_id --subtitle-tracks $forced_ids"
            NEEDS_PROPEDIT=true
        else
            FINAL_TRACK_OPTS="--video-tracks 0 --audio-tracks $audio_id --no-subtitles"
            NEEDS_PROPEDIT=false
        fi

        # Step E: EXECUTE MERGE
        log "🔨 Merging into: ${final_title}.mkv"
        if mkvmerge -q -o "$target_output" $FINAL_TRACK_OPTS "$working_file"; then
            
            # 10MB Safety Check
            actual_size=$(stat -c%s "$target_output")
            if [ "$actual_size" -lt 10485760 ]; then
                log "❌ Error: Resulting file is empty/tiny. Aborting."
                rm -f "$target_output"
                mv "$working_file" "$DIR_MEDIA_HOLD/$current_filename"
                continue
            fi

            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$target_output" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "✅ Merge Successful. Archiving original..."
            sync

            # Step F: THE MOVE (Using the exact working_file path)
            if mv -f "$working_file" "$DIR_MEDIA_FINISHED/$current_filename"; then
                log "✨ Original archived. Cleaning up QBT..."
                manage_remote_torrent "delete" "$FILE_NAME_BASE"
                radarr_ingest "$DIR_MEDIA_COMPLETED_MOVIES"
            else
                log "❌ CRITICAL: Move failed. Check permissions on $DIR_MEDIA_FINISHED"
            fi
        else
            log "❌ Error: mkvmerge failed."
            mv "$working_file" "$DIR_MEDIA_HOLD/$current_filename"
        fi
    done

    sleep "$SLEEP_INTERVAL"
done
