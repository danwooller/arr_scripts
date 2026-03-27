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
    
    # 1. Discovery: Extract SxE or SxE-E and normalize to "S E_START E_END"
    # This turns "5x04-05" into "5 4 5" and "5x01" into "5 1 1"
    mapfile -t ep_list < <(find "$CURRENT_DIR" -type f \
        -not -path "*Specials*" -not -path "*Season 00*" \
        -name "*[0-9]x[0-9]*" -exec basename {} \; | \
        grep -oE "[0-9]+x[0-9]+(-[0-9]+)?" | \
        sed -E 's/x|--?/ /g' | \
        awk '{if ($3 == "") $3=$2; print $1, $2, $3}' | \
        sort -k1,1n -k2,2n | \
        uniq)

    # Add this line immediately after the mapfile -t ep_list line:
    [[ "$LOG_LEVEL" == "debug" ]] && printf "DEBUG: Raw Episode List for %s:\n%s\n" "$series_name" "$(printf '%s\n' "${ep_list[@]}")"

    if [[ ${#ep_list[@]} -eq 0 ]]; then continue; fi

    missing_in_series=""
    prev_s=-1
    expected_e=1

    for line in "${ep_list[@]}"; do
        # line format: "Season Start_Episode End_Episode"
        read -r s_raw e_start_raw e_end_raw <<< "$line"

        # Force Base-10 (Decimal)
        curr_s=$((10#$s_raw))
        curr_e_start=$((10#$e_start_raw))
        curr_e_end=$((10#$e_end_raw))

        # Season Transition
        if [[ "$curr_s" -ne "$prev_s" ]]; then
            [[ "$prev_s" -ne -1 ]] && [[ "$LOG_LEVEL" == "debug" ]] && log "Moving from Season $prev_s to $curr_s"
            expected_e=1
            prev_s=$curr_s
        fi

        # Gap Detection
        if (( curr_e_start > expected_e )); then
            for ((i=expected_e; i<curr_e_start; i++)); do
                missing_in_series+="${curr_s}x$(printf "%02d" $i) "
            done
        fi
        
        # Next expected is one after the END of the current file/range
        expected_e=$((curr_e_end + 1))
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
