#!/bin/bash

# --- EXIT TRAP FOR CLEAN SHUTDOWN ---
trap 'log "Stopping DVD ripper daemon."; exit 0' SIGINT SIGTERM

# --- LOAD SHARED FUNCTIONS ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ Common functions missing."
    exit 1
fi

# --- CONFIGURATION ---
DVD_DEVICE="/dev/sr0"
OUTPUT_DIR="/mnt/media/torrent/hold"

# --- RUN DEPENDENCY CHECK ---
check_dependencies "HandBrakeCLI" "eject" "udevadm" "lsof"

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
    # Queries the kernel block properties directly to bypass stale file system caches
    udevadm info --query=property --name="$DVD_DEVICE" 2>/dev/null | grep -q "ID_CDROM_MEDIA=1"
}

get_dynamic_preset() {
    local dev="$1"
    
    # Query HandBrake for disc geometry on main feature / title 0
    local scan_info
    scan_info=$(HandBrakeCLI -i "$dev" --title 0 2>&1 | grep -i "Geometry:")
    
    # Extract vertical resolution (e.g., 720x576 -> 576)
    local height
    height=$(echo "$scan_info" | grep -oP '\d+x\d+' | head -n1 | cut -d'x' -f2)

    # Fallback if height couldn't be parsed
    if [ -z "$height" ]; then
        log "WARNING: Could not parse native disc resolution. Defaulting to Fast 576p25."
        echo "Fast 576p25"
        return
    fi

    log "Detected source video height: ${height}p"

    if [ "$height" -le 576 ]; then
        # Standard Definition (PAL 576 / NTSC 480)
        echo "Fast 576p25"
    elif [ "$height" -le 720 ]; then
        # 720p HD
        echo "Fast 720p30"
    else
        # 1080p+ Full HD
        echo "Fast 1080p30"
    fi
}

convert_dvd() {
    log "Ready disc detected! Scanning disc properties..."

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    # 1. Dynamically select preset based on native height
    local detected_preset
    detected_preset=$(get_dynamic_preset "$DVD_DEVICE")
    local active_preset=(--preset "$detected_preset")

    log "Selected HandBrake preset: $detected_preset"

    # 2. Identify main feature track number
    local main_title
    main_title=$(HandBrakeCLI -i "$DVD_DEVICE" --main-feature --title 0 2>&1 | grep -i "main feature" | awk '{print $NF}' | tr -d ':')
    [ -z "$main_title" ] && main_title="1"

    local track_num
    track_num=$(printf "%02d" "$main_title")
    local output_file="${OUTPUT_DIR}/DVD_Rip_${timestamp}_T${track_num}.mp4"

    log "Executing: HandBrakeCLI -i $DVD_DEVICE -o $output_file --title $main_title ${active_preset[*]}"

    HandBrakeCLI -i "$DVD_DEVICE" -o "$output_file" --title "$main_title" "${active_preset[@]}"
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
            convert_dvd
            
            # Cooldown pause to swap discs without immediate re-triggering
            sleep 30
        else
            log "Disc detected, but drive is busy. Retrying in 15s..."
        fi
    fi

    sleep 15
done