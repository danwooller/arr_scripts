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
    # 1. Standardize spacing in the source directory
    find "$DIR_MEDIA_COMPLETED_MOVIES" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Process all MKVs found in the source
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -type f -iname "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do        
        filename=$(basename "$file")
        FILE_NAME="${filename%.*}"
        
        # Stability Check (ensure the file isn't still being written)
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        log "🎬 Processing: $filename"

        # MOVE TO TEMP: Prevents the 'find' loop from re-processing this file
        working_file="${file}.processing.tmp"
        mv "$file" "$working_file"

        # --- Identify Metadata for Naming & Tracks ---
        metadata=$(mkvmerge --identify "$working_file" --identification-format json)
        
        # 1. Try to get Official Title/Year from metadata tags
        raw_title=$(echo "$FILE_NAME" | sed -E 's/([ ._-]?[0-9]{4})//g' | tr '._' ' ' | xargs)
        
        # 2. Extract the year: Look for any 4-digit sequence
        release_year=$(echo "$FILE_NAME" | grep -oP '\d{4}' | head -n 1)

        # 3. Final Construction
        # If we found a year, add it cleanly; if not, just use the title
        if [ -n "$release_year" ]; then
            final_name="$raw_title ($release_year).mkv"
        else
            final_name="$raw_title.mkv"
        fi

        target_output="$DIR_MEDIA_COMPLETED_MOVIES/$final_name"
        # --- (Your Sonos Audio & Subtitle Logic - Same as before) ---
        # Note: Ensure these functions/logic blocks use "$working_file" as input
        
        # ... [Audio Fix / Subtitle Logic Here] ...

        # --- EXECUTE MERGE ---
        if mkvmerge -q -o "$target_output" $TRACK_OPTS "$working_file"; then
            
            # 1. Metadata Polish on the NEW file
            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$target_output" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "✅ Merge successful: $(basename "$target_output")"
            
            # 2. THE FIX: Move the ORIGINAL (.tmp) file to FINISHED
            # We use the original $filename to keep the source name in history
            if mv "$working_file" "$DIR_MEDIA_FINISHED/$filename"; then
                log "✨ Original moved to FINISHED. Cleaning up QBT..."
                
                # 3. Delete from QBT using the clean filename
                manage_remote_torrent "delete" "$FILE_NAME"
                
                # 4. Trigger Radarr to find the NEW clean file
                radarr_ingest
            else
                log "⚠️ Warning: Could not move $working_file to FINISHED. Is the drive full?"
            fi
        else
            log "❌ Error: mkvmerge failed for $filename"
            # Restore the file so we can try again or move to HOLD
            mv "$working_file" "$DIR_MEDIA_HOLD/$filename"
            manage_remote_torrent "resume" "$FILE_NAME"
        fi
    done

    sleep "$SLEEP_INTERVAL"
done
