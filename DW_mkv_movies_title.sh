#!/bin/bash

# A script to check and update the "Title" field in an MKV file
# and ensure the filename matches the containing folder.

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
    
    # 1. Determine the Desired Name (The Parent Folder Name)
    local folder_name=$(basename "$dir")

    # 2. RENAME LOGIC (Keep the year in the filename)
    if [[ "$name_no_ext" != "$folder_name" ]]; then
        local new_name="${folder_name}${MKV_EXTENSION}"
        local new_path="$dir/$new_name"
        
        log "ℹ️ RENAME: \"$base\" -> \"$new_name\""
        mv "$file" "$new_path"
        file="$new_path" 
        
        if declare -f radarr_targeted_scan > /dev/null; then
            radarr_targeted_scan "$folder_name"
        fi
    fi

    # 3. METADATA LOGIC (Strip the year for the internal title)
    # This creates a "clean" version of the folder name for the metadata tag
    # Example: "Solo Mio (2026)" becomes "Solo Mio"
    local clean_title=$(echo "$folder_name" | sed 's/ ([0-9]\{4\})$//')

    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Checking Metadata: $file"

    local current_title=$(mkvinfo "$file" 2>/dev/null | grep -m 1 "Title:" | sed 's/^.*Title: //; s/^ *//; s/ *$//')

    if [[ "$current_title" == "$clean_title" ]]; then
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Title metadata already matches \"$clean_title\". No action."
    else
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Updating Title Metadata to: \"$clean_title\""
        mkvpropedit "$file" --edit info --set "title=$clean_title"

        if [ $? -eq 0 ]; then
            log "✅ SUCCESS: Metadata updated to \"$clean_title\""
        else
            log "❌ ERROR: mkvpropedit failed."
            return 1
        fi
    fi
}

# --- Main Script Logic ---

# Use $1 as target directory, fallback to default if $1 is empty
TARGET_DIR="${1:-$DEFAULT_TARGET_DIR}"

# Ensure the directory exists
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "❌ Error: Target directory '$TARGET_DIR' does not exist."
    exit 1
fi

log_start "$TARGET_DIR"
files_to_process=()

[[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Searching recursively for *${MKV_EXTENSION} in $TARGET_DIR..."

# Use find -print0 for robust handling of spaces
while IFS= read -r -d $'\0' file; do
    files_to_process+=("$file")
done < <(find "$TARGET_DIR" -type f -name "*${MKV_EXTENSION}" -print0)

# Process the identified files
if [ ${#files_to_process[@]} -eq 0 ]; then
    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ No ${MKV_EXTENSION} files found in: $TARGET_DIR"
    exit 0
fi

[[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Found ${#files_to_process[@]} file(s) to check."

for mkv_file in "${files_to_process[@]}"; do
    process_mkv "$mkv_file"
done

[[ $LOG_LEVEL == "debug" ]] && log_end "$TARGET_DIR"
