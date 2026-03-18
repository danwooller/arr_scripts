#!/bin/bash

# 1. Setup Variables
WIDTH=${1:-80}
INNER=$((WIDTH - 2))

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

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 2. Define Functions
print_hr() {
    local left=$1 middle=$2 right=$3
    printf "%s" "$left"
    printf "%.0s$middle" $(seq 1 "$INNER")
    printf "%s\n" "$right"
}

print_section() {
    local dir=$1
    [ ! -d "$dir" ] && return

    # ANSI Colors & Formatting
    local BOLD='\033[1m'
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'

    local count=$(find "$dir" -maxdepth 1 -type f | wc -l)
    
    # Directory Header - Now BOLD
    local dir_str="$dir ($count files)"
    # We apply BOLD to the string but calculate padding based on raw text length
    printf "│%b%s%b%*s│\n" "$BOLD" "$dir_str" "$NC" "$((INNER - ${#dir_str}))" ""

    # File List
    ls -lh "$dir" 2>/dev/null | tail -n +2 | head -n $MAX_FILES | while read -r line; do
        size=$(echo "$line" | awk '{print $5}')
        name=$(echo "$line" | awk '{for(i=9;i<=NF;i++) printf $i (i==NF?"":FS); print ""}')
        
        local color=$NC
        if [[ $size == *G* ]]; then
            color=$RED
        elif [[ $size == *M* ]]; then
            [[ ${size:0:1} =~ [5-9] ]] && color=$YELLOW || color=$GREEN
        fi

        local max_n=$(( INNER - ${#size} - 1 ))
        [ ${#name} -gt $max_n ] && name="${name:0:$((max_n - 3))}..."

        local pad_len=$(( INNER - 1 - ${#size} - ${#name} ))
        [ $pad_len -lt 0 ] && pad_len=0
        
        printf "│%b%s%b %s%*s│\n" "$color" "$size" "$NC" "$name" "$pad_len" ""
    done

    # Footer/More logic
    if [ "$count" -gt "$MAX_FILES" ]; then
        local more="    ... ($((count - MAX_FILES)) more)"
        printf "│%s%*s│\n" "$more" "$((INNER - ${#more}))" ""
    fi
    printf "│%*s│\n" "$INNER" ""
}

# 3. The Execution Loop
# Hide the cursor for a cleaner look
tput civis
trap "tput cnorm; exit" INT TERM # Show cursor again on exit

while true; do
    clear
    print_hr "┌" "─" "┐"
    
    header="$(hostname) [$(date +%H:%M:%S)]"
    printf "│%s%*s│\n" "$header" "$((INNER - ${#header}))" ""
    
    print_hr "├" "─" "┤"

    print_section "$LOCAL_DONE_FOLDER"
    print_section "$LOCAL_CONVERT_FOLDER"
    print_section "$REMOTE_CONVERT_FOLDER"

    print_hr "└" "─" "┘"

    # Fixed Countdown at the bottom
    for ((i=REFRESH_INTERVAL; i>0; i--)); do
        # Move to the start of the line and clear to end of line
        printf "\r\033[K  Refresh in: %2d seconds... (Ctrl+C to stop)" "$i"
        sleep 1
    done
done
