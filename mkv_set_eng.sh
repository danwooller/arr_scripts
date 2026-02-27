#!/bin/bash

# --- Setup & Includes ---
source "/usr/local/bin/common_functions.sh"

# Configuration
TARGET_DIR="${1:-/mnt/media/Movies}"
DRY_RUN=${DRY_RUN:-false}        # Defaults to false if not set/exported
#LOG_LEVEL="debug"

# Reset the internal timer
SECONDS=0

# Enable recursive globbing
shopt -s globstar

# Ensure tools are present
check_dependencies "jq" "mkvtoolnix"

# Initialize Counters
total_files=0
modified_files=0
audio_fixed=0
subs_fixed=0

log_start "$TARGET_DIR"

[[ "$DRY_RUN" == "true" ]] && log "MODE: DRY RUN (No changes will be saved)"

for file in "$TARGET_DIR"/**/*.mkv; do
    [[ -e "$file" ]] || continue
    ((total_files++))

    filename=$(basename "$file")
    metadata=$(mkvmerge -J "$file")
    
    this_file_audio=0
    this_file_subs=0
    
    # 1. Check Audio Tracks
    audio_idx=0
    while read -r lang; do
        ((audio_idx++))
        if [[ "$lang" == "und" || "$lang" == "null" ]]; then
            ((this_file_audio++))
            [[ "$LOG_LEVEL" == "debug" ]] && log "DEBUG: $filename -> Audio #$audio_idx is '$lang'"
            
            if [[ "$DRY_RUN" != "true" ]]; then
                mkvpropedit "$file" --edit "track:a$audio_idx" --set language=eng >/dev/null
            fi
        fi
    done < <(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio") | .properties.language // "null"')

    # 2. Check Subtitle Tracks
    sub_idx=0
    while read -r sub_id; do
        ((sub_idx++))
        ((this_file_subs++))
        [[ "$LOG_LEVEL" == "debug" ]] && log "DEBUG: $filename -> Subtitle #$sub_idx needs eng"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            mkvpropedit "$file" --edit "track:s$sub_idx" --set language=eng >/dev/null
        fi
    done < <(echo "$metadata" | jq -r '.tracks[] | select(.type=="subtitles") | .id')

    # Update global counters
    if (( this_file_audio > 0 || this_file_subs > 0 )); then
        ((modified_files++))
        ((audio_fixed += this_file_audio))
        ((subs_fixed += this_file_subs))
        log "MODIFIED: $filename (Audio: $this_file_audio, Subs: $this_file_subs)"
    fi
done

# Calculate time elapsed
duration=$SECONDS
minutes=$((duration / 60))
seconds=$((duration % 60))

# --- Final Summary ---
summary_msg="SCAN COMPLETE. Files: $total_files | Modified: $modified_files | Audio Fixed: $audio_fixed | Subs Fixed: $subs_fixed | Time: ${minutes}m ${seconds}s"
log "$summary_msg"
