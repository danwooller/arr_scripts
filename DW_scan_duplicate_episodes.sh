#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Load External Configuration ---
CONFIG_FILE="/mnt/media/torrent/ubuntu24_sonarr_mapping.txt"
[[ -f "$CONFIG_FILE" ]] && source <(sed 's/\r$//' "$CONFIG_FILE")

check_dependencies "curl" "jq" "sed" "grep"

INPUT_PATH="${1:-/mnt/media/TV}"

# --- Hybrid Path Detection ---
if find "$INPUT_PATH" -maxdepth 1 -type d -name "Season*" | grep -q .; then
    SERIES_LIST=("$INPUT_PATH")
else
    mapfile -t SERIES_LIST < <(find "$INPUT_PATH" -maxdepth 1 -mindepth 1 -type d)
fi

log_start "Duplicate Check: $INPUT_PATH"

for series_path in "${SERIES_LIST[@]}"; do
    # Strip trailing slash
    series_path="${series_path%/}"
    series_name=$(basename "$series_path")
    
    for exclude in "${EXCLUDE_DIRS[@]}"; do
        [[ "$series_name" == "$exclude" ]] && continue 2
    done

    # 1. Scan for duplicate video files
    duplicates=$(find "$series_path" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) \
        -not -path "*Specials*" -not -path "*Season 00*" \
        | grep -oE "[0-9]+x[0-9]+" | sort | uniq -c | awk '$1 > 1 {print $2}')

    if [[ -n "$duplicates" ]]; then
        dup_list=$(echo $duplicates | xargs)
        log "⚠️ Duplicate(s) in $series_name: $dup_list"
        
        # 2. Sync to Seerr
        seerr_sync_issue "$series_name" "tv" "Duplicate Episode(s): $dup_list" "${MANUAL_MAPS[$series_name]}"
    else
        [[ $LOG_LEVEL == "debug" ]] && log "✨ No duplicates for $series_name. Checking for resolution..."

        seerr_resolve_issue "$series_path"
        # 3. Resolution Logic (Fixed scope: removed 'local')
        # Get TVDB ID from Sonarr using the path
#        tvdb_id=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/series" | \
#                        jq -r --arg path "$series_path" '.[] | select(.path == $path or .path == ($path + "/")) | .tvdbId')

#        if [[ -n "$tvdb_id" && "$tvdb_id" != "null" ]]; then
            # Fetch open issues from Seerr
#            open_issues=$(curl -s -H "X-Api-Key: $SEERR_API_KEY" "$SEERR_URL/api/v1/issue?filter=open")
            
            # Find the Issue ID that matches this TVDB ID
#            issue_id=$(echo "$open_issues" | jq -r --arg tid "$tvdb_id" '.results[] | select(.media.tvdbId | tostring == $tid) | .id' | head -n 1)

#            if [[ -n "$issue_id" && "$issue_id" != "null" ]]; then
#                log "✅ Duplicates resolved for $series_name. Closing Seerr Issue #$issue_id..."
#                curl -s -X POST "$SEERR_URL/api/v1/issue/$issue_id/resolved" -H "X-Api-Key: $SEERR_API_KEY" > /dev/null
                
                # Trigger Sonarr Rescan
#                s_id=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/series" | jq -r --arg path "$series_path" '.[] | select(.path == $path) | .id')
#                [[ -n "$s_id" ]] && curl -s -X POST "$SONARR_URL/api/v3/command" -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" -d "{\"name\": \"RescanSeries\", \"seriesId\": $s_id}" > /dev/null
#            fi
#        fi
    fi
done

log_end "Duplicate Check: $INPUT_PATH"
