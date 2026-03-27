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
# --- Execution Loop ---
for CURRENT_DIR in "${TARGET_PATHS[@]}"; do
    
    # 1. Check if the directory actually exists/is mounted
    if [ ! -d "$CURRENT_DIR" ]; then
        log "❌ SKIP: $CURRENT_DIR is not available."
        continue
    fi

    # 2. Check if empty
    if [ -z "$(ls -A "$CURRENT_DIR" 2>/dev/null)" ]; then
        log "⚠️ WARNING: $CURRENT_DIR appears empty."
        continue
    fi

    # Use the folder name as the Series Name
    series_name=$(basename "$CURRENT_DIR")
    [[ "$LOG_LEVEL" == "debug" ]] && log "🔍 Processing Series: $series_name"
    
    # 3. Get ALL episodes in the series folder (including all Season subfolders)
    mapfile -t ep_list < <(find "$CURRENT_DIR" -type f \
        -not -path "*Specials*" \
        -not -path "*Season 00*" \
        -name "*[0-9]x[0-9]*" \
        -exec basename {} \; | grep -oE "[0-9]+x[0-9]+(-[0-9]+)?" | sort -V | uniq)

    if [[ ${#ep_list[@]} -lt 2 ]]; then
        [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ Not enough episodes in $series_name to check for gaps."
        continue
    fi

    # 4. Gap Detection Logic
    missing_in_series=""
    prev_s=-1
    prev_e=-1

    for ep in "${ep_list[@]}"; do
        curr_s=$(echo "$ep" | cut -d'x' -f1)
        range=$(echo "$ep" | cut -d'x' -f2)
        start_e=$(echo "$range" | cut -d'-' -f1 | sed 's/^0*//')
        end_e=$(echo "$range" | cut -d'-' -f2 | sed 's/^0*//')

        if [[ "$curr_s" -eq "$prev_s" ]]; then
            expected=$((prev_e + 1))
            if [[ "$start_e" -gt "$expected" ]]; then
                for ((i=expected; i<start_e; i++)); do 
                    missing_in_series+="${curr_s}x$(printf "%02d" $i) "
                done
            fi
        fi
        prev_s=$curr_s
        prev_e=$end_e
    done

    # 5. Reporting / Resolution
    if [[ -n "$missing_in_series" ]]; then
        log "⚠️ $series_name is missing: $missing_in_series"
        seerr_sync_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "${MANUAL_MAPS[$series_name]}"
    else
        log "✨ No gaps found for $series_name. Resolving Seerr issues..."
        # Resolve by season folder
        find "$CURRENT_DIR" -maxdepth 1 -type d -name "Season*" | while read -r season_folder; do
             seerr_resolve_issue "$season_folder"
        done
    fi

    log "✅ Completed scan for $series_name"
done
[[ "$LOG_LEVEL" == "debug" ]] && log "🏁 Tasks finished."
exit 0
