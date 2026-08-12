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
    # Returns 0 (success) as soon as the kernel detects physical media
    udevadm info --query=property --name="$DVD_DEVICE" 2>/dev/null | grep -q "ID_CDROM_MEDIA=1"
}

get_dynamic_preset() {
    log "Probing disc geometry on $DVD_DEVICE to determine preset..."

    # Scan the disc title to extract vertical resolution integer
    local probed_height
    probed_height=$(HandBrakeCLI --min-duration 0 -i "$DVD_DEVICE" --title 1 --scan 2>&1 | grep -oP '\d+(?=x\d+)' | tail -n 1 || echo "")

    local selected_preset
    case "$probed_height" in
        576)
            selected_preset="Fast 576p25"      # Standard UK / PAL DVD
            ;;
        480)
            selected_preset="Fast 480p30"      # Standard NTSC DVD
            ;;
        720)
            selected_preset="Fast 720p30"      # HD Source
            ;;
        1080)
            selected_preset="Fast 1080p30"     # Full HD Source
            ;;
        *)
            log "WARNING: Could not determine height reliably (detected: '${probed_height:-none}'). Defaulting to Fast 1080p30."
            selected_preset="Fast 1080p30"
            ;;
    esac

    log "Detected resolution: ${probed_height:-Unknown}p -> Selected Preset: '$selected_preset'"
    echo "$selected_preset"
}

convert_dvd() {
    log "DVD detected. Starting processing..."

    # Detect preset dynamically for the inserted disc
    local preset
    preset=$(get_dynamic_preset)

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="${OUTPUT_DIR}/DVD_Rip_${timestamp}.mp4"

    log "Executing: HandBrakeCLI -i $DVD_DEVICE -o $output_file --main-feature --preset \"$preset\" --crop 0:0:0:0"

    # --main-feature automatically selects the main movie title
    HandBrakeCLI -i "$DVD_DEVICE" -o "$output_file" --main-feature --preset "$preset" --crop 0:0:0:0
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