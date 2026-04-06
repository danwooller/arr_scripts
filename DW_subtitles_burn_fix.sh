#!/bin/bash

# --- Load Shared Functions & Subtitle Logic ---
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

# Logic: Manual vs Scheduled
if [ -n "$1" ]; then
    TARGET_PATHS=("${1}")
else
    TARGET_PATHS=("${DIR_TV[@]}" "${DIR_MOVIES[@]}")
fi

for CURRENT_DIR in "${TARGET_PATHS[@]}"; do
    if [ ! -d "$CURRENT_DIR" ]; then continue; fi

    find "$CURRENT_DIR" -type f -name "*.mkv" | while read -r file; do
        
        file_name=$(basename "$file")
        temp_file="${file%.*}_smart_tmp.mkv"
        temp_srt="/tmp/dw_conv_${file_name%.*}.srt"

        # 1. Run the shared logic (Populates $TRACK_OPTS and $NEEDS_PROPEDIT)
        subtitle_opts "$file"

        # 2. Check for problematic codecs to determine if we act
        problem_subs=$(ffprobe -v error -select_streams s -show_entries stream=codec_name -of csv=p=0 "$file" | grep -E "ass|hdmv_pgs_subtitle|dvd_subtitle")

        if [ -n "$problem_subs" ]; then
            log "🔧 FIXING: $file_name (Converting to SRT & Cleaning)"

            # --- INTERCEPT LOGIC: Convert ASS to SRT if it was selected ---
            # Extract the subtitle ID from the shared TRACK_OPTS
            sub_id=$(echo "$TRACK_OPTS" | grep -oP '(?<=--subtitle-tracks )\d+')

            if [ -n "$sub_id" ]; then
                # Convert the specific track to SRT via ffmpeg
                # mkvmerge IDs usually match ffmpeg stream indices for MKVs
                if ffmpeg -i "$file" -map 0:"$sub_id" "$temp_srt" -y >/dev/null 2>&1; then
                    # REWRITE TRACK_OPTS: Remove the internal ASS track and add the SRT file
                    # We use --no-subtitles to strip the original internal tracks
                    BASE_OPTS=$(echo "$TRACK_OPTS" | sed -E 's/--subtitle-tracks [0-9,]+//')
                    TRACK_OPTS="$BASE_OPTS --no-subtitles $temp_srt"
                fi
            fi

            # 3. Execute Remux
            if mkvmerge -o "$temp_file" $TRACK_OPTS "$file" >/dev/null 2>&1; then
                
                # 4. Swap and Backup
                mv "$file" "$DIR_MEDIA_HOLD/${file_name}.original"
                mv "$temp_file" "${file%.*}.mkv"
                
                log "✨ SUCCESS: $file_name now contains SRT. (Used: $TRACK_OPTS)"
                
                if [ "$NEEDS_PROPEDIT" = true ]; then
                    log "📝 Flagging SRT as Forced..."
                    mkvpropedit "${file%.*}.mkv" --edit track:s1 --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
                fi
                
                # Cleanup temp srt
                rm -f "$temp_srt"
            else
                log "❌ FAILED: mkvmerge failed for $file_name"
                [ -f "$temp_file" ] && rm "$temp_file"
                rm -f "$temp_srt"
            fi
        else
            [[ "$LOG_LEVEL" == "debug" ]] && log "✅ SKIP: $file_name already compliant."
        fi

    done
    log "✅ Completed scan for $CURRENT_DIR"
done

exit 0
