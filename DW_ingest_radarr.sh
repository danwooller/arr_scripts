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
check_dependencies "lsof" "mkvmerge" "jq" "mkvpropedit" "qbittorrent-cli" "rename"

log_start "$DIR_MEDIA_COMPLETED_MOVIES"

while true; do
    # 1. Standardize spacing in source
    find "$DIR_MEDIA_COMPLETED_MOVIES" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Process MKVs
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -type f -iname "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do        
        filename=$(basename "$file")
        FILE_NAME="${filename%.*}"
        
        # Stability Check
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        log "🎬 Processing: $filename"

        # Step A: Hide from loop
        working_file="${file}.processing.tmp"
        mv "$file" "$working_file"

        # Step B: Robust Naming & Year Extraction
        release_year=$(echo "$filename" | grep -oP '\d{4}' | head -n 1)
        
        # Strip everything after resolution/source markers
        clean_title=$(echo "$FILE_NAME" | sed -E "s/([0-9]{3,4}p|BluRay|BDRip|WEB-DL|x26[45]|LAMA|${release_year:-0000}).*//i" | tr '._' ' ' | xargs)
        
        # KILL THE TRAILING 'p': Specifically removes a lone 'p' or 'P' at the end of the title
        clean_title=$(echo "$clean_title" | sed -E 's/ [pP]$//g' | xargs)
        
        if [ -n "$release_year" ]; then
            final_name="$clean_title ($release_year).mkv"
        else
            final_name="$clean_title.mkv"
        fi
        target_output="$DIR_MEDIA_COMPLETED_MOVIES/$final_name"

        # Step C: Sonos Fix (Modifies $working_file)
        sonos_audio_fix "$working_file"

        # Step D: Metadata & Track Selection
        metadata=$(mkvmerge --identify "$working_file" --identification-format json)
        
        # Identify English/Und Audio ID
        audio_id=$(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and (.properties.language=="eng" or .properties.language=="und" or .properties.language==null)) | .id' | head -n 1)
        
        # Identify Forced Subtitles
        forced_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id] | join(",")')
        
        # Build mkvmerge track options
        # We EXPLICITLY include video (0) and the selected audio to prevent 5KB empty files
        if [ -n "$forced_ids" ]; then
            primary_forced=$(echo "$forced_ids" | cut -d',' -f1)
            mkvextract tracks "$working_file" "$primary_forced:$DIR_MEDIA_SUBTITLES/${clean_title}.srt" >/dev/null 2>&1
            FINAL_TRACK_OPTS="--video-tracks 0 --audio-tracks $audio_id --subtitle-tracks $forced_ids"
            NEEDS_PROPEDIT=true
        else
            FINAL_TRACK_OPTS="--video-tracks 0 --audio-tracks $audio_id --no-subtitles"
            NEEDS_PROPEDIT=false
        fi

        # Step E: EXECUTE MERGE
        log "🔨 Merging into: $final_name"
        if mkvmerge -q -o "$target_output" $FINAL_TRACK_OPTS "$working_file"; then
            
            # --- SIZE VERIFICATION ---
            # If the output is less than 10MB, it's a failure (prevents 5KB ghost files)
            actual_size=$(stat -c%s "$target_output")
            if [ "$actual_size" -lt 10485760 ]; then
                log "❌ Error: Resulting file is way too small ($actual_size bytes). Aborting merge."
                rm "$target_output"
                mv "$working_file" "$DIR_MEDIA_HOLD/$filename"
                continue
            fi

            # Post-Merge Tagging
            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$target_output" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "✅ Merge Successful ($(du -sh "$target_output" | cut -f1))."

            # Step F: Move Original & Trigger Radarr
            if mv "$working_file" "$DIR_MEDIA_FINISHED/$filename"; then
                log "✨ Source archived. Cleaning up QBT..."
                manage_remote_torrent "delete" "$FILE_NAME"
                
                # Triggers both Import and the RenameMovie command
                radarr_ingest "$DIR_MEDIA_COMPLETED_MOVIES"
            else
                log "❌ Error: Could not move source to $DIR_MEDIA_FINISHED"
            fi
        else
            log "❌ Error: mkvmerge engine failed."
            mv "$working_file" "$DIR_MEDIA_HOLD/$filename"
        fi
    done

    sleep "$SLEEP_INTERVAL"
done
