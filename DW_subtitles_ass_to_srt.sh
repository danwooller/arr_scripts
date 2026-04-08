#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

cleanup() {
    log "⚠️ Interruption. Cleaning up..."
    find "${TARGET_PATHS[@]}" -type f -name "*_smart_tmp.mkv" -delete 2>/dev/null
    rm -f /tmp/dw_conv_*.srt 2>/dev/null
    exit 1
}
trap cleanup SIGINT SIGTERM

if [ -n "$1" ]; then
    TARGET_PATHS=("$1")
else
    TARGET_PATHS=("${DIR_TV[@]}" "${DIR_MOVIES[@]}")
fi

for CURRENT_DIR in "${TARGET_PATHS[@]}"; do
    if [ ! -d "$CURRENT_DIR" ]; then continue; fi

    find "$CURRENT_DIR" -type f -name "*.mkv" -print0 | while IFS= read -r -d '' file; do
        
        unset TRACK_OPTS
        unset NEEDS_PROPEDIT
        
        file_name=$(basename "$file")
        temp_file="${file%.*}_smart_tmp.mkv"
        temp_srt="/tmp/dw_conv_$(date +%s).srt"

        subtitle_opts "$file"

        # Identify chosen subtitle ID and its codec
        sub_id=$(echo "$TRACK_OPTS" | grep -oP '(?<=--subtitle-tracks )\d+')
        
        if [ -n "$sub_id" ]; then
            codec_type=$(ffprobe -v error -select_streams "$sub_id" -show_entries stream=codec_name -of csv=p=0 "$file")
            
            if [[ "$codec_type" =~ ^(ass|hdmv_pgs_subtitle|dvd_subtitle)$ ]]; then
                log "🔧 FIXING: $file_name ($codec_type -> SRT)"

                if ffmpeg -i "$file" -map 0:"$sub_id" "$temp_srt" -y < /dev/null >/dev/null 2>&1; then
                    CLEAN_OPTS=$(echo "$TRACK_OPTS" | sed -E 's/--subtitle-tracks [0-9,]+//; s/--no-subtitles//')
                    
                    if mkvmerge -o "$temp_file" $CLEAN_OPTS --no-subtitles "$file" "$temp_srt" < /dev/null >/dev/null 2>&1; then
                        mv "$file" "$DIR_MEDIA_HOLD/${file_name}.original"
                        mv "$temp_file" "${file%.*}.mkv"
                        log "✨ SUCCESS: $file_name converted to SRT."
                        mkvpropedit "${file%.*}.mkv" --edit track:s1 --set language=eng --set name="Forced" --set flag-forced=1 --set flag-default=1 < /dev/null >/dev/null 2>&1
                    fi
                fi
                rm -f "$temp_srt"
            else
                # If it's already SRT but needs remuxing to apply our track selection
                log "✅ KEEPING: $file_name already has SRT or compliant sub."
                # [Optional: You could add a remux block here if you want to strip extra tracks even if no conversion is needed]
            fi
        fi
    done

    # Plex Library Updates
    case "$CURRENT_DIR" in
        *"/TV"*|*"TV"*)
            plex_library_update "$PLEX_TV_SRC" "$PLEX_TV_NAME"
            ;;
        *"/4kTV"*|*"4kTV"*)
            plex_library_update "$PLEX_4KTV_SRC" "$PLEX_4KTV_NAME"
            ;;
        *"/Movies"*|*"Movies"*)
            plex_library_update "$PLEX_MOVIES_SRC" "$PLEX_MOVIES_NAME"
            ;;
        *"/4kMovies"*|*"4kMovies"*)
            plex_library_update "$PLEX_4KMOVIES_SRC" "$PLEX_4KMOVIES_NAME"
            ;;
        *)
            log "⚠️ Directory $CURRENT_DIR finished, but no Plex library match found."
            ;;
    esac
    log "✅ Completed scan for $CURRENT_DIR"
done
