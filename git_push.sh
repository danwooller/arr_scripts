#!/bin/bash

REAL_USER="pi"
DEST_DIR="/home/pi/arr_scripts"
SOURCE_PATH=$1

if [ -z "$SOURCE_PATH" ]; then
    echo "Usage: ./git_push.sh /path/to/file"
    exit 1
fi

FILENAME=$(basename "$SOURCE_PATH")

# 1. Sync file
sudo cp "$SOURCE_PATH" "$DEST_DIR/"
sudo chown $REAL_USER:$REAL_USER "$DEST_DIR/$FILENAME"

cd "$DEST_DIR" || exit

# 2. Identify the active branch (main or master)
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

# 3. Fix permissions and pull
sudo chown -R $REAL_USER:$REAL_USER "$DEST_DIR"
sudo -u $REAL_USER git pull origin "$BRANCH" --rebase

# 4. Add, Commit, and Push
sudo -u $REAL_USER git add "$FILENAME"
sudo -u $REAL_USER git commit -m "Update $FILENAME"
sudo -u $REAL_USER git push origin "$BRANCH"

echo "Pushed to branch: $BRANCH"
