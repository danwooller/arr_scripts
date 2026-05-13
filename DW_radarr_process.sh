#!/bin/bash
source "/usr/local/bin/DW_common_functions.sh"

FILE_PATH="$radarr_moviefile_path"

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
    exit 0
fi

log "🎬 Processing: $radarr_movie_title"

# --- STEP 1: Audio & Subtitle Cleanup ---
# This decides which tracks to keep based on your English/Forced rules
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
# Now we fix the audio on the already-cleaned file
if sonos_audio_fix "$FILE_PATH"; then
    log "✅ Step 2: Sonos Fix Complete."
else
    log "⚠️ Step 2: Sonos Fix skipped or failed (check logs)."
fi

# --- STEP 3: Final Flags ---
# Set the 'Forced' flags if needed after all remuxing is done
if [ "$NEEDS_PROPEDIT" = true ]; then
    mkvpropedit "$FILE_PATH" --edit track:s1 --set name="Forced" --set flag-forced=1 --set flag-default=1 >/dev/null 2>&1
fi

log "🏁 All processing finished for $radarr_movie_title"
