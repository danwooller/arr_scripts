#!/bin/bash

HOST=$(hostname -s)

# --- Shared Logging Function ---
log() {
    # Using local variables for cleaner output
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local script_name="${0##*/}"
    echo "[$timestamp] ($script_name) $1" | tee -a "$LOG_FILE"
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
            log "ℹ️ Torrent Found: [$t_name]. Sending $action..."
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

    log "ℹ️ Synology Sync Started for: $SHOW_NAME"

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
            log "ℹ️ Sync completed for '$SHOW_NAME'"

            if ! $DRY_RUN; then
                # Clean up empty sub-directories
                find "$SOURCE_SHOW_PATH" -mindepth 1 -type d -empty -delete
                
                # Remove show folder if empty
                if [[ -d "$SOURCE_SHOW_PATH" ]] && [[ -z "$(ls -A "$SOURCE_SHOW_PATH")" ]]; then
                    rmdir "$SOURCE_SHOW_PATH"
                    log "Removed empty source folder: $SHOW_NAME"
                fi
            fi
        else
            log "[ERROR] rsync failed for '$SHOW_NAME'."
            return 1
        fi
    else
        log "No source files found for '$SHOW_NAME' in $MEDIA_DIR."
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
    # DW_sort_tv.sh
    # Expects the movie folder name
    local movie_name="$1"
    
    if [ -z "$RADARR_API_KEY" ]; then 
        log "⚠️ Radarr API Key missing."
        return 1 
    fi

    [[ $LOG_LEVEL == "debug" ]] && log "🔍 Requesting Radarr ID for: $movie_name"

    # --- Attempt to find the Movie ID by matching the folder name in the path ---
    local movie_id=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_API_BASE/movie" | \
        jq -r --arg name "$movie_name" '.[] | select(.path | ascii_downcase | endswith("/" + ($name | ascii_downcase))) | .id' | head -n 1)

    # --- Fallback: Try matching by Title if Path failed ---
    if [ -z "$movie_id" ] || [ "$movie_id" = "null" ]; then
        [[ $LOG_LEVEL == "debug" ]] && log "🔄 PATH match failed for '$movie_name', trying TITLE match..."
        movie_id=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_API_BASE/movie" | \
            jq -r --arg name "$movie_name" '.[] | select(.title | ascii_downcase == ($name | ascii_downcase | sub(" \\(\\d{4}\\)$"; ""))) | .id' | head -n 1)
    fi

    if [ -n "$movie_id" ] && [ "$movie_id" != "null" ]; then  
        # --- Trigger Rescan (Disks) ---
        [[ $LOG_LEVEL == "debug" ]] && log "🔄 Triggering Radarr rescan for $movie_name (ID: $movie_id)"
        curl -s -H "X-Api-Key: $RADARR_API_KEY" \
             -H "Content-Type: application/json" \
             -X POST -d "{\"name\": \"RescanMovie\", \"movieId\": $movie_id}" \
             "$RADARR_API_BASE/command" > /dev/null

        # --- Brief Wait for Scan to Register ---
        sleep 5 

        # --- Trigger Rename (Organize) ---
        [[ $LOG_LEVEL == "debug" ]] && log "📝 Triggering Radarr rename for $movie_name"
        curl -s -H "X-Api-Key: $RADARR_API_KEY" \
             -H "Content-Type: application/json" \
             -X POST -d "{\"name\": \"RenameMovie\", \"movieIds\": [$movie_id]}" \
             "$RADARR_API_BASE/command" > /dev/null
    else
        log "⚠️ Could not map '$movie_name' to a Radarr Movie ID."
    fi
}

# --- END RADARR SECTION ---
# --- SEERR SECTION ---

