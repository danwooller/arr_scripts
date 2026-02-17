#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# --- Configuration ---
SOURCE_DIR="/mnt/media/torrent/completed-movies"
DEST_DIR="/mnt/media/torrent/completed"
FINISHED_DIR="/mnt/media/torrent/finished"
SUBTITLE_DIR="/mnt/media/backup/subtitles"
SLEEP_INTERVAL=120

mkdir -p "$DEST_DIR" "$FINISHED_DIR" "$SUBTITLE_DIR"
check_dependencies "lsof" "mkvmerge" "jq" "mkvpropedit" "rename"

log "Monitoring $SOURCE_DIR..."

while true; do
    find "$SOURCE_DIR" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    find -L "$SOURCE_DIR" -type f -iname "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do        
        filename=$(basename "$file")
        
        # Stability Check
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ] || lsof "$file" &> /dev/null; then continue; fi

        log "Processing: $filename"
        metadata=$(mkvmerge --identify "$file" --identification-format json)
        
        # 1. Identify Target Audio using UID for absolute precision
        # We look for 'eng', 'und', or null language
        read -r audio_id audio_uid audio_lang <<< $(echo "$metadata" | jq -r '.tracks[] | select(.type=="audio" and (.properties.language=="eng" or .properties.language=="und" or .properties.language==null)) | "\(.id) \(.properties.uid) \(.properties.language)"' | head -n 1)

        if [ -z "$audio_id" ]; then
            log "No English/Und audio found."
            eng_sub_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng") | .id] | join(",")')
            TRACK_OPTS=$([ -n "$eng_sub_ids" ] && echo "--subtitle-tracks $eng_sub_ids" || echo "--no-subtitles")
            NEEDS_PROPEDIT=false
        else
            # 2. Update Undefined using the UID selector
            if [ "$audio_lang" == "und" ] || [ "$audio_lang" == "null" ]; then
                log "Found Undefined audio (UID: $audio_uid). Forcing English..."
                
                # 'track:=UID' is the most reliable selector in mkvpropedit
                # We also clear tags to prevent them from overriding the header
                mkvpropedit "$file" \
                    --edit "track:=$audio_uid" \
                    --set language=eng \
                    --set language-ietf=en \
                    --tags all: >/dev/null 2>&1
                
                # Refresh metadata
                metadata=$(mkvmerge --identify "$file" --identification-format json)
                verify=$(echo "$metadata" | jq -r ".tracks[] | select(.properties.uid==$audio_uid) | .properties.language")
                log "Verification: Track UID $audio_uid is now '$verify'"
            fi

            # 3. Subtitle Logic
            forced_ids=$(echo "$metadata" | jq -r '[.tracks[] | select(.type=="subtitles" and .properties.language=="eng" and .properties.forced_track==true) | .id] | join(",")')
            if [ -n "$forced_ids" ]; then
                primary_forced=$(echo "$forced_ids" | cut -d',' -f1)
                mkvextract tracks "$file" "$primary_forced:$SUBTITLE_DIR/${filename%.*}.srt" >/dev/null 2>&1
                TRACK_OPTS="--subtitle-tracks $forced_ids"
                NEEDS_PROPEDIT=true
            else
                TRACK_OPTS="--no-subtitles"
                NEEDS_PROPEDIT=false
            fi
        fi

        # Execute Merge
        if mkvmerge -q -o "$DEST_DIR/$filename" $TRACK_OPTS "$file"; then
            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$DEST_DIR/$filename" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi
            log "Success! Finalizing..."
            mv "$file" "$FINISHED_DIR/"
        else
            log "❌ Error: Merge failed."
            rm -f "$DEST_DIR/$filename"
        fi
    done
    sleep "$SLEEP_INTERVAL"
done
