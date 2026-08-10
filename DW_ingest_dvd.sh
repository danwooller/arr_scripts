#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

log_start "DVD ingest service"

# --- CONFIGURATION ---
DVD_DEVICE="/dev/sr0"
OUTPUT_DIR="/mnt/media/torrent/hold"
HANDBRAKE_PRESET=(--preset "Fast 1080p30")

# --- Run Dependency Check ---
check_dependencies "HandBrakeCLI" "eject" "blkid" "lsof"

if [ ! -d "$OUTPUT_DIR" ]; then
    log "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR" || { log "ERROR: Failed to create output directory."; exit 1; }
fi

# --- FUNCTIONS ---

eject_disk() {
    log "Ejecting disk from $DVD_DEVICE."
    eject "$DVD_DEVICE"
}

disc_is_present() {
    # -p forces blkid to bypass cache and query the physical drive directly
    blkid -p "$DVD_DEVICE" &> /dev/null
}

convert_dvd() {
    log "DVD detected. Starting processing..."

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="${OUTPUT_DIR}/DVD_Rip_${timestamp}.mp4"

    log "Executing: HandBrakeCLI -i $DVD_DEVICE -o $output_file --main-feature ${HANDBRAKE_PRESET[*]}"

    # --main-feature automatically selects the main movie title
    HandBrakeCLI -i "$DVD_DEVICE" -o "$output_file" --main-feature "${HANDBRAKE_PRESET[@]}"
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "SUCCESS: Conversion completed -> $output_file"
    else
        log "ERROR: HandBrakeCLI failed with exit code $exit_code."
        if [ -f "$output_file" ]; then
            log "Cleaning up incomplete output file: $output_file"
            rm -f "$output_file"
        fi
    fi

    eject_disk
}

# --- MAIN DAEMON LOOP ---

log "Starting DVD monitor loop on $DVD_DEVICE (polling every 15s)..."

while true; do
    if disc_is_present; then
        if ! lsof "$DVD_DEVICE" &> /dev/null; then
            log "Ready disc detected!"
            convert_dvd
            
            # Cooldown pause to swap discs without immediate re-triggering
            sleep 30
        else
            log "Disc detected, but drive is busy. Retrying in 15s..."
        fi
    fi

    sleep 15
done