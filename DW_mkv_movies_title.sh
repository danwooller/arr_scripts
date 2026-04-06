#!/bin/bash

# A script to check and update the "Title" field in an MKV file
# using mkvinfo and mkvpropedit. The desired title is set to match
# the name of the immediate containing folder.

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Run Dependency Check ---
check_dependencies "mkvpropedit"

# --- Configuration ---
MKV_EXTENSION=".mkv"
DEFAULT_TARGET_DIR="/mnt/media/Movies"
#LOG_LEVEL="debug"

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
    
    if [[ "$name_no_ext" =~ \ \([0-9]{4}\)$ ]]; then
        local new_name="${name_no_ext% (*)}$MKV_EXTENSION"
        local new_path="$dir/$new_name"
        
        if [[ "$file" != "$new_path" ]]; then
            log "ℹ️ RENAME: \"$base\" -> \"$new_name\""
            mv "$file" "$new_path"
            file="$new_path" 
            radarr_targeted_scan "$name_no_ext"
        fi
    fi

    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Processing: $file"

    local file_dir=$(dirname "$file")
    local desired_title=$(basename "$file_dir")

    local current_title=$(mkvinfo "$file" 2>/dev/null | grep -m 1 "Title:" | sed 's/^.*Title: //; s/^ *//; s/ *$//')

    if [[ -z "$current_title" ]]; then
        current_title=""
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Current Title: <None Set>"
    else
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Current Title: \"$current_title\""
    fi

    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Desired Title: \"$desired_title\""

    if [[ "$current_title" == "$desired_title" ]]; then
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Title already matches the folder name. No action required."
    else
        [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Updating \"$desired_title\""
        mkvpropedit "$file" --edit info --set "title=$desired_title"

        if [ $? -eq 0 ]; then
            log "✅ SUCCESS: Title updated to \"$desired_title\""
        else
            log "❌ ERROR: Failed to update \"$desired_title\" using mkvpropedit."
            return 1
        fi
    fi
}

# --- Main Script Logic ---

# 1. Determine the Target Directory
# Use $1 if provided; otherwise, use the default.
TARGET_DIR="${1:-$DEFAULT_TARGET_DIR}"

# 2. Validate Directory Existence
if [[ ! -d "$TARGET_DIR" ]]; then
    log "❌ Error: Target directory '$TARGET_DIR' does not exist."
    exit 1
fi

files_to_process=()
log_start "$TARGET_DIR"

# 3. Collect files
[[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Searching recursively for *${MKV_EXTENSION} in $TARGET_DIR..."

# Use find -print0 for robust handling of spaces in filenames
while IFS= read -r -d $'\0' file; do
    files_to_process+=("$file")
done < <(find "$TARGET_DIR" -type f -name "*${MKV_EXTENSION}" -print0)

# 4. Process the identified files
if [ ${#files_to_process[@]} -eq 0 ]; then
    [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ No ${MKV_EXTENSION} files found in: $TARGET_DIR"
    exit 0
fi

[[ $LOG_LEVEL == "debug" ]] && log "ℹ️ Found ${#files_to_process[@]} file(s) to check."

for mkv_file in "${files_to_process[@]}"; do
    process_mkv "$mkv_file"
done

[[ $LOG_LEVEL == "debug" ]] && log_end "$TARGET_DIR"
