#!/bin/bash

# Run: cd ~/arr_scripts && sudo ./git_pull.sh DW_install_sorttv.sh && cd /usr/local/bin && sudo ./DW_install_sorttv.sh
# to install, includes fixes for really old code
# Run a manual scan: cd /opt/sorttv && ./sort-tv

# --- Load Shared Functions ---
# Checking existence to prevent 'set -e' from killing the script cryptically
if [ -f "/usr/local/bin/DW_common_functions.sh" ]; then
    source "/usr/local/bin/DW_common_functions.sh"
else
    echo "⚠️ /usr/local/bin/DW_common_functions.sh missing. Exiting."
    exit 1
fi

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
log "ℹ️ Installing CPAN modules..."
# Initialize CPAN config and install modules non-interactively
export PERL_MM_USE_DEFAULT=1
perl -MCPAN -e 'CPAN::HandleConfig->load(); CPAN::Config->commit();'
cpan TVDB::API WWW::TheMovieDB

# 5. Directory Setup
log "ℹ️ Preparing /opt/sorttv..."
mkdir -p /opt/sorttv
mkdir -p /opt/sorttv/lib/IO/Uncompress/

# 6. Restore Configuration and Scripts from Backup
SOURCE_PATH="/mnt/media/backup/$(hostname -s)/opt/sorttv"

if [ -d "$SOURCE_PATH" ]; then
    log "ℹ️ Restoring files from $SOURCE_PATH..."
    # Using -a (archive) is often better for preserving permissions/timestamps
    cp -a "$SOURCE_PATH/." /opt/sorttv/
    chmod +x /opt/sorttv/sorttv.pl
    log "ℹ️ Restoration complete."
else
    log "⚠️ ERROR: Backup source $SOURCE_PATH not found!"
    log "⚠️ Ensure your backup drive is mounted before running."
    exit 1
fi

# Bulletproof the TVDB API against malformed responses
log "ℹ️ Applying safety patch to TVDB::API..."
TVDB_API="/usr/local/share/perl/5.38.2/TVDB/API.pm"
if [ -f "$TVDB_API" ]; then
    sudo sed -i 's/return \$self->{xml}->XMLin(\$xml);/my \$data; eval { \$data = \$self->{xml}->XMLin(\$xml) }; if (\$@) { return undef; } return \$data;/' "$TVDB_API"
    log "✅ TVDB::API crash protection applied."
fi

log "ℹ️ Verifying permissions and paths..."
# Get the actual user who called sudo, defaulting to 'dan' if not found
REAL_USER=${SUDO_USER:-dan}
chown -R "$REAL_USER":"$REAL_USER" /opt/sorttv
chmod -R 755 /opt/sorttv/lib

if [ -f "/opt/sorttv/lib/IO/Uncompress/Unzip.pm" ]; then
    log "✅ Local Unzip.pm is in place and readable."
else
    log "⚠️ WARNING: Local Unzip.pm missing from backup! Sorting may crash on malformed MKVs."
fi

if /opt/sorttv/sorttv.pl --version > /dev/null 2>&1; then
    log "✅ SortTV binary is functional."
fi

log_end "Installation Successful!"
