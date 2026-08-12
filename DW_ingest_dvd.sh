#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# DW_ingest_dvd.sh
# Automated DVD Ingest Script for Multi-Episode TV Discs & Movies
# ------------------------------------------------------------------------------

# 1. Define LOCK_FILE BEFORE sourcing shared functions
# (Ensures variables exist if common functions bind EXIT/TERM traps immediately)
LOCK_FILE="/tmp/DW_ingest_dvd.lock"
INPUT_DRIVE="/dev/sr0"
OUTPUT_DIR="/mnt/storage/media/dvd_ingest"
MIN_DURATION_SECS=300  # 5 minutes in seconds

# --- LOAD SHARED FUNCTIONS ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ Common functions missing."
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. Concurrency Control (Single Instance Lock)
# ------------------------------------------------------------------------------
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log_msg "INFO" "Another instance of DW_ingest_dvd.sh is actively running. Exiting."
    exit 0
fi

cleanup() {
    log_msg "INFO" "Releasing process locks and terminating ingest sequence."
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT INT TERM

log_msg "INFO" "======================================================================"
log_msg "INFO" "Starting DVD ingestion job on target drive: ${DVD_DEVICE}"

# Verify device node availability
if [[ ! -b "$DVD_DEVICE" ]]; then
    log_msg "ERROR" "Specified device node '${DVD_DEVICE}' does not exist or is not a block device."
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. Dynamic Resolution Probing & Preset Selection
# ------------------------------------------------------------------------------
log_msg "INFO" "Scanning disc geometry with HandBrakeCLI to calculate dynamic preset..."

# Scan disc metadata to extract frame height integer
SCAN_DATA=$(HandBrakeCLI --min-duration 0 -i "$DVD_DEVICE" --title 0 --scan 2>&1 || true)
PROBED_HEIGHT=$(echo "$SCAN_DATA" | grep -oP '\d+(?=x\d+)' | head -n 1 || echo "")

# Map geometry directly to modern HandBrake category namespaces
case "$PROBED_HEIGHT" in
    576)
        HB_PRESET="General/Fast 576p25"      # Standard UK / PAL DVD
        ;;
    480)
        HB_PRESET="General/Fast 480p30"      # Standard NTSC DVD
        ;;
    720)
        HB_PRESET="General/Fast 720p30"      # HD broadcast / standard source
        ;;
    1080)
        HB_PRESET="General/Fast 1080p30"     # Full HD source
        ;;
    *)
        # Safeguard fallback when scan stream fails to output discrete dimensions
        log_msg "WARN" "Could not parse vertical height reliably (probed value: '${PROBED_HEIGHT:-empty}'). Defaulting to PAL SD preset."
        HB_PRESET="General/Fast 576p25"
        ;;
esac

log_msg "INFO" "Detected resolution: ${PROBED_HEIGHT:-Unknown}p | Selected HandBrake Preset: '${HB_PRESET}'"

# ------------------------------------------------------------------------------
# 4. Disc Metadata Parsing & Directory Setup
# ------------------------------------------------------------------------------
log_msg "INFO" "Querying lsdvd for disc label and title track layouts..."

RAW_LABEL=$(lsdvd "$DVD_DEVICE" 2>/dev/null | grep -i "Disc Title:" | cut -d: -f2 | xargs || echo "")
if [[ -z "$RAW_LABEL" || "$RAW_LABEL" == "null" ]]; then
    DISC_LABEL="DVD_$(date +%Y%m%d_%H%M%S)"
else
    # Sanitize label for filesystem safety
    DISC_LABEL=$(echo "$RAW_LABEL" | tr ' ' '_' | tr -cd '[:alnum:]_')
fi

TARGET_DIR="${INGEST_RAW_DIR:-/media/ingest/dvds}/${DISC_LABEL}"
mkdir -p "$TARGET_DIR"

log_msg "INFO" "Target destination initialized: ${TARGET_DIR}"

# ------------------------------------------------------------------------------
# 5. Multi-Title Batch Transcode Processing Loop
# ------------------------------------------------------------------------------
# Extract track titles matching minimum duration filter to handle both TV series & movies
MATCHED_TITLES=$(HandBrakeCLI --input "$DVD_DEVICE" --title 0 --min-duration "$MIN_DURATION" --scan 2>&1 \
    | grep -oP '^\+ title \K\d+' || echo "")

if [[ -z "$MATCHED_TITLES" ]]; then
    log_msg "WARN" "No titles found matching minimum duration criteria (${MIN_DURATION}s). Falling back to main-feature encoding."
    MATCHED_TITLES="main"
fi

PROCESSING_ERRORS=0

for TITLE_NUM in $MATCHED_TITLES; do
    if [[ "$TITLE_NUM" == "main" ]]; then
        OUTPUT_FILE="${TARGET_DIR}/${DISC_LABEL}_main.mp4"
        LOG_LABEL="Main Feature"
        HB_TITLE_FLAG="--main-feature"
    else
        OUTPUT_FILE="${TARGET_DIR}/${DISC_LABEL}_title_${TITLE_NUM}.mp4"
        LOG_LABEL="Title Track #${TITLE_NUM}"
        HB_TITLE_FLAG="--title ${TITLE_NUM}"
    fi

    log_msg "INFO" "Starting transcode for ${LOG_LABEL} -> $(basename "$OUTPUT_FILE")"

    # Transcode execution enforcing raw dimension retention via --crop 0:0:0:0
    if HandBrakeCLI \
        --input "$DVD_DEVICE" \
        $HB_TITLE_FLAG \
        --output "$OUTPUT_FILE" \
        --preset "$HB_PRESET" \
        --crop 0:0:0:0 \
        --format av_mp4 \
        >> "${LOG_FILE:-/dev/null}" 2>&1; then
        
        log_msg "INFO" "Successfully transcoded ${LOG_LABEL}."
    else
        log_msg "ERROR" "Transcode failed for ${LOG_LABEL} on device ${DVD_DEVICE}."
        ((PROCESSING_ERRORS++))
    fi
done

# ------------------------------------------------------------------------------
# 6. Post-Processing & Ejection Cleanup
# ------------------------------------------------------------------------------
if [[ $PROCESSING_ERRORS -eq 0 ]]; then
    log_msg "INFO" "All titles processed successfully for disc '${DISC_LABEL}'."
    
    if command -v eject >/dev/null 2>&1; then
        log_msg "INFO" "Ejecting media from ${DVD_DEVICE}..."
        eject "$DVD_DEVICE" || log_msg "WARN" "Eject command failed or device busy."
    fi
    exit 0
else
    log_msg "ERROR" "Completed processing with ${PROCESSING_ERRORS} failed title(s)."
    exit 1
fi