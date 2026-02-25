# --- Consolidated Seerr Sync & Search Function ---
sync_seerr_issue() {
    local media_name="$1"
    local media_type="$2"  # 'tv' or 'movie'
    local issue_msg="$3"
    local media_id="$4"
    local target_status="${5:-1}"

    # --- THE TRUTH BLOCK ---
    # We are hard-coding these here to bypass the broken variable logic
    local s_key="1740497542629daf0528f-86cf-46f9-a891-8e30e1cf76f9"
    local s_url="http://192.168.0.24:5055/api/v3"
    # -----------------------

    # 1. FIND THE MEDIA ID
    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        local search_term=$(echo "$media_name" | sed -E 's/\([0-9]{4}\)//g; s/[._]/ /g; s/ +/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        local encoded_query=$(echo -n "$search_term" | jq -sRr @uri | tr -d '\r\n')
        local search_url="$s_url/search?query=${encoded_query}"

        local search_results=$(curl -s -X GET "$search_url" -H "X-Api-Key: $s_key" -H "Accept: application/json")
        
        # Extract ID (Filtering for TV specifically if it's a TV show)
        media_id=$(echo "$search_results" | jq -r --arg type "$media_type" '.results // [] | .[] | select(.mediaType == $type) | (.mediaInfo.id // .id) // empty' 2>/dev/null | head -n 1)
        
        if [[ -z "$media_id" || "$media_id" == "null" ]]; then
            log "⚠️ Seerr: Could not find ID for '$media_name' at $search_url"
            return 1
        fi
    fi

    # 2. CHECK FOR EXISTING ISSUES
    local issues_url="$s_url/issue?take=100&filter=open"
    local existing_issue=$(curl -s -X GET "$issues_url" -H "X-Api-Key: $s_key" | jq -r --arg id "$media_id" '.results[] | select(.media.id == ($id|tonumber)) | .id' 2>/dev/null | head -n 1)

    if [[ -n "$existing_issue" && "$existing_issue" != "null" ]]; then
        log "✅ Seerr: Issue #$existing_issue already exists for '$media_name' (ID: $media_id)."
        return 0
    fi

    # 3. CREATE THE ISSUE
    local create_url="$s_url/issue"
    local json_payload=$(jq -n --arg id "$media_id" --arg msg "$issue_msg" --arg type "$media_type" \
        '{mediaId: ($id|tonumber), issueType: 1, message: $msg, mediaType: $type}')

    local response=$(curl -s -X POST "$create_url" \
        -H "X-Api-Key: $s_key" \
        -H "Content-Type: application/json" \
        -d "$json_payload")

    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        local new_id=$(echo "$response" | jq -r '.id')
        log "🎫 Seerr: Created issue #$new_id for '$media_name'."
    else
        log "❌ Seerr: Failed to create issue for '$media_name'. Response: $response"
    fi
}
