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
MIN_DURATION_SECS=900  # 15 minutes in seconds

# --- LOAD SHARED FUNCTIONS ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ Common functions missing."
    exit 1
fi

# ------------------------------------------------------------------------------
# Cleanup / Trap Handling
# ------------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    # Guard with ${LOCK_FILE:-} so 'set -u' never throws an unbound error on exit
    if [[ -n "${LOCK_FILE:-}" ]] && [[ -f "${LOCK_FILE:-}" ]]; then
        rm -f "${LOCK_FILE}"
    fi
    exit "${exit_code}"
}
trap cleanup EXIT INT TERM

# Prevent duplicate execution
if [[ -f "${LOCK_FILE}" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Lockfile exists at ${LOCK_FILE}. Process already running."
    exit 0
fi
touch "${LOCK_FILE}"

# ------------------------------------------------------------------------------
# Main Processing Logic
# ------------------------------------------------------------------------------
mkdir -p "${OUTPUT_DIR}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting DVD scan on ${INPUT_DRIVE}..."

# Scan disc structure and capture stdout/stderr to parse title durations
SCAN_OUTPUT=$(HandBrakeCLI --input "${INPUT_DRIVE}" --title 0 --min-duration "${MIN_DURATION_SECS}" 2>&1 || true)

# Extract all valid title numbers matching the minimum duration filter
# HandBrake prints candidate titles formatted as "+ title X:"
mapfile -t VALID_TITLES < <(echo "${SCAN_OUTPUT}" | grep -E '^\+ title [0-9]+:' | awk '{print $3}' | tr -d ':')

if [[ ${#VALID_TITLES[@]} -eq 0 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No valid titles found over $((MIN_DURATION_SECS / 60)) minutes. Ejecting."
    eject "${INPUT_DRIVE}" || true
    exit 0
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found ${#VALID_TITLES[@]} title(s) matching criteria: ${VALID_TITLES[*]}"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Loop over each qualifying episode title
for TITLE_NUM in "${VALID_TITLES[@]}"; do
    OUTPUT_FILE="${OUTPUT_DIR}/DVD_Ingest_${TIMESTAMP}_T${TITLE_NUM}.mp4"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ripping Title ${TITLE_NUM} -> ${OUTPUT_FILE}"
    
    HandBrakeCLI \
        --input "${INPUT_DRIVE}" \
        --output "${OUTPUT_FILE}" \
        --title "${TITLE_NUM}" \
        --min-duration "${MIN_DURATION_SECS}" \
        --crop 0:0:0:0 \
        --preset "Normal" \
        --quality 20 \
        --encoder x264 \
        --aencoder aac \
        --comb-detect \
        --decomb

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Completed Title ${TITLE_NUM}."
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] All titles processed successfully. Ejecting disc."
eject "${INPUT_DRIVE}" || true