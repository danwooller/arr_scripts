# --- Consolidated Seerr Sync & Search Function ---
sync_seerr_issue() {
    local media_name="$1"
    local media_type="$2"   # "tv" or "movie"
    local message="$3"      # Error details or missing ep list
    local media_id="$4"     # Optional Manual Map ID

    # 1. Get Seerr Media ID
    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        local search_term=$(echo "$media_name" | sed -E 's/\.[^.]*$//; s/[0-9]+x[0-9]+.*//i; s/\([0-9]{4}\)//g; s/[._]/ /g; s/ +/ /g')
        local encoded_query=$(echo "$search_term" | jq -Rr @uri)
        local search_results=$(curl -s -X GET "$SEERR_URL/api/v1/search?query=$encoded_query" -H "X-Api-Key: $SEERR_API_KEY")
        media_id=$(echo "$search_results" | jq -r --arg type "$media_type" '.results[] | select(.mediaType == $type).mediaInfo.id // empty' | head -n 1)
    fi

    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        log "⚠️  Seerr: Could not link '$media_name' to an ID."
        return 1
    fi

    # 2. Deduplication Check
    local existing_issues=$(curl -s -X GET "$SEERR_URL/api/v1/issue?take=100&filter=open" -H "X-Api-Key: $SEERR_API_KEY")
    local existing_data=$(echo "$existing_issues" | jq -r --arg mid "$media_id" \
        '.results[] | select(.media.id == ($mid|tonumber) and .issueType == 1) | "\(.id)|\(.message)"' | head -n 1)
    
    local issue_id=$(echo "$existing_data" | cut -d'|' -f1)
    local old_msg=$(echo "$existing_data" | cut -d'|' -f2)

    # 3. Resolution Logic
    if [[ -z "$message" ]]; then
        if [[ -n "$issue_id" ]]; then
            log "✅ RESOLVED: Closing Seerr issue #$issue_id for $media_name."
            curl -s -X DELETE "$SEERR_URL/api/v1/issue/$issue_id" -H "X-Api-Key: $SEERR_API_KEY"
        fi
        return 0
    fi

    # 4. Change Detection
    if [[ -n "$issue_id" ]]; then
        local norm_old=$(echo "$old_msg" | grep -oE "[0-9]+x[0-9]+" | sort | xargs)
        local norm_new=$(echo "$message" | grep -oE "[0-9]+x[0-9]+" | sort | xargs)

        if [[ "$norm_old" == "$norm_new" && -n "$norm_new" ]]; then
            return 0 # No change in episode list
        else
            curl -s -X DELETE "$SEERR_URL/api/v1/issue/$issue_id" -H "X-Api-Key: $SEERR_API_KEY"
        fi
    fi

    # 5. Create New Issue
    local json_payload=$(jq -n --arg mt "1" --arg msg "$message" --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')
    curl -s -X POST "$SEERR_URL/api/v1/issue" -H "X-Api-Key: $SEERR_API_KEY" -H "Content-Type: application/json" -d "$json_payload" > /dev/null
    log "🚀 Seerr Issue created for $media_name."

    # 6. Trigger Arr Search
    if [[ "$media_type" == "tv" ]]; then
        local sonarr_series=$(curl -s -X GET "$SONARR_URL/api/v3/series" -H "X-Api-Key: $SONARR_API_KEY")
        local s_data=$(echo "$sonarr_series" | jq -r --arg name "$media_name" '.[] | select(.title == $name or .path == $name) | "\(.id)|\(.monitored)"' | head -n 1)
        if [[ "$(echo "$s_data" | cut -d'|' -f2)" == "true" ]]; then
            local s_id=$(echo "$s_data" | cut -d'|' -f1)
            log "🔍 Sonarr: Triggering search for $media_name..."
            curl -s -X POST "$SONARR_URL/api/v3/command" -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
                -d "$(jq -n --arg id "$s_id" '{name: "SeriesSearch", seriesId: ($id|tonumber)}')" > /dev/null
        fi
    elif [[ "$media_type" == "movie" ]]; then
        local radarr_movies=$(curl -s -X GET "$RADARR_URL/api/v3/movie" -H "X-Api-Key: $RADARR_API_KEY")
        local r_data=$(echo "$radarr_movies" | jq -r --arg name "$media_name" '.[] | select(.title == $name or .path == $name) | "\(.id)|\(.monitored)"' | head -n 1)
        if [[ "$(echo "$r_data" | cut -d'|' -f2)" == "true" ]]; then
            local r_id=$(echo "$r_data" | cut -d'|' -f1)
            log "🔍 Radarr: Triggering search for $media_name..."
            curl -s -X POST "$RADARR_URL/api/v3/command" -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
                -d "$(jq -n --arg id "$r_id" '{name: "MoviesSearch", movieIds: [($id|tonumber)]}')" > /dev/null
        fi
    fi
}
