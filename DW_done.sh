#!/bin/bash

# Hard-code the width for consistency (default 80)
WIDTH=${1:-80}
INNER=$((WIDTH - 2))

# Configuration
if [[ $HOSTNAME == "pi"* ]]; then 
    HOME_DIR="/home/pi"
else 
    HOME_DIR="/home/dan"
fi

LOCAL_DONE_FOLDER="$HOME_DIR/$(hostname)_done"
LOCAL_CONVERT_FOLDER="$HOME_DIR/convert"
REMOTE_CONVERT_FOLDER="/mnt/media/torrent/$(hostname)_convert"

REFRESH_INTERVAL=30
MAX_FILES=10

# Helper to print a horizontal line
print_hr() {
    local left=$1 middle=$2 right=$3
    printf "%s" "$left"
    printf "%.0s$middle" $(seq 1 "$INNER")
    printf "%s\n" "$right"
}

while true; do
    clear
    # Top Border
    print_hr "┌" "─" "┐"
    
    # Header Line
    header="$(hostname) [$(date +%H:%M:%S)]"
    header_pad=$(( INNER - ${#header} ))
    printf "│%s%*s│\n" "$header" "$header_pad" ""
    
    # Header Divider
    print_hr "├" "─" "┤"

    print_section() {
        local dir=$1
        if [ ! -d "$dir" ]; then return; fi

        local count=$(find "$dir" -maxdepth 1 -type f | wc -l)
        
        # Directory Header Line
        local dir_string="$dir ($count files)"
        local dir_pad=$(( INNER - ${#dir_string} ))
        printf "│%s%*s│\n" "$dir_string" "$dir_pad" ""

        # File List
        # Note: Using awk to get size ($5) and everything from $9 onwards for the name
        ls -lh "$dir" 2>/dev/null | tail -n +2 | head -n $MAX_FILES | while read -r line; do
            size=$(echo "$line" | awk '{print $5}')
            name=$(echo "$line" | awk '{for(i=9;i<=NF;i++) printf $i (i==NF?"":FS); print ""}')
            
            # Truncate name if it's too long to fit (leaving room for size + space + borders)
            local max_name_len=$(( INNER - ${#size} - 1 ))
            if [ ${#name} -gt "$max_name_len" ]; then
                name="${name:0:$((max_name_len - 3))}..."
            fi

            pad_len=$(( INNER - 1 - ${#size} - ${#name} ))
            (( pad_len < 0 )) && pad_len=0
            
            printf "│%s %s%*s│\n" "$size" "$name" "$pad_len" ""
        done

        # "More" files indicator
        if [ "$count" -gt "$MAX_FILES" ]; then
            local info_string="    ... ($((count - MAX_FILES)) more)"
            local info_pad=$(( INNER - ${#info_string} ))
            printf "│%s%*s│\n" "$info_string" "$info_pad" ""
        fi

        # Empty spacer line within the box
        printf "│%*s│\n" "$INNER" ""
    }

    print_section "$LOCAL_DONE_FOLDER"
    print_section "$LOCAL_CONVERT_FOLDER"
    print_section "$REMOTE_CONVERT_FOLDER"

    # Bottom Border
    print_hr "└" "─" "┘"

    for ((i=REFRESH_INTERVAL; i>0; i--)); do
        printf "\r  Refresh in: %2d seconds... (Ctrl+C to stop)" "$i"
        sleep 1
    done
done
