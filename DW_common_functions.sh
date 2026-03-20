#!/bin/bash

HOST=$(hostname -s)

# --- Shared Logging Function ---
log() {

    # 1. Force the path if the variable is missing/empty
    local target_log="${LOG_FILE:-/mnt/media/torrent/ubuntu24.log}"
    
    # 2. Format the message
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local script_name="${0##*/}"
    
    # 3. Use 'stdbuf' to ensure the line is written to disk immediately
    # and 'tee -a' to send it to both the Docker Log and the physical file
    echo "[$timestamp] ($script_name) $1" | stdbuf -oL tee -a "$target_log"

}

log_start() {
    local target_path="$1"
    # If no path is provided, don't show the "in: ..." part
    if [[ -n "$target_path" ]]; then
        log "🚀 Starting in: $target_path"
    else
        log "🚀 Starting"
    fi
}

log_end() {
    local target_path="$1"
    # If no path is provided, don't show the "in: ..." part
    if [[ -n "$target_path" ]]; then
       log "🏁 Complete in: $target_path"
    else
        log "🏁 Complete"
    fi
}

# Universal Graceful Exit
#trap "log '🛑 Process interrupted by user (SIGINT/SIGTERM).'; exit 1" SIGINT SIGTERM
cleanup() {
    if [ -f "$LOCK_FILE" ]; then
        log "🛑 Service stopping. Removing lock file."
        rm -f "$LOCK_FILE"
    else
        log "🛑 Service stopping."
    fi
    exit
}
trap cleanup SIGTERM SIGINT

# --- Load External Configuration ---
CONFIG_FILE="/usr/local/bin/common_keys.txt"
if [[ -f "$CONFIG_FILE" ]]; then
    source <(sed 's/\r$//' "$CONFIG_FILE")
    # Source the file, but strip any trailing Windows CR characters on the fly
else
    log "WARN: Config file $CONFIG_FILE not found."
fi

