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
    # Returns 0 (success) as soon as the kernel detects physical media
    udevadm info --query=property --name="$DVD_DEVICE" 2>/dev/null | grep -q "ID_CDROM_MEDIA=1"
}

convert_dvd() {
    log "DVD detected. Scanning titles..."

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    # 1. Get total number of titles from HandBrake CLI output
    local title_count
    title_count=$(HandBrakeCLI -i "$DVD_DEVICE" --title 0 2>&1 | grep -E "^\+ title " | wc -l)

    if [ "$title_count" -eq 0 ]; then
        log "ERROR: No valid titles found on DVD."
        eject_disk
        return 1
    fi

    log "Found $title_count title(s). Starting extraction..."

    # 2. Loop through each title and append track number T01, T02, etc.
    local t
    for (( t=1; t<=title_count; t++ )); do
        # Format title number with leading zeros (e.g. 01, 02)
        local track_num
        track_num=$(printf "%02d" "$t")
        local output_file="${OUTPUT_DIR}/DVD_Rip_${timestamp}_T${track_num}.mp4"

        log "Processing Track $t of $title_count -> $output_file"

        # --title $t extracts the specific track
        # --min-duration 900 ignores extra tracks shorter than 15 mins (menus, trailers, etc.)
        HandBrakeCLI -i "$DVD_DEVICE" -o "$output_file" --title "$t" --min-duration 900 "${HANDBRAKE_PRESET[@]}"
        
        if [ $? -eq 0 ]; then
            log "SUCCESS: Extracted Track $t -> $output_file"
        else
            log "WARNING: Track $t failed or was skipped (shorter than min-duration)."
            # Clean up empty/failed file if created
            [ -f "$output_file" ] && [ ! -s "$output_file" ] && rm -f "$output_file"
        fi
    done

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