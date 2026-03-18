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
    
    # 1. Directory Header - BOLD
    local dir_str="$dir ($count files)"
    printf "│%b%s%b%*s│\n" "$BOLD" "$dir_str" "$NC" "$((INNER - ${#dir_str}))" ""

    # 2. Check for empty directory
    if [ "$count" -eq 0 ]; then
        local empty_msg="    (No files found)"
        printf "│%s%*s│\n" "$empty_msg" "$((INNER - ${#empty_msg}))" ""
    else
        # 3. File List with Color-Coded Sizes
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
    fi

    # 4. "More" files logic
    if [ "$count" -gt "$MAX_FILES" ]; then
        local more="    ... ($((count - MAX_FILES)) more)"
        printf "│%s%*s│\n" "$more" "$((INNER - ${#more}))" ""
    fi

    # Spacer line
    printf "│%*s│\n" "$INNER" ""
}
# 3. The Execution Loop
# Hide the cursor for a cleaner look
tput civis
trap "tput cnorm; exit" INT TERM # Show cursor again on exit

while true; do
    clear
    print_hr "┌" "─" "┐"

    # 1. Prepare Header (Left Side)
    header="$(hostname) [$(date +%H:%M:%S)]"
    
    # 2. Prepare Load (Right Side)
    load_1m=$(awk '{print $1}' /proc/loadavg)
    load_str="Load: $load_1m"
    
    # Determine Color
    load_color=$NC
    if (( $(echo "$load_1m > 4.0" | bc -l 2>/dev/null || echo 0) )); then
        load_color=$RED
    elif (( $(echo "$load_1m > 2.0" | bc -l 2>/dev/null || echo 0) )); then
        load_color=$YELLOW
    fi

    # 3. Calculate Padding
    # INNER - length of left side - length of right side
    mid_pad=$(( INNER - ${#header} - ${#load_str} ))
    [ $mid_pad -lt 0 ] && mid_pad=0

    # 4. Print the Combined Line
    # %s (Header) + %*s (Spaces) + %b%s%b (Colored Load)
    printf "│%s%*s%b%s%b│\n" "$header" "$mid_pad" "" "$load_color" "$load_str" "$NC"

    print_hr "├" "─" "┤"

    print_section "$LOCAL_DONE_FOLDER"
    print_section "$LOCAL_CONVERT_FOLDER"
    print_section "$REMOTE_CONVERT_FOLDER"

    print_hr "└" "─" "┘"

    # Capture the time this specific refresh completed
    last_fetch=$(date +%H:%M:%S)

    for ((i=REFRESH_INTERVAL; i>0; i--)); do
        # \r = start of line, \033[K = clear line
        printf "\r\033[K  [Data Last Fetched: %s]  Next Refresh in: %2d seconds... (Ctrl+C)" "$last_fetch" "$i"
        sleep 1
    done
done
