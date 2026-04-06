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
    # Use a safer delete for tmp files
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

    # CRITICAL: -print0 and read -d '' handles spaces in filenames perfectly
    find "$CURRENT_DIR" -type f -name "*.mkv" -print0 | while IFS= read -r -d '' file; do
        
        # Reset variables for each file to prevent "bleeding" logic
        unset TRACK_OPTS
        unset NEEDS_PROPEDIT
        
        file_name=$(basename "$file")
        temp_file="${file%.*}_smart_tmp.mkv"
        temp_srt="/tmp/dw_conv_$(date +%s).srt"

        # 1. Run shared logic
        subtitle_opts "$file"

        # 2. Check for problematic codecs
        # We wrap "$file" in quotes to ensure ffprobe sees the full path
        problem_subs=$(ffprobe -v error -select_streams s -show_entries stream=codec_name -of csv=p=0 "$file" | grep -E "ass|hdmv_pgs_subtitle|dvd_subtitle")

        if [ -n "$problem_subs" ]; then
            log "🔧 FIXING: $file_name (Converting to SRT)"

            # INTERCEPT: Get the Subtitle ID from the shared TRACK_OPTS
            sub_id=$(echo "$TRACK_OPTS" | grep -oP '(?<=--subtitle-tracks )\d+')

            if [ -n "$sub_id" ]; then
                # Convert specific track to SRT
                if ffmpeg -i "$file" -map 0:"$sub_id" "$temp_srt" -y >/dev/null 2>&1; then
                    
                    # Strip the internal subtitle flags from TRACK_OPTS
                    CLEAN_OPTS=$(echo "$TRACK_OPTS" | sed -E 's/--subtitle-tracks [0-9,]+//')
                    
                    # EXECUTE: Input MKV (stripping subs) + Input SRT
                    if mkvmerge -o "$temp_file" $CLEAN_OPTS --no-subtitles "$file" "$temp_srt" >/dev/null 2>&1; then
                        mv "$file" "$DIR_MEDIA_HOLD/${file_name}.original"
                        mv "$temp_file" "${file%.*}.mkv"
                        log "✨ SUCCESS: $file_name converted to SRT."
                        
                        if [ "$NEEDS_PROPEDIT" = true ]; then
                             mkvpropedit "${file%.*}.mkv" --edit track:s1 --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
                        fi
                    else
                        log "❌ FAILED: mkvmerge failed for $file_name"
                    fi
                else
                    log "❌ FAILED: ffmpeg conversion failed for $file_name"
                fi
            fi
            rm -f "$temp_srt"
        else
            [[ "$LOG_LEVEL" == "debug" ]] && log "✅ SKIP: $file_name is already compliant."
        fi
    done
    log "✅ Completed scan for $CURRENT_DIR"
done
