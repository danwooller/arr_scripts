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
    if [ ! -d "$CURRENT_DIR" ] || [ -z "$(ls -A "$CURRENT_DIR" 2>/dev/null)" ]; then
        log "❌ SKIP: $CURRENT_DIR is missing or empty."
        continue
    fi

    series_name=$(basename "$CURRENT_DIR")
    [[ "$LOG_LEVEL" == "debug" ]] && log "🔍 Processing Series: $series_name"
    
    # Clean extraction: Get "5x01" style strings, sort them numerically
    mapfile -t ep_list < <(find "$CURRENT_DIR" -type f \
        -not -path "*Specials*" \
        -not -path "*Season 00*" \
        -name "*[0-9]x[0-9]*" \
        -exec basename {} \; | grep -oE "[0-9]+x[0-9]+(-[0-9]+)?" | sort -V | uniq)

    if [[ ${#ep_list[@]} -eq 0 ]]; then
        continue
    fi

    missing_in_series=""
    prev_s=-1
    expected_e=1 # Reset to 1 at start

    for ep in "${ep_list[@]}"; do
        # 1. Cleanly split 5x04 into 5 and 04
        curr_s="${ep%%x*}"
        range="${ep#*x}"
        
        # 2. Handle ranges like 01-02 and strip ALL leading zeros
        # We use 10# to force Bash to treat the number as Base-10 (Decimal)
        start_raw=$(echo "${range%%-*}" | sed 's/^0*//')
        end_raw=$(echo "${range##*-}" | sed 's/^0*//')
        
        # If sed stripped everything (e.g., from "00"), default to 0
        start_e=${start_raw:-0}
        end_e=${end_raw:-0}

        # 3. If the season changed, log it and reset the expected episode to 1
        if [[ "$curr_s" -ne "$prev_s" ]]; then
            [[ "$prev_s" -ne -1 ]] && [[ "$LOG_LEVEL" == "debug" ]] && log "Moving from Season $prev_s to $curr_s"
            expected_e=1
            prev_s=$curr_s
        fi

        # 4. Check for Gaps
        if (( start_e > expected_e )); then
            for ((i=expected_e; i<start_e; i++)); do
                missing_in_series+="${curr_s}x$(printf "%02d" $i) "
            done
        fi
        
        # 5. Set expected to the NEXT episode after this file
        expected_e=$((end_e + 1))
    done

    # --- Final Reporting ---
    if [[ -n "$missing_in_series" ]]; then
        log "⚠️ $series_name is missing: $missing_in_series"
        seerr_sync_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "${MANUAL_MAPS[$series_name]}"
    else
        log "✨ No gaps found for $series_name. Resolving issues..."
        find "$CURRENT_DIR" -maxdepth 1 -type d -name "Season*" | while read -r season_folder; do
             seerr_resolve_issue "$season_folder"
        done
    fi
done

[[ "$LOG_LEVEL" == "debug" ]] && log "🏁 Tasks finished."
exit 0
