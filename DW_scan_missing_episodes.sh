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
        [[ "$LOG_LEVEL" == "debug" ]] && log "🔍 Processing Series: $series_name"

        # 3. Episode Extraction: Filter for VIDEO files only
        # Normalizes "5x04-05" or "5x01" into "Season Start_Ep End_Ep" format
        mapfile -t ep_list < <(find "$CURRENT_SERIES_PATH" -type f \
            \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" -o -name "*.ts" \) \
            -not -path "*Specials*" -not -path "*Season 00*" \
            -name "*[0-9]x[0-9]*" -exec basename {} \; | \
            grep -oE "[0-9]+x[0-9]+(-[0-9]+)?" | \
            sed -E 's/x|--?| / /g' | \
            awk '{if ($3 == "") $3=$2; print $1, $2, $3}' | \
            sort -k1,1n -k2,2n | \
            uniq)

        if [[ ${#ep_list[@]} -eq 0 ]]; then
            continue
        fi

        # 4. Gap Detection Logic
        missing_in_series=""
        prev_s=-1
        expected_e=-1 # Changed from 1 to a flag

        for line in "${ep_list[@]}"; do
            read -r s_raw e_start_raw e_end_raw <<< "$line"

            curr_s=$((10#$s_raw))
            curr_e_start=$((10#$e_start_raw))
            curr_e_end=$((10#$e_end_raw))

            # Reset logic on Season Change
            if [[ "$curr_s" -ne "$prev_s" ]]; then
                # On a new season, set the expectation to the first episode found
                # This prevents marking 01 as missing if the season starts at 05
                expected_e=$curr_e_start 
                prev_s=$curr_s
            fi

            # Check for Gaps
            if (( curr_e_start > expected_e )); then
                for ((i=expected_e; i<curr_e_start; i++)); do
                    missing_in_series+="${curr_s}x$(printf "%02d" $i) "
                done
            fi
            
            # Next expected is one after the current file's end episode
            expected_e=$((curr_e_end + 1))
        done

        # 5. Reporting & Seerr Resolution
        if [[ -n "$missing_in_series" ]]; then
            log "⚠️ $series_name is missing: $missing_in_series"
            seerr_sync_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "${MANUAL_MAPS[$series_name]}"
        else
            [[ "$LOG_LEVEL" == "debug" ]] && log "✨ No gaps found for $series_name. Resolving Seerr issues..."
            
            # Send the Series path and explicitly state "tv"
            # We use the CURRENT_SERIES_PATH so Sonarr can actually find the match
            seerr_resolve_issue "$CURRENT_SERIES_PATH" "tv"
        fi

        [[ $LOG_LEVEL == "debug" ]] && log "✅ Completed scan for $series_name"
    done
done

[[ "$LOG_LEVEL" == "debug" ]] && log "🏁 Tasks finished."
exit 0
