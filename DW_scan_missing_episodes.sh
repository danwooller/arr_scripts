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

# --- 1. Pre-fetch Sonarr Data (Optimization) ---
declare -A SERIES_TYPE_MAP
declare -A SONARR_TMDB_MAP  # New map for IDs
log "Fetching library metadata from Sonarr..."

while IFS="|" read -r path type tmdb; do
    if [[ -n "$path" ]]; then
        SERIES_TYPE_MAP["$path"]="$type"
        # Only map if TMDB ID exists and isn't 0
        [[ "$tmdb" != "0" && -n "$tmdb" ]] && SONARR_TMDB_MAP["$path"]="$tmdb"
    fi
done < <(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_API_BASE/series" | \
         jq -r '.[] | "\(.path)|\(.seriesType)|\(.tmdbId)"')

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

        # Lookup Sonarr type (default to standard if not found)
        this_series_type="${SERIES_TYPE_MAP[$CURRENT_SERIES_PATH]:-standard}"

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

            # --- NEW SAFETY CHECK: Skip Season 0 (Specials) ---
            if [[ "$curr_s" -eq 0 ]]; then
                continue
            fi

            # Season Change Reset
            if [[ "$curr_s" -ne "$prev_s" ]]; then
                # Only flag missing 01-XX if it's NOT a daily/weekly rolling show
                if [[ "$this_series_type" != "daily" && "$curr_e_start" -gt 1 ]]; then
                    for ((i=1; i<curr_e_start; i++)); do
                        missing_in_series+="${curr_s}x$(printf "%02d" $i) "
                    done
                fi
                prev_s=$curr_s
                expected_e=$((curr_e_end + 1))
                continue
            fi

            # Check for Gaps within the season (Always happens regardless of type)
            if (( curr_e_start > expected_e )); then
                for ((i=expected_e; i<curr_e_start; i++)); do
                    missing_in_series+="${curr_s}x$(printf "%02d" $i) "
                done
            fi
            
            expected_e=$((curr_e_end + 1))
        done

        # 4. Reporting & Seerr Sync
        # Priority: Check Manual Map, then fallback to the automated Sonarr map
        tmdb_id="${MANUAL_MAPS[$series_name]:-${SONARR_TMDB_MAP[$CURRENT_SERIES_PATH]}}"

        if [[ -n "$missing_in_series" ]]; then
            log "⚠️ $series_name is missing: $missing_in_series"
            
            if [[ -n "$tmdb_id" ]]; then
                seerr_issue_notify "$series_name" "$tmdb_id" "Missing episodes: $missing_in_series" "tv"
                seerr_sync_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "$tmdb_id"
            else
                log "❌ Could not sync $series_name: No TMDB ID found in Manual Maps or Sonarr."
            fi

        elif [[ ${#ep_list[@]} -gt 0 ]]; then
            # We only look for an open issue if we actually have a TMDB ID to check against
            if [[ -n "$tmdb_id" ]]; then
                # Fetch issues and store in a variable first to check for success
                issue_json=$(curl -s -X GET "$SEERR_URL/api/v1/issue?status=1" -H "X-Api-Key: $SEERR_API_KEY")
                
                if [[ -n "$issue_json" && "$issue_json" != "null" ]]; then
                    open_issue_id=$(echo "$issue_json" | jq -r --arg id "$tmdb_id" '.results[]? | select(.media.tmdbId == ($id|tonumber)) | .id')
                else
                    open_issue_id=""
                fi
                # Check if there is an OPEN issue in Seerr before we resolve it
                open_issue_id=$(curl -s -X GET "$SEERR_URL/api/v1/issue?status=1" \
                    -H "X-Api-Key: $SEERR_API_KEY" | \
                    jq -r --arg id "$tmdb_id" '.results[] | select(.media.tmdbId == ($id|tonumber)) | .id')

                if [[ -n "$open_issue_id" ]]; then
                    log "✨ Gaps fixed for $series_name. Notifying user and resolving Seerr issue..."
                    seerr_resolve_notify "$series_name" "$tmdb_id" "tv"
                    seerr_resolve_issue "$series_name" "tv"
                fi
            fi
        else
            log "❓ No episodes detected for $series_name. Skipping resolution to be safe."
        fi
        
        [[ $LOG_LEVEL == "debug" ]] && log "✅ Completed scan for $series_name"
    done
done

[[ "$LOG_LEVEL" == "debug" ]] && log "🏁 Tasks finished."
exit 0
