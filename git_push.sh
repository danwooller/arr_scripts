#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/common_functions.sh"

# 1. Detect the Real User
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER=$(id -u -n)
fi

CURRENT_HOSTNAME=$(hostname)

# 2. Configuration
GH_USER="danwooller"
GH_EMAIL="danwooller@gmail.com"
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
sudo chown "$REAL_USER:$REAL_USER" "$DEST_DIR/$FILENAME"

cd "$DEST_DIR" || exit

# 5. Auto-Initialize Git if missing
if [ ! -d ".git" ]; then
    echo "Initializing new Git repository in $DEST_DIR..."
    sudo -u "$REAL_USER" git init
    sudo -u "$REAL_USER" git remote add origin "https://$GH_USER@github.com/$GH_USER/arr_scripts.git"
    # Force local branch to be named 'main'
    sudo -u "$REAL_USER" git branch -M main
fi

# 6. Safety & Identity
sudo chown -R "$REAL_USER:$REAL_USER" "$DEST_DIR"
sudo rm -f .git/index.lock

# Apply GitHub identity locally to this repo
sudo -u "$REAL_USER" git config user.name "$GH_USER"
sudo -u "$REAL_USER" git config user.email "$GH_EMAIL"
sudo -u "$REAL_USER" git config credential.helper store

# Ensure we are on the 'main' branch locally
CURRENT_BRANCH=$(sudo -u "$REAL_USER" git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
    sudo -u "$REAL_USER" git branch -M main
fi

# 7. Sync and Push
echo "Using System User: $REAL_USER on $CURRENT_HOSTNAME"
echo "Checking $FILENAME for changes..."

# Stage the file to check for differences
sudo -u "$REAL_USER" git add "$FILENAME"

# Check if there are ACTUAL differences
if ! sudo -u "$REAL_USER" git diff --cached --exit-code > /dev/null; then
    echo "Actual changes detected. Committing..."
    sudo -u "$REAL_USER" git commit -m "Update $FILENAME from $CURRENT_HOSTNAME"
    
    echo "Pulling latest from GitHub (Rebasing)..."
    sudo -u "$REAL_USER" git pull origin main --rebase
    
    echo "Pushing to GitHub..."
    sudo -u "$REAL_USER" git push origin main
    echo "Successfully pushed $FILENAME!"
else
    echo "No actual changes in $FILENAME. Clearing the Git index..."
    # Resetting ensures 'git pull' won't complain about unstaged changes
    sudo -u "$REAL_USER" git reset --hard HEAD
    
    echo "Pulling latest updates from GitHub..."
    sudo -u "$REAL_USER" git pull origin main --rebase
    echo "Local repository is now up to date."
fi

log "Pushed $FILENAME to GitHub..."
