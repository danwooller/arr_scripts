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

check_dependencies "jq" "curl" "mail" "find" "sed" "awk" "realpath" "ssh" "basename" "dirname"

# --- 1. Pre-fetch Sonarr Data (Optimization) ---
declare -A SERIES_TYPE_MAP
declare -A SONARR_TMDB_MAP  # New map for IDs
log "Fetching library metadata from Sonarr..."

shopt -s nocasematch

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

        # --- Exclusion Check (Now inside the Series Loop) ---
        MATCH_FOUND=0
        for EXCLUSION in "${MANUAL_MAPS_EXCLUSIONS[@]}"; do
            if [[ "$series_name" == "$EXCLUSION" ]]; then
                MATCH_FOUND=1
                break
            fi
        done

        if [[ $MATCH_FOUND -eq 1 ]]; then
            log "ℹ️ Skipping $series_name (Exclusion List)"
            continue
        fi
        # --- End Exclusion Check ---

        [[ "$LOG_LEVEL" == "debug" ]] && log "🔍 Processing $series_name"

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
            # Skip Season 0
            [[ "$curr_s" -eq 0 ]] && continue

            # Season Change
            if [[ "$curr_s" -ne "$prev_s" ]]; then
                # If NOT daily, check for missing episodes 1 thru (start-1)
                if [[ "$this_series_type" != "daily" && "$curr_e_start" -gt 1 ]]; then
                    for ((i=1; i<curr_e_start; i++)); do
                        missing_in_series+="${curr_s}x$(printf "%02d" $i) "
                    done
                fi
                prev_s=$curr_s
                expected_e=$((curr_e_end + 1))
                continue
            fi

            # INTERNAL GAP CHECK
            if [[ "$curr_e_start" -gt "$expected_e" ]]; then
                for ((i=expected_e; i<curr_e_start; i++)); do
                    missing_in_series+="${curr_s}x$(printf "%02d" $i) "
                done
            fi
            
            # Update expected for next iteration
            expected_e=$((curr_e_end + 1))
        done

        # 4. Reporting & Seerr Sync
        tmdb_id="${MANUAL_MAPS[$series_name]:-${SONARR_TMDB_MAP[$CURRENT_SERIES_PATH]}}"
        
        if [[ -n "$missing_in_series" ]]; then
            log "⚠️ $series_name is missing: $missing_in_series"
            
            if [[ -n "$tmdb_id" && "$tmdb_id" != "null" ]]; then
                seerr_issue_notify "$series_name" "$tmdb_id" "Missing episodes: $missing_in_series" "tv"
                seerr_sync_issue "$series_name" "tv" "Missing Episode(s): $missing_in_series" "${MANUAL_MAPS[$series_name]}"
            else
                log "❌ Could not notify: No TMDB ID found for $series_name"
            fi

        elif [[ ${#ep_list[@]} -gt 0 ]]; then
            if [[ -n "$tmdb_id" && "$tmdb_id" != "null" ]]; then
                # Pass the TMDB ID we already have to avoid the "No ID found" errors
                if seerr_resolve_issue "$CURRENT_SERIES_PATH" "tv" "$tmdb_id"; then
                    seerr_resolve_notify "$series_name" "$tmdb_id" "tv"
                fi
            fi
        else
            log "❓ No episodes detected for $series_name. Skipping resolution to be safe."
        fi
        
        [[ $LOG_LEVEL == "debug" ]] && log "✅ Completed $series_name"
    done
done

[[ "$LOG_LEVEL" == "debug" ]] && log "🏁 Tasks finished."
exit 0
