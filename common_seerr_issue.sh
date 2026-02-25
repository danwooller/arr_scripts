sync_seerr_issue() {
    local media_name="$1"
    local media_type="$2"   # "tv" or "movie"
    local message="$3"      # Error details or missing ep list
    local media_id="$4"     # Optional Manual Map ID

    # 1. Get Seerr Media ID
    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        local search_term=$(echo "$media_name" | sed -E 's/\.[^.]*$//; s/[0-9]+x[0-9]+.*//i; s/\([0-9]{4}\)//g; s/[._]/ /g; s/ +/ /g')
        local encoded_query=$(echo "$search_term" | jq -Rr @uri)
        local search_results=$(curl -s -X GET "$SEERR_API_BASE/search?query=$encoded_query" -H "X-Api-Key: $SEERR_API_KEY")
        media_id=$(echo "$search_results" | jq -r --arg type "$media_type" '.results[] | select(.mediaType == $type).mediaInfo.id // empty' | head -n 1)
    fi

    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        log "⚠️  Seerr: Could not link '$media_name' to an ID."
        return 1
    fi

    # 2. Deduplication Check
    local existing_issues=$(curl -s -X GET "$SEERR_API_BASE/issue?take=100&filter=open" -H "X-Api-Key: $SEERR_API_KEY")
    local existing_data=$(echo "$existing_issues" | jq -r --arg mid "$media_id" \
        '.results[] | select(.media.id == ($mid|tonumber) and .issueType == 1) | "\(.id)|\(.message)"' | head -n 1)
    
    local issue_id=$(echo "$existing_data" | cut -d'|' -f1)
    local old_msg=$(echo "$existing_data" | cut -d'|' -f2)

    # 3. Resolution Logic
    if [[ -z "$message" ]]; then
        if [[ -n "$issue_id" ]]; then
            log "✅ RESOLVED: Marking Seerr issue #$issue_id for $media_name as resolved."
            curl -s -o /dev/null -X POST "$SEERR_API_BASE/issue/$issue_id/resolved" -H "X-Api-Key: $SEERR_API_KEY"
        fi
        return 0
    fi

    # 4. Change Detection (Episode-Only Comparison)
    if [[ -n "$issue_id" ]]; then
        # Extract episode codes (e.g., 2x08, 10x12) and normalize them
        local norm_old=$(echo "$old_msg" | grep -oE "[0-9]+x[0-9]+" | sort -u | xargs)
        local norm_new=$(echo "$message" | grep -oE "[0-9]+x[0-9]+" | sort -u | xargs)

        # If the list of missing episodes hasn't changed, exit quietly
        if [[ "$norm_old" == "$norm_new" && -n "$norm_new" ]]; then
            # log "ℹ️  No change in missing episodes for $media_name. Skipping."
            return 0 
        else
            # Only resolve if the episode list actually changed
            log "🔄 Change detected for $media_name. Updating Seerr issue..."
            curl -s -o /dev/null -X POST "$SEERR_API_BASE/issue/$issue_id/resolved" -H "X-Api-Key: $SEERR_API_KEY"
        fi
    fi

    # 5. Create New Issue (Crucial: Capture http_status)
    local json_payload=$(jq -n --arg mt "1" --arg msg "$message" --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')
    
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SEERR_API_BASE/issue" \
        -H "X-Api-Key: $SEERR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload")
    
    log "🚀 Seerr Issue created for $media_name."

    # 6. Trigger Arr Search
    # This now only runs once, using the robust path-matching logic
    if [[ -n "$message" ]]; then
        local target_url=""
        local target_key=""
        local instance_name=""
        local payload=""

        if [[ "$media_type" == "tv" ]]; then
            [[ "$media_name" =~ "4K" ]] && target_url="$SONARR4K_API_BASE" || target_url="$SONARR_API_BASE"
            [[ "$media_name" =~ "4K" ]] && target_key="$SONARR4K_API_KEY" || target_key="$SONARR_API_KEY"
            instance_name="Sonarr"

            local folder_name=$(basename "${media_name%/}")
            local s_data=$(curl -s -H "X-Api-Key: $target_key" "$target_url/series" | jq -r --arg folder "$folder_name" '
                .[] | ((.path | sub("/*$"; "")) | split("/") | last) as $sonarr_folder |
                select(($sonarr_folder | ascii_downcase) == ($folder | ascii_downcase)) | 
                "\(.id)|\(.monitored)"' | head -n 1)
            
            local s_id=$(echo "$s_data" | cut -d'|' -f1)
            local s_mon=$(echo "$s_data" | cut -d'|' -f2)

            if [[ -n "$s_id" && "$s_mon" == "true" ]]; then
                payload=$(jq -n --arg id "$s_id" '{name: "SeriesSearch", seriesId: ($id|tonumber)}')
            fi

        elif [[ "$media_type" == "movie" ]]; then
            [[ "$media_name" =~ "4K" ]] && target_url="$RADARR4K_API_BASE" || target_url="$RADARR_API_BASE"
            [[ "$media_name" =~ "4K" ]] && target_key="$RADARR4K_API_KEY" || target_key="$RADARR_API_KEY"
            instance_name="Radarr"

            local folder_name=$(basename "${media_name%/}")
            local r_data=$(curl -s -H "X-Api-Key: $target_key" "$target_url/movie" | jq -r --arg folder "$folder_name" '
                .[] | ((.path | sub("/*$"; "")) | split("/") | last) as $radarr_folder |
                select(($radarr_folder | ascii_downcase) == ($folder | ascii_downcase)) | 
                "\(.id)|\(.monitored)"' | head -n 1)
            
            local r_id=$(echo "$r_data" | cut -d'|' -f1)
            local r_mon=$(echo "$r_data" | cut -d'|' -f2)

            if [[ -n "$r_id" && "$r_mon" == "true" ]]; then
                payload=$(jq -n --arg id "$r_id" '{name: "MoviesSearch", movieIds: [($id|tonumber)]}')
            fi
        fi

        if [[ -n "$payload" ]]; then
            log "📡 $instance_name: Triggering search for '$media_name'..."
            curl -s -o /dev/null -X POST "$target_url/command" -H "X-Api-Key: $target_key" -H "Content-Type: application/json" -d "$payload"
        else
            log "⚠️  $instance_name: Could not find monitored entry for '$media_name'."
        fi
    fi
}
