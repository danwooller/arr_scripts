#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# Configuration
MOVIE_ROOT="${1:-/mnt/synology/Movies}"
SCANNER_SCRIPT="/usr/local/bin/scan_corrupt_media.sh"

# Stats counters
TOTAL=0
SKIPPED=0

log "🚀 Starting full library sweep in: $MOVIE_ROOT"

# Use find to feed the loop
while IFS= read -r -d '' folder; do
    ((TOTAL++))
    
    if find "$folder" -maxdepth 1 -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" | grep -q .; then
        # Call the main scanner
        "$SCANNER_SCRIPT" "$folder"
        #echo "Would scan: $folder"
    else
        log "⚠️ Skipping: No media found in $(basename "$folder")"
        ((SKIPPED++))
    fi

done < <(find "$MOVIE_ROOT" -maxdepth 1 -mindepth 1 -type d -print0)

# Final Summary
PROCESSED=$((TOTAL - SKIPPED))
log "-------------------------------------------"
log "✅ Full library sweep complete."
log "📊 Stats: Total Folders: $TOTAL | Processed: $PROCESSED | Skipped: $SKIPPED"
log "-------------------------------------------"
