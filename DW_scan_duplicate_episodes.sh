#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub currently in progress on $BASE_HOST6. Exiting to protect disks."
    exit 0
fi

# --- Logic: Manual vs Scheduled ---
if [ -n "$1" ]; then
    # If an argument is passed, we only scan that specific path
    log "Manual scan requested for: $1"
    TARGET_PATHS=("$1")
else
    # If no argument, we run the full array (Systemd Timer mode)
    [[ "$LOG_LEVEL" == "debug" ]] && log "Starting scheduled scan of all TV locations..."
    TARGET_PATHS=("${DIR_TV[@]}")
fi

# --- Execution Loop ---
for CURRENT_DIR in "${TARGET_PATHS[@]}"; do
    
    # 1. Check if the directory actually exists/is mounted
    if [ ! -d "$CURRENT_DIR" ]; then
        log "❌ SKIP: $CURRENT_DIR is not available (Check mount/network)."
        continue
    fi

    # 2. Check if the directory is empty (common sign of a dropped mount)
    if [ -z "$(ls -A "$CURRENT_DIR" 2>/dev/null)" ]; then
        log "⚠️ WARNING: $CURRENT_DIR appears empty. Skipping to prevent data loss/errors."
        continue
    fi

    [[ "$LOG_LEVEL" == "debug" ]] && log "🔍 Processing: $CURRENT_DIR"
    
    # Use process substitution to avoid subshell variable isolation
    while read -r series_path; do
        series_path="${series_path%/}"
        series_name=$(basename "$series_path")
        
        # Check Exclusions
        skip=false
        for exclude in "${EXCLUDE_DIRS[@]}"; do
            [[ "$series_name" == "$exclude" ]] && skip=true && break
        done
        [[ "$skip" == "true" ]] && continue

        # 1. Scan for duplicate video files
        duplicates=$(find "$series_path" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) \
            -not -path "*Specials*" -not -path "*Season 00*" \
            | grep -oE "[0-9]+x[0-9]+" | sort | uniq -c | awk '$1 > 1 {print $2}')

        if [[ -n "$duplicates" ]]; then
            dup_list=$(echo $duplicates | xargs)
            log "⚠️ Duplicate(s) in $series_name: $dup_list"
            
            # 2. Sync to Seerr
            # Removed 'local' here as we are in the main script body
            manual_id="${MANUAL_MAPS[$series_name]}"
            seerr_sync_issue "$series_name" "tv" "Duplicate Episode(s): $dup_list" "$manual_id"
        else
            [[ "$LOG_LEVEL" == "debug" ]] && log "✨ No duplicates for $series_name. Checking for resolution..."
            seerr_resolve_issue "$series_path"
        fi

    done < <(find "$CURRENT_DIR" -maxdepth 1 -mindepth 1 -type d)

    log "✅ Completed scan for $CURRENT_DIR"
done

[[ "$LOG_LEVEL" == "debug" ]] && log "🏁 Tasks finished."
exit 0
