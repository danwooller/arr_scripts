resolve_seerr_issue() {
    local media_name="$1"
    
    # 1. Clean variables
    local base_url=$(echo "$SEERR_API_BASE" | tr -d '\r' | sed 's|/*$||')
    local api_key=$(echo "$SEERR_API_KEY" | tr -d '\r' | xargs)

    # 2. Get TMDB ID
    local tmdb_id=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_API_BASE/movie" | \
        jq -r --arg folder "$media_name" '.[] | select(.path | endswith($folder)) | .tmdbId' | tr -d '\r')

    # 3. Corrected URL (Removed &limit=100)
    local full_url="${base_url}/issue?filter=open"

    # 4. Execute
    local response_file="/tmp/seerr_resp.json"
    local http_code=$(curl -s -o "$response_file" -w "%{http_code}" \
        -H "Accept: application/json" \
        -H "X-Api-Key: $api_key" \
        "$full_url")

    if [[ "$http_code" != "200" ]]; then
        log "❌ Seerr API Error: HTTP $http_code"
        log "   Response Body: $(cat "$response_file")"
        return 1
    fi

    # 5. Search for the ID anywhere in the response
    local issue_id=$(jq -r --arg tid "$tmdb_id" '.results[]? | select(tostring | contains($tid)) | .id' "$response_file" | head -n 1)

    if [[ -n "$issue_id" && "$issue_id" != "null" ]]; then
        log "✅ Seerr: Found Issue #$issue_id. Resolving..."
        curl -s -X POST "${base_url}/issue/$issue_id/resolved" -H "X-Api-Key: $api_key" > /dev/null

        # Radarr Rescan
        # 1. Get the Radarr Internal Movie ID
        local r_id=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_API_BASE/movie" | jq -r --arg folder "$media_name" '.[] | select(.path | endswith($folder)) | .id')

        if [[ -n "$r_id" ]]; then
            log "🎬 Radarr: Performing surgical rescan on Movie ID $r_id..."
            
            # 1. Force Disk Scan for THIS movie only
            # This makes Radarr look at the folder and find 'The Order.mkv'
            curl -s -X POST "$RADARR_API_BASE/command" \
                 -H "X-Api-Key: $RADARR_API_KEY" \
                 -H "Content-Type: application/json" \
                 -d "{\"name\": \"RescanMovie\", \"movieId\": $r_id}" > /dev/null

            # 2. Refresh the UI status for THIS movie only
            curl -s -X POST "$RADARR_API_BASE/command" \
                 -H "X-Api-Key: $RADARR_API_KEY" \
                 -H "Content-Type: application/json" \
                 -d "{\"name\": \"RefreshMovie\", \"movieId\": $r_id}" > /dev/null
        fi
    else
        log "ℹ️ Seerr: No open issues found for TMDB $tmdb_id."
    fi
}

