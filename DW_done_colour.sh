#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

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
REMOTE_CONVERT_FOLDER="$DIR_MEDIA_TORRENT/$(hostname)/$(hostname)_convert"
REMOTE_FORCED_FOLDER="$DIR_MEDIA_TORRENT/$(hostname)/subtitles/forced"

REFRESH_INTERVAL=10
MAX_FILES=4

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

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

    # Get Free Space (in GB for easier threshold comparison)
    # Using df -m gives us Megabytes; we then divide by 1024 for GB
    local free_space_m=$(df -m "$dir" | awk 'NR==2 {print $4}')
    local free_space_gb=$((free_space_m / 1024))
    
    # Set color for free space warning
    local fs_color=$NC
    if [ "$free_space_gb" -lt 5 ]; then
        fs_color=$RED
    fi
    
    local count=$(find "$dir" -maxdepth 1 -type f | wc -l)
    
    # 1. Directory Header - BOLD with Color-Coded Free Space
    local dir_str="$dir ($count files)"
    local fs_str=" [Free: ${free_space_gb}G]"
    
    printf "│%b%s%b%b%s%b%*s│\n" "$BOLD" "$dir_str" "$NC" "$fs_color" "$fs_str" "$NC" "$((INNER - ${#dir_str} - ${#fs_str}))" ""

    # 2. Check for empty directory
    if [ "$count" -eq 0 ]; then
        local empty_msg="    (No files found)"
        printf "│%s%*s│\n" "$empty_msg" "$((INNER - ${#empty_msg}))" ""
    else
        # 3. File List with Color-Coded Sizes (Warning for >10G)
        ls -lh "$dir" 2>/dev/null | tail -n +2 | head -n $MAX_FILES | while read -r line; do
            size_human=$(echo "$line" | awk '{print $5}')
            name=$(echo "$line" | awk '{for(i=9;i<=NF;i++) printf $i (i==NF?"":FS); print ""}')
            
            local color=$NC
            
            # 1. Handle Gigabytes (G)
            if [[ $size_human == *G ]]; then
                # Strip 'G' AND strip any decimal (e.g., 3.4G becomes 3)
                val_raw=${size_human%G}
                val_int=${val_raw%.*} 
                
                if [ "$val_int" -ge 10 ]; then
                    color=$RED
                else
                    color=$YELLOW
                fi
                
            # 2. Handle Megabytes (M)
            elif [[ $size_human == *M ]]; then
                val_raw=${size_human%M}
                val_int=${val_raw%.*}
                
                # Green if 500MB or larger
                [ "$val_int" -ge 500 ] && color=$GREEN
            fi

            # Padding and Display
            local max_n=$(( INNER - ${#size_human} - 1 ))
            [ ${#name} -gt $max_n ] && name="${name:0:$((max_n - 3))}..."
            local pad_len=$(( INNER - 1 - ${#size_human} - ${#name} ))
            [ $pad_len -lt 0 ] && pad_len=0
            
            printf "│%b%s%b %s%*s│\n" "$color" "$size_human" "$NC" "$name" "$pad_len" ""
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
tput civis
trap "tput cnorm; exit" INT TERM

while true; do
    clear
    print_hr "┌" "─" "┐"

    header="$(hostname) [$(date +%H:%M:%S)]"
    load_1m=$(awk '{print $1}' /proc/loadavg)
    load_str="Load: $load_1m"
    
    load_color=$NC
    # Use standard shell comparison for simplicity where possible, 
    # but bc is safer for decimals as per your original script
    if (( $(echo "$load_1m > 4.0" | bc -l 2>/dev/null || echo 0) )); then
        load_color=$RED
    elif (( $(echo "$load_1m > 2.0" | bc -l 2>/dev/null || echo 0) )); then
        load_color=$YELLOW
    fi

    mid_pad=$(( INNER - ${#header} - ${#load_str} ))
    [ $mid_pad -lt 0 ] && mid_pad=0

    printf "│%s%*s%b%s%b│\n" "$header" "$mid_pad" "" "$load_color" "$load_str" "$NC"

    print_hr "├" "─" "┤"

    print_section "$LOCAL_DONE_FOLDER"
    print_section "$LOCAL_CONVERT_FOLDER"
    print_section "$REMOTE_CONVERT_FOLDER"
    print_section "$REMOTE_FORCED_FOLDER"

    print_hr "└" "─" "┘"

    last_fetch=$(date +%H:%M:%S)

    for ((i=REFRESH_INTERVAL; i>0; i--)); do
        printf "\r\033[K  [Data Last Fetched: %s]  Next Refresh in: %2d seconds... (Ctrl+C)" "$last_fetch" "$i"
        sleep 1
    done
done
