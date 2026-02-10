#!/bin/bash

# --- Configuration ---
HOST=$(hostname -s)
SOURCE_DIR="/mnt/media/torrent/completed-movies"
DEST_DIR="/mnt/media/torrent/completed"
FINISHED_DIR="/mnt/media/torrent/finished"
LOG_FILE="/mnt/media/torrent/${HOST}.log"

# Ensure directories exist
mkdir -p "$DEST_DIR" "$FINISHED_DIR"

# --- Logging Function ---
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# --- Dependency Check & Auto-Installer ---
check_and_install_dependencies() {
    local dependencies=("mkvmerge" "mkvpropedit" "jq" "lsof")
    local missing_deps=()

    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            if [[ "$cmd" == "mkvmerge" || "$cmd" == "mkvpropedit" ]]; then
                missing_deps+=("mkvtoolnix")
            else
                missing_deps+=("$cmd")
            fi
        fi
    done

    # Deduplicate
    missing_deps=($(echo "${missing_deps[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "Missing dependencies detected: ${missing_deps[*]}"
        if [ "$EUID" -ne 0 ]; then
            log "Error: Script must be run with sudo to install missing dependencies."
            exit 1
        fi
        log "Attempting to install missing packages..."
        apt-get update -qq && apt-get install -y "${missing_deps[@]}"
    fi
}

check_and_install_dependencies

log "Monitoring $SOURCE_DIR every 120 seconds..."

while true; do
    shopt -s nullglob
    for file in "$SOURCE_DIR"/*.mkv; do
        filename=$(basename "$file")

        if lsof "$file" &> /dev/null; then
            log "Skipping $filename: File is currently in use."
            continue
        fi

        log "Processing: $filename"
        metadata=$(mkvmerge --identify "$file" --identification-format json)
        has_eng_audio=$(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and .properties.language=="eng") | .id' | head -n 1)
        
        # Process logic
        if [ -z "$has_eng_audio" ]; then
            log "No English audio. Keeping ALL English subtitles."
            eng_sub_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng") | .id] | join(",")')
            
            if [ -n "$eng_sub_ids" ]; then
                mkvmerge -q -o "$DEST_DIR/$filename" --subtitle-tracks "$eng_sub_ids" "$file"
            else
                log "Warning: No English subs found. Stripping all."
                mkvmerge -q -o "$DEST_DIR/$filename" --no-subtitles "$file"
            fi
        else
            log "English audio detected. Filtering for Forced subtitles..."
            forced_id=$(echo "$metadata" | jq -r '.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id' | head -n 1)

            if [ -n "$forced_id" ]; then
                mkvmerge -q -o "$DEST_DIR/$filename" --subtitle-tracks "$forced_id" "$file"
                mkvpropedit "$DEST_DIR/$filename" --edit track:s1 --set name="Forced"
            else
                mkvmerge -q -o "$DEST_DIR/$filename" --no-subtitles "$file"
            fi
        fi

        # --- Move Original File After Success ---
        if [ $? -eq 0 ] && [ -f "$DEST_DIR/$filename" ]; then
            log "Success! Moving original to $FINISHED_DIR"
            mv "$file" "$FINISHED_DIR/"
        else
            log "Error: Processing failed for $filename. Original kept in source."
        fi
    done

    sleep 120
done
