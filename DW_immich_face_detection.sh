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

# Run the script and capture all output to a temporary file
OUTPUT=$(python3 /usr/local/bin/DW_immich_face_detection.py)

# Print the full output so you can still see the logs in the console
echo "$OUTPUT"

# Extract the variables using grep
SYNC_TIME=$(echo "$OUTPUT" | grep "RESULT:TIME=" | cut -d'=' -f2)
SYNC_SUCCESS=$(echo "$OUTPUT" | grep "RESULT:SUCCESS=" | cut -d'=' -f2)
SYNC_ALREADY=$(echo "$OUTPUT" | grep "RESULT:ALREADY=" | cut -d'=' -f2)

# Now you can use them with your common_functions.sh
log "Sync complete in $SYNC_TIME minutes."
log "Assigned: $SYNC_SUCCESS | Skipped: $SYNC_ALREADY"

# Example: If you have a notification function in common_functions
# send_notification "Immich Sync finished. Added $SYNC_SUCCESS names."
