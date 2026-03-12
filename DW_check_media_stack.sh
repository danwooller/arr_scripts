#!/bin/bash

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

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

# Bazarr
check_service "Bazarr" "$BAZARR_API_BASE" "$BAZARR_API_KEY" "/api/$BAZARR_API_VER/system/status"
[[ $? -eq 0 ]] && ha_update_status "Bazarr" "online" || ha_update_status "Bazarr" "offline"

# Dispatcharr
check_service "Dispatcharr Tuner" "$DISPATCHARR_URL" "NONE" "/discover.json"
[[ $? -eq 0 ]] && ha_update_status "Dispatcharr Tuner" "online" || ha_update_status "Dispatcharr Tuner" "offline"

# Lidarr
check_service "Lidarr" "$LIDARR_API_BASE" "$LIDARR_API_KEY" "/system/status"
[[ $? -eq 0 ]] && ha_update_status "Lidarr" "online" || ha_update_status "Lidarr" "offline"

# Prowlarr
check_service "Prowlarr" "$PROWLARR_API_BASE" "$PROWLARR_API_KEY" "/system/status"
[[ $? -eq 0 ]] && ha_update_status "Prowlarr" "online" || ha_update_status "Prowlarr" "offline"

# Seerr
check_service "Seerr" "$SEERR_API_BASE" "$SEERR_API_KEY" "/status"
[[ $? -eq 0 ]] && ha_update_status "Seerr" "online" || ha_update_status "Seerr" "offline"

# Sonarr & Sonarr 4K
check_service "Sonarr" "$SONARR_API_BASE" "$SONARR_API_KEY" "/system/status"
[[ $? -eq 0 ]] && ha_update_status "Sonarr" "online" || ha_update_status "Sonarr" "offline"

check_service "Sonarr 4K" "$SONARR4K_API_BASE" "$SONARR4K_API_KEY" "/system/status"
[[ $? -eq 0 ]] && ha_update_status "Sonarr 4K" "online" || ha_update_status "Sonarr 4K" "offline"

# Radarr & Radarr 4K
check_service "Radarr" "$RADARR_API_BASE" "$RADARR_API_KEY" "/system/status"
[[ $? -eq 0 ]] && ha_update_status "Radarr" "online" || ha_update_status "Radarr" "offline"

check_service "Radarr 4K" "$RADARR4K_API_BASE" "$RADARR4K_API_KEY" "/system/status"
[[ $? -eq 0 ]] && ha_update_status "Radarr 4K" "online" || ha_update_status "Radarr 4K" "offline"

# Tautulli
check_service "Tautulli" "$TAUTULLI_API_BASE" "$TAUTULLI_API_KEY" "?apikey=$TAUTULLI_API_KEY&cmd=status"
[[ $? -eq 0 ]] && ha_update_status "Tautulli" "online" || ha_update_status "Tautulli" "offline"

# Wizarr
check_service "Wizarr" "$WIZARR_API_BASE" "$WIZARR_API_KEY" "/users"
[[ $? -eq 0 ]] && ha_update_status "Wizarr" "online" || ha_update_status "Wizarr" "offline"

# Qbittorrent
QBT_NAMES=("TV" "Movies" "Music" "4K TV" "4K Movies")

for i in "${!QBT_SERVERS[@]}"; do
    URL="${QBT_SERVERS[$i]}"
    FRIENDLY_NAME="${QBT_NAMES[$i]}"
    
    # If the name is missing for some reason, fallback to the index
    [[ -z "$FRIENDLY_NAME" ]] && FRIENDLY_NAME="Instance $i"

    echo -n "Checking qBittorrent ($FRIENDLY_NAME)... "

    if [[ -z "$URL" ]]; then
        echo -e "${RED}FAILED (URL Empty)${NC}"
        ((TOTAL_ERRORS++))
        continue
    fi

    # Heartbeat check
    status=$(curl -s -L -o /dev/null --connect-timeout 3 -w "%{http_code}" "$URL/api/v2/app/version")

    # Prepare a clean Entity ID for Home Assistant (e.g., "qbt_4k_movies")
    # This removes spaces, converts to lowercase, and removes parentheses
    HA_ENTITY_NAME=$(echo "qbt_$FRIENDLY_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/ /_/g' | sed 's/[()]//g')

    if [[ "$status" == "200" ]]; then
        echo -e "${GREEN}OK (HTTP 200)${NC}"
        ha_update_status "$HA_ENTITY_NAME" "online"
    else
        echo -e "${RED}FAILED (HTTP $status)${NC}"
        ha_update_status "$HA_ENTITY_NAME" "offline"
        ((TOTAL_ERRORS++))
    fi
done

echo "-------------------------------------------"
if [ $TOTAL_ERRORS -eq 0 ]; then
    echo -e "${GREEN}PASS: All systems operational.${NC}"
else
    echo -e "${YELLOW}WARN: $TOTAL_ERRORS issues detected.${NC}"
fi
