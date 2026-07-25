#!/bin/sh
set -e

# ============================================
# Variables Configuration
# ============================================
channel="Hazem-Wahba"
version="motor"
REMOTE_URL="https://raw.githubusercontent.com/Ham-ahmed/257/refs/heads/main/channels_backup_20260620.tar.gz"
LOCAL_PATH="/var/volatile/tmp/channels_backup_20260620.tar.gz"
BACKUP_DIR="/tmp/enigma2_backup_$(date +%Y%m%d_%H%M%S)"

# ============================================
# Helper Functions
# ============================================
print_header() {
    echo "*********************************************************"
    echo "*     $1"
    echo "*********************************************************"
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "❌ Error: Please run as root"
        exit 1
    fi
}

check_requirements() {
    for cmd in wget tar grep; do
        if ! command -v $cmd > /dev/null 2>&1; then
            echo "❌ Command $cmd not found"
            exit 1
        fi
    done
}

backup_old_channels() {
    if [ -d "/etc/enigma2" ]; then
        echo "> Creating backup..."
        mkdir -p "$BACKUP_DIR"
        cp -r /etc/enigma2 "$BACKUP_DIR/" 2>/dev/null || true
        echo "✅ Backup at: $BACKUP_DIR"
    fi
}

# ============================================
# Main Execution
# ============================================
check_root
check_requirements
print_header "Downloading $channel $version Channels"

# Download file
cd /var/volatile/tmp
echo "> Downloading..."
if ! wget -O "$LOCAL_PATH" "$REMOTE_URL"; then
    echo "❌ Download failed"
    exit 1
fi

# Verify file integrity
if ! file "$LOCAL_PATH" | grep -q "gzip compressed data"; then
    echo "❌ File format is invalid"
    rm -f "$LOCAL_PATH"
    exit 1
fi

echo "✅ Download completed successfully"
echo "> Installing new channels..."

# Backup
backup_old_channels

# Clean old files (safe)
rm -f /etc/enigma2/lamedb
rm -f /etc/enigma2/userbouquet.*
rm -f /etc/enigma2/*.tv 2>/dev/null
rm -f /etc/enigma2/*.radio 2>/dev/null

# Extract archive
if ! tar -xzf "$LOCAL_PATH" -C /; then
    echo "❌ Extraction failed"
    exit 1
fi

rm -f "$LOCAL_PATH"
echo "✅ Channels installed successfully"

# Reload services
wget -qO - http://127.0.0.1/web/servicelistreload?mode=0 > /dev/null 2>&1
sleep 2

print_header "✅ Completed Successfully"
echo "* $channel $version channels are ready"
echo "* Backup location: $BACKUP_DIR"
exit 0