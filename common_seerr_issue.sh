# --- Consolidated Seerr Sync & Search Function ---
sync_seerr_issue() {
    local media_name="$1"
    local media_type="$2"
    local issue_msg="$3"
    local media_id="$4"
    local target_status="${5:-1}"

    # 1. FORCE LOAD AND CLEAN RIGHT HERE
    # We use grep and sed to pull the raw value directly from the file, 
    # bypassing any shell environment issues.
    local s_key=$(grep "SEERR_API_KEY" /usr/local/bin/common_keys.txt | cut -d'"' -f2 | tr -d '\r\n[:space:]')
    local s_url=$(grep "SEERR_URL" /usr/local/bin/common_keys.txt | cut -d'"' -f2 | head -n 1 | tr -d '\r\n[:space:]')
    
    # Fallback if the grep fails
    [[ -z "$s_key" ]] && s_key="$SEERR_API_KEY"
    [[ -z "$s_base" ]] && s_base="${SEERR_URL%/}"

    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        local search_term=$(echo "$media_name" | sed -E 's/\([0-9]{4}\)//g; s/[._]/ /g; s/ +/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        local encoded_query=$(echo -n "$search_term" | jq -sRr @uri | tr -d '\r\n')
        local full_url="${s_url%/}/api/v3/search?query=${encoded_query}"

        # 2. Use the forced local variable
        local search_results=$(curl -s -X GET "$full_url" -H "X-Api-Key: $s_key" -H "Accept: application/json")

        if [[ -z "$search_results" || "$search_results" == *"<html>"* ]]; then
            local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X GET "$full_url" -H "X-Api-Key: $s_key")
            log "⚠️ Seerr Fail (HTTP $http_code) for '$media_name'."
            return 1
        fi
        
        media_id=$(echo "$search_results" | jq -r '.results // [] | .[] | select(.mediaType == "tv") | (.mediaInfo.id // .id) // empty' 2>/dev/null | head -n 1)
    fi

    # 1. Get Seerr Media ID if not provided
    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        # 1. Aggressive cleaning of the search term (No xargs to avoid quote crashes)
        local search_term=$(echo "$media_name" | sed -E 's/\([0-9]{4}\)//g; s/[._]/ /g; s/ +/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 2. Encode query
        local encoded_query=$(echo -n "$search_term" | jq -sRr @uri | tr -d '\r\n')
        
        # 3. Force-scrub the Key and URL right before use
        local s_key=$(echo "$SEERR_API_KEY" | tr -d '\r\n[:space:]')
        local s_url=$(echo "$SEERR_API_SEARCH" | tr -d '\r\n[:space:]')
        local full_url="${s_url%/}/search?query=${encoded_query}"

        # 4. Perform the search
        local search_results=$(curl -s -f -X GET "$full_url" -H "X-Api-Key: $s_key")

        if [[ -z "$search_results" ]]; then
            # GET THE ACTUAL HTTP CODE
            local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X GET "$full_url" -H "X-Api-Key: $s_key")
            
            # DEBUG: This will tell us if the key is empty
            if [[ -z "$s_key" ]]; then
                log "❌ CRITICAL: SEERR_API_KEY is EMPTY inside the function!"
            else
                log "⚠️ Seerr: API failed for '$media_name' (HTTP: $http_code)."
            fi
            return 1
        fi
        
        # 5. Extract ID
        media_id=$(echo "$search_results" | jq -r '.results // [] | .[] | select(.mediaType == "tv") | (.mediaInfo.id // .id) // empty' | head -n 1)
    fi

    # If we still don't have a media_id, we can't do anything else
    if [[ -z "$media_id" ]]; then
        log "⚠️ Seerr: Could not link '$media_name' to an ID."
        return 1
    fi

    # 2. Check for existing issue
    local existing_issue=$(curl -s -X GET "${SEERR_API_ISSUES}/issue?mediaId=${media_id}&status=open" \
        -H "X-Api-Key: $SEERR_API_KEY" | jq -r '.results[0].id // empty')

    # 3. If target_status is 3 (Resolved), handle exclusion closure
    if [[ "$target_status" == "3" ]]; then
        if [[ -n "$existing_issue" ]]; then
            # Add comment
            curl -s -X POST "${SEERR_API_ISSUES}/issue/$existing_issue/comment" \
                -H "X-Api-Key: $SEERR_API_KEY" -H "Content-Type: application/json" \
                -d "{\"message\": \"$issue_msg\"}"
            # Mark Resolved
            curl -s -X POST "${SEERR_API_ISSUES}/issue/$existing_issue/resolved" \
                -H "X-Api-Key: $SEERR_API_KEY"
            log "✅ RESOLVED: Closed Seerr issue #$existing_issue for $media_name ($issue_msg)."
        fi
        return 0
    fi

    # 4. Process existing issue (Resolution if message is empty)
    if [[ -z "$issue_msg" ]]; then
        if [[ -n "$existing_issue" ]]; then
            log "✅ RESOLVED: Marking Seerr issue #$existing_issue for $media_name as resolved."
            curl -s -o /dev/null -X POST "$SEERR_API_ISSUES/issue/$existing_issue/resolved" -H "X-Api-Key: $SEERR_API_KEY"
        fi
        return 0
    fi

    # 5. Change Detection / Deduplication
    if [[ -n "$existing_issue" ]]; then
        local old_msg=$(curl -s -X GET "$SEERR_API_ISSUES/issue/$existing_issue" -H "X-Api-Key: $SEERR_API_KEY" | jq -r '.message // ""')
        
        local norm_old=$(echo "$old_msg" | grep -oE "[0-9]+x[0-9]+" | sort | xargs)
        local norm_new=$(echo "$issue_msg" | grep -oE "[0-9]+x[0-9]+" | sort | xargs)

        if [[ "$norm_old" == "$norm_new" && -n "$norm_new" ]]; then
            return 0 # No change, keep existing issue
        else
            # Message changed, resolve old one to create fresh one
            curl -s -o /dev/null -X POST "$SEERR_API_ISSUES/issue/$existing_issue/resolved" -H "X-Api-Key: $SEERR_API_KEY"
        fi
    fi

    # 6. Create New Issue
    local json_payload=$(jq -n --arg mt "1" --arg msg "$issue_msg" --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')
    
    curl -s -o /dev/null -X POST "$SEERR_API_ISSUES/issue" \
        -H "X-Api-Key: $SEERR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload"
    log "🚀 Seerr Issue created for $media_name."

# 7. Trigger Arr Search (Smart Instance Detection)
    local target_url=""
    local target_key=""
    local instance_name=""
    local payload=""

    if [[ "$media_type" == "tv" ]]; then
        # Check if it's a 4K show based on path or message
        if [[ "$issue_msg" =~ "4K" || "$TARGET_DIR" =~ "4K" ]]; then
            target_url="$SONARR4K_API_BASE"
            target_key="$SONARR4K_API_KEY"
            instance_name="Sonarr 4K"
        else
            target_url="$SONARR_API_BASE"
            target_key="$SONARR_API_KEY"
            instance_name="Sonarr"
        fi
        
        # Verify show is monitored in Sonarr before searching
        local s_data=$(curl -s -H "X-Api-Key: $target_key" "$target_url/series" | jq -r --arg name "$media_name" '.[] | select(.title == $name or .path == $name) | "\(.id)|\(.monitored)"' | head -n 1)
        local s_id=$(echo "$s_data" | cut -d'|' -f1)
        local s_mon=$(echo "$s_data" | cut -d'|' -f2)

        if [[ -n "$s_id" && "$s_mon" == "true" ]]; then
            payload=$(jq -n --arg id "$s_id" '{name: "SeriesSearch", seriesId: ($id|tonumber)}')
        fi

    elif [[ "$media_type" == "movie" ]]; then
        if [[ "$issue_msg" =~ "4K" || "$TARGET_DIR" =~ "4K" ]]; then
            target_url="$RADARR4K_API_BASE"
            target_key="$RADARR4K_API_KEY"
            instance_name="Radarr 4K"
        else
            target_url="$RADARR_API_BASE"
            target_key="$RADARR_API_KEY"
            instance_name="Radarr"
        fi
        
        # Verify movie is monitored in Radarr before searching
        local r_data=$(curl -s -H "X-Api-Key: $target_key" "$target_url/movie" | jq -r --arg name "$media_name" '.[] | select(.title == $name or .path == $name) | "\(.id)|\(.monitored)"' | head -n 1)
        local r_id=$(echo "$r_data" | cut -d'|' -f1)
        local r_mon=$(echo "$r_data" | cut -d'|' -f2)

        if [[ -n "$r_id" && "$r_mon" == "true" ]]; then
            payload=$(jq -n --arg id "$r_id" '{name: "MoviesSearch", movieIds: [($id|tonumber)]}')
        fi
    fi

    # Execute the Search Command
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
