#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Safety Check: ZFS Scrub ---
if sudo ssh -o ConnectTimeout=10 "$BASE_HOST6" "zpool status" | grep -q "scrub in progress"; then
    log "⚠️ ZFS Scrub currently in progress on $BASE_HOST6. Exiting to protect disks."
    exit 0
fi

# --- Logic: Manual vs Scheduled ---
if [ -n "$1" ]; then
    log "Manual scan requested for: $1"
    TARGET_ROOTS=("$(realpath "$1")")
else
    [[ "$LOG_LEVEL" == "debug" ]] && log "Starting scheduled scan of all TV locations..."
    TARGET_ROOTS=("${DIR_TV[@]}")
fi

# --- Execution Loop ---
for ROOT_DIR in "${TARGET_ROOTS[@]}"; do

    if [ ! -d "$ROOT_DIR" ]; then
        log "❌ SKIP: Root $ROOT_DIR is unavailable."
        continue
    fi

    # Discovery: Find Series folders (folders containing 'Season' subdirectories)
    mapfile -t SERIES_LIST < <(find "$ROOT_DIR" -maxdepth 2 -type d -name "Season*" -exec dirname {} \; | sort -u)

    for CURRENT_SERIES_PATH in "${SERIES_LIST[@]}"; do
        series_name=$(basename "$CURRENT_SERIES_PATH")
        [[ "$LOG_LEVEL" == "debug" ]] && log "🔍 Processing Series: $series_name"

        # 1. Safeguard: Check for metadata to ensure mount is healthy
        if [[ ! -f "$CURRENT_SERIES_PATH/tvshow.nfo" && ! -d "$CURRENT_SERIES_PATH/Season 1" ]]; then
            log "⚠️ $series_name: Missing metadata/Season 1. Potential mount issue. Skipping."
            continue
        fi

        # 2. Episode Extraction: Normalize "5x04" into "Season Start_Ep End_Ep"
        mapfile -t ep_list < <(find "$CURRENT_SERIES_PATH" -type f \
            \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" -o -name "*.ts" \) \
            -not -path "*Specials*" -not -path "*Season 00*" \
            -name "*[0-9]x[0-9]*" -exec basename {} \; | \
            grep -oE "[0-9]+x[0-9]+(-[0-9]+)?" | \
            sed -E 's/x|--?| / /g' | \
            awk '{if ($3 == "") $3=$2; print $1, $2, $3}' | \
            sort -k1,1n -k2,2n | \
            uniq)

        # 3. Gap Detection Logic
        missing_in_series=""
        prev_s=-1
        expected_e=-1 

        for line in "${ep_list[@]}"; do
            read -r s_raw e_start_raw e_end_raw <<< "$line"

            curr_s=$((10#$s_raw))
            curr_e_start=$((10#$e_start_raw))
            curr_e_end=$((10#$e_end_raw))

            # --- Season Change or First Run ---
            if [[ "$curr_s" -ne "$prev_s" ]]; then
                # Logic: If it's a new season, we don't assume it starts at 01.
                # We set the 'expected_e' to whatever the first found episode is.
                # This ignores missing leading episodes for weekly/rolling shows.
                prev_s=$curr_s
                expected_e=$((curr_e_end + 1))
                continue
            fi

            # --- Check for Gaps within the season ---
            # Now we only flag gaps that occur BETWEEN existing files.
            if (( curr_e_start > expected_e )); then
                for ((i=expected_e; i<curr_e_start; i++)); do
                    missing_in_series+="${curr_s}x$(printf "%02d" $i) "
                done
            fi
            
            expected_e=$((curr_e_end + 1))
        done

        # 4. Reporting & Seerr Sync
        if [[ -n "$missing_in_series" ]]; then
            log "⚠️ $series_name is missing: $missing_in_series"
            # Use the Seerr Function we fixed earlier
            seerr_sync_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "${MANUAL_MAPS[$series_name]}"
        
        elif [[ ${#ep_list[@]} -gt 0 ]]; then
            # ONLY resolve if we actually found episodes and found ZERO gaps.
            [[ "$LOG_LEVEL" == "debug" ]] && log "✨ No gaps found for $series_name. Resolving Seerr issues..."
            seerr_resolve_issue "$series_name" "tv"
        else
            log "❓ No episodes detected for $series_name. Skipping resolution to be safe."
        fi
        
        [[ $LOG_LEVEL == "debug" ]] && log "✅ Completed scan for $series_name"
    done
done

[[ "$LOG_LEVEL" == "debug" ]] && log "🏁 Tasks finished."
exit 0
