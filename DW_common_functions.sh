#!/bin/bash

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
# This will now apply to any script that sources this file
trap "log '🛑 Process interrupted by user (SIGINT/SIGTERM).'; exit 1" SIGINT SIGTERM

# --- Load External Configuration ---
CONFIG_FILE="/usr/local/bin/common_keys.txt"
if [[ -f "$CONFIG_FILE" ]]; then
    # Source the file, but strip any trailing Windows CR characters on the fly
    source <(sed 's/\r$//' "$CONFIG_FILE")
else
    log "WARN: Config file $CONFIG_FILE not found."
fi

# --- Shared Dependency Checker ---
check_dependencies() {
    local missing_deps=()
    
    for dep in "$@"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        else
            [[ $LOG_LEVEL == "debug" ]] && log "✅ '$dep' is ready."
        fi
    done

    # If there are missing dependencies, handle them in one go
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log "Missing dependencies: ${missing_deps[*]}"
        log "Attempting to install missing packages..."
        
        # Note: Package names don't always match command names (e.g., HandBrakeCLI vs handbrake-cli)
        # This logic attempts to install the command name, but may need manual overrides
        sudo apt-get update && sudo apt-get install -y "${missing_deps[@]}"
        
        # Final verification
        for dep in "${missing_deps[@]}"; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                log "❌ Critical Error: Failed to install '$dep'. Script exiting."
                exit 1
            fi
        done
    fi
}

manage_remote_torrent() {
    local action=$1    # "stop" or "delete"
    local filename="$2"
    
    # Clean the name for searching (strip extension, replace underscores with spaces)
    # We also escape double quotes to prevent jq syntax errors
    local search_name=$(echo "${filename%.*}" | sed 's/_/ /g' | sed 's/"/\\"/g')

    for server in "${QBT_SERVERS[@]}"; do
        # Ensure the server URL includes the port if not already there (e.g., http://192.168.1.50:8080)
        local api_url="${server}/api/v2/torrents"

        # 1. Find the Hash using the info endpoint
        local t_hash=$(curl -s -u "$QBT_USER:$QBT_PASS" "${api_url}/info?all=true" | \
                       jq -r ".[] | select(.name | contains(\"$search_name\")) | .hash" | head -n 1)

        # 2. Try a second "fuzzy" search (first 15 chars) if the first one fails
        if [ -z "$t_hash" ] || [ "$t_hash" == "null" ]; then
            local short_name="${search_name:0:15}"
            t_hash=$(curl -s -u "$QBT_USER:$QBT_PASS" "${api_url}/info?all=true" | \
                     jq -r ".[] | select(.name | contains(\"$short_name\")) | .hash" | head -n 1)
        fi

        # 3. Perform the Action
        if [ -n "$t_hash" ] && [ "$t_hash" != "null" ]; then
            log "✅ Found on $server (Hash: ${t_hash:0:8}...). Sending $action..."
            
            if [ "$action" == "delete" ]; then
                # deleteFiles=false ensures we only remove the entry from the UI
                curl -s -u "$QBT_USER:$QBT_PASS" -X POST "${api_url}/delete" -d "hashes=$t_hash&deleteFiles=false"
            else
                # Using the 'stop' (pause) command
                curl -s -u "$QBT_USER:$QBT_PASS" -X POST "${api_url}/stop" -d "hashes=$t_hash"
            fi
            return 0
        fi
    done

    log "⚠️ Could not find torrent matching: $search_name"
    return 1
}

update_ha_status() {
    local service_name=$1
    local status=$2 # Expects "online" or "offline"
    local icon="mdi:server"

    # Set icon based on status
    [[ "$status" == "online" ]] && icon="mdi:check-circle" || icon="mdi:alert-circle"

    curl -X POST -H "Authorization: Bearer $HA_TOKEN" \
         -H "Content-Type: application/json" \
         -d "{\"state\": \"$status\", \"attributes\": {\"friendly_name\": \"$service_name Status\", \"icon\": \"$icon\"}}" \
         "$HA_URL/api/states/sensor.media_$(echo $service_name | tr '[:upper:] ' '[:lower:]_')"
}
