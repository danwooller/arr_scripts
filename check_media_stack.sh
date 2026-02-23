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

    local status=$(curl -s -L -o /dev/null --connect-timeout 5 -w "%{http_code}" -H "X-Api-Key: $key" "$url$endpoint")

    if [[ "$status" == "200" ]]; then
        echo -e "${GREEN}OK (HTTP 200)${NC}"
    else
        echo -e "${RED}FAILED (HTTP $status)${NC}"
        ((TOTAL_ERRORS++))
    fi
}

echo "--- Media Stack Connectivity Diagnostic ---"

# Bazarr (Subtitles)
check_service "Bazarr ($BAZARR_API_VER)" "$BAZARR_API_BASE" "$BAZARR_API_KEY" "/api/$BAZARR_API_VER/system/status"

# Check Dispatcharr
check_service "Dispatcharr (Tuner)" "$DISPATCHARR_URL" "NONE" "/discover.json"
check_service "Dispatcharr (Web UI)" "$DISPATCHARR_URL" "NONE" "/swagger"

# Lidarr (Music)
check_service "Lidarr ($LIDARR_API_VER)" "$LIDARR_API_BASE" "$LIDARR_API_KEY" "/system/status"

# Pi-hole
check_service "Pi-hole (9)" "$PIHOLE9_API_BASE" "$PIHOLE9_API_KEY" "/info/version?password=$PIHOLE9_API_KEY"
check_service "Pi-hole (9) Ping" "$PIHOLE9_URL" "NONE" "/api/info/hostname"
check_service "Pi-hole (24)" "$PIHOLE24_API_BASE" "$PIHOLE24_API_KEY" "/info/version?password=$PIHOLE24_API_KEY"

# Prowlarr (Indexers)
check_service "Prowlarr ($PROWLARR_API_VER)" "$PROWLARR_API_BASE" "$PROWLARR_API_KEY" "/system/status"

# Seerr
check_service "Seerr ($SEERR_API_VER)" "$SEERR_API_BASE" "$SEERR_API_KEY" "/status"

# Sonarr Instances
check_service "Sonarr ($SONARR_API_VER)" "$SONARR_API_BASE" "$SONARR_API_KEY" "/system/status"
check_service "Sonarr 4K  ($SONARR_API_VER)" "$SONARR4K_API_BASE" "$SONARR4K_API_KEY" "/system/status"

# Radarr Instances
check_service "Radarr ($RADARR_API_VER)" "$RADARR_API_BASE" "$RADARR_API_KEY" "/system/status"
check_service "Radarr 4K  ($RADARR_API_VER)" "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "/system/status"

# Check Tautulli (Requires specific cmd parameter)
check_service "Tautulli" "$TAUTULLI_API_BASE" "$TAUTULLI_API_KEY" "?apikey=$TAUTULLI_API_KEY&cmd=status"

# Wizarr (Invitation)
check_service "Wizarr" "$WIZARR_API_BASE" "$WIZARR_API_KEY" "/users"

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
