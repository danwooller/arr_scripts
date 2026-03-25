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
    # 1. Standardize spacing in the source directory to underscores
    find "$DIR_MEDIA_COMPLETED_MOVIES" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Process all MKVs
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -type f -iname "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do        
        filename=$(basename "$file")
        FILE_NAME="${filename%.*}"
        
        # Stability Check (Wait for file to finish writing/moving)
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        log "🎬 Processing: $filename"

        # Step A: Hide the file from the loop immediately
        working_file="${file}.processing.tmp"
        mv "$file" "$working_file"

        # Step B: Robust Naming Logic
        # Extract the year first
        release_year=$(echo "$filename" | grep -oP '\d{4}' | head -n 1)
        
        # Clean the title by stripping resolution, source, codec, and the year itself
        # This handles the "Austin Powers...p BluRay" issue by cutting everything after the title
        clean_title=$(echo "$FILE_NAME" | sed -E "s/([0-9]{3,4}p|BluRay|BDRip|WEB-DL|x26[45]|LAMA|${release_year:-0000}).*//i" | tr '._' ' ' | xargs)
        
        if [ -n "$release_year" ]; then
            final_name="$clean_title ($release_year).mkv"
        else
            final_name="$clean_title.mkv"
        fi
        
        target_output="$DIR_MEDIA_COMPLETED_MOVIES/$final_name"

        # Step C: Sonos Audio Fix (Modifies $working_file in place)
        sonos_audio_fix "$working_file"

        # Step D: Metadata Extraction for Subtitles
        metadata=$(mkvmerge --identify "$working_file" --identification-format json)
        
        # Identify Audio
        read -r audio_id audio_uid audio_lang <<< $(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and (.properties.language=="eng" or .properties.language=="und" or .properties.language==null)) | "\(.id) \(.properties.uid) \(.properties.language)"' | head -n 1)

        # Handle Subtitle Selection
        forced_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id] | join(",")')
        
        if [ -n "$forced_ids" ]; then
            primary_forced=$(echo "$forced_ids" | cut -d',' -f1)
            mkvextract tracks "$working_file" "$primary_forced:$DIR_MEDIA_SUBTITLES/${clean_title}.srt" >/dev/null 2>&1
            TRACK_OPTS="--subtitle-tracks $forced_ids"
            NEEDS_PROPEDIT=true
        else
            TRACK_OPTS="--no-subtitles"
            NEEDS_PROPEDIT=false
        fi

        # Step E: EXECUTE MERGE
        log "🔨 Merging into: $final_name"
        if mkvmerge -q -o "$target_output" $TRACK_OPTS "$working_file"; then
            
            # Post-Merge Tagging
            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$target_output" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "✅ Merge Successful."

            # Step F: Move Original to FINISHED and Trigger Radarr
            # Using $working_file (the .tmp) as the source for the move
            if mv "$working_file" "$DIR_MEDIA_FINISHED/$filename"; then
                log "✨ Source moved to FINISHED. Triggering Radarr..."
                manage_remote_torrent "delete" "$FILE_NAME"
                
                # Use the function from DW_common_functions.sh
                radarr_ingest "$DIR_MEDIA_COMPLETED_MOVIES"
            else
                log "❌ Error: Could not move source to $DIR_MEDIA_FINISHED"
            fi
        else
            log "❌ Error: mkvmerge failed. Restoring to HOLD..."
            mv "$working_file" "$DIR_MEDIA_HOLD/$filename"
            manage_remote_torrent "resume" "$FILE_NAME"
        fi
    done

    sleep "$SLEEP_INTERVAL"
done
