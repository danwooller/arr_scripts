#!/bin/bash

# Fix audio for Sonos Playbar
# for dir in /mnt/media/TV/A*/; do sudo LOG_LEVEL=debug ./DW_sonos_audio_fix.sh "$dir"; done

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# Safety check: Don't run during a ZFS scrub
if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub currently in progress on $BASE_HOST6. Exiting to protect disks."
    exit 0
fi

check_dependencies "ffmpeg"

# --- Logic: Manual vs Scheduled ---
if [ -n "$1" ]; then
    log "Manual scan requested for: $1"
    TARGET_PATHS=("$1")
else
    [[ "$LOG_LEVEL" == "debug" ]] && log "Starting scheduled scan of all TV locations..."
    TARGET_PATHS=("${DIR_TV[@]}" "${DIR_MOVIES[@]}")
fi

# --- Execution Loop ---
for CURRENT_DIR in "${TARGET_PATHS[@]}"; do

    # 1. Existence and Mount Check
    if [ ! -d "$CURRENT_DIR" ]; then
        log "❌ SKIP: $CURRENT_DIR is not available."
        continue
    fi

    # 2. Empty Directory Check
    if [ -z "$(ls -A "$CURRENT_DIR" 2>/dev/null)" ]; then
        log "⚠️ WARNING: $CURRENT_DIR appears empty. Skipping."
        continue
    fi

    [[ "$LOG_LEVEL" == "debug" ]] && log "🔍 Processing: $CURRENT_DIR"

    # 3. Find and Log Filenames
    # This finds all files, excludes common non-media paths, and logs just the name
    find "$CURRENT_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) \
    -not -path "*/.*" | while read -r file; do
        #file_name=$(basename "$file")
        #log "📄 Found: $file_name"
        # Optional: If you want the full path instead of just the name, 
        # use 'log "📄 Found: $file"' instead.
		sonos_audio_fix "$file"
    done
    [[ "$LOG_LEVEL" == "debug" ]] && log "✅ Completed scan for $CURRENT_DIR"
done

plex_library_update "$PLEX_TV_SRC" "$PLEX_TV_NAME"
[[ "$LOG_LEVEL" == "debug" ]] && log "🏁 Tasks finished."
exit 0
