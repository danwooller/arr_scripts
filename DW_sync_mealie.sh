#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"

cd /opt/mealie_integration
log "--- Starting Global Sync $(date) ---"
# Run the Google Calendar fetcher (change index.js if needed)
node index.js
# Run the Mealie Importer
node import_to_mealie.js
log "--- Sync Finished ---"
