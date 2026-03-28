#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- NEW: Signal Handling (Cleanup on Exit/Interruption) ---
# This looks for any temp files created by this script and deletes them if you hit Ctrl+C
cleanup() {
    log "⚠️ Interruption detected. Cleaning up temporary files..."
    find "${TARGET_PATHS[@]}" -type f -name "*_srt_tmp.mkv" -delete 2>/dev/null
    exit 1
}
trap cleanup SIGINT SIGTERM

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

    find "$CURRENT_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" \) | while read -r file; do
        
        file_name=$(basename "$file")
        temp_file="${file%.*}_srt_tmp.mkv"

        # 1. Identify problematic subtitle codecs
        problem_subs=$(ffprobe -v error -select_streams s -show_entries stream=codec_name -of csv=p=0 "$file" | grep -E "ass|hdmv_pgs_subtitle|dvd_subtitle")

        if [ -z "$problem_subs" ]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "✅ COMPATIBLE: $file_name"
            continue
        fi

        log "🔧 CONVERTING SUBS: $file_name ($problem_subs detected)"

        # 2. Remux and Convert
        if ffmpeg -v error -i "$file" -map 0 -c:v copy -c:a copy -c:s srt "$temp_file" < /dev/null; then
            
            # 3. Swap and Backup
            mv "$file" "$DIR_MEDIA_HOLD/${file_name}.original"
            mv "$temp_file" "${file%.*}.mkv"
            
            log "✨ SUCCESS: $file_name is now Plex-friendly (SRT)."
        else
            log "❌ FAILED: Subtitle conversion failed for $file_name"
            # Explicitly remove the specific temp file if this one file fails
            [ -f "$temp_file" ] && rm "$temp_file"
        fi

    done
    log "✅ Completed subtitle scan for $CURRENT_DIR"
done

log "🏁 Tasks finished. System clean."
exit 0
