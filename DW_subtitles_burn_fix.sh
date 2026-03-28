#!/bin/bash

# --- Load Shared Functions & Subtitle Logic ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- [PASTE YOUR subtitle_opts() FUNCTION HERE] ---

cleanup() {
    log "⚠️ Interruption. Cleaning up..."
    find "${TARGET_PATHS[@]}" -type f -name "*_smart_tmp.mkv" -delete 2>/dev/null
    exit 1
}
trap cleanup SIGINT SIGTERM

# --- Logic: Manual vs Scheduled ---
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

        # 1. Run your selection logic
        # This populates $TRACK_OPTS and $NEEDS_PROPEDIT
        subtitle_opts "$file"

        # 2. Check if the file actually needs fixing
        # If TRACK_OPTS includes "--no-subtitles" or specific IDs, 
        # we check if the original file matches that already.
        # To keep it simple: we remux if the codec is problematic.
        problem_subs=$(ffprobe -v error -select_streams s -show_entries stream=codec_name -of csv=p=0 "$file" | grep -E "ass|hdmv_pgs_subtitle|dvd_subtitle")

        if [ -n "$problem_subs" ]; then
            log "🔧 REMUXING: $file_name (Applying smart track selection)"

            # 3. Execute Remux with mkvmerge using your calculated TRACK_OPTS
            if mkvmerge -o "$temp_file" $TRACK_OPTS "$file" >/dev/null 2>&1; then
                
                # 4. Swap and Backup
                mv "$file" "$DIR_MEDIA_HOLD/${file_name}.original"
                mv "$temp_file" "${file%.*}.mkv"
                
                log "✨ SUCCESS: $file_name cleaned. (Options: $TRACK_OPTS)"
                
                # Optional: Handle property edits if your logic flagged it
                if [ "$NEEDS_PROPEDIT" = true ]; then
                    log "📝 Flagging Forced subs in metadata..."
                    mkvpropedit "${file%.*}.mkv" --edit track:s1 --set flag-forced=1 >/dev/null 2>&1
                fi
            else
                log "❌ FAILED: mkvmerge failed for $file_name"
                [ -f "$temp_file" ] && rm "$temp_file"
            fi
        else
            [[ "$LOG_LEVEL" == "debug" ]] && log "✅ SKIP: $file_name is already compliant."
        fi

    done
    log "✅ Completed scan for $CURRENT_DIR"
done

exit 0
