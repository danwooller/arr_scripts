#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ Common functions missing."
    exit 1
fi

PLEX24_SRC=${1:-2}
PLEX24_NAME=${2:-TV Shows}

plex_library_update "$PLEX24_SRC" "$PLEX24_NAME"

log "Plex uppdate for $PLEX24_NAME"
