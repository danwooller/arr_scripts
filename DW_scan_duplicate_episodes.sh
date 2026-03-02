resolve_seerr_issue() {
    local folder_path="${1%/}" # Strip trailing slash
    local base_url="${SEERR_API_BASE%/}"
    local api_key="$SEERR_API_KEY"
    
    local media_type="movie"
    local show_folder=""
    local season_num="0"
    local lookup_id=""
    local id_type=""

    # 1. Detect TV vs Movie
    if [[ "$folder_path" == *"/TV/"* ]]; then
        media_type="tv"
        
        # Logic: If the folder name contains "Season", we need to go up 1 level for the Show ID.
        # If it doesn't, we are already at the Show root.
        if [[ "$(basename "$folder_path")" == *"Season"* ]]; then
            show_folder=$(dirname "$folder_path")
            season_num=$(basename "$folder_path" | grep -oP '\d+' || echo "0")
        else
            show_folder="$folder_path"
            season_num="0" # Or logic to loop through seasons if needed
        fi
        # Get TVDB ID from Sonarr using the verified Show Folder
        lookup_id=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_API_BASE/series" | \
            jq -r --arg path "${show_folder%/}" '.[] | select(.path == $path or .path == ($path + "/")) | .tvdbId')
        id_type="tvdbId"
    else
        # Get TMDB ID from Radarr
        lookup_id=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_API_BASE/movie" | \
            jq -r --arg path "$folder_path" '.[] | select(.path == $path or .path == ($path + "/")) | .tmdbId')
        id_type="tmdbId"
    fi

    # Validation check
    if [[ -z "$lookup_id" || "$lookup_id" == "null" ]]; then
        [[ "$LOG_LEVEL" == "debug" ]] && log "⚠️ Seerr: Could not link '$(basename "$folder_path")' to an ID."
        return 1
    fi

    # 2. Search Seerr for open issues
    local response_file="/tmp/seerr_resp.json"
    curl -s -o "$response_file" -H "X-Api-Key: $api_key" "$base_url/issue?filter=open"

    # 3. Match Issue ID
    local issue_id=""
    if [[ "$media_type" == "movie" ]]; then
        issue_id=$(jq -r --arg tid "$lookup_id" '.results[]? | select(.media.tmdbId | tostring == $tid) | .id' "$response_file" | head -n 1)
    else
        # Try to match the specific season first, OR match Season 0 (General/Specials)
        issue_id=$(jq -r --arg tid "$lookup_id" --arg snum "$season_num" '
            .results[]? | 
            select(.media.tvdbId | tostring == $tid) |
            select((.problemSeason | tostring == $snum) or (.problemSeason | tostring == "0")) |
            .id' "$response_file" | head -n 1)
    fi

    # 4. Resolve and Rescan
    if [[ -n "$issue_id" && "$issue_id" != "null" ]]; then
        [[ "$LOG_LEVEL" == "debug" ]] && log "✅ Seerr: Found $media_type issue #$issue_id. Resolving..."
        curl -s -X POST "$base_url/issue/$issue_id/resolved" -H "X-Api-Key: $api_key" > /dev/null

        if [[ "$media_type" == "movie" ]]; then
            local r_id=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_API_BASE/movie" | jq -r --arg path "$folder_path" '.[] | select(.path == $path) | .id')
            curl -s -X POST "$RADARR_API_BASE/command" -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" -d "{\"name\": \"RescanMovie\", \"movieId\": $r_id}" > /dev/null
        else
            local s_id=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_API_BASE/series" | jq -r --arg path "$show_folder" '.[] | select(.path == $path) | .id')
            curl -s -X POST "$SONARR_API_BASE/command" -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" -d "{\"name\": \"RescanSeries\", \"seriesId\": $s_id}" > /dev/null
        fi
    else
        [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ Seerr: No matching open issues found for $media_type at $folder_path"
    fi
}
