#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- File & Title Detection ---
INPUT_PATH="${1:-${sonarr_episodefile_path:-$radarr_moviefile_path}}"

if [[ -z "$INPUT_PATH" ]]; then
    echo "❌ Error: No input path provided."
    echo "Usage: $0 <path_to_mkv_file_or_directory> [target_directory]"
    exit 1
fi

# If $1 is a directory, find the first .mkv file inside it
if [[ -d "$INPUT_PATH" ]]; then
    INPUT_FILE=$(find "$INPUT_PATH" -maxdepth 2 -type f -name "*.mkv" | head -n 1)
    if [[ -z "$INPUT_FILE" ]]; then
        echo "❌ Error: No .mkv file found inside directory '$INPUT_PATH'."
        exit 1
    fi
else
    INPUT_FILE="$INPUT_PATH"
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "❌ Error: File '$INPUT_FILE' does not exist."
    exit 1
fi

TITLE="${sonarr_series_title:-${radarr_movie_title:-$(basename "$INPUT_FILE" | sed 's/\.[^.]*$//')}}"
FILE_PATH="$INPUT_FILE"

# --- Target Folder Handling ($2) ---
TARGET_DIR="$2"

if [[ -n "$TARGET_DIR" ]]; then
    mkdir -p "$TARGET_DIR"
    
    FILENAME=$(basename "$FILE_PATH")
    NEW_FILE_PATH="$TARGET_DIR/$FILENAME"
    
    if [[ "$FILE_PATH" != "$NEW_FILE_PATH" ]]; then
        log "📦 Moving file to target folder: $TARGET_DIR"
        if mv "$FILE_PATH" "$NEW_FILE_PATH"; then
            FILE_PATH="$NEW_FILE_PATH"
        else
            log "❌ Failed to move file to $TARGET_DIR. Exiting."
            exit 1
        fi
    fi
fi

log "📺 Processing: $TITLE"

# Setup temporary working path in the SAME directory
TARGET_DIR_PATH=$(dirname "$FILE_PATH")
TARGET_FILENAME=$(basename "$FILE_PATH")
TEMP_WORK_FILE="${TARGET_DIR_PATH}/.${TARGET_FILENAME}.tmp"

# --- STEP 1: Audio & Subtitle Cleanup ---
audio_subtitle_opt "$FILE_PATH"

if mkvmerge -q -o "$TEMP_WORK_FILE" $TRACK_OPTS "$FILE_PATH"; then
    mv "$TEMP_WORK_FILE" "$FILE_PATH"
    log "✅ Step 1: Optimization Complete (Tracks stripped)."
else
    log "❌ Step 1 Failed."
    rm -f "$TEMP_WORK_FILE"
    exit 1
fi

# --- STEP 2: Sonos Audio Fix ---
# Note: Ensure sonos_audio_fix accepts output path or handles temp file internally
if sonos_audio_fix "$FILE_PATH"; then
    log "✅ Step 2: Sonos Fix Complete."
else
    log "⚠️ Step 2: Sonos Fix skipped or failed (check logs)."
fi

# --- STEP 3: Final Flags & Extraction ---
if [ "$NEEDS_PROPEDIT" = true ]; then
    log "📝 Finalizing: Extracting forced subtitles and setting flags..."
    subtitle_extract "$FILE_PATH"
    
    if mkvpropedit "$FILE_PATH" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1; then
        log "✅ Internal flags set and subtitle extracted."
    else
        log "⚠️ Subtitle flags could not be set."
    fi
fi

log "🏁 All processing finished for $TITLE"