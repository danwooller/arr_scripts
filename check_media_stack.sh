#!/bin/bash

# Load your modular library files
source "/usr/local/bin/common_functions.sh"
source "/usr/local/bin/common_seerr_issue.sh"

# Colors for readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' 

TOTAL_ERRORS=0

check_service() {
    local name=$1
    local url=$2
    local key=$3
    local endpoint=$4

    echo -n "Checking $name... "
    
    if [[ -z "$url" || -z "$key" ]]; then
        echo -e "${RED}FAILED (Missing Config)${NC}"
        ((TOTAL_ERRORS++))
        return 1
    fi

    local status=$(curl -s -o /dev/null --connect-timeout 5 -w "%{http_code}" -H "X-Api-Key: $key" "$url$endpoint")

    if [[ "$status" == "200" ]]; then
        echo -e "${GREEN}OK (HTTP 200)${NC}"
    else
        echo -e "${RED}FAILED (HTTP $status)${NC}"
        ((TOTAL_ERRORS++))
    fi
}

echo "--- Media Stack Connectivity Diagnostic ---"

# 1. Seerr
check_service "Lidarr ($LIDARR_API_VER)" "$LIDARR_API_BASE" "$LIDARR_API_KEY" "/status"

# 1. Seerr
check_service "Prowlarr ($PROWLARR_API_VER)" "$PROWLARR_API_BASE" "$PROWLARR_API_KEY" "/status"

# 1. Seerr
check_service "Seerr ($SEERR_API_VER)" "$SEERR_API_BASE" "$SEERR_API_KEY" "/status"

# 2. Sonarr Instances
check_service "Sonarr STD ($SONARR_API_VER)" "$SONARR_API_BASE" "$SONARR_API_KEY" "/system/status"
check_service "Sonarr 4K  ($SONARR_API_VER)" "$SONARR4K_API_BASE" "$SONARR4K_API_KEY" "/system/status"

# 3. Radarr Instances
check_service "Radarr STD ($RADARR_API_VER)" "$RADARR_API_BASE" "$RADARR_API_KEY" "/system/status"
check_service "Radarr 4K  ($RADARR_API_VER)" "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "/system/status"

# 4. Config File
CONFIG_FILE="/mnt/media/torrent/ubuntu9_sonarr.txt"
echo -n "Checking Config File... "
if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "${GREEN}FOUND${NC}"
else
    echo -e "${RED}NOT FOUND ($CONFIG_FILE)${NC}"
    ((TOTAL_ERRORS++))
fi

echo "-------------------------------------------"
if [ $TOTAL_ERRORS -eq 0 ]; then
    echo -e "${GREEN}PASS: All systems operational.${NC}"
else
    echo -e "${YELLOW}WARN: $TOTAL_ERRORS issues detected.${NC}"
fi
