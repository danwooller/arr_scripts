#!/bin/bash

# --- Shared Configuration ---
HOST=$(hostname -s)
LOG_FILE="/mnt/media/torrent/${HOST}.log"
# --- arr Configuration ---
RADARR__URL="http://wooller.com:7878"
RADARR_API_KEY="5297e69b26744cd9bdc20cf5dbe7abda"
RADARR4K__URL="http://wooller.com:7879"
RADARR4K_API_KEY="6326920d1b4d4959be9bca08b1167c60"
SEERR_URL="http://wooller.com:5055" # Update with your IP/Port
SEERR_API_KEY="MTc0MDQ5NzU0MjYyOWRhZjA1MjhmLTg2Y2YtNDZmOS1hODkxLThlMzBlMWNmNzZmOQ=="
SONARR_URL="http://wooller.com:8989"
SONARR_API_KEY="61736d7438db43df9a2c514e967f2358"
SONARR4K_URL="http://wooller.com:8990"
SONARR4K_API_KEY="8e8dbedf18bb45b7841ba0e09757eee9"

# --- Shared Logging Function ---
log() {
    # Using local variables for cleaner output
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local script_name="${0##*/}"
    echo "[$timestamp] ($script_name) $1" | tee -a "$LOG_FILE"
}

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
