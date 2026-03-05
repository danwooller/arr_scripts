#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

cd /opt/mealie_integration
log "--- Starting Global Sync $(date) ---"
# Run the Google Calendar fetcher (change index.js if needed)
node index.js
# Run the Mealie Importer
node import_to_mealie.js
log "--- Sync Finished ---"
