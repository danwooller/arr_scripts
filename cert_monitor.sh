#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# Configuration
HOST=$(hostname -s)
DOMAIN="wooller.com"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
OUTPUT_FILE="$CERT_PATH/certificate.p12"
P12_PASSWORD="VoorboorseT7676"
CHECK_INTERVAL=86400 # 24 hours

# Path to Docker binary and restart command
DOCKER_BIN="/opt/docker"
RESTART_COMMAND="$DOCKER_BIN restart plex"

# --- Logging Function ---
log() {
    echo "$(date +'%H:%M'): $1" | tee -a "$LOG_FILE"
}

while true; do
    if [ ! -d "$CERT_PATH" ]; then
        log "ERROR: Directory $CERT_PATH not found. Retrying in 1 hour..."
        sleep 3600
        continue
    fi

    # Check if cert is expired OR if the P12 file is missing
    if openssl x509 -checkend 0 -noout -in "$CERT_PATH/fullchain.pem" > /dev/null 2>&1 && [ -f "$OUTPUT_FILE" ]; then
        log "Certificate is valid and P12 exists. Sleeping..."
    else
        log "Action Required: Certificate expired/missing or P12 missing. Generating $OUTPUT_FILE..."

        # Generate PKCS12
        openssl pkcs12 -export \
            -in "$CERT_PATH/fullchain.pem" \
            -inkey "$CERT_PATH/privkey.pem" \
            -out "$OUTPUT_FILE" \
            -name "$DOMAIN" \
            -passout "pass:$P12_PASSWORD"

        if [ $? -eq 0 ]; then
            log "SUCCESS: New P12 generated."
            chmod 600 "$OUTPUT_FILE"
            
            log "Executing: $RESTART_COMMAND"
            $RESTART_COMMAND >> "$LOG_FILE" 2>&1
            
            if [ $? -eq 0 ]; then
                log "Plex restarted successfully."
            else
                log "ERROR: Failed to restart Plex. Check if $DOCKER_BIN is correct."
            fi
        else
            log "ERROR: Failed to generate P12 file."
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
