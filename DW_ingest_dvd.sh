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
set -euo pipefail
DVD_DEVICE="${1:-/dev/sr0}"
OUTPUT_DIR="${2:-/mnt/storage/media/dvd_ingest}"
DEFAULT_PRESET="General/Fast 576p25"
POLL_INTERVAL=5

# --- Disc Detection Helpers ---
is_disc_inserted() {
  local dev="$1"
  # Use udevadm to check physical media state
  if udevadm info --query=property --name="$dev" 2>/dev/null | grep -q "ID_CDROM_MEDIA=1"; then
    return 0
  fi
  return 1
}

wait_for_disc_ready() {
  local dev="$1"
  log "Disc inserted. Waiting for drive to settle..."
  sleep 5
  
  # Ensure drive isn't busy or locked by another process
  while lsof "$dev" >/dev/null 2>&1; do
    log "Drive $dev is busy, waiting..."
    sleep 3
  done
}

# --- Resolution Detection & Preset Fallback ---
detect_preset() {
  local dev="$1"
  local res_info
  
  # Capture scan output safely
  if res_info=$(HandBrakeCLI -i "$dev" --min-duration 0 --scan 2>&1); then
    if echo "$res_info" | grep -q "576i\|576p\|720x576"; then
      echo "General/Fast 576p25"
      return 0
    elif echo "$res_info" | grep -q "480i\|480p\|720x480"; then
      echo "General/Fast 480p30"
      return 0
    fi
  fi

  # Log warning via DW_common_functions (stderr), return ONLY clean string to stdout
  log "Could not parse native disc resolution. Defaulting to ${DEFAULT_PRESET}."
  echo "$DEFAULT_PRESET"
}

# --- Title Detection ---
detect_main_title() {
  local dev="$1"
  local main_title

  # Parse main feature title from HandBrake scan output
  main_title=$(HandBrakeCLI -i "$dev" --title 0 2>&1 | grep "+ title " | awk '{print $3}' | tr -d ':' | head -n 1)

  # Ensure main_title is purely numeric
  if [[ -n "$main_title" && "$main_title" =~ ^[0-9]+$ ]]; then
    echo "$main_title"
  else
    log "Could not automatically determine main title. Defaulting to title 1."
    echo "1"
  fi
}

# --- Main Service Loop ---
mkdir -p "$OUTPUT_DIR"
log "Starting DVD ingestion daemon monitoring ${DVD_DEVICE}..."

while true; do
  if is_disc_inserted "$DVD_DEVICE"; then
    wait_for_disc_ready "$DVD_DEVICE"

    log "Starting DVD ingestion scan..."

    PRESET=$(detect_preset "$DVD_DEVICE")
    TITLE_NUM=$(detect_main_title "$DVD_DEVICE")

    TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
    OUTPUT_FILE="${OUTPUT_DIR}/DVD_Ingest_${TIMESTAMP}.mp4"

    log "Selected Title: ${TITLE_NUM} | Selected Preset: ${PRESET}"
    log "Beginning transcoding output to ${OUTPUT_FILE}..."

    # Executing HandBrake with strictly quoted arguments
    if HandBrakeCLI \
      --input "$DVD_DEVICE" \
      --output "$OUTPUT_FILE" \
      --title "$TITLE_NUM" \
      --preset "$PRESET" \
      2>&1; then
      
      log "DVD ingestion completed successfully."
    else
      log "HandBrakeCLI transcode failed."
    fi

    log "Ejecting disc from ${DVD_DEVICE}..."
    eject "$DVD_DEVICE" || true
    
    # Pause to allow user time to swap disc before re-polling
    sleep 10
  fi

  sleep "$POLL_INTERVAL"
done