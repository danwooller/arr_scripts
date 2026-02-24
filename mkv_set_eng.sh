#!/bin/bash

# --- Setup & Includes ---
source "/usr/local/bin/common_functions.sh"

# Configuration
SOURCE_DIR="${1:-/mnt/media/Movies}"
DRY_RUN=${DRY_RUN:-false}        # Defaults to false if not set/exported
LOG_LEVEL=${LOG_LEVEL:-"info"}   # Defaults to info if not set

# Enable recursive globbing
shopt -s globstar

# Ensure tools are present
check_dependencies "jq" "mkvpropedit" "mkvmerge"

# Initialize Counters
total_files=0
modified_files=0
audio_fixed=0
subs_fixed=0

log "STARTING SCAN: $SOURCE_DIR"
[[ "$DRY_RUN" == "true" ]] && log "MODE: DRY RUN (No changes will be saved)"

for file in "$SOURCE_DIR"/**/*.mkv; do
    [[ -e "$file" ]] || continue
    ((total_files++))

    filename=$(basename "$file")
    metadata=$(mkvmerge -J "$file")
    file_was_modified=false
    
    # 1. Process Audio Tracks
    audio_idx=0
    while read -r lang; do
        ((audio_idx++))
        if [[ "$lang" == "und" || "$lang" == "null" ]]; then
            ((audio_fixed++))
            file_was_modified=true
            [[ "$LOG_LEVEL" == "debug" ]] && log "FIXING: $filename -> Audio #$audio_idx ($lang -> eng)"
            
            if [[ "$DRY_RUN" == "false" ]]; then
                mkvpropedit "$file" --edit "track:a$audio_idx" --set language=eng >/dev/null
            fi
        fi
    done < <(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio") | .properties.language // "null"')

    # 2. Process Subtitle Tracks
    sub_idx=0
    while read -r sub_id; do
        ((sub_idx++))
        ((subs_fixed++))
        file_was_modified=true
        [[ "$LOG_LEVEL" == "debug" ]] && log "FIXING: $filename -> Subtitle #$sub_idx to eng"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            mkvpropedit "$file" --edit "track:s$sub_idx" --set language=eng >/dev/null
        fi
    done < <(echo "$metadata" | jq -r '.tracks[] | select(.type=="subtitles") | .id')

    if [[ "$file_was_modified" == "true" ]]; then
        ((modified_files++))
    else
        echo "Skipping: $filename (No changes needed)"
    fi
done

# --- Final Summary ---
summary_msg="SCAN COMPLETE. Files Processed: $total_files | Modified: $modified_files | Audio Tracks Fixed: $audio_fixed | Subtitles Fixed: $subs_fixed"
log "$summary_msg"

if [[ "$LOG_LEVEL" == "debug" ]]; then
    log "FINISHED SCAN."
fi
