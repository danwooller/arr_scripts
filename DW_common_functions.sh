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
trap "log '🛑 Process interrupted by user (SIGINT/SIGTERM).'; exit 1" SIGINT SIGTERM
# This will now apply to any script that sources this file

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

manage_remote_torrent() {
    local action=$1
    # Assigns the first argument (stop/delete) to a local variable for clarity.
    local filename="$2"
    # Assigns the filename passed from the main script to a local variable.
    local search_regex=$(echo "${filename:0:25}" | sed 's/[^a-zA-Z0-9]/.*/g')
    # Takes the first 25 chars, then replaces all non-alphanumeric chars with '.*' (the regex wildcard).

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
            curl -s -u "$QBT_USER:$QBT_PASS" -X POST "${server}/api/v2/torrents/${q_cmd}" -d "hashes=$t_hash&deleteFiles=false"
            # Sends the POST request to the server to pause or delete the hash, ensuring files are kept safe.
            return 0
            # Exits the function with a 'success' code so the main script knows it can move on.
        fi
    done
    # Ends the loop if the current server didn't have the torrent, moving to the next server.
    return 1
    # Exits with an 'error' code if no server in the array contained a matching torrent.
}

restart_vpn_containers() {
    log "🚀 Starting Media Stack Restart..."

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

        log "🔄 Restarting Container: $container_id"
        
        # Perform the restart and check for success
        if docker restart "$container_id" >/dev/null 2>&1; then
            log "✅ Successfully restarted $container_id"
        else
            log "❌ Failed to restart $container_id. Check if container exists."
        fi
    done

    log "🏁 Media Stack Restart Sequence Complete."
}

update_ha_status() {
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
