#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- ZFS Safety Check ---
if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub currently in progress on $BASE_HOST6. Exiting."
    exit 0
fi

# --- Logic: Manual vs Scheduled ---
if [ -n "$1" ]; then
    log "Manual subtitle scan requested for: $1"
    TARGET_PATHS=("$1")
else
    [[ "$LOG_LEVEL" == "debug" ]] && log "Starting scheduled subtitle scan..."
    TARGET_PATHS=("${DIR_TV[@]}" "${DIR_MOVIES[@]}")
fi

for CURRENT_DIR in "${TARGET_PATHS[@]}"; do
    if [ ! -d "$CURRENT_DIR" ]; then continue; fi

    # Scan for mkv/mp4 files
    find "$CURRENT_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" \) | while read -r file; do
        
        file_name=$(basename "$file")
        file_extension="${file##*.}"
        temp_file="${file%.*}_srt_tmp.mkv"

        # 1. Identify problematic subtitle codecs
        # Targets: ass (Complex), hdmv_pgs_subtitle (Blu-ray), dvd_subtitle (DVD)
        problem_subs=$(ffprobe -v error -select_streams s -show_entries stream=codec_name -of csv=p=0 "$file" | grep -E "ass|hdmv_pgs_subtitle|dvd_subtitle")

        if [ -z "$problem_subs" ]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "✅ COMPATIBLE: $file_name (SRT or No Subs)"
            continue
        fi

        log "🔧 CONVERTING SUBS: $file_name ($problem_subs detected)"

        # 2. Remux and Convert
        # -map 0: Copies all streams (video, audio, all subs, chapters)
        # -c:v copy / -c:a copy: No re-encoding of video/audio (fast!)
        # -c:s srt: Converts all subtitle streams to SRT format
        if ffmpeg -v error -i "$file" -map 0 -c:v copy -c:a copy -c:s srt "$temp_file" < /dev/null; then
            
            # 3. Swap and Backup
            # We move the original to your HOLD directory as a safety net
            mv "$file" "$DIR_MEDIA_HOLD/${file_name}.original"
            mv "$temp_file" "${file%.*}.mkv"
            
            log "✨ SUCCESS: $file_name is now Plex-friendly (SRT)."
        else
            log "❌ FAILED: Subtitle conversion failed for $file_name"
            [ -f "$temp_file" ] && rm "$temp_file"
        fi

    done
    log "✅ Completed subtitle scan for $CURRENT_DIR"
done

exit 0
