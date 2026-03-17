#!/bin/bash

# Hard-code the width for consistency
WIDTH=${1:-80}
INNER="$((WIDTH-2))"

# Configuration
if [[ $HOSTNAME == "pi"* ]]; then HOME_DIR="/home/pi"; else HOME_DIR="/home/dan"; fi
LOCAL_DONE_FOLDER="$HOME_DIR/$(hostname)_done"
LOCAL_CONVERT_FOLDER="$HOME_DIR/convert"
REMOTE_CONVERT_FOLDER="/mnt/media/torrent/$(hostname)_convert"

REFRESH_INTERVAL=30
MAX_FILES=10

while true; do
  clear
  printf "┌"; printf '─%.0s' $(seq 1 $INNER); printf "┐\n"
  header="$(hostname) [$(date +%H:%M:%S)]"
  printf "│%-${INNER}s│\n" "$header"
  printf "├"; printf '─%.0s' $(seq 1 $INNER); printf "┤\n"

  print_section() {
    local dir=$1
    #local count=$(ls -1 "$dir" 2>/dev/null | wc -l)
    # Faster counting for large directories
    local count=$(find "$dir" -maxdepth 1 -type f | wc -l)
    printf "│ %-76s │\n" "$dir ($count files)"

    ls -lh "$dir" 2>/dev/null | tail -n +2 | head -n $MAX_FILES | while read -r line; do
        # Extract size (col 5) and name (everything after col $MAX_FILES)
        size=$(echo "$line" | awk '{print $5}')
        name=$(echo "$line" | cut -d' ' -f9-)
        # Truncate name to fit (78 - 4 padding - $MAX_FILES size - 2 gap = 64)
        [ ${#name} -gt 64 ] && name="${name:0:61}..."
        printf "│   %-8s %-65s │\n" "$size" "$name"
    done
    if [ "$count" -gt "$MAX_FILES" ]; then
        # The text inside the box excluding the borders
        info_string="   ... ($((count - MAX_FILES)) more)"
        # Total INNER (78) - length of the text string
        pad_len=$((INNER - ${#info_string}))
        # Print the string followed by spaces, then the closing border
        printf "│%s%${pad_len}s│\n" "$info_string" ""
    fi
    #printf "│%78s│\n" ""
    printf "│%-${INNER}s│\n" ""
  }

  print_section "$LOCAL_DONE_FOLDER"
  print_section "$LOCAL_CONVERT_FOLDER"
  print_section "$REMOTE_CONVERT_FOLDER"

  printf "└"; printf '─%.0s' $(seq 1 $INNER); printf "┘\n"

  for ((i=REFRESH_INTERVAL; i>0; i--)); do
    printf "\r  Refresh in: %2d seconds... (Ctrl+C to stop)" "$i"
    sleep 1
  done
done
