#!/bin/bash

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

log_start

# --- Setup Library Mappings ---
# We pair the directory with its corresponding Plex Section ID and Library Name.
# Adjust the Section IDs (the numbers) to match your actual Plex setup.
DIR_1="$DIR_MEDIA_TV"
SEC_1="2"
NAM_1="TV"

DIR_2="$DIR_MEDIA_MOVIES"
SEC_2="1"
NAM_2="Movies"

DIR_3="$DIR_SYNOLOGY_TV"
SEC_3="2"
NAM_3="TV"

DIR_4="$DIR_SYNOLOGY_MOVIES"
SEC_4="1"
NAM_4="Movies"

# --- Step 1: Select Library ---
echo "============================================="
echo "  Plex 'Recently Added' Date Modifier"
echo "============================================="
echo "Select the library directory to view:"
echo "1) Media - TV Show ($DIR_1)"
echo "2) Media - Movies ($DIR_2)"
echo "3) Synology - TV Show ($DIR_3)"
echo "4) Synology - Movies ($DIR_4)"
echo "5) Exit"
echo "---------------------------------------------"
read -rp "Enter choice [1-5]: " lib_choice

case "$lib_choice" in
    1) TARGET_DIR="$DIR_1"; PLEX_SEC="$SEC_1"; PLEX_NAM="$NAM_1" ;;
    2) TARGET_DIR="$DIR_2"; PLEX_SEC="$SEC_2"; PLEX_NAM="$NAM_2" ;;
    3) TARGET_DIR="$DIR_3"; PLEX_SEC="$SEC_3"; PLEX_NAM="$NAM_3" ;;
    4) TARGET_DIR="$DIR_4"; PLEX_SEC="$SEC_4"; PLEX_NAM="$NAM_4" ;;
    *) echo "Exiting."; exit 0 ;;
esac

# Verify target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    log "FAIL: Target directory $TARGET_DIR does not exist."
    echo "Error: $TARGET_DIR is not accessible."
    exit 1
fi

# --- Step 2: List Top 10 Directories ---
echo ""
echo "Fetching top 10 most recently modified items in $TARGET_DIR..."
echo "------------------------------------------------------------------------"

cd "$TARGET_DIR" || exit 1

# Safely parse directories into an array
IFS=$'\n' read -r -d '' -a dirs < <(find . -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\n' | sort -rn | head -n 200 | cut -d' ' -f2- && printf '\0')

if [ ${#dirs[@]} -eq 0 ]; then
    echo "No directories found."
    exit 0
fi

# Present selection menu
for i in "${!dirs[@]}"; do
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

selected_item="${dirs[$((item_choice-1))]}"
absolute_path="$TARGET_DIR/${selected_item#./}"

# --- Step 3: Backdate the Directory and all its contents ---
# Calculate date 1 year in the past
backdate=$(date -d "1 year ago" +%Y%m%d%H%M.%S 2>/dev/null || date -v -1y +%Y%m%d%H%M.%S)

echo "Updating modification date for: ${selected_item#./} (including all seasons/files)..."
echo "Setting modification time to 1 year ago..."

# Added the -h flag (to not follow symlinks) and applied touch recursively
if find "$absolute_path" -exec touch -h -t "$backdate" {} +; then
    log "PASS: Recursively backdated ${selected_item#./} to prevent Plex pickup."
    echo "Success! Show, Season folders, and media files have been backdated."
    
    # --- Step 4: Optional Plex Library Update ---
    echo "---------------------------------------------"
    read -rp "Would you like to trigger a Plex library update for '$PLEX_NAM' now? [y/N]: " trigger_choice
    case "$trigger_choice" in
        [yY][eE][sS]|[yY])
            echo "Calling plex_library_update for Section $PLEX_SEC ($PLEX_NAM)..."
            # Execute your common function
            plex_library_update "$PLEX_SEC" "$PLEX_NAM"
            ;;
        *)
            echo "Plex scan skipped. Run a manual scan in Plex later to apply changes."
            ;;
    esac
else
    log "FAIL: Failed to touch directory ${selected_item#./}"
    echo "Error updating directory timestamp. Check permissions."
fi
