# --- Consolidated Seerr Sync & Search Function ---
sync_seerr_issue() {
    local media_name="$1"
    local media_type="$2"
    local issue_msg="$3"    # This is the message passed from the script
    local media_id="$4"
    local target_status="${5:-1}" # Default to 1 (Open) if not specified

    # 1. Get Seerr Media ID if not provided
    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        local search_term=$(echo "$media_name" | sed -E 's/\([0-9]{4}\)//g; s/[._]/ /g; s/ +/ /g')
        local encoded_query=$(echo "$search_term" | jq -Rr @uri)
        
        # Build the URL using the exported global from common_keys.txt
        local full_url="${SEERR_API_SEARCH}/search?query=${encoded_query}"

        # Perform the Search using the global API Key
        local search_results=$(curl -s -X GET "$full_url" -H "X-Api-Key: $SEERR_API_KEY")
        
        # Safeguard: If search_results is empty, stop here to avoid jq errors
        if [[ -z "$search_results" ]]; then
            log "⚠️ Seerr: API search returned nothing for '$media_name'."
            return 1
        fi

        # Robust Extraction
        media_id=$(echo "$search_results" | jq -r '
            .results | .[] | 
            select(.mediaType | test("tv|series"; "i")) | 
            (.mediaInfo.id // .id)
        ' | head -n 1)

        # Cleanup: Ensure we don't return the string "null"
        [[ "$media_id" == "null" || -z "$media_id" ]] && media_id=""
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

    # 7. Trigger Arr Search Logic... (The rest of your existing Sonarr/Radarr logic)
    # Ensure you use $media_name and $issue_msg here
}
