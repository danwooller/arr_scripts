#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ Common functions missing."
    exit 1
fi

PLEX_SRC=${1:-2}
PLEX_NAME=${2:-TV Shows}

plex_library_update "$PLEX_SRC" "$PLEX_NAME"

log "ℹ️ Plex update for $PLEX24_NAME"
