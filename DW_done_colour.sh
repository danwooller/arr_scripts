# Define Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_section() {
    local dir=$1
    if [ ! -d "$dir" ]; then return; fi

    local count=$(find "$dir" -maxdepth 1 -type f | wc -l)
    
    # Directory Header Line
    local dir_string="$dir ($count files)"
    local dir_pad=$(( INNER - ${#dir_string} ))
    printf "│%s%*s│\n" "$dir_string" "$dir_pad" ""

    ls -lh "$dir" 2>/dev/null | tail -n +2 | head -n $MAX_FILES | while read -r line; do
        size=$(echo "$line" | awk '{print $5}')
        name=$(echo "$line" | awk '{for(i=9;i<=NF;i++) printf $i (i==NF?"":FS); print ""}')
        
        # 1. Determine Color based on unit
        local color=$NC
        if [[ $size == *G ]]; then
            color=$RED     # Gigabytes are Red
        elif [[ $size == *M ]]; then
            # If Megabytes > 500, make it Yellow
            val=$(echo $size | sed 's/M//')
            if (( $(echo "$val > 500" | bc -l 2>/dev/null || echo 0) )); then
                color=$YELLOW
            else
                color=$GREEN
            fi
        fi

        # 2. Truncate name if too long
        local max_name_len=$(( INNER - ${#size} - 1 ))
        if [ ${#name} -gt "$max_name_len" ]; then
            name="${name:0:$((max_name_len - 3))}..."
        fi

        # 3. Calculate padding BEFORE adding color codes
        pad_len=$(( INNER - 1 - ${#size} - ${#name} ))
        (( pad_len < 0 )) && pad_len=0
        
        # 4. Print with Color (Notice %b for the color variable)
        # We use %b to interpret the backslash escapes in the color variable
        printf "│%b%s%b %s%*s│\n" "$color" "$size" "$NC" "$name" "$pad_len" ""
    done

    if [ "$count" -gt "$MAX_FILES" ]; then
        local info_string="    ... ($((count - MAX_FILES)) more)"
        local info_pad=$(( INNER - ${#info_string} ))
        printf "│%s%*s│\n" "$info_string" "$info_pad" ""
    fi

    printf "│%*s│\n" "$INNER" ""
}
