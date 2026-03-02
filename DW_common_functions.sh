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
    local action=$1
    local filename="$2"
    
    # 1. Prepare a "Regex-safe" search string
    # We strip the extension, then replace ALL dots, underscores, and dashes 
    # with a "." (which means "any character" in Regex).
    # "Frozen.II.2019...[YTS.MX]" -> "Frozen.II.2019.*YTS"
    local search_regex=$(echo "${filename%.*}" | sed 's/[._ -]/./g' | sed 's/\[/\\\[/g; s/\]/\\\]/g')

    for server in "${QBT_SERVERS[@]}"; do
        local api_url="${server}/api/v2/torrents"

        # 2. Use 'test' with the regex for a much "stickier" match
        # The "i" makes it case-insensitive
        local t_hash=$(curl -s -u "$QBT_USER:$QBT_PASS" "${api_url}/info?all=true" | \
                       jq -r ".[] | select(.name | test(\"$search_regex\"; \"i\")) | .hash" | head -n 1)

        # 3. Perform the Action
        if [[ -n "$t_hash" && "$t_hash" != "null" ]]; then
            log "✅ Found on $server (Hash: ${t_hash:0:8}). Sending $action..."
            
            if [[ "$action" == "delete" ]]; then
                curl -s -u "$QBT_USER:$QBT_PASS" -X POST "${api_url}/delete" -d "hashes=$t_hash&deleteFiles=false"
            else
                curl -s -u "$QBT_USER:$QBT_PASS" -X POST "${api_url}/stop" -d "hashes=$t_hash"
            fi
            return 0
        fi
    done

    # If we get here, log the REASON it failed
    log "⚠️ Could not find torrent matching regex: $search_regex"
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
