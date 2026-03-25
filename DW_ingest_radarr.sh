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
        official_title=$(echo "$metadata" | jq -r '.container.properties.title // empty')
        release_year=$(echo "$metadata" | jq -r '.container.properties.year // empty')

        # 2. Regex Fallback: If year is empty, pull 4 digits from the filename
        if [ -z "$release_year" ]; then
            release_year=$(echo "$filename" | grep -oP '\d{4}' | head -n 1)
        fi

        # 3. Title Fallback: If title is empty, use the filename minus the year and dots
        if [ -z "$official_title" ]; then
            # Strips the year, replaces dots/underscores with spaces
            official_title=$(echo "$FILE_NAME" | sed -E 's/\.?\(?[0-9]{4}\)?.*//' | tr '._' ' ' | xargs)
        fi

        # 4. Final Construction (with a safety check for the year)
        if [ -n "$release_year" ]; then
            final_name="$official_title ($release_year).mkv"
        else
            final_name="$official_title.mkv"
        fi

        target_output="$DIR_MEDIA_COMPLETED_MOVIES/$final_name"
        # --- (Your Sonos Audio & Subtitle Logic - Same as before) ---
        # Note: Ensure these functions/logic blocks use "$working_file" as input
        
        # ... [Audio Fix / Subtitle Logic Here] ...

        # --- EXECUTE MERGE ---
        if mkvmerge -q -o "$target_output" $TRACK_OPTS "$working_file"; then
            
            # Metadata Polish
            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$target_output" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "✅ Merge successful: $final_name"
            
            # Move the ORIGINAL source to finished (renamed for clarity)
            if mv "$working_file" "$DIR_MEDIA_FINISHED/$filename"; then
                log "✨ Cleaning up QBT and Triggering Radarr..."
                manage_remote_torrent "delete" "$FILE_NAME"
                
                # Calls the updated radarr_ingest that triggers 'RenameMovie'
                radarr_ingest
            fi
        else
            log "❌ Error: Merge failed. Moving to HOLD."
            manage_remote_torrent "resume" "$FILE_NAME"
            mv "$working_file" "$DIR_MEDIA_HOLD/$filename"
        fi
    done

    sleep "$SLEEP_INTERVAL"
done
