# --- Consolidated Seerr Sync & Search Function ---
sync_seerr_issue() {

	local media_name="$1"
    local media_type="$2"
    local issue_msg="$3"
    local media_id="$4"
    local target_status="${5:-1}" # Default to 1 (Open) if not specified

    # ---------------------------------------------

    # 1. Get Seerr Media ID if not provided
    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        local search_term=$(echo "$media_name" | sed -E 's/\([0-9]{4}\)//g; s/[._]/ /g; s/ +/ /g')
        local encoded_query=$(echo "$search_term" | jq -Rr @uri)
        
        # Build the URL using our local 'search_api' variable
        local full_url="${search_api%/}/search?query=${encoded_query}"

	# Perform the Search
        local search_results=$(curl -s -X GET "$full_url" -H "X-Api-Key: $api_key")
        
        # Robust Extraction
        media_id=$(echo "$search_results" | jq -r '
            .results | .[] | 
            select(.mediaType | test("tv|series"; "i")) | 
            (.mediaInfo.id // .id)
        ' | head -n 1)

        # Cleanup: Ensure we don't return the string "null"
        [[ "$media_id" == "null" ]] && media_id=""
    fi

	# 2. Check for existing issue
	local existing_issue=$(curl -s -X GET "${SEERR_API_ISSUES}/issue?mediaId=${media_id}&status=open" \
        -H "X-Api-Key: $SEERR_API_KEY" | jq -r '.results[0].id // empty')

    if [[ -n "$existing_issue" ]]; then
        if [[ "$target_status" == "3" ]]; then
            # Resolve the issue with the exclusion comment
            curl -s -X POST "${SEERR_API_ISSUES}/issue/$existing_issue/comment" \
                -H "X-Api-Key: $SEERR_API_KEY" -H "Content-Type: application/json" \
                -d "{\"message\": \"$issue_msg\"}"
                
            curl -s -X POST "${SEERR_API_ISSUES}/issue/$existing_issue/resolved" \
                -H "X-Api-Key: $SEERR_API_KEY"
            
            log "✅ RESOLVED: Closed Seerr issue #$existing_issue for $media_name ($issue_msg)."
        fi
    fi

    # 3. Deduplication Check
    local existing_issues=$(curl -s -X GET "$SEERR_API_ISSUES/issue?take=100&filter=open" -H "X-Api-Key: $SEERR_API_KEY")
    local existing_data=$(echo "$existing_issues" | jq -r --arg mid "$media_id" \
        '.results[] | select(.media.id == ($mid|tonumber) and .issueType == 1) | "\(.id)|\(.message)"' | head -n 1)
    
    local issue_id=$(echo "$existing_data" | cut -d'|' -f1)
    local old_msg=$(echo "$existing_data" | cut -d'|' -f2)

    # 4. Resolution Logic
    if [[ -z "$message" ]]; then
        if [[ -n "$issue_id" ]]; then
            log "✅ RESOLVED: Marking Seerr issue #$issue_id for $media_name as resolved."
            # Changed from DELETE to POST and updated the URL endpoint
            curl -s -o /dev/null -X POST "$SEERR_API_ISSUES/issue/$issue_id/resolved" -H "X-Api-Key: $SEERR_API_KEY"
        fi
        return 0
    fi

    # 5. Change Detection
    if [[ -n "$issue_id" ]]; then
        local norm_old=$(echo "$old_msg" | grep -oE "[0-9]+x[0-9]+" | sort | xargs)
        local norm_new=$(echo "$message" | grep -oE "[0-9]+x[0-9]+" | sort | xargs)

    if [[ "$norm_old" == "$norm_new" && -n "$norm_new" ]]; then
            return 0 # No change in episode list
        else
            # Changed from DELETE to POST/resolved
            curl -s -o /dev/null -X POST "$SEERR_API_ISSUES/issue/$issue_id/resolved" -H "X-Api-Key: $SEERR_API_KEY"
        fi
    fi

    # 6. Create New Issue
    local json_payload=$(jq -n --arg mt "1" --arg msg "$message" --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')
    curl -s -o /dev/null -X POST "$SEERR_API_ISSUES/issue" -H "X-Api-Key: $SEERR_API_KEY" -H "Content-Type: application/json" -d "$json_payload"
    log "🚀 Seerr Issue created for $media_name."

    # 6. Trigger Arr Search (Smart Instance Detection)
    local target_url=""
    local target_key=""
    local instance_name=""
    local payload=""

    if [[ "$media_type" == "tv" ]]; then
        if [[ "$message" =~ "4K" || "$TARGET_DIR" =~ "4K" ]]; then
            target_url="$SONARR4K_API_BASE"
            target_key="$SONARR4K_API_KEY"
            instance_name="Sonarr 4K"
        else
            target_url="$SONARR_API_BASE"
            target_key="$SONARR_API_KEY"
            instance_name="Sonarr"
        fi
        
        local s_data=$(curl -s -H "X-Api-Key: $target_key" "$target_url/series" | jq -r --arg name "$media_name" '.[] | select(.title == $name or .path == $name) | "\(.id)|\(.monitored)"' | head -n 1)
        local s_id=$(echo "$s_data" | cut -d'|' -f1)
        local s_mon=$(echo "$s_data" | cut -d'|' -f2)

        if [[ -n "$s_id" && "$s_mon" == "true" ]]; then
            payload=$(jq -n --arg id "$s_id" '{name: "SeriesSearch", seriesId: ($id|tonumber)}')
        fi

    elif [[ "$media_type" == "movie" ]]; then
        if [[ "$message" =~ "4K" || "$TARGET_DIR" =~ "4K" ]]; then
            target_url="$RADARR4K_API_BASE"
            target_key="$RADARR4K_API_KEY"
            instance_name="Radarr 4K"
        else
            target_url="$RADARR_API_BASE"
            target_key="$RADARR_API_KEY"
            instance_name="Radarr"
        fi
        
        local r_data=$(curl -s -H "X-Api-Key: $target_key" "$target_url/movie" | jq -r --arg name "$media_name" '.[] | select(.title == $name or .path == $name) | "\(.id)|\(.monitored)"' | head -n 1)
        local r_id=$(echo "$r_data" | cut -d'|' -f1)
        local r_mon=$(echo "$r_data" | cut -d'|' -f2)

        if [[ -n "$r_id" && "$r_mon" == "true" ]]; then
            payload=$(jq -n --arg id "$r_id" '{name: "MoviesSearch", movieIds: [($id|tonumber)]}')
        fi
    fi

    # Execute Search if payload was built
    if [[ -n "$payload" ]]; then
        log "📡 $instance_name: Triggering search for '$media_name'..."
        curl -s -o /dev/null -X POST "$target_url/command" \
            -H "X-Api-Key: $target_key" \
            -H "Content-Type: application/json" \
            -d "$payload"
    elif [[ -n "$instance_name" ]]; then
        log "⚠️  $instance_name: Could not find monitored entry for '$media_name' to trigger search."
    fi
}
