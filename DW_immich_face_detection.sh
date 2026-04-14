#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

log_start

OUTPUT=$(python3 /usr/local/bin/DW_immich_face_detection.py)
EXIT_CODE=$?

echo "$OUTPUT"

if [ $EXIT_CODE -ne 0 ]; then
    log "❌ Sync failed with exit code $EXIT_CODE"
    exit $EXIT_CODE
fi

# Extract variables with a fallback to 0
SYNC_TIME=$(echo "$OUTPUT" | grep "RESULT:TIME=" | cut -d'=' -f2)
SYNC_TIME=${SYNC_TIME:-0}

SYNC_SUCCESS=$(echo "$OUTPUT" | grep "RESULT:SUCCESS=" | cut -d'=' -f2)
SYNC_SUCCESS=${SYNC_SUCCESS:-0}

SYNC_ALREADY=$(echo "$OUTPUT" | grep "RESULT:ALREADY=" | cut -d'=' -f2)
SYNC_ALREADY=${SYNC_ALREADY:-0}

# Now you can use them with your common_functions.sh
log "Sync complete in $SYNC_TIME minutes."
log "Assigned: $SYNC_SUCCESS | Skipped: $SYNC_ALREADY"

# Example: If you have a notification function in common_functions
# send_notification "Immich Sync finished. Added $SYNC_SUCCESS names."
