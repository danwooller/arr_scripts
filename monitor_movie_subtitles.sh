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

# Fixed: Added $ to SUBTITLE_DIR
mkdir -p "$DEST_DIR" "$FINISHED_DIR" "$SUBTITLE_DIR"

# --- Dependencies ---
check_dependencies "lsof" "mkvmerge" "jq" "mkvpropedit" "rename"

log "Monitoring $SOURCE_DIR for MKV (process) every ${SLEEP_INTERVAL}s"

while true; do
    # 1. Standardize filenames (replaces spaces with underscores)
    find "$SOURCE_DIR" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Process Files
    find -L "$SOURCE_DIR" -type f -iname "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do        
        filename=$(basename "$file")
        
        # Skip if file is in use
        if lsof "$file" &> /dev/null; then
            log "Skipping $filename: File is currently in use."
            continue
        fi

        log "Processing MKV: $filename"
        metadata=$(mkvmerge --identify "$file" --identification-format json)
        
        # Check for English Audio
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
            # Capture all English forced subtitle IDs
            forced_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id] | join(",")')

            if [ -n "$forced_ids" ]; then
                # Extraction for backup (takes the first forced ID found)
                primary_forced=$(echo "$forced_ids" | cut -d',' -f1)
                BASE_NAME="${filename%.*}"
                SUB_FILE="$SUBTITLE_DIR/$BASE_NAME.srt"
                
                mkvextract tracks "$file" "$primary_forced:$SUB_FILE" >/dev/null 2>&1
                log " -> Forced subtitles extracted to backup: $BASE_NAME.srt"
                
                mkvmerge -q -o "$DEST_DIR/$filename" --subtitle-tracks "$forced_ids" "$file"
                # Only edit metadata if a track was actually merged
                mkvpropedit "$DEST_DIR/$filename" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            else
                log " -> No forced subs found. Stripping all subtitles."
                mkvmerge -q -o "$DEST_DIR/$filename" --no-subtitles "$file"
            fi
        fi

        # 3. Finalization
        if [ $? -eq 0 ] && [ -f "$DEST_DIR/$filename" ]; then
            log "Success! Moving original to finished."
            mv "$file" "$FINISHED_DIR/"
        else
            log "❌ Error: Processing failed for $filename."
        fi
    done

    # 4. Cleanup empty sub-folders
    find "$SOURCE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null

    sleep "$SLEEP_INTERVAL"
done