seerr_resolve_issue() {
    local folder_path="${1%/}" 
    local base_url="${SEERR_API_BASE%/}"
    # Use the email/password for your "API-Reporter" user here
    local seerr_user="${SEERR_EMAIL}"
    local seerr_pass="${SEERR_PASSWORD}"

    local cookie_file="/tmp/seerr_cookie.txt"
    local media_type="movie"
    local show_folder=""
    local season_num="0"
    local lookup_id=""

    # --- 1. LOGIN (The "Magic" to trigger notifications) ---
    # This creates a session as the reporter user. 
    # Because it's NOT your admin account, Overseerr will email you.
    curl -s -c "$cookie_file" -X POST "$base_url/auth/local" \
         -H "Content-Type: application/json" \
         -d "{\"email\": \"$seerr_user\", \"password\": \"$seerr_pass\"}" > /dev/null

    # --- 2. Detect TV vs Movie ---
    if [[ "$folder_path" == *"/TV/"* ]]; then
        media_type="tv"
        if [[ "$(basename "$folder_path")" == *"Season"* ]]; then
            show_folder=$(dirname "$folder_path")
            season_num=$(basename "$folder_path" | grep -oP '\d+' || echo "0")
        else
            show_folder="$folder_path"
            season_num="0"
        fi
        lookup_id=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_API_BASE/series" | \
            jq -r --arg path "${show_folder%/}" '.[] | select(.path == $path or .path == ($path + "/")) | .tvdbId')
    else
        lookup_id=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_API_BASE/movie" | \
            jq -r --arg path "$folder_path" '.[] | select(.path == $path or .path == ($path + "/")) | .tmdbId')
    fi

    if [[ -z "$lookup_id" || "$lookup_id" == "null" ]]; then
        return 1
    fi

    # --- 3. Search Seerr for open issues (Using Cookie) ---
    local response_file="/tmp/seerr_resp.json"
    curl -s -b "$cookie_file" -o "$response_file" "$base_url/issue?filter=open"

    # --- 4. Match Issue ID ---
    local issue_id=""
    if [[ "$media_type" == "movie" ]]; then
        issue_id=$(jq -r --arg tid "$lookup_id" '.results[]? | select(.media.tmdbId | tostring == $tid) | .id' "$response_file" | head -n 1)
    else
        issue_id=$(jq -r --arg tid "$lookup_id" --arg snum "$season_num" '
            .results[]? | 
            select(.media.tvdbId | tostring == $tid) |
            select((.problemSeason | tostring == $snum) or (.problemSeason | tostring == "0")) |
            .id' "$response_file" | head -n 1)
    fi

    # --- 5. Resolve (Using Cookie) ---
    if [[ -n "$issue_id" && "$issue_id" != "null" ]]; then
        # Resolving via cookie so the notification says the reporter/system resolved it
        curl -s -b "$cookie_file" -X POST "$base_url/issue/$issue_id/resolved" > /dev/null

        # Rescan commands still use standard API keys for Radarr/Sonarr
        if [[ "$media_type" == "movie" ]]; then
            local r_id=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_API_BASE/movie" | jq -r --arg path "$folder_path" '.[] | select(.path == $path) | .id')
            curl -s -X POST "$RADARR_API_BASE/command" -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" -d "{\"name\": \"RescanMovie\", \"movieId\": $r_id}" > /dev/null
        else
            local s_id=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_API_BASE/series" | jq -r --arg path "$show_folder" '.[] | select(.path == $path) | .id')
            curl -s -X POST "$SONARR_API_BASE/command" -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" -d "{\"name\": \"RescanSeries\", \"seriesId\": $s_id}" > /dev/null
        fi
    fi
    
    rm -f "$cookie_file"
}

seerr_sync_issue() {
    local media_name="$1"
    local media_type="$2"   # "tv" or "movie"
    local message="$3"      # Error details or missing ep list
    local media_id="$4"     # Optional Manual Map ID

    # --- NEW: Service Account Auth ---
    local seerr_user="${SEERR_EMAIL}"
    local seerr_pass="${SEERR_PASSWORD}"
    local cookie_file="/tmp/seerr_sync_cookie.txt"

    # Authenticate to get the session cookie
    curl -s -c "$cookie_file" -X POST "${SEERR_API_BASE%/}/auth/local" \
         -H "Content-Type: application/json" \
         -d "{\"email\": \"$seerr_user\", \"password\": \"$seerr_pass\"}" > /dev/null

    # 1. Trigger Arr Search (Kept standard API keys for Arrs)
    if [[ -n "$message" ]]; then
        # ... [Keep your existing Sonarr/Radarr logic exactly as it is] ...
        # (It uses $target_key, which is correct for Arrs)
    fi

    # 2. Get Seerr Media ID (Using Cookie)
    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        local search_term=$(echo "$media_name" | sed -E 's/\.[^.]*$//; s/[0-9]+x[0-9]+.*//i; s/\([0-9]{4}\)//g; s/[._]/ /g; s/ +/ /g')
        local encoded_query=$(echo "$search_term" | jq -Rr @uri)
        local search_results=$(curl -s -b "$cookie_file" -X GET "$SEERR_API_BASE/search?query=$encoded_query")
        media_id=$(echo "$search_results" | jq -r --arg type "$media_type" '.results[] | select(.mediaType == $type).mediaInfo.id // empty' | head -n 1)
    fi

    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        [[ "$LOG_LEVEL" == "debug" ]] && log "⚠️  Seerr: Could not link '$media_name' to an ID."
        rm -f "$cookie_file"
        return 1
    fi

    # 3. Deduplication Check (Using Cookie)
    local existing_issues=$(curl -s -b "$cookie_file" -X GET "$SEERR_API_BASE/issue?take=100&filter=open")
    local issue_id=$(echo "$existing_issues" | jq -r --arg mid "$media_id" '.results[] | select(.media.id == ($mid|tonumber)) | .id' | head -n 1)

    if [[ -n "$issue_id" && "$issue_id" != "null" ]]; then
        [[ "$LOG_LEVEL" == "debug" ]] && log "🔄 Seerr: Issue #$issue_id already open. Adding comment..."
        
        # This comment will now show as coming from the "API-Reporter"
        curl -s -b "$cookie_file" -X POST "$SEERR_API_BASE/issue/$issue_id/comment" \
            -H "Content-Type: application/json" \
            -d "{\"message\": \"$message\"}"
            
        rm -f "$cookie_file"
        return 0 
    fi

    # 4. Create New Issue (Using Cookie - THIS TRIGGERS THE EMAIL)
    local json_payload=$(jq -n --arg mt "1" --arg msg "$message" --arg id "$media_id" \
        '{issueType: ($mt|tonumber), message: $msg, mediaId: ($id|tonumber)}')
    
    local http_status=$(curl -s -b "$cookie_file" -o /dev/null -w "%{http_code}" -X POST "$SEERR_API_BASE/issue" \
        -H "Content-Type: application/json" \
        -d "$json_payload")
    
    if [[ "$http_status" == "201" || "$http_status" == "200" ]]; then
        log "🚀 Seerr Issue created for $media_name (via API-Reporter)."
    else
        log "❌ Seerr: Failed to create issue. Status: $http_status"
    fi

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
    # DW_move_tv_shows_synology.sh
    # DW_sort_tv.sh
    local search_path="$1"
    if [ -z "$SONARR_API_KEY" ]; then return 1; fi
    # Normalize the path (remove trailing slash)
    search_path="${search_path%/}"
    # Get just the show folder name
    local show_name=$(basename "$search_path")
    [[ $LOG_LEVEL == "debug" ]] && log "🔍 Requesting Sonarr ID for: $show_name"
    local series_id=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_API_BASE/series" | \
        jq -r --arg name "$show_name" '.[] | select(.path | ascii_downcase | contains("/" + ($name | ascii_downcase))) | .id' | head -n 1)
    # --- Fallback: Try matching by Title if Path failed ---
    if [ -z "$series_id" ] || [ "$series_id" = "null" ]; then
        [[ $LOG_LEVEL == "debug" ]] && log "🔄 PATH match failed for '$show_name', trying TITLE match..."
        series_id=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_API_BASE/series" | \
            jq -r ".[] | select(.title | ascii_downcase == \"$show_name\" or .title | test(\"^$show_name( \\\\(\\\\d{4}\\\\))?$\"; \"i\")) | .id" | head -n 1)
    fi
    if [ -n "$series_id" ] && [ "$series_id" != "null" ]; then  
        # --- Trigger Refresh ---
        [[ $LOG_LEVEL == "debug" ]] && log "🔄 Triggering Sonarr refresh for $show_name"
        curl -s -H "X-Api-Key: $SONARR_API_KEY" \
             -H "Content-Type: application/json" \
             -X POST -d "{\"name\": \"RescanSeries\", \"seriesId\": $series_id}" \
             "$SONARR_API_BASE/command" > /dev/null
        # --- Brief Wait ---
        sleep 5 
        # --- Trigger Rename ---
        [[ $LOG_LEVEL == "debug" ]] && log "📝 Triggering Sonarr rename for $show_name"
        curl -s -H "X-Api-Key: $SONARR_API_KEY" \
             -H "Content-Type: application/json" \
             -X POST -d "{\"name\": \"RenameSeries\", \"seriesIds\": [$series_id]}" \
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
