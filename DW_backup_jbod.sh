#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

log_start

# --- Movie Transfers ---

log "Transferring Movies A-L..."
rsync -rlvP --size-only --include="/[0-9A-La-l¡]*" --exclude="/*" /mnt/media/Movies/ /mnt/Movies_A-L/Movies/ > /dev/null 2>&1
if [ $? -eq 0 ]; then log "Movies A-L: PASS"; else log "Movies A-L: FAIL"; fi

log "Transferring Movies M-S..."
rsync -rlvP --size-only --include="/[M-Sm-s]*" --exclude="/*" /mnt/media/Movies/ /mnt/Movies_M-S/Movies/ > /dev/null 2>&1
if [ $? -eq 0 ]; then log "Movies M-S: PASS"; else log "Movies M-S: FAIL"; fi

log "Transferring Movies T-Z..."
rsync -rlvP --size-only --include="/[T-Zt-z]*" --exclude="/*" /mnt/media/Movies/ /mnt/Movies_T-Z/Movies/ > /dev/null 2>&1
if [ $? -eq 0 ]; then log "Movies T-Z: PASS"; else log "Movies T-Z: FAIL"; fi


# --- TV Transfers ---

log "Transferring TV Shows A-O..."
rsync -rlvP --size-only --include="/[A-Oa-o]*" --exclude="/*" /mnt/media/TV/ /mnt/TV_A-O/TV/ > /dev/null 2>&1
if [ $? -eq 0 ]; then log "TV Shows A-O: PASS"; else log "TV Shows A-O: FAIL"; fi

log "Transferring TV Shows M-Z..."
rsync -rlvP --size-only --include="/[M-ZM-z]*" --exclude="/*" /mnt/media/TV/ /mnt/TV_M-Z/TV/ > /dev/null 2>&1
if [ $? -eq 0 ]; then log "TV Shows M-Z: PASS"; else log "TV Shows M-Z: FAIL"; fi
