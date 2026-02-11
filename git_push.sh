#!/bin/bash

# 1. Detect Hostname and Set User
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" == *"pi"* ]]; then
    REAL_USER="pi"
else
    REAL_USER="dan"
fi

# 2. Configuration
GH_USER="danwooller"
DEST_DIR="/home/$REAL_USER/arr_scripts"
SOURCE_PATH=$1

if [ -z "$SOURCE_PATH" ]; then
    echo "Usage: ./git_push.sh /path/to/file"
    exit 1
fi

FILENAME=$(basename "$SOURCE_PATH")

# 3. Ensure the local repo directory exists
mkdir -p "$DEST_DIR"

# 4. Sync file from source to local repo
sudo cp "$SOURCE_PATH" "$DEST_DIR/"
sudo chown $REAL_USER:$REAL_USER "$DEST_DIR/$FILENAME"

cd "$DEST_DIR" || exit

# 5. Auto-Initialize Git if missing
if [ ! -d ".git" ]; then
    echo "Initializing new Git repository in $DEST_DIR..."
    sudo -u $REAL_USER git init
    sudo -u $REAL_USER git remote add origin "https://$GH_USER@github.com/$GH_USER/arr_scripts.git"
    sudo -u $REAL_USER git branch -M main
fi

# 6. Safety: Fix permissions and identify as danwooller
sudo chown -R $REAL_USER:$REAL_USER "$DEST_DIR"
sudo rm -f .git/index.lock
sudo -u $REAL_USER git config user.name "$GH_USER"
sudo -u $REAL_USER git config credential.helper store

# 7. Sync and Push
echo "Using user: $REAL_USER on $CURRENT_HOSTNAME"
sudo -u $REAL_USER git pull origin main --rebase
sudo -u $REAL_USER git add "$FILENAME"
sudo -u $REAL_USER git commit -m "Update $FILENAME from $CURRENT_HOSTNAME"
sudo -u $REAL_USER git push origin main

echo "Successfully pushed $FILENAME to GitHub!"
