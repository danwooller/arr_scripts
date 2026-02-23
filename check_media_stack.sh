#!/bin/bash

# Load your modular library files
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# Colors for readability
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

check_service() {
    local name=$1
    local url=$2
    local key=$3
    local endpoint=$4

    echo -n "Checking $name... "
    
    if [[ -z "$url" || -z "$key" ]]; then
        echo -e "${RED}FAILED (Missing Config)${NC}"
        return 1
    fi

    local status=$(curl -s -o /dev/null --connect-timeout 5 -w "%{http_code}" -H "X-Api-Key: $key" "$url$endpoint")

    if [[ "$status" == "200" ]]; then
        echo -e "${GREEN}OK (HTTP 200)${NC}"
    else
        echo -e "${RED}FAILED (HTTP $status)${NC}"
    fi
}

echo "--- Media Stack Connectivity Diagnostic ---"

# 1. Check Seerr (Overserr)
check_service "Seerr ($SEERR_API_VER)"  "$SEERR_API_BASE"  "$SEERR_API_KEY"  "/status"

# 2. Check Sonarr
check_service "Sonarr ($SONARR_API_VER)" "$SONARR_API_BASE" "$SONARR_API_KEY" "/system/status"

# 3. Check Radarr
check_service "Radarr ($RADARR_API_VER)" "$RADARR_API_BASE" "$RADARR_API_KEY" "/system/status"

# 4. Check Sonarr
check_service "Sonarr4K ($SONARR_API_VER)" "$SONARR4K_API_BASE" "$SONARR4K_API_KEY" "/system/status"

# 5. Check Radarr
check_service "Radarr4K ($RADARR_API_VER)" "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "/system/status"

# 6. Check External Config File
CONFIG_FILE="/mnt/media/torrent/ubuntu9_sonarr.txt"
echo -n "Checking Config File ($CONFIG_FILE)... "
if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "${GREEN}FOUND${NC}"
else
    echo -e "${RED}NOT FOUND${NC}"
fi

echo "-------------------------------------------"
