#!/bin/bash

# enable truenas4 and reload fstab

# --- Load Shared Functions ---
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

# Ensure the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or using sudo."
  exit 1
fi

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: Missing arguments."
  echo "Usage: sudo $0 <NEW_NAS> <OLD_NAS>"
  echo "Example: sudo $0 truenas4 truenas6"
  exit 1
fi

NEW_NAS=$1
OLD_NAS=$2
FSTAB_FILE="/etc/fstab"
BACKUP_FILE="/etc/fstab.bak"

# 1. Create a backup just in case
cp "$FSTAB_FILE" "$BACKUP_FILE"

echo "Modifying $FSTAB_FILE..."

# 2. Enable truenas4 (remove the '#' at the start of the line)
sed -i "s|^#\(\/\/${NEW_NAS}\.wooller\.com/media\)[[:space:]]|\1 |" "$FSTAB_FILE"

# 3. Disable truenas6 (add a '#' at the start of the line)
sed -i "s|^\(\/\/${OLD_NAS}\.wooller\.com/media\)[[:space:]]|#\1 |" "$FSTAB_FILE"

# 4. Reload the mounts
echo "Unmounting current share..."
umount /mnt/media 2>/dev/null

echo "Mounting new share..."
mount -a

if [ $? -eq 0 ]; then
  echo "Successfully switched to truenas4 and reloaded mounts!"
else
  echo "Error: Mount failed. Restoring backup."
  cp "$BACKUP_FILE" "$FSTAB_FILE"
  exit 1
fi
