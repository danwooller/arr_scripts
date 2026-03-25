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
    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -type f -iname "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do        
        filename=$(basename "$file")
        FILE_NAME="${filename%.*}"
        
        # Stability Check
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        log "🎬 Processing: $filename"

        # Renaming to .tmp prevents the loop from seeing this file twice
        working_file="${file}.processing.tmp"
        mv "$file" "$working_file"

        # --- Get Metadata for Naming ---
        metadata=$(mkvmerge --identify "$working_file" --identification-format json)
        
        # We try to get the 'Official' Title and Year from the file's existing tags
        # or we fallback to the current filename if tags are empty
        raw_title=$(echo "$metadata" | jq -r '.container.properties.title // empty')
        if [ -z "$raw_title" ]; then raw_title=$(echo "$FILE_NAME" | tr '.' ' '); fi
        
        # Clean the title for the filesystem
        clean_target_name="$(echo "$raw_title" | xargs).mkv"
        target_output="$DIR_MEDIA_COMPLETED_MOVIES/$clean_target_name"

        # ... (Insert your Audio/Subtitle logic here as before) ...

        # --- EXECUTE MERGE ---
        # Outputting to a 'cleaner' name helps Radarr's parser
        if mkvmerge -q -o "$target_output" $TRACK_OPTS "$working_file"; then
            log "✅ Merge successful: $clean_target_name"
            
            # Move the original messy file to finished
            if mv "$working_file" "$DIR_MEDIA_FINISHED/$filename"; then
                log "✨ Cleaning up QBT and Triggering Radarr..."
                manage_remote_torrent "delete" "$FILE_NAME"
                
                # This function now handles the Import AND the Rename
                radarr_ingest
            fi
        else
            log "❌ Error: Merge failed."
            mv "$working_file" "$DIR_MEDIA_HOLD/$filename"
        fi
    done
    sleep "$SLEEP_INTERVAL"
done
