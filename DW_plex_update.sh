#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ Common functions missing."
    exit 1
fi

PLEX24_TV_SRC=${1:-default}
PLEX24_TV_NAME=${2:-default}

plex_library_update "PLEX24_TV_SRC" "PLEX24_TV_NAME"
