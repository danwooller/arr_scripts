#!/bin/bash

# --- Load Shared Functions ---
source "/usr/local/bin/DW_common_functions.sh"

# Exit immediately if a command exits with a non-zero status
set -e

log_start "SortTV Installation..."

# 1. Ensure the script is run with sudo/root
if [ "$EUID" -ne 0 ]; then 
  log "⚠️ Please run as root (use sudo)"
  exit 1
fi

# 2. Update and Install System Dependencies
log "ℹ️ Updating system packages..."
apt update
apt install -y build-essential libxml-sax-expat-perl make wget unzip rar

# 3. Install Perl Modules (Apt)
log "ℹ️ Installing Perl libraries via apt..."
apt install -y libfile-copy-recursive-perl libwww-perl libxml-simple-perl \
               libjson-parse-perl libgetopt-long-descriptive-perl libswitch-perl

# 4. Install Perl Modules (CPAN)
log "ℹ️ Installing CPAN modules (this may take a minute)..."
# 'PERL_MM_USE_DEFAULT=1' tells CPAN to stay quiet and use default answers
PERL_MM_USE_DEFAULT=1 cpan TVDB::API WWW::TheMovieDB

# 5. Directory Setup
log "ℹ️ Preparing /opt/sorttv..."
mkdir -p /opt/sorttv

# 6. Restore Configuration and Scripts from Backup
SOURCE_PATH="/mnt/media/backup/$(hostname -s)/opt/sorttv"

if [ -d "$SOURCE_PATH" ]; then
    log "ℹ️ Restoring files from $SOURCE_PATH..."
    cp -r "$SOURCE_PATH/." /opt/sorttv/
    chmod +x /opt/sorttv/sorttv.pl
    log "ℹ️ Restoration complete."
else
    log "⚠️ ERROR: Backup source $SOURCE_PATH not found!"
    log "⚠️ Ensure your backup drive is mounted before running."
    exit 1
fi

log_end "Installation Successful!"
