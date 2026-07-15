#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

log_start

# --- Step 1: Select Library ---
echo "============================================="
echo "  Plex 'Recently Added' Date Modifier"
echo "============================================="
echo "Select the library directory to view:"
echo "1) Media - TV Show ($DIR_MEDIA_TV)"
echo "2) Media - Movies ($DIR_MEDIA_MOVIES)"
echo "3) Synology - TV Show ($DIR_SYNOLOGY_TV)"
echo "4) Synology - Movies ($DIR_SYNOLOGY_MOVIES)"
echo "5) Exit"
echo "---------------------------------------------"
read -rp "Enter choice [1-5]: " lib_choice

case "$lib_choice" in
    1) TARGET_DIR="$DIR_MEDIA_TV" ;;
    2) TARGET_DIR="$DIR_MEDIA_MOVIES" ;;
    3) TARGET_DIR="$DIR_SYNOLOGY_TV" ;;
    4) TARGET_DIR="$DIR_SYNOLOGY_MOVIES" ;;
    *) echo "Exiting."; exit 0 ;;
esac

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
    log "FAIL: Target directory $TARGET_DIR does not exist."
    echo "Error: $TARGET_DIR is not accessible."
    exit 1
fi

# --- Step 2: List Top 10 Directories by Modification Time ---
echo ""
echo "Fetching top 10 most recently modified items in $TARGET_DIR..."
echo "------------------------------------------------------------------------"

# Map the top 10 directories into an array
# Using find & stat is more robust, but since you are using standard structure,
# we can parse 'ls -dt */' to target only directories, sorted by time
cd "$TARGET_DIR" || exit 1

IFS=$'\n' read -r -d '' -a dirs < <(find . -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\n' | sort -rn | head -n 10 | cut -d' ' -f2- && printf '\0')

if [ ${#dirs[@]} -eq 0 ]; then
    echo "No directories found."
    exit 0
fi

# Present the directories in a selection menu
for i in "${!dirs[@]}"; do
    # Strip leading "./" for cleaner display
    display_name="${dirs[$i]#./}"
    echo "$((i+1))) $display_name"
done
echo "$(( ${#dirs[@]} + 1 ))) Cancel"
echo "------------------------------------------------------------------------"

read -rp "Select item to modify [1-$(( ${#dirs[@]} + 1 ))]: " item_choice

# Validate choice
if [[ ! "$item_choice" =~ ^[0-9]+$ ]] || [ "$item_choice" -lt 1 ] || [ "$item_choice" -gt "$(( ${#dirs[@]} + 1 ))" ]; then
    echo "Invalid selection. Exiting."
    exit 1
elif [ "$item_choice" -eq "$(( ${#dirs[@]} + 1 ))" ]; then
    echo "Cancelled."
    exit 0
fi

# Get the absolute path of the chosen directory
selected_item="${dirs[$((item_choice-1))]}"
absolute_path="$TARGET_DIR/${selected_item#./}"

# --- Step 3: Backdate the Directory ---
# Calculate date 1 year in the past (compatible with both GNU and BSD date)
backdate=$(date -d "1 year ago" +%Y%m%d%H%M.%S 2>/dev/null || date -v -1y +%Y%m%d%H%M.%S)

echo "Updating modification date for: ${selected_item#./}"
echo "Setting modification time to 1 year ago..."

# Apply the old date to the directory itself and optionally its contents
if touch -t "$backdate" "$absolute_path"; then
    log "PASS: Backdated directory ${selected_item#./} to prevent Plex pickup."
    echo "Success! Remember to run a library scan in Plex to update the library view."
else
    log "FAIL: Failed to touch directory ${selected_item#./}"
    echo "Error updating directory timestamp. Check permissions."
fi
