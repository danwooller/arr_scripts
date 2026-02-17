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
    # 1. Standardize filenames recursively
    find "$SOURCE_DIR" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    # 2. Search for MKV files
    find -L "$SOURCE_DIR" -type f -iname "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do        
        filename=$(basename "$file")
        
        # --- STABILITY & LOCK CHECK ---
        SIZE1=$(stat -c%s "$file")
        sleep 5
        SIZE2=$(stat -c%s "$file")
        
        if [ "$SIZE1" -ne "$SIZE2" ]; then
            log "Skipping $filename: File is still being written."
            continue
        fi

        if lsof "$file" &> /dev/null; then
            log "Skipping $filename: File is currently locked."
            continue
        fi

        log "Processing MKV: $filename"
        metadata=$(mkvmerge --identify "$file" --identification-format json)
        
        # --- NEW LOGIC: Check for English OR Undefined audio ---
        # Get the ID of the first track that is 'eng' or 'und'
        target_audio_id=$(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and (.properties.language=="eng" or .properties.language=="und")) | .id' | head -n 1)
        audio_lang=$(echo "$metadata" | jq -r ".tracks[] | select(.id==${target_audio_id:-999}) | .properties.language")

        # If it was undefined, let's fix the source metadata so the output is correct
        if [ "$audio_lang" == "und" ]; then
            log "Undefined audio found. Tagging track ID $target_audio_id as English..."
            mkvpropedit "$file" --edit "track:=$target_audio_id" --set language=eng >/dev/null 2>&1
            # Refresh metadata after change
            metadata=$(mkvmerge --identify "$file" --identification-format json)
        fi

        # Prepare mkvmerge command arguments
        # If target_audio_id is empty, it means no English/Undefined audio was found
        if [ -z "$target_audio_id" ]; then
            log "No English/Und audio. Keeping English subs."
            eng_sub_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng") | .id] | join(",")')
            
            if [ -n "$eng_sub_ids" ]; then
                TRACK_OPTS="--subtitle-tracks $eng_sub_ids"
                NEEDS_PROPEDIT=false
            else
                TRACK_OPTS="--no-subtitles"
                NEEDS_PROPEDIT=false
            fi
        else
            log "English/Und audio detected. Filtering for Forced subs..."
            forced_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id] | join(",")')

            if [ -n "$forced_ids" ]; then
                primary_forced=$(echo "$forced_ids" | cut -d',' -f1)
                BASE_NAME="${filename%.*}"
                SUB_FILE="$SUBTITLE_DIR/$BASE_NAME.srt"
                
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
        CMD_OUTPUT=$(mkvmerge -q -o "$DEST_DIR/$filename" $TRACK_OPTS "$file" 2>&1)
        exit_code=$?

        # --- FINALIZATION ---
        if [[ $exit_code -le 1 ]] && [[ -s "$DEST_DIR/$filename" ]]; then
            if [ "$NEEDS_PROPEDIT" = true ]; then
                # Ensure the kept subtitle track is named and flagged correctly
                mkvpropedit "$DEST_DIR/$filename" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi

            log "Success! Moving original MKV to $FINISHED_DIR"
            mv "$file" "$FINISHED_DIR/"
        else
            log "❌ Error: Processing failed for $filename."
            rm -f "$DEST_DIR/$filename"
        fi
    done

    find "$SOURCE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null
    sleep "$SLEEP_INTERVAL"
done
