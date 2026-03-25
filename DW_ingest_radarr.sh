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
    # 1. Standardize spacing in source
    find "$DIR_MEDIA_COMPLETED_MOVIES" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Process MKVs
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -type f -iname "*.mkv" ! -name "*.processing.tmp" -print0 | while IFS= read -r -d $'\0' file; do        
        filename=$(basename "$file")
        FILE_NAME="${filename%.*}"
        
        # Stability Check
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        log "🎬 Processing: $filename"

        # Step A: Create a unique working file path
        working_file="${file}.processing.tmp"
        mv "$file" "$working_file"
        sync # Flush disk buffer

        # Step B: Robust Naming Logic (Title Only)
        release_year=$(echo "$filename" | grep -oP '\d{4}' | head -n 1)
        
        # Extract title, strip resolution/codec/year, and kill the trailing 'p'
        clean_title=$(echo "$FILE_NAME" | sed -E "s/([0-9]{3,4}p|BluRay|BDRip|WEB-DL|x26[45]|LAMA|${release_year:-0000}).*//i" | tr '._' ' ' | xargs)
        final_title=$(echo "$clean_title" | sed -E 's/ [pP]$//g' | xargs)
        
        # Result: "Austin Powers in Goldmember.mkv"
        target_output="$DIR_MEDIA_COMPLETED_MOVIES/${final_title}.mkv"

        # Step C: Sonos Fix (Modifies $working_file in place)
        sonos_audio_fix "$working_file"

        # Step D: Metadata & Track Selection
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
            
            # --- 10MB SAFETY CHECK ---
            actual_size=$(stat -c%s "$target_output")
            if [ "$actual_size" -lt 10485760 ]; then
                log "❌ Error: Merged file is tiny ($actual_size bytes). Aborting."
                rm -f "$target_output"
                mv "$working_file" "$DIR_MEDIA_HOLD/$filename"
                continue
            fi

            # Metadata Polish
            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$target_output" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "✅ Merge Successful. Moving original..."
            sync # Ensure merge is fully committed to disk

            # Step F: THE MOVE (The Archiving Step)
            # This moves the .tmp file to FINISHED and restores its original .mkv extension
            if mv -f "$working_file" "$DIR_MEDIA_FINISHED/$filename"; then
                log "✨ Original archived to FINISHED. Triggering Radarr..."
                
                # Cleanup QBT
                manage_remote_torrent "delete" "$FILE_NAME"
                
                # IMPORTANT: Radarr should only look at the CLEAN target name
                radarr_ingest "$DIR_MEDIA_COMPLETED_MOVIES"
            else
                log "❌ CRITICAL: Move failed. Check permissions on $DIR_MEDIA_FINISHED"
                # If move fails, we leave the .tmp file so it doesn't get double-processed
            fi
        else
            log "❌ Error: mkvmerge failed."
            mv "$working_file" "$DIR_MEDIA_HOLD/$filename"
        fi
    done

    sleep "$SLEEP_INTERVAL"
done
