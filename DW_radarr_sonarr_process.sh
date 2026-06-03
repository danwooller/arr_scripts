#!/bin/bash

# Called by radarr - Navigate to Settings > Connect

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# --- Sonarr/Radarr Variable Detection ---
# This allows the script to work regardless of which service calls it
FILE_PATH="${sonarr_episodefile_path:-$radarr_moviefile_path}"
TITLE="${sonarr_series_title:-$radarr_movie_title}"

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
    exit 0
fi

log "📺 Processing: $TITLE"

# --- STEP 1: Audio & Subtitle Cleanup ---
# Filters tracks based on your English/Forced logic
audio_subtitle_opt "$FILE_PATH"

TEMP_CLEAN="${FILE_PATH}.clean"
if mkvmerge -q -o "$TEMP_CLEAN" $TRACK_OPTS "$FILE_PATH"; then
    mv "$TEMP_CLEAN" "$FILE_PATH"
    log "✅ Step 1: Optimization Complete (Tracks stripped)."
else
    log "❌ Step 1 Failed."
    rm -f "$TEMP_CLEAN"
    exit 1
fi

# --- STEP 2: Sonos Audio Fix ---
# Transcodes audio to AC3/EAC3 for Sonos compatibility
if sonos_audio_fix "$FILE_PATH"; then
    log "✅ Step 2: Sonos Fix Complete."
else
    log "⚠️ Step 2: Sonos Fix skipped or failed (check logs)."
fi

# --- STEP 3: Final Flags & Extraction ---
if [ "$NEEDS_PROPEDIT" = true ]; then
    log "📝 Finalizing: Extracting forced subtitles and setting flags..."
    
    # 1. Extract the subtitle first as an external backup
    subtitle_extract "$FILE_PATH"
    
    # 2. Set the flags on the internal track
    # Note: track:s1 assumes this is the first subtitle track after remux
    if mkvpropedit "$FILE_PATH" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1; then
        log "✅ Internal flags set and subtitle extracted."
    else
        log "⚠️ Subtitle flags could not be set."
    fi
fi

log "🏁 All processing finished for $TITLE"
