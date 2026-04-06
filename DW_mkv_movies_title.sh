#!/bin/bash

# A script to sync MKV metadata to the Folder Name (with year)
# and rename the Filename to a "Clean" version (without year).

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Run Dependency Check ---
check_dependencies "mkvpropedit" "mkvinfo"

# --- Configuration ---
MKV_EXTENSION=".mkv"
DEFAULT_TARGET_DIR="/mnt/media/Movies"

# Function to process a single MKV file
process_mkv() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Skipping: $file is not a regular file."
        return 1
    fi

    local dir=$(dirname "$file")
    local base=$(basename "$file")
    local name_no_ext="${base%.*}"
    
    # 1. Determine the Names
    # Folder Name (with year): "Solo Mio (2026)"
    local folder_name=$(basename "$dir")
    # Clean Name (strip year): "Solo Mio"
    local clean_name=$(echo "$folder_name" | sed 's/ ([0-9]\{4\})$//')

    # 2. RENAME LOGIC (Strip year from filename)
    if [[ "$name_no_ext" != "$clean_name" ]]; then
        local new_name="${clean_name}${MKV_EXTENSION}"
        local new_path="$dir/$new_name"
        
        log "ℹ️ RENAME: \"$base\" -> \"$new_name\""
        mv "$file" "$new_path"
        file="$new_path" # Update variable for metadata step
        
        if declare -f radarr_targeted_scan > /dev/null; then
            radarr_targeted_scan "$clean_name"
        fi
    fi

    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Checking Metadata: $file"

    # 3. METADATA LOGIC (Use folder name WITH year)
    local current_title=$(mkvinfo "$file" 2>/dev/null | grep -m 1 "Title:" | sed 's/^.*Title: //; s/^ *//; s/ *$//')

    if [[ "$current_title" == "$folder_name" ]]; then
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Title metadata already matches \"$folder_name\". No action."
    else
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Updating Title Metadata to: \"$folder_name\""
        mkvpropedit "$file" --edit info --set "title=$folder_name"

        if [ $? -eq 0 ]; then
            log "✅ Metadata updated to \"$folder_name\""
        else
            log "❌ mkvpropedit failed."
            return 1
        fi
    fi
}

# --- Main Script Logic ---
TARGET_DIR="${1:-$DEFAULT_TARGET_DIR}"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "❌ Error: Target directory '$TARGET_DIR' does not exist."
    exit 1
fi

log_start "$TARGET_DIR"
files_to_process=()

while IFS= read -r -d $'\0' file; do
    files_to_process+=("$file")
done < <(find "$TARGET_DIR" -type f -name "*${MKV_EXTENSION}" -print0)

if [ ${#files_to_process[@]} -eq 0 ]; then
    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ No files found."
    exit 0
fi

for mkv_file in "${files_to_process[@]}"; do
    process_mkv "$mkv_file"
done

case "$TARGET_DIR" in
    *"/TV"*|*"TV"*)
        plex_library_update "$PLEX_TV_SRC" "$PLEX_TV_NAME"
        ;;
    *"/4kTV"*|*"4kTV"*)
        plex_library_update "$PLEX_4KTV_SRC" "$PLEX_4KTV_NAME"
        ;;
    *"/Movies"*|*"Movies"*)
        plex_library_update "$PLEX_MOVIES_SRC" "$PLEX_MOVIES_NAME"
        ;;
    *"/4kMovies"*|*"4kMovies"*)
        plex_library_update "$PLEX_4KMOVIES_SRC" "$PLEX_4KMOVIES_NAME"
        ;;
    *)
        log "❌ Directory $TARGET_DIR did not match any library."
        ;;
esac

[[ $LOG_LEVEL == "debug" ]] && log_end "$TARGET_DIR"
