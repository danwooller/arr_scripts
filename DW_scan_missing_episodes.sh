#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Safety Check: ZFS Scrub ---
# Prevents heavy disk I/O if the pool is currently scrubbing
if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub currently in progress on $BASE_HOST6. Exiting to protect disks."
    exit 0
fi

# --- Logic: Manual vs Scheduled ---
if [ -n "$1" ]; then
    log "Manual scan requested for: $1"
    TARGET_ROOTS=("$1")
else
    [[ "$LOG_LEVEL" == "debug" ]] && log "Starting scheduled scan of all TV locations..."
    TARGET_ROOTS=("${DIR_TV[@]}")
fi

# --- Execution Loop ---
for ROOT_DIR in "${TARGET_ROOTS[@]}"; do

    # 1. Validation: Ensure root exists
    if [ ! -d "$ROOT_DIR" ]; then
        log "❌ SKIP: Root $ROOT_DIR is unavailable."
        continue
    fi

    # 2. Discovery: Find all Series folders (folders containing 'Season' subdirectories)
    # This allows the script to run against /mnt/media/TV or a specific show folder.
    mapfile -t SERIES_LIST < <(find "$ROOT_DIR" -maxdepth 2 -type d -name "Season*" -exec dirname {} \; | sort -u)

    for CURRENT_SERIES_PATH in "${SERIES_LIST[@]}"; do
        series_name=$(basename "$CURRENT_SERIES_PATH")
        
        # --- Safeguard 1: Ensure the directory isn't empty/unmounted ---
        # If the folder exists but we can't see the NFO or Season folders, 
        # it's a disk/mount glitch. Skip it.
        if [[ ! -f "$CURRENT_SERIES_PATH/tvshow.nfo" && ! -d "$CURRENT_SERIES_PATH/Season 1" ]]; then
            log "⚠️ $series_name: Missing metadata/Season 1. Potential mount issue. Skipping."
            continue
        fi

        # 3. Episode Extraction (Existing logic...)
        mapfile -t ep_list < <(find "$CURRENT_SERIES_PATH" -type f \
            \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" -o -name "*.ts" \) \
            -not -path "*Specials*" -not -path "*Season 00*" \
            -name "*[0-9]x[0-9]*" -exec basename {} \; | \
            grep -oE "[0-9]+x[0-9]+(-[0-9]+)?" | \
            sed -E 's/x|--?| / /g' | \
            awk '{if ($3 == "") $3=$2; print $1, $2, $3}' | \
            sort -k1,1n -k2,2n | \
            uniq)

        # --- Gap Detection (Existing logic...) ---
        missing_in_series=""
        # ... [Your existing for loop that populates missing_in_series] ...

        # 5. Reporting & Seerr Resolution
        if [[ -n "$missing_in_series" ]]; then
            log "⚠️ $series_name is missing: $missing_in_series"
            seerr_sync_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "${MANUAL_MAPS[$series_name]}"
        
        elif [[ ${#ep_list[@]} -gt 0 ]]; then
            # SAFE TO RESOLVE: We found episodes and NO gaps.
            [[ "$LOG_LEVEL" == "debug" ]] && log "✨ No gaps found for $series_name. Resolving Seerr issues..."
            
            # Use the Clean Name instead of the Path for the resolution search
            seerr_resolve_issue "$series_name" "tv"
        else
            # Safeguard: We found the folder, but no video files.
            # Don't resolve anything, as this is likely a scan error.
            log "❓ $series_name: No episodes detected in scan. Skipping resolution safety check."
        fi
        
        [[ $LOG_LEVEL == "debug" ]] && log "✅ Completed scan for $series_name"
    done
done

[[ "$LOG_LEVEL" == "debug" ]] && log "🏁 Tasks finished."
exit 0