sync_seerr_issue() {
    local media_name="$1"
    local media_type="$2"   # "tv" or "movie"
    local message="$3"      # Error details or missing ep list
    local media_id="$4"     # Optional Manual Map ID

    # 1. Trigger Arr Search
    # This now only runs once, using the robust path-matching logic
    if [[ -n "$message" ]]; then
        # --- Sonarr Logic (TV) ---
        if [[ "$media_type" == "tv" ]]; then
            local target_url="$SONARR_API_BASE"
            local target_key="$SONARR_API_KEY"
            [[ "$media_name" =~ "4K" ]] && target_url="$SONARR4K_API_BASE" && target_key="$SONARR4K_API_KEY"

            # 1. Get Series ID
            local s_id=$(curl -s -H "X-Api-Key: $target_key" "$target_url/series" | jq -r --arg folder "$media_name" '
                .[] | ((.path | sub("/*$"; "")) | split("/") | last) as $sonarr_folder |
                select(($sonarr_folder | ascii_downcase) == ($folder | ascii_downcase)) | .id')

            if [[ -n "$s_id" ]]; then
                # 2. Check if this is a CORRUPTION event (message contains "CORRUPT:")
                if [[ "$message" == *"CORRUPT:"* ]]; then
                    # Extract filename from message
                    local corrupt_filename=$(echo "$message" | grep -oP '(?<=CORRUPT: ).*?(?=\ \()')
                    
                    log "📡 Sonarr: Identifying specific file record for purge..."
                    local ep_file_id=$(curl -s -H "X-Api-Key: $target_key" "$target_url/episodefile?seriesId=$s_id" | \
                        jq -r --arg fname "$corrupt_filename" '.[] | select(.relativePath | contains($fname)) | .id')
                    
                    if [[ -n "$ep_file_id" ]]; then
                        log "🗑️  Sonarr: Purging file record (ID: $ep_file_id) for '$corrupt_filename'..."
                        curl -s -X DELETE "$target_url/episodefile/$ep_file_id" -H "X-Api-Key: $target_key"
                        sleep 2
                    fi
                fi

                # 3. Trigger Search (Always safe for monitored items)
                # If we have no specific episode ID from a purge, we search the series for missing items
                log "📡 Sonarr: Triggering search for missing monitored episodes in '$media_name'..."
                curl -s -o /dev/null -X POST "$target_url/command" -H "X-Api-Key: $target_key" -H "Content-Type: application/json" \
                     -d "{\"name\": \"SeriesSearch\", \"seriesId\": $s_id}"
            fi
        fi # End TV Block

        # --- Radarr Logic (Movie) ---
        if [[ "$media_type" == "movie" ]]; then
            local target_url="$RADARR_API_BASE"
            local target_key="$RADARR_API_KEY"
            [[ "$media_name" =~ "4K" ]] && target_url="$RADARR4K_API_BASE" && target_key="$RADARR4K_API_KEY"

            # Get ID
            local r_data=$(curl -s -H "X-Api-Key: $target_key" "$target_url/movie" | jq -r --arg folder "$media_name" '
                .[] | ((.path | sub("/*$"; "")) | split("/") | last) as $radarr_folder |
                select(($radarr_folder | ascii_downcase) == ($folder | ascii_downcase)) | 
                "\(.id)|\(.monitored)"' | head -n 1)

            local r_id=$(echo "$r_data" | cut -d'|' -f1 | tr -d '[:space:]')
            local r_mon=$(echo "$r_data" | cut -d'|' -f2 | tr -d '[:space:]')

            if [[ -n "$r_id" && "$r_mon" == "true" ]]; then
                log "📡 Radarr: Cleaning database for '$media_name' (ID: $r_id)..."

                # 1. Get the File ID from the movie data
                local file_id=$(curl -s -H "X-Api-Key: $target_key" "$target_url/movie/$r_id" | jq -r '.movieFile.id // empty')

                # 2. If a file record exists in Radarr, tell Radarr to delete it
                if [[ -n "$file_id" ]]; then
                    log "🗑️  Radarr: Removing file record (FileID: $file_id) to force 'Missing' status..."
                    curl -s -X DELETE "$target_url/moviefile/$file_id" -H "X-Api-Key: $target_key"
                    sleep 2
                fi

                # 3. Now trigger the search
                log "📡 Radarr: Status is now officially 'Missing'. Triggering search..."
                curl -s -o /dev/null -X POST "$target_url/command" -H "X-Api-Key: $target_key" -H "Content-Type: application/json" \
                     -d "{\"name\": \"MoviesSearch\", \"movieIds\": [$r_id]}"
            else
                log "⚠️  Radarr: Could not find movie entry for '$media_name'."
            fi
        fi # End Movie Block
    fi

    # 2. Get Seerr Media ID
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

    # 3. Deduplication Check
    #    local existing_issues=$(curl -s -X GET "$SEERR_API_BASE/issue?take=100&filter=open" -H "X-Api-Key: $SEERR_API_KEY")   
    # NEW JQ: Extract the first comment's message
#    local existing_data=$(echo "$existing_issues" | jq -r --arg mid "$media_id" '
#        .results[] | 
#        select(.media.id == ($mid|tonumber)) | 
#        "\(.id)|\(.comments[0].message // "")"' | head -n 1)
#    local issue_id=$(echo "$existing_data" | cut -d'|' -f1)
#    local old_msg=$(echo "$existing_data" | cut -d'|' -f2-)
    local existing_issues=$(curl -s -X GET "$SEERR_API_BASE/issue?take=100&filter=open" -H "X-Api-Key: $SEERR_API_KEY")
    # Check if an issue ID exists for this specific Media ID
    local issue_id=$(echo "$existing_issues" | jq -r --arg mid "$media_id" '
        .results[] | select(.media.id == ($mid|tonumber)) | .id' | head -n 1)

    if [[ -n "$issue_id" ]]; then
        log "🔄 Seerr: Issue #$issue_id already open for Media ID $media_id. Updating..."
        
        # Add the new message as a comment so you have a history of the errors
        curl -s -X POST "$SEERR_API_BASE/issue/$issue_id/comment" \
            -H "X-Api-Key: $SEERR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"message\": \"$message\"}"
            
        return 0 # CRITICAL: Exit here so we don't create a second issue!
    fi

    # 4. Resolution Logic
    if [[ -z "$message" ]]; then
        if [[ -n "$issue_id" ]]; then
            log "✅ RESOLVED: Marking Seerr issue #$issue_id for $media_name as resolved."
            curl -s -o /dev/null -X POST "$SEERR_API_BASE/issue/$issue_id/resolved" -H "X-Api-Key: $SEERR_API_KEY"
        fi
        return 0
    fi

    # 5. Change Detection
    if [[ -n "$issue_id" ]]; then
        # If old_msg came back empty from JQ, we need to know
        if [[ -z "$old_msg" || "$old_msg" == "null" ]]; then
             log "⚠️  Warning: Found issue #$issue_id but could not read the message from Seerr."
        fi

        local norm_old=$(echo "$old_msg" | grep -oE "[0-9]+x[0-9]+" | sort -V | xargs | tr -d '\r\n')
        local norm_new=$(echo "$message" | grep -oE "[0-9]+x[0-9]+" | sort -V | xargs | tr -d '\r\n')

        if [[ "$norm_old" == "$norm_new" && -n "$norm_new" ]]; then
            return 0 
        else
            log "🔄 Change detected for $media_name ($norm_old -> $norm_new). Updating Seerr issue..."
            curl -s -o /dev/null -X POST "$SEERR_API_BASE/issue/$issue_id/resolved" -H "X-Api-Key: $SEERR_API_KEY"
        fi
    fi

    # 6. Create New Issue (Crucial: Capture http_status)
    local json_payload=$(jq -n --arg mt "1" --arg msg "$message" --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')
    
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SEERR_API_BASE/issue" \
        -H "X-Api-Key: $SEERR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload")
    
    log "🚀 Seerr Issue created for $media_name."
}
