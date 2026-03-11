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
            log "ℹ️ Match Found: [$t_name]. Sending $action..."
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
        echo "📡 Notifying Sonarr to scan for new downloads..."
        curl -s -H "X-Api-Key: $SONARR_API_KEY" \
             -H "Content-Type: application/json" \
             -X POST -d '{"name": "DownloadedEpisodesScan"}' \
             "$SONARR_API_BASE/command" > /dev/null
    else
        echo "⚠️ SONARR_API_KEY not found. Skipping Sonarr notify."
    fi

    # Notify Radarr
    if [ -n "$RADARR_API_KEY" ]; then
        echo "🎬 Notifying Radarr to scan for new downloads..."
        # Note: Radarr uses the same command name as Sonarr
        curl -s -H "X-Api-Key: $RADARR_API_KEY" \
             -H "Content-Type: application/json" \
             -X POST -d '{"name": "DownloadedEpisodesScan"}' \
             "$RADARR_API_BASE/command" > /dev/null
    else
        echo "⚠️ RADARR_API_KEY not found. Skipping Radarr notify."
    fi
    # Update Plex server
    plex_library_update "$PLEX_TV_SRC" "$PLEX_TV_NAME"
    sleep 5
    plex_library_update "$PLEX_MOVIES_SRC" "$PLEX_MOVIES_NAME"
}

notify_sonarr_targeted_rename() {
    # DW_move_tv_shows_synology.sh
    # DW_sort_tv.sh
    local search_path="$1"
    
    if [ -z "$SONARR_API_KEY" ]; then return 1; fi

    # Normalize the path (remove trailing slash)
    search_path="${search_path%/}"
    
    # Get just the show folder name
    local show_name=$(basename "$search_path")

    log "🔍 Requesting Sonarr ID for: $show_name"

    # Fetch Series ID
    local series_id=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_API_BASE/series" | \
        jq -r ".[] | select(.path | contains(\"/$show_name\")) | .id")

    if [ -n "$series_id" ] && [ "$series_id" != "null" ]; then
        
        # 1. Trigger Refresh (Disk Scan)
        log "🔄 Triggering Sonarr refresh for $show_name"
        curl -s -H "X-Api-Key: $SONARR_API_KEY" \
             -H "Content-Type: application/json" \
             -X POST -d "{\"name\": \"RescanSeries\", \"seriesId\": $series_id}" \
             "$SONARR_API_BASE/command" > /dev/null

        # 2. Brief Wait
        # Sonarr needs a moment to pick up the files from the disk. 
        # For a few episodes, 5s is usually plenty.
        sleep 5 

        # 3. Trigger Rename
        log "📝 Triggering Sonarr rename for $show_name"
        curl -s -H "X-Api-Key: $SONARR_API_KEY" \
             -H "Content-Type: application/json" \
             -X POST -d "{\"name\": \"RenameSeries\", \"seriesIds\": [$series_id]}" \
             "$SONARR_API_BASE/command" > /dev/null
        
        log "✅ Sonarr tasks (Refresh + Rename) queued."
    else
        log "⚠️ Could not map '$show_name' to a Sonarr Series ID."
    fi
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
        log "Error: No show name provided to sync_tv_show function."
        return 1
    fi

    log "--- TV Show Sync Started for: $SHOW_NAME ---"

    # Check if the destination exists
    if [[ ! -d "$DEST_SHOW_PATH" ]]; then
        log "Error: Destination folder '$SHOW_NAME' not found in $SYNOLOGY_DIR"
        return 1
    fi

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
            log "✅ Sync completed for '$SHOW_NAME'"

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

trigger_sonarr_search() {
    local series_name="$1"
    local sonarr_series=$(curl -s -X GET "$SONARR_URL/api/v3/series" -H "X-Api-Key: $SONARR_API_KEY")
    local sonarr_data=$(echo "$sonarr_series" | jq -r --arg name "$series_name" \
        '.[] | select(.title == $name or .path == $name) | "\(.id)|\(.monitored)"' | head -n 1)

    if [[ -n "$sonarr_data" ]]; then
        local s_id=$(echo "$sonarr_data" | cut -d'|' -f1)
        local s_monitored=$(echo "$sonarr_data" | cut -d'|' -f2)
        if [[ "$s_monitored" == "true" ]]; then
            log "🔍 Triggering Sonarr Search for $series_name"
            local payload=$(jq -n --arg id "$s_id" '{name: "SeriesSearch", seriesId: ($id|tonumber)}')
            curl -s -o /dev/null -X POST "$SONARR_URL/api/v3/command" -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" -d "$payload"
        fi
    fi
}

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

    while [ $attempt -le $max_retries ]; do
        local response=$(curl -s -L -g -o /dev/null -w "%{http_code}" \
            "$url/library/sections/$section_id/refresh" \
            -H "X-Plex-Token: $token" \
            -H "Accept: application/json" \
            --max-time 10) # Added timeout to prevent hanging

        if [[ "$response" == "200" ]]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "✅ Plex scan successful for $library_name (Attempt $attempt)."
            success=true
            break
        else
            log "⚠️ Plex scan attempt $attempt failed for $library_name with code $response. Retrying..."
            sleep 5
            ((attempt++))
        fi
    done

    if [ "$success" = false ]; then
        log "❌ ERROR: Plex scan failed after $max_retries attempts for $library_name."
    fi
}

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
