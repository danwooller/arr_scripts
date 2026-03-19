#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

log "ℹ️ Starting FLAC monitor service..."

# Infinite loop for service persistence
while true; do
    mkdir -p "$DIR_MEDIA_HOLD"
    
    # Initialize associative array in the main shell
    declare -A UPDATED_FOLDERS

    # Use Process Substitution to avoid the subshell 'pipe' trap
    while read -r flac_file; do
        
        # Define directory for Lidarr mapping
        album_dir=$(dirname "$flac_file")
        rel_path="${flac_file#$DIR_MEDIA_MUSIC/}"
        rel_dir=$(dirname "$rel_path")
        mp3_file="${flac_file%.flac}.mp3"
        
        if [ -f "$mp3_file" ] && [ -f "$DIR_MEDIA_HOLD/$rel_path" ]; then
            continue
        fi

        [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ Converting $rel_path"
        
        ffmpeg -v error -i "$flac_file" -qscale:a 2 -n "$mp3_file" </dev/null
        
        if [ $? -eq 0 ]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "✅ Moving original to hold..."
            mkdir -p "$DIR_MEDIA_HOLD/$rel_dir"
            mv "$flac_file" "$DIR_MEDIA_HOLD/$rel_path"
            
            # This now persists because we aren't in a subshell pipe
            UPDATED_FOLDERS["$album_dir"]=1
        else
            log "⚠️ Error converting $flac_file. Skipping move."
        fi

    # The "< <(...)" syntax is the key here
    done < <(find "$DIR_MEDIA_MUSIC" -type f -name "*.flac")

    # Trigger Lidarr for each unique folder found
    if [ ${#UPDATED_FOLDERS[@]} -gt 0 ]; then
        for folder in "${!UPDATED_FOLDERS[@]}"; do
            lidarr_targeted_rename "$folder"
        done
    fi
    
    unset UPDATED_FOLDERS
    sleep "$CHECK_INTERVAL"
done
