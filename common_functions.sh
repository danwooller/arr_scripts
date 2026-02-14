#!/bin/bash

# --- Shared Configuration ---
HOST=$(hostname -s)
LOG_FILE="/mnt/media/torrent/${HOST}.log"

# --- Shared Logging Function ---
log() {
    # ${0##*/} removes the leading path from the script name
    echo "$(date +'%H:%M'): (${0##*/}) $1" | tee -a "$LOG_FILE"
}

# --- Shared Dependency Checker ---
# Usage: check_dependencies "cmd1" "cmd2" "cmd3"
check_dependencies() {
    for dep in "$@"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log "Installing '$dep' via apt-get..."
            sudo apt-get update && sudo apt-get install -y "${dep%-*}"
        else
            # Only log readiness if debug is on to keep logs clean
            [[ $LOG_LEVEL == "debug" ]] && log "✅ '$dep' is ready."
        fi
    done
}
