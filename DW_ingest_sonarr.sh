#!/bin/bash

# --- Load Shared Functions ---
COMMON_FUNCTIONS="/usr/local/bin/DW_common_functions.sh"
if [ -f "$COMMON_FUNCTIONS" ]; then
    source "$COMMON_FUNCTIONS"
else
    echo "⚠️ $COMMON_FUNCTIONS missing. Exiting."
    exit 1
fi

# --- Configuration ---
LOCK_FILE="/tmp/ingest_running.lock"
CHECK_INTERVAL=300 # 5 minutes
#LOG_LEVEL="debug"

# --- Cleanup Trap ---
# Ensures the lock file is deleted if the script is stopped (Ctrl+C, reboot, etc.)
trap 'rm -f "$LOCK_FILE"; exit' INT TERM EXIT

# --- Initialization ---
check_dependencies "curl" "jq"
log_start "🚀 Ingest Service Started"

# --- Service Loop ---
while true; do
    # 1. Verify Mountpoint
    if mountpoint -q "$DIR_MEDIA"; then
        
        # 2. Check for Lock File
        if [ -f "$LOCK_FILE" ]; then
            [[ "$LOG_LEVEL" == "debug" ]] && log "⚠️ Lock file exists. Process may be active. Skipping."
        else
            # 3. Process Files
            #if [ -n "$(ls -A "$DIR_MEDIA_COMPLETED_TV" 2>/dev/null)" ]; then
            if find "$DIR_MEDIA_COMPLETED_TV" -maxdepth 1 -name "*.mkv" -print -quit | grep -q .; then
                touch "$LOCK_FILE"
                
                log "📂 Files detected in $DIR_MEDIA_COMPLETED_TV. Starting ingest..."
                
                # Trigger the Force Import function from common_functions
                sonarr_ingest "$DIR_MEDIA_COMPLETED_TV"

                # Brief pause to allow the move/rename to finish across the network
                sleep 15
                
                rm -f "$LOCK_FILE"
            else
                [[ "$LOG_LEVEL" == "debug" ]] && log "ℹ️ No mkv files in $DIR_MEDIA_COMPLETED_TV. Skipping."
            fi
        fi
    else
        log "❌ Media mount $DIR_MEDIA not active. Attempting mount -a..."
        mount -a 2>/dev/null
    fi   

    # --- Wait for next poll ---
    sleep "$CHECK_INTERVAL"
done
