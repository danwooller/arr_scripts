#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# --- Configuration ---
HOST=$(hostname -s)
SOURCE_DIR="/mnt/media/torrent/completed-movies"
DEST_DIR="/mnt/media/torrent/completed"
FINISHED_DIR="/mnt/media/torrent/finished"
SUBTITLE_DIR="/mnt/media/backup/subtitles"
SLEEP_INTERVAL=120

# Ensure directories exist
mkdir -p "$DEST_DIR" "$FINISHED_DIR" "$SUBTITLE_DIR"

# --- Dependencies ---
check_dependencies "lsof" "mkvmerge" "jq" "mkvpropedit" "rename"

log "Monitoring $SOURCE_DIR for MKV (process) every ${SLEEP_INTERVAL}s"

while true; do
    # 1. Standardize filenames recursively (spaces -> underscores)
    find "$SOURCE_DIR" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Search for MKV files
    find -L "$SOURCE_DIR" -type f -iname "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do        
        filename=$(basename "$file")
        
        # --- STABILITY & LOCK CHECK ---
        # Checks if file size is still changing or if a process has an active lock
        SIZE1=$(stat -c%s "$file")
        sleep 5
        SIZE2=$(stat -c%s "$file")
        
        if [ "$SIZE1" -ne "$SIZE2" ]; then
            log "Skipping $filename: File is still being written (size changing)."
            continue
        fi

        if lsof "$file" &> /dev/null; then
            log "Skipping $filename: File is currently locked by another process."
            continue
        fi

        log "Processing MKV: $filename"
        metadata=$(mkvmerge --identify "$file" --identification-format json)
        
        # Determine if English audio exists
        has_eng_audio=$(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and .properties.language=="eng") | .id' | head -n 1)
        
        # Prepare mkvmerge command arguments based on audio language
        if [ -z "$has_eng_audio" ]; then
            log "No English audio. Keeping English subs."
            eng_sub_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng") | .id] | join(",")')
            
            if [ -n "$eng_sub_ids" ]; then
                # Merge only English subs
                TRACK_OPTS="--subtitle-tracks $eng_sub_ids"
                NEEDS_PROPEDIT=false
            else
                # No English subs found, strip all
                TRACK_OPTS="--no-subtitles"
                NEEDS_PROPEDIT=false
            fi
        else
            log "English audio detected. Filtering for Forced subs..."
            # Capture all English forced subtitle IDs
            forced_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id] | join(",")')

            if [ -n "$forced_ids" ]; then
                primary_forced=$(echo "$forced_ids" | cut -d',' -f1)
                BASE_NAME="${filename%.*}"
                SUB_FILE="$SUBTITLE_DIR/$BASE_NAME.srt"
                
                # Export to backup
                mkvextract tracks "$file" "$primary_forced:$SUB_FILE" >/dev/null 2>&1
                log " -> Forced subs extracted: $BASE_NAME.srt"
                
                TRACK_OPTS="--subtitle-tracks $forced_ids"
                NEEDS_PROPEDIT=true
            else
                log " -> No forced subs found. Stripping all subtitles."
                TRACK_OPTS="--no-subtitles"
                NEEDS_PROPEDIT=false
            fi
        fi

        # --- EXECUTE MERGE ---
        # Capture stdout and stderr to CMD_OUTPUT
        CMD_OUTPUT=$(mkvmerge -q -o "$DEST_DIR/$filename" $TRACK_OPTS "$file" 2>&1)
        exit_code=$?

        # --- FINALIZATION ---
        # exit_code 0 = success, 1 = warning (file is usually fine)
        if [[ $exit_code -le 1 ]] && [[ -s "$DEST_DIR/$filename" ]]; then
            
            # Apply metadata tags if we kept a forced track
            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$DEST_DIR/$filename" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "Success! Moving original MKV to $FINISHED_DIR"
            mv "$file" "$FINISHED_DIR/"
        else
            log "❌ Error: Processing failed for $filename."
            log "   Reason: ${CMD_OUTPUT:-Unknown error (Exit Code: $exit_code)}"
            # Remove failed output to prevent a corrupted file from blocking the next run
            rm -f "$DEST_DIR/$filename"
        fi
    done

    # 3. Cleanup empty sub-folders
    find "$SOURCE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null

    sleep "$SLEEP_INTERVAL"
done
