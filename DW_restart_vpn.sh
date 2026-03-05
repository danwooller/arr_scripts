#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi
if [ -f "/usr/local/bin/DW_common_seerr_issue.sh" ]; then
    source "/usr/local/bin/DW_common_seerr_issue.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_seerr_issue.sh missing. Exiting."
    exit 1
fi

restart_vpn_containers
