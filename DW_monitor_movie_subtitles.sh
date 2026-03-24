#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Configuration ---
#SOURCE_DIR="/mnt/media/torrent/completed-movies"
#DEST_DIR="/mnt/media/torrent/completed"
#FINISHED_DIR="/mnt/media/torrent/finished"
#SUBTITLE_DIR="/mnt/media/backup/subtitles"
SLEEP_INTERVAL=120

mkdir -p "$DIR_MEDIA_COMPLETED" "$DIR_MEDIA_FINISHED" "$DIR_MEDIA_SUBTITLES"
check_dependencies "lsof" "mkvmerge" "jq" "mkvpropedit" "qbittorrent-cli" "rename"

log_start "$DIR_MEDIA_COMPLETED_MOVIES"

while true; do
    find "$DIR_MEDIA_COMPLETED_MOVIES" -depth -name "* *" -execdir rename 's/ /_/g' "{}" + 2>/dev/null

    find -L "$DIR_MEDIA_COMPLETED_MOVIES" -type f -iname "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do        
        filename=$(basename "$file")
        
        # Stability Check
        SIZE1=$(stat -c%s "$file"); sleep 5; SIZE2=$(stat -c%s "$file")
        if [ "$SIZE1" -ne "$SIZE2" ]; then continue; fi

        #manage_remote_torrent() {
        #    local action=$1
        #    local t_name=$2
        #    local found=false 
        #    for server in "${QBT_SERVERS[@]}"; do
        #        # We add the credentials directly to the command string
        #        if qbittorrent-cli torrent list --server "$server" --username "$QBT_USER" --password "$QBT_PASS" | grep -q "$t_name"; then
        #            log "Action [$action] on $server for: $t_name"
        #            qbittorrent-cli torrent "$action" --server "$server" --username "$QBT_USER" --password "$QBT_PASS" --name "$t_name" >/dev/null 2>&1
        #            found=true
        #            break
        #        fi
        #    done
        #}
        manage_remote_torrent "delete" $filename

        log "Processing: $filename"

        # --- Fix audio for Sonos ---
        sonos_audio_fix "$file"

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
                mkvextract tracks "$file" "$primary_forced:$DIR_MEDIA_SUBTITLES/${filename%.*}.srt" >/dev/null 2>&1
                TRACK_OPTS="--subtitle-tracks $forced_ids"
                NEEDS_PROPEDIT=true
            else
                TRACK_OPTS="--no-subtitles"
                NEEDS_PROPEDIT=false
            fi
        fi

        # Execute Merge
        if mkvmerge -q -o "$DIR_MEDIA_COMPLETED/$filename" $TRACK_OPTS "$file"; then
            if [ "$NEEDS_PROPEDIT" = true ]; then
                mkvpropedit "$DIR_MEDIA_COMPLETED/$filename" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
            fi
            FILE_NAME="${filename%.*}"
            log "✅ Finishing ${filename%.*}"
            if mv "$file" "$DIR_MEDIA_FINISHED/"; then
                log "✅ Processed and moved. Cleaning up QBT..."
                # 3. Search & Delete across all 5 servers
                #manage_remote_torrent "delete" "$torrent_name"
                manage_remote_torrent "delete" "$FILE_NAME"
            fi
        else
            log "❌ Error: Merge failed. Resuming torrent..."
            # 4. Search & Resume across all 5 servers
            #manage_remote_torrent "resume" "$torrent_name"
            manage_remote_torrent "resume" "$FILE_NAME"
        fi
    done
    sleep "$SLEEP_INTERVAL"
done

log_end "$DIR_MEDIA_COMPLETED_MOVIES"
