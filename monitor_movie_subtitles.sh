#!/bin/bash

# --- Configuration ---
HOST=$(hostname -s)
SOURCE_DIR="/mnt/media/torrent/completed-movies"
DEST_DIR="/mnt/media/torrent/completed"
FINISHED_DIR="/mnt/media/torrent/finished"
CONVERT_MKV_DIR="/mnt/media/torrent/srt/convertmkv"
LOG_FILE="/mnt/media/torrent/${HOST}.log"
SLEEP_INTERVAL=120

# Ensure directories exist
mkdir -p "$DEST_DIR" "$FINISHED_DIR" "$CONVERT_MKV_DIR"

# --- Logging Function ---
log() {
    echo "$(date +'%H:%M'): $1" | tee -a "$LOG_FILE"
}

# --- Dependency Check ---
check_and_install_dependencies() {
    local dependencies=("mkvmerge" "mkvpropedit" "jq" "lsof")
    local missing_deps=()
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "Missing dependencies detected. Please install mkvtoolnix, jq, and lsof."
        # Auto-install logic omitted for brevity, but stays in your local version
    fi
}

check_and_install_dependencies

log "Monitoring $SOURCE_DIR for MKV (process) and MP4 (move) every $SLEEP_INTERVALs..."

while true; do
    # Search for both mkv and mp4 recursively
    find -L "$SOURCE_DIR" -type f \( -iname "*.mkv" -o -iname "*.mp4" \) -print0 | while IFS= read -r -d $'\0' file; do
        
        filename=$(basename "$file")
        extension="${file##*.}"

        # Skip if file is in use
        if lsof "$file" &> /dev/null; then
            log "Skipping $filename: File is currently in use."
            continue
        fi

        # --- BRANCH 1: MP4 Files (Direct Move) ---
        if [[ "${extension,,}" == "mp4" ]]; then
            log "MP4 Detected: Moving $filename to convertmkv folder."
            if mv "$file" "$CONVERT_MKV_DIR/"; then
                log "Success: Moved $filename"
            else
                log "Error: Failed to move $filename"
            fi
            continue # Move to next file
        fi

        # --- BRANCH 2: MKV Files (Process Metadata) ---
        log "Processing MKV: $filename"
        metadata=$(mkvmerge --identify "$file" --identification-format json)
        has_eng_audio=$(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and .properties.language=="eng") | .id' | head -n 1)
        
        if [ -z "$has_eng_audio" ]; then
            log "No English audio. Keeping English subs."
            eng_sub_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng") | .id] | join(",")')
            
            if [ -n "$eng_sub_ids" ]; then
                mkvmerge -q -o "$DEST_DIR/$filename" --subtitle-tracks "$eng_sub_ids" "$file"
            else
                mkvmerge -q -o "$DEST_DIR/$filename" --no-subtitles "$file"
            fi
        else
            log "English audio detected. Filtering for Forced subs..."
            forced_id=$(echo "$metadata" | jq -r '.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id' | head -n 1)

            if [ -n "$forced_id" ]; then
                mkvmerge -q -o "$DEST_DIR/$filename" --subtitle-tracks "$forced_id" "$file"
                mkvpropedit "$DEST_DIR/$filename" --edit track:s1 --set name="Forced"
            else
                mkvmerge -q -o "$DEST_DIR/$filename" --no-subtitles "$file"
            fi
        fi

        # Move original MKV to finished after processing
        if [ $? -eq 0 ] && [ -f "$DEST_DIR/$filename" ]; then
            log "Success! Moving original MKV to $FINISHED_DIR"
            mv "$file" "$FINISHED_DIR/"
        else
            log "Error: Processing failed for $filename."
        fi
    done

    # Cleanup empty sub-folders
    find "$SOURCE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null

    sleep "$SLEEP_INTERVAL"
done
