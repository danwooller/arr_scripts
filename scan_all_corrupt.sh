#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# Configuration
MOVIE_ROOT="${1:-/mnt/synology/Movies}"
SCANNER_SCRIPT="/usr/local/bin/scan_corrupt_media.sh"

# Stats counters
TOTAL=0
SKIPPED=0

# Graceful exit on Ctrl+C
trap "log '🛑 Scan interrupted by user.'; exit 1" SIGINT SIGTERM

log "🚀 Starting full library sweep in: $MOVIE_ROOT"

# Use find to feed the loop
while IFS= read -r -d '' folder; do
    ((TOTAL++))
    
    # Quick check for video files to avoid unnecessary script overhead
    # We check for common extensions (case-insensitive)
    if ls "$folder"/*.[mM][kK][vV] "$folder"/*.[mM][pP]4 "$folder"/*.[aA][vV][iI] >/dev/null 2>&1; then
        # Call the main scanner
        # Temporary change for testing
        # "$SCANNER_SCRIPT" "$folder"  <-- Comment this out
        log "Would scan: $folder"    # <-- Add this
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
