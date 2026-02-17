#!/bin/bash

# A script to check and update the "Title" field in an MKV file
# using mkvinfo and mkvpropedit. The desired title is set to match
# the name of the immediate containing folder.

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# --- Configuration ---
# Set the MKV extension to check for
MKV_EXTENSION=".mkv"

# Set the default directory to scan if no files are provided as arguments
# This default is used if the user doesn't specify a directory or files.
DEFAULT_TARGET_DIR="/mnt/media/Movies"
#LOG_LEVEL="debug"

# --- Dependencies ---
check_dependencies "mkvtoolnix"

# --- Helper Function ---

# Function to process a single MKV file
process_mkv() {
    local file="$1"
    
    # 1. Check if the file exists and is a regular file
    if [[ ! -f "$file" ]]; then
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "Skipping: $file is not a regular file."
        fi
        return 1
    fi

    if [[ $LOG_LEVEL = "debug" ]]; then
        log "--- Processing: $file ---"
    fi

    # 2. Determine the desired title (the name of the containing folder)
    # We first get the path of the parent directory, then extract its base name.
    local file_dir=$(dirname "$file")
    local desired_title=$(basename "$file_dir")

    # 3. Read the current "Title" property from the MKV file
    # We use mkvinfo and grep, focusing on the global document title.
    # The 'sed' command strips everything before "Title: "
    local current_title=$(mkvinfo "$file" 2>/dev/null | grep -m 1 "Title:" | sed 's/^.*Title: //; s/^ *//; s/ *$//')

    # If the current_title is empty (meaning no title is set), use an empty string for comparison
    if [[ -z "$current_title" ]]; then
        current_title=""
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "Current Title: <None Set>"
        fi
    else
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "Current Title: \"$current_title\""
        fi
    fi

    if [[ $LOG_LEVEL = "debug" ]]; then
        log "Desired Title: \"$desired_title\""
    fi

    # 4. Compare and Update
    if [[ "$current_title" == "$desired_title" ]]; then
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "Status: Title already matches the folder name. No action required."
        fi
    else
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "Action: Updating \"$desired_title\""
        fi
        # Use mkvpropedit to set the segment title
        mkvpropedit "$file" --edit info --set "title=$desired_title"

        if [ $? -eq 0 ]; then
            #if [[ $LOG_LEVEL = "debug" ]]; then
                log "SUCCESS: Title updated to \"$desired_title\""
            #fi
        else
            #if [[ $LOG_LEVEL = "debug" ]]; then
                log "ERROR: Failed to update \"$desired_title\" using mkvpropedit."
            #fi
            return 1
        fi
    fi
}

# --- Main Script Logic ---

# Check dependencies
if ! command -v mkvpropedit &> /dev/null || ! command -v mkvinfo &> /dev/null; then
    if [[ $LOG_LEVEL = "debug" ]]; then
        log "Error: 'mkvpropedit' or 'mkvinfo' (part of mkvtoolnix) is not installed." >&2
        log "Please install mkvtoolnix to run this script." >&2
    fi
    exit 1
fi

# Determine files to process
files_to_process=()
TARGET_DIR="$DEFAULT_TARGET_DIR"

if [ "$#" -gt 0 ]; then
    # Check if the first argument is a directory
    if [[ -d "$1" ]]; then
        # If $1 is a directory, use it as the new TARGET_DIR for a recursive search
        TARGET_DIR="$1"
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "Directory provided as argument. Searching recursively for *.mkv in $TARGET_DIR..."
        fi
        # Use find -print0 for robust, recursive searching.
        while IFS= read -r -d $'\0' file; do
            files_to_process+=("$file")
        done < <(find "$TARGET_DIR" -type f -name "*${MKV_EXTENSION}" -print0)

    else
        # If arguments are provided but $1 is NOT a directory, assume arguments are specific files
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "Arguments provided are not a directory. Processing specific files..."
        fi
        files_to_process=("$@")
    fi
else
    # If no arguments are provided, process the default directory recursively
    if [[ $LOG_LEVEL = "debug" ]]; then
        log "No files specified. Searching recursively for *.mkv in $TARGET_DIR..."
    fi
    if [[ ! -d "$TARGET_DIR" ]]; then
        if [[ $LOG_LEVEL = "debug" ]]; then
            log "Error: Default target directory '$TARGET_DIR' does not exist or is not a directory." >&2
        fi
        exit 1
    fi
    
    # Use find -print0 for robust, recursive searching.
    while IFS= read -r -d $'\0' file; do
        files_to_process+=("$file")
    done < <(find "$TARGET_DIR" -type f -name "*${MKV_EXTENSION}" -print0)
fi


# Process the identified files
if [ ${#files_to_process[@]} -eq 0 ]; then
    if [[ $LOG_LEVEL = "debug" ]]; then
        log "No ${MKV_EXTENSION} files found to process in the specified location: $TARGET_DIR"
    fi
    exit 0
fi
if [[ $LOG_LEVEL = "debug" ]]; then
    log "Found ${#files_to_process[@]} file(s) to check."
fi
for mkv_file in "${files_to_process[@]}"; do
    process_mkv "$mkv_file"
done
if [[ $LOG_LEVEL = "debug" ]]; then
    log "Script finished."
fi