check_dependencies() {
    local missing_deps=()
    # Initializes an empty array to store the names of any tools not found on the system.
    
    for dep in "$@"; do
    # Loops through every argument passed to the function (e.g., "jq", "curl", "mkvmerge").
        if ! command -v "$dep" >/dev/null 2>&1; then
        # Checks if the command exists in the system PATH; redirects output to 'null' to keep the terminal clean.
            missing_deps+=("$dep")
            # If the command is NOT found, adds that specific tool name to the missing_deps array.
        else
            [[ $LOG_LEVEL == "debug" ]] && log "ℹ️ '$dep' is ready."
            # If the tool IS found and you have debug logging enabled, it records that the dependency is satisfied.
        fi
    done

    # If there are missing dependencies, handle them in one go
    if [ ${#missing_deps[@]} -gt 0 ]; then
    # Checks if the count of items in the missing_deps array is greater than zero.
        log "Missing dependencies: ${missing_deps[*]}"
        # Logs the list of all missing tools in a single line.
        log "Attempting to install missing packages..."
        # Informs the user that the script is about to try and fix the problem automatically.
        
        # Note: Package names don't always match command names (e.g., HandBrakeCLI vs handbrake-cli)
        # This logic attempts to install the command name, but may need manual overrides
        sudo apt-get update && sudo apt-get install -y "${missing_deps[@]}"
        # Refreshes the package list and attempts to install the missing tools using the Debian/Ubuntu package manager.
        
        # Final verification
        for dep in "${missing_deps[@]}"; do
        # Loops back through the list of tools that were just supposedly installed.
            if ! command -v "$dep" >/dev/null 2>&1; then
            # Re-checks if the command is now available in the system PATH.
                log "❌ Critical Error: Failed to install '$dep'. Script exiting."
                # Logs a failure message if the 'apt-get' command didn't actually provide the required tool.
                exit 1
                # Terminates the entire script with an error code to prevent it from crashing later during execution.
            fi
        done
    fi
}

ha_update_status() {
    # DW_check_media_stack.sh
    local service_name=$1
    # Assigns the human-readable name of the service (e.g., "Radarr" or "Plex") to a local variable.
    local status=$2 # Expects "online" or "offline"
    # Assigns the current state of the service passed from the script to a local variable.
    local icon="mdi:server"
    # Sets a default Material Design Icon for the sensor in case the status check fails.
    [[ "$status" == "online" ]] && icon="mdi:check-circle" || icon="mdi:alert-circle"
    # A shorthand IF/ELSE: If status is 'online', use a green check; otherwise, use a red alert icon.
    curl -X POST -H "Authorization: Bearer $HA_TOKEN" \
         -H "Content-Type: application/json" \
         -d "{\"state\": \"$status\", \"attributes\": {\"friendly_name\": \"$service_name Status\", \"icon\": \"$icon\"}}" \
         "$HA_URL/api/states/sensor.media_$(echo $service_name | tr '[:upper:] ' '[:lower:]_')"
    # Sends a POST request to your HA instance to create/update a sensor.
    # The JSON payload (-d) includes the state (online/offline) and the friendly name.
    # The final URL uses 'tr' to convert "Media Server" into "sensor.media_server" for HA compatibility.
}

manage_remote_torrent() {
    # DW_clean_malicious.sh
    # DW_convert_mkv.sh
    # DW_monitor_convert.sh
    # DW_monitor_movie_subtitles.sh
    local action=$1
    # Assigns the first argument (stop/delete) to a local variable for clarity.
    local filename="$2"
    # Assigns the filename passed from the main script to a local variable.
    #local search_regex=$(echo "${filename:0:25}" | sed 's/[^a-zA-Z0-9]/.*/g')
    # Takes the first 25 chars, then replaces all non-alphanumeric chars with '.*' (the regex wildcard).
    # We shorten the capture to 10 characters to avoid "BluRay/BrRip" mismatches
    local delete_data="${3:-false}" # Defaults to false if no argument is provided
    local search_regex=$(echo "${filename:0:10}" | sed 's/[^a-zA-Z0-9]/.*/g')
    for server in "${QBT_SERVERS[@]}"; do
    # Loops through every server URL defined in your common_functions.sh array.
        local t_data=$(curl -s -u "$QBT_USER:$QBT_PASS" "${server}/api/v2/torrents/info?all=true" | \
                       jq -r --arg RGX "$search_regex" '.[] | select(.name | test($RGX; "i")) | "\(.hash)|\(.name)"' | head -n 1)
        # Fetches all torrents, uses jq to find one matching the regex (case-insensitive), and returns "hash|name".

        if [[ -n "$t_data" && "$t_data" != "|" ]]; then
        # Checks if t_data is not empty and contains more than just the pipe separator (meaning a match was found).
            local t_hash=$(echo "$t_data" | cut -d'|' -f1)
            # Extracts the unique 40-character torrent hash from the first part of the string.
            local t_name=$(echo "$t_data" | cut -d'|' -f2)
            # Extracts the actual torrent name as it appears in qBittorrent for logging purposes.
            log "ℹ️ ${action^} torrent: $t_name"
            # Records the successful match and the intended action to your host-specific log file.
            local q_cmd="${action}"
            # Creates a local variable for the command to be sent to the qBittorrent API.
            [[ "$action" == "stop" ]] && q_cmd="pause"
            # Since the qBittorrent API uses '/pause' instead of '/stop', this translates the intent.
            #curl -s -u "$QBT_USER:$QBT_PASS" -X POST "${server}/api/v2/torrents/${q_cmd}" -d "hashes=$t_hash&deleteFiles=false"
            curl -s -u "$QBT_USER:$QBT_PASS" -X POST "${server}/api/v2/torrents/${q_cmd}" -d "hashes=$t_hash&deleteFiles=$delete_data" > /dev/null
            # Sends the POST request to the server to pause or delete the hash, ensuring files are kept safe.
            return 0
            # Exits the function with a 'success' code so the main script knows it can move on.
        fi
    done
    # Ends the loop if the current server didn't have the torrent, moving to the next server.
    return 1
    # Exits with an 'error' code if no server in the array contained a matching torrent.
}

# --- Media Library Notification Function ---
notify_media_managers() {
    # DW_sort_tv.sh
    # Notify Sonarr
    if [ -n "$SONARR_API_KEY" ]; then
        [[ "$LOG_LEVEL" == "debug" ]] && log "📡 Notifying Sonarr to scan for new downloads..."
        curl -s -H "X-Api-Key: $SONARR_API_KEY" \
             -H "Content-Type: application/json" \
             -X POST -d '{"name": "DownloadedEpisodesScan"}' \
             "$SONARR_API_BASE/command" > /dev/null
    else
        log "⚠️ SONARR_API_KEY not found. Skipping Sonarr notify."
    fi

    # Notify Radarr
    if [ -n "$RADARR_API_KEY" ]; then
        [[ "$LOG_LEVEL" == "debug" ]] && log "🎬 Notifying Radarr to scan for new downloads..."
        # Note: Radarr uses the same command name as Sonarr
        curl -s -H "X-Api-Key: $RADARR_API_KEY" \
             -H "Content-Type: application/json" \
             -X POST -d '{"name": "RescanMovie"}' \
             "$RADARR_API_BASE/command" > /dev/null
    else
        log "⚠️ RADARR_API_KEY not found. Skipping Radarr notify."
    fi
    # Update Plex server
    plex_library_update "$PLEX_TV_SRC" "$PLEX_TV_NAME"
    plex_library_update "$PLEX_MOVIES_SRC" "$PLEX_MOVIES_NAME"
}

# --- Function to sync a specific TV show folder ---
# Usage: synology_tv_show_sync "Show Name (Year)"
synology_tv_show_sync() {
    # DW_sort_tv.sh
    local SHOW_NAME="$1"    
    # Ensure variables are available (inherited from the calling script)
    local SYNOLOGY_DIR="${SYNOLOGY_DIR:-/mnt/synology/TV}"
    local MEDIA_DIR="${MEDIA_DIR:-/mnt/media/TV}"
    local DRY_RUN="${DRY_RUN:-false}"
    
    local DEST_SHOW_PATH="$SYNOLOGY_DIR/$SHOW_NAME"
    local SOURCE_SHOW_PATH="$MEDIA_DIR/$SHOW_NAME"

    if [[ -z "$SHOW_NAME" ]]; then
        log "ℹ️ No show name provided to sync_tv_show function."
        return 1
    fi

    # Check if the destination exists before doing anything
    if [[ ! -d "$DEST_SHOW_PATH" ]]; then
        [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ Destination folder '$SHOW_NAME' not found in $SYNOLOGY_DIR. Sync aborted."
        return 0
    fi

    [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ Synology sync started for: $SHOW_NAME"

    # Check if the source exists
    if [[ -d "$SOURCE_SHOW_PATH" ]]; then
        # Configure rsync options based on DRY_RUN
        local RSYNC_OPTS="-avh"
        if $DRY_RUN; then
            log "DRY RUN ENABLED for '$SHOW_NAME'."
            RSYNC_OPTS="-avhn"
        else
            RSYNC_OPTS="-avh --remove-source-files"
        fi

        # Execute rsync
        rsync $RSYNC_OPTS "$SOURCE_SHOW_PATH/" "$DEST_SHOW_PATH"
        
        if [[ $? -eq 0 ]]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ Sync completed for '$SHOW_NAME'"

            if ! $DRY_RUN; then
                # Clean up empty sub-directories
                find "$SOURCE_SHOW_PATH" -mindepth 1 -type d -empty -delete
                
                # Remove show folder if empty
                if [[ -d "$SOURCE_SHOW_PATH" ]] && [[ -z "$(ls -A "$SOURCE_SHOW_PATH")" ]]; then
                    rmdir "$SOURCE_SHOW_PATH"
                    log "Removed folder: $SHOW_NAME"
                fi
            fi
        else
            log "❌ rsync failed for $SHOW_NAME."
            return 1
        fi
    else
        log "🔄 No source files found for $SHOW_NAME in $MEDIA_DIR."
        return 0 # Return 0 because there's nothing to do, not necessarily a script failure
    fi
}

# --- Lidarr section ---

lidarr_targeted_rename() {
    local search_path="$1"
    if [ -z "$LIDARR_API_KEY" ]; then return 1; fi

    search_path="${search_path%/}"
    local folder_name=$(basename "$search_path")

    # --- Fix for Multi-Disc Folders ---
    # If the folder is "Disc 01" or "CD 1", step up to the parent directory
    if [[ "$folder_name" =~ ^(Disc|CD|Side)\ [0-9]+$ ]] || [[ "$folder_name" =~ ^(Disc|CD|Side)[0-9]+$ ]]; then
        search_path=$(dirname "$search_path")
        folder_name=$(basename "$search_path")
        [[ $LOG_LEVEL == "debug" ]] && log "📂 Multi-disc folder detected. Moving up to: $folder_name"
    fi
    
    [[ $LOG_LEVEL == "debug" ]] && log "🔍 Requesting Lidarr ID for: $folder_name"

    # --- Hardened JQ Logic ---
    # Added 'select(type == "string")' to prevent the "explode" error
    local album_id=$(curl -s -H "X-Api-Key: $LIDARR_API_KEY" "$LIDARR_API_BASE/album" | \
        jq -r --arg name "$folder_name" '
            .[] | select(.path != null and (.path | type == "string") and (.path | ascii_downcase | contains("/" + ($name | ascii_downcase)))) | .id
        ' | head -n 1)

    if [ -z "$album_id" ] || [ "$album_id" = "null" ]; then
        [[ $LOG_LEVEL == "debug" ]] && log "🔄 PATH match failed, trying TITLE match..."
        album_id=$(curl -s -H "X-Api-Key: $LIDARR_API_KEY" "$LIDARR_API_BASE/album" | \
            jq -r --arg name "$folder_name" '
                .[] | select(.title != null and (.title | type == "string") and ((.title | ascii_downcase == ($name | ascii_downcase)) or (.title | test("^" + $name + "( \\(\\d{4}\\))?$"; "i")))) | .id
            ' | head -n 1)
    fi

    if [ -n "$album_id" ] && [ "$album_id" != "null" ]; then  
        log "🔄 Refreshing & Renaming Album: $folder_name (ID: $album_id)"
        curl -s -H "X-Api-Key: $LIDARR_API_KEY" -H "Content-Type: application/json" \
             -X POST -d "{\"name\": \"RescanAlbum\", \"albumId\": $album_id}" "$LIDARR_API_BASE/command" > /dev/null
        sleep 5 
        curl -s -H "X-Api-Key: $LIDARR_API_KEY" -H "Content-Type: application/json" \
             -X POST -d "{\"name\": \"RenameFiles\", \"albumIds\": [$album_id]}" "$LIDARR_API_BASE/command" > /dev/null
    else
        log "⚠️ Could not map '$folder_name' to a Lidarr Album ID."
    fi
}

# --- Lidarr section ---
# --- PLEX SECTION ---

plex_library_update() {
    # DW_move_movies_synology.sh
    # DW_move_tv_shows_synology.sh
    # DW_sort_tv.sh
    local section_id="$1"
    local library_name="$2"
    local url="$PLEX_URL"
    local token="$PLEX_TOKEN"
    local max_retries=3
    local attempt=1
    local success=false
    if [[ -z "$section_id" || -z "$library_name" ]]; then
        log "❌ plex_library_update called with missing arguments. (ID: '$section_id', Name: '$library_name')"
        return 1
    fi
    # --- Check if Plex is busy ---

    if plex_busy; then
        [[ "$LOG_LEVEL" == "debug" ]] && log "⚠️ Plex returned a busy signal."
        return 0 # Exit gracefully, don't trigger the failure log
    fi
    if plex_active_streams; then
        [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ User is streaming. Skipping Plex scan for $library_name to preserve playback quality."
        return 0 # Exit gracefully, don't trigger the failure log
    fi
    while [ $attempt -le $max_retries ]; do
        local response=$(curl -s -L -g -o /dev/null -w "%{http_code}" \
            "$url/library/sections/$section_id/refresh" \
            -H "X-Plex-Token: $token" \
            -H "Accept: application/json")
        if [[ "$response" == "200" ]]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "✅ Plex scan successful for $library_name (Attempt $attempt)."
            success=true
            break
        else
            [[ "$LOG_LEVEL" == "debug" ]] && log "⚠️ Plex scan attempt $attempt failed for $library_name with code $response. Retrying..."
            sleep 5
            ((attempt++))
        fi
    done

    if [ "$success" = false ]; then
        log "❌ Plex scan failed after $max_retries attempts for $library_name."
    fi
}

plex_active_streams() {
    local url="$PLEX_URL"
    local token="$PLEX_TOKEN"
    
    # Fetch data and count video sessions
    # We redirect stderr to /dev/null so curl errors don't clutter your logs
    local response
    response=$(curl -s -H "X-Plex-Token: $token" "$url/status/sessions" 2>/dev/null)
    
    # Count occurrences of "<Video"
    local count=$(echo "$response" | grep -c "<Video" || echo 0)
    
    # Validate: check if count is actually a number
    if [[ "$count" =~ ^[0-9]+$ ]]; then
        if [ "$count" -gt 0 ]; then
            return 0 # Streams active
        else
            return 1 # No streams
        fi
    else
        # Handle the case where the API call failed or returned bad data
        return 1
    fi
}

plex_busy() {
    local url="$PLEX_URL"
    local token="$PLEX_TOKEN"

    # Query the activity endpoint
    local activity=$(curl -s -H "X-Plex-Token: $token" "$url/status/sessions")
    
    # Check if there is an active scanner task
    # (Plex reports scanning status via the 'scan' field in metadata updates)
    if [[ "$activity" == *"scan"* ]]; then
        return 0 # Plex is busy
    else
        return 1 # Plex is idle
    fi
}

# --- END PLEX SECTION ---
# --- RADARR SECTION ---

radarr_targeted_scan() {
    local movie_name="$1"
    
    if [ -z "$RADARR_API_KEY" ]; then 
        log "⚠️ Radarr API Key missing."
        return 1 
    fi

    # 1. Fetch ALL movies (once) to avoid multiple API hits
    local radarr_data=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_API_BASE/movie")

    # 2. Normalize the SortTV name for matching (removes hyphens, spaces, and years)
    local clean_name=$(echo "$movie_name" | sed -E 's/_\([0-9]{4}\)$//; s/\([0-9]{4}\)$//' | tr -dc '[:alnum:]' | tr '[:upper:]' '[:lower:]')

    # 3. Fuzzy Match to get the ID and the current JSON Object
    local movie_json=$(echo "$radarr_data" | jq -c --arg clean "$clean_name" '.[] | select((.title | gsub("[^a-zA-Z0-9]"; "") | ascii_downcase) == $clean or (.folderName | gsub("[^a-zA-Z0-9]"; "") | ascii_downcase | contains($clean)))')
    local movie_id=$(echo "$movie_json" | jq -r '.id // empty')

    if [ -n "$movie_id" ] && [ "$movie_id" != "null" ]; then
        # Define the NEW path where SortTV just moved it
        # Adjust "/mnt/media/Movies/" to match your DIR_MEDIA variable if needed
        local new_path="/mnt/media/Movies/$movie_name"

        log "🔗 Updating Radarr path for '$movie_name' to: $new_path"

        # 4. PUSH the path update to Radarr
        # We take the original JSON, update the path, and PUT it back
        echo "$movie_json" | jq --arg p "$new_path" '.path = $p' | \
        curl -s -X PUT -H "X-Api-Key: $RADARR_API_KEY" \
             -H "Content-Type: application/json" \
             -d @- "$RADARR_API_BASE/movie/$movie_id" > /dev/null

        # 5. Trigger Rescan
        log "🔄 Triggering Radarr rescan for ID: $movie_id"
        curl -s -H "X-Api-Key: $RADARR_API_KEY" -X POST -H "Content-Type: application/json" \
             -d "{\"name\": \"RescanMovie\", \"movieId\": $movie_id}" \
             "$RADARR_API_BASE/command" > /dev/null

    else
        log "⚠️ Could not map '$movie_name' (Clean: $clean_name) to a Radarr Movie ID."
    fi
}

# --- END RADARR SECTION ---
# --- SEERR SECTION ---

seerr_resolve_issue() {
    local folder_path="${1%/}" 
    local base_url="${SEERR_API_BASE%/}"
    local seerr_user="${SEERR_EMAIL}"
    local seerr_pass="${SEERR_PASSWORD}"
    local cookie_file="/tmp/seerr_res_cookie.txt"
    
    local media_type="movie"
    local show_folder=""
    local lookup_id=""

    # Authenticate
    curl -s -c "$cookie_file" -X POST "$base_url/auth/local" \
         -H "Content-Type: application/json" \
         -d "{\"email\": \"$seerr_user\", \"password\": \"$seerr_pass\"}" > /dev/null

    # 1. ID Lookup Logic
    if [[ "$folder_path" == *"/TV/"* ]]; then
        media_type="tv"
        [[ "$(basename "$folder_path")" == *"Season"* ]] && show_folder=$(dirname "$folder_path") || show_folder="$folder_path"
        
        lookup_id=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_API_BASE/series" | \
            jq -r --arg path "${show_folder%/}" '.[] | select(.path == $path or .path == ($path + "/")) | .tvdbId')
    else
        lookup_id=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_API_BASE/movie" | \
            jq -r --arg path "$folder_path" '.[] | select(.path == $path or .path == ($path + "/")) | .tmdbId')
    fi

    [[ -z "$lookup_id" || "$lookup_id" == "null" ]] && { rm -f "$cookie_file"; return 1; }

    # 2. Find and Resolve
    local response_file="/tmp/seerr_open_issues.json"
    curl -s -b "$cookie_file" -o "$response_file" "$base_url/issue?filter=open"

    local issue_id=$(jq -r --arg tid "$lookup_id" --arg type "$media_type" '
        .results[]? | select(.media.mediaType == $type) |
        select((.media.tmdbId | tostring == $tid) or (.media.tvdbId | tostring == $tid)) | .id' "$response_file" | head -n 1)

    if [[ -n "$issue_id" && "$issue_id" != "null" ]]; then
        log "✅ Seerr: Found $media_type issue #$issue_id. Resolving..."
        curl -s -b "$cookie_file" -X POST "$base_url/issue/$issue_id/resolved" > /dev/null
    fi
    
    rm -f "$cookie_file"
}

seerr_sync_issue() {
    local media_name="$1"
    local media_type="$2"   # "tv" or "movie"
    local message=$(echo "$3" | xargs) # Trim whitespace to ensure clean comparison
    local media_id="$4"

    # --- Service Account Auth (Triggers Email) ---
    local seerr_user="${SEERR_EMAIL}"
    local seerr_pass="${SEERR_PASSWORD}"
    local cookie_file="/tmp/seerr_sync_cookie.txt"

    curl -s -c "$cookie_file" -X POST "${SEERR_API_BASE%/}/auth/local" \
         -H "Content-Type: application/json" \
         -d "{\"email\": \"$seerr_user\", \"password\": \"$seerr_pass\"}" > /dev/null

    # 1. Arr Search Logic (Existing Sonarr/Radarr search blocks go here)
    # ... [Keep your existing Arr search code] ...

    # 2. Get Seerr Media ID
    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        local search_term=$(echo "$media_name" | sed -E 's/\.[^.]*$//; s/[0-9]+x[0-9]+.*//i; s/\([0-9]{4}\)//g; s/[._]/ /g; s/ +/ /g')
        local encoded_query=$(echo "$search_term" | jq -Rr @uri)
        local search_results=$(curl -s -b "$cookie_file" -X GET "$SEERR_API_BASE/search?query=$encoded_query")
        media_id=$(echo "$search_results" | jq -r --arg type "$media_type" '.results[] | select(.mediaType == $type).mediaInfo.id // empty' | head -n 1)
    fi

    [[ -z "$media_id" || "$media_id" == "null" ]] && { rm -f "$cookie_file"; return 1; }

    # 3. Deduplication & Anti-Spam Check
    local existing_issues=$(curl -s -b "$cookie_file" -X GET "$SEERR_API_BASE/issue?take=100&filter=open")
    
    # Extract Issue ID, Main Message, and Last Comment Message
    local issue_info=$(echo "$existing_issues" | jq -r --arg mid "$media_id" '
        .results[] | select(.media.id == ($mid|tonumber)) | 
        "\(.id)|\(.message)|\(.comments[-1].message // "none")"' | head -n 1)

    local issue_id=$(echo "$issue_info" | cut -d'|' -f1)
    local main_desc=$(echo "$issue_info" | cut -d'|' -f2)
    local last_comment=$(echo "$issue_info" | cut -d'|' -f3-)

    if [[ -n "$issue_id" && "$issue_id" != "null" ]]; then
        # Check if message is already present in either the main desc or the last comment
        if [[ "$message" == "$main_desc" || "$message" == "$last_comment" ]]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ Seerr: Issue #$issue_id already up to date. Skipping email."
            rm -f "$cookie_file"
            return 0
        fi

        # If we got here, the message is NEW or CHANGED
        curl -s -b "$cookie_file" -X POST "$SEERR_API_BASE/issue/$issue_id/comment" \
            -H "Content-Type: application/json" -d "{\"message\": \"$message\"}"
        rm -f "$cookie_file"
        return 0 
    fi

    # 4. Create New Issue (If none exists)
    local json_payload=$(jq -n --arg mt "1" --arg msg "$message" --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')
    
    curl -s -b "$cookie_file" -X POST "$SEERR_API_BASE/issue" \
        -H "Content-Type: application/json" -d "$json_payload" > /dev/null
    
    log "🚀 Seerr Issue created for $media_name."
    rm -f "$cookie_file"
}

# --- END SEERR SECTION ---
# --- SONARR SECTION ---

sonarr_missing_episodes() {
    local sonarr_missing=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SONARR_API_BASE/command" \
         -H "Content-Type: application/json" \
         -H "X-Api-Key: $SONARR_API_KEY" \
         -d '{"name": "MissingEpisodeSearch"}')
    if [ "$sonarr_missing" -eq 201 ] || [ "$sonarr_missing" -eq 200 ]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ Sonarr search triggered (HTTP $sonarr_missing)."
        else
            log "❌ Failed to trigger search (HTTP $sonarr_missing)."
            return 1
        fi
}

sonarr_search() {
    # UNUSED
    local series_name="$1"
    local sonarr_series=$(curl -s -X GET "$SONARR_API_BASE/series" -H "X-Api-Key: $SONARR_API_KEY")
    local sonarr_data=$(echo "$sonarr_series" | jq -r --arg name "$series_name" \
        '.[] | select(.title == $name or .path == $name) | "\(.id)|\(.monitored)"' | head -n 1)

    if [[ -n "$sonarr_data" ]]; then
        local s_id=$(echo "$sonarr_data" | cut -d'|' -f1)
        local s_monitored=$(echo "$sonarr_data" | cut -d'|' -f2)
        if [[ "$s_monitored" == "true" ]]; then
            log "🔍 Triggering Sonarr Search for $series_name"
            local payload=$(jq -n --arg id "$s_id" '{name: "SeriesSearch", seriesId: ($id|tonumber)}')
            curl -s -o /dev/null -X POST "$SONARR_API_BASE/command" -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" -d "$payload"
        fi
    fi
}

sonarr_targeted_rename() {
    local search_path="$1"
    if [ -z "$SONARR_API_KEY" ]; then return 1; fi

    # 1. Normalize the path and get the folder name
    search_path="${search_path%/}"
    local show_name=$(basename "$search_path")
    
    # Create a "Clean" name for fuzzy matching (no spaces, no special chars, lowercase)
    local clean_name=$(echo "$show_name" | sed -E 's/ \([0-9]{4}\)$//' | tr -dc '[:alnum:]' | tr '[:upper:]' '[:lower:]')

    [[ $LOG_LEVEL == "debug" ]] && log "🔍 Requesting Sonarr ID for: $show_name (Clean: $clean_name)"

    # 2. Fetch all series and find the match
    local sonarr_data=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_API_BASE/series")
    
    # Match by Title or Path using the same fuzzy logic as Radarr
    local series_json=$(echo "$sonarr_data" | jq -c --arg clean "$clean_name" '.[] | select((.title | gsub("[^a-zA-Z0-9]"; "") | ascii_downcase) == $clean or (.path | gsub("[^a-zA-Z0-9]"; "") | ascii_downcase | endswith($clean)))')
    local series_id=$(echo "$series_json" | jq -r '.id // empty')

    if [ -n "$series_id" ] && [ "$series_id" != "null" ]; then
        # Define the NEW path (Ensure this matches the internal container path)
        local new_path="/mnt/media/TV/$show_name"

        log "🔗 Updating Sonarr path for '$show_name' to: $new_path"

        # 3. PUSH the path update to Sonarr
        echo "$series_json" | jq --arg p "$new_path" '.path = $p' | \
        curl -s -X PUT -H "X-Api-Key: $SONARR_API_KEY" \
             -H "Content-Type: application/json" \
             -d @- "$SONARR_API_BASE/series/$series_id" > /dev/null

        # 4. Trigger Rescan
        [[ $LOG_LEVEL == "debug" ]] && log "🔄 Triggering Sonarr rescan for ID: $series_id"
        curl -s -H "X-Api-Key: $SONARR_API_KEY" \
             -H "Content-Type: application/json" \
             -X POST -d "{\"name\": \"RescanSeries\", \"seriesId\": $series_id}" \
             "$SONARR_API_BASE/command" > /dev/null
    else
        log "⚠️ Could not map '$show_name' to a Sonarr Series ID."
    fi
}
# --- END SONARR SECTION ---
# --- VPN SECTION ---

vpn_restart_containers() {
    # DW_restart_vpn.sh
    log "🚀 Restarting VPN Containers..."
    # 1. Restart the VPN Container first
    # This ensures the network tunnel is ready for the dependent containers
    log "🔄 Restarting VPN: $VPN_CONTAINER"
    docker restart "$VPN_CONTAINER"
    # Wait 5 seconds for the VPN tunnel to initialize
    sleep 5 
    # 2. Loop through the QBT names and transform them
    for friendly_name in "${QBT_NAMES[@]}"; do
        # Transformation steps:
        # 1. tr '[:upper:]' '[:lower:]' -> convert to lowercase (4K TV -> 4k tv)
        # 2. sed 's/ //g'               -> remove all spaces (4k tv -> 4ktv)
        # 3. Prepend "qbittorrent-"     -> (4ktv -> qbittorrent-4ktv)
        clean_name=$(echo "$friendly_name" | tr '[:upper:]' '[:lower:]' | sed 's/ //g')
        container_id="qbittorrent-$clean_name"
        #log "🔄 Restarting Container: $container_id"
        # Perform the restart and check for success
        if docker restart "$container_id" >/dev/null 2>&1; then
            log "✅ Successfully restarted $container_id"
        else
            log "❌ Failed to restart $container_id. Check if container exists."
        fi
    done
    # 3. Loop through the TRANSMISSION names and transform them
    for friendly_name in "${TRANS_NAMES[@]}"; do
        # Transformation steps:
        # 1. tr '[:upper:]' '[:lower:]' -> convert to lowercase (4K TV -> 4k tv)
        # 2. sed 's/ //g'               -> remove all spaces (4k tv -> 4ktv)
        # 3. Prepend "transmission-"     -> (4ktv -> transmission-4ktv)
        clean_name=$(echo "$friendly_name" | tr '[:upper:]' '[:lower:]' | sed 's/ //g')
        container_id="transmission-$clean_name"
        #log "🔄 Restarting Container: $container_id"
        # Perform the restart and check for success
        if docker restart "$container_id" >/dev/null 2>&1; then
            log "✅ Successfully restarted $container_id"
        else
            log "❌ Failed to restart $container_id. Check if container exists."
        fi
    done
    log "🏁 VPN Container Restart Complete."
}

# --- END VPN SECTION ---
