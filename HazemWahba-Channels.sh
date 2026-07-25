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
LOG_FILE="/tmp/channels_install_$(date +%Y%m%d_%H%M%S).log"

# ============================================
# Helper Functions
# ============================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo "*********************************************************"
    echo "*     $1"
    echo "*********************************************************"
    log "START: $1"
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "❌ Error: Please run as root (use: sudo $0)"
        log "ERROR: Not running as root"
        exit 1
    fi
    log "✅ Root privileges confirmed"
}

check_requirements() {
    local missing=0
    for cmd in wget tar grep file; do
        if ! command -v $cmd > /dev/null 2>&1; then
            echo "❌ Command $cmd not found"
            log "ERROR: Missing command: $cmd"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        echo "Please install missing packages: opkg install wget tar grep file"
        exit 1
    fi
    log "✅ All required commands available"
}

check_disk_space() {
    # Check if at least 5MB free space
    local required_space=5120  # 5MB in KB
    local available_space=$(df -k /var/volatile/tmp | awk 'NR==2 {print $4}')
    
    if [ "$available_space" -lt "$required_space" ]; then
        echo "❌ Insufficient disk space. Required: 5MB, Available: $((available_space/1024))MB"
        log "ERROR: Insufficient disk space"
        exit 1
    fi
    log "✅ Disk space OK ($((available_space/1024))MB available)"
}

backup_old_channels() {
    if [ -d "/etc/enigma2" ]; then
        log "> Creating backup..."
        mkdir -p "$BACKUP_DIR"
        
        # Backup only important files
        cp -r /etc/enigma2/lamedb "$BACKUP_DIR/" 2>/dev/null || true
        cp -r /etc/enigma2/userbouquet.* "$BACKUP_DIR/" 2>/dev/null || true
        cp -r /etc/enigma2/*.tv "$BACKUP_DIR/" 2>/dev/null || true
        cp -r /etc/enigma2/*.radio "$BACKUP_DIR/" 2>/dev/null || true
        cp -r /etc/enigma2/*.xml "$BACKUP_DIR/" 2>/dev/null || true
        
        # Create backup info file
        echo "Backup created: $(date)" > "$BACKUP_DIR/backup_info.txt"
        echo "Channel version: $channel $version" >> "$BACKUP_DIR/backup_info.txt"
        echo "Files count: $(find "$BACKUP_DIR" -type f | wc -l)" >> "$BACKUP_DIR/backup_info.txt"
        
        echo "✅ Backup at: $BACKUP_DIR"
        log "✅ Backup created at $BACKUP_DIR"
    else
        log "⚠️ No existing enigma2 directory found"
    fi
}

safe_remove() {
    local file="$1"
    if [ -f "$file" ] || [ -d "$file" ]; then
        rm -f "$file" 2>/dev/null || true
        log "Removed: $file"
    fi
}

restart_enigma2() {
    log "Attempting to reload services..."
    
    # Try web interface reload
    if wget -qO - http://127.0.0.1/web/servicelistreload?mode=0 > /dev/null 2>&1; then
        log "✅ Services reloaded via web interface"
        sleep 3
    else
        log "⚠️ Web interface reload failed, trying alternative..."
        
        # Try to restart enigma2 gracefully
        if command -v init > /dev/null 2>&1; then
            echo "> Restarting GUI..."
            init 4 > /dev/null 2>&1
            sleep 3
            init 3 > /dev/null 2>&1
            log "✅ GUI restarted via init"
        else
            log "⚠️ Could not restart GUI. Please restart your receiver manually."
            echo "⚠️ Please restart your receiver to apply changes."
        fi
    fi
}

verify_installation() {
    if [ ! -f "/etc/enigma2/lamedb" ]; then
        log "❌ Installation failed: lamedb not found"
        echo "❌ Installation failed! Restoring backup..."
        if [ -d "$BACKUP_DIR" ]; then
            cp -r "$BACKUP_DIR"/* /etc/enigma2/ 2>/dev/null || true
            echo "✅ Backup restored from: $BACKUP_DIR"
            log "✅ Backup restored"
        fi
        exit 1
    fi
    log "✅ Installation verified successfully"
}

# ============================================
# Main Execution
# ============================================
# Clear screen
clear

print_header "Downloading $channel $version Channels"
echo "Log file: $LOG_FILE"
echo ""

# Initial checks
check_root
check_requirements
check_disk_space

# Change to temp directory
cd /var/volatile/tmp || {
    echo "❌ Cannot access /var/volatile/tmp"
    log "ERROR: Cannot access temp directory"
    exit 1
}

# Download file with progress
echo "> Downloading..."
if wget --progress=bar:force -O "$LOCAL_PATH" "$REMOTE_URL" 2>&1; then
    log "✅ Download completed successfully"
else
    echo "❌ Download failed"
    log "ERROR: Download failed"
    exit 1
fi

# Verify file size
local_size=$(stat -c%s "$LOCAL_PATH" 2>/dev/null || stat -f%z "$LOCAL_PATH" 2>/dev/null)
if [ "$local_size" -lt 1000 ]; then
    echo "❌ File is too small (likely corrupted)"
    log "ERROR: File size too small: $local_size bytes"
    rm -f "$LOCAL_PATH"
    exit 1
fi
log "✅ File size: $((local_size/1024))KB"

# Verify file integrity
if ! file "$LOCAL_PATH" | grep -q "gzip compressed data"; then
    echo "❌ File format is invalid"
    log "ERROR: Invalid file format"
    rm -f "$LOCAL_PATH"
    exit 1
fi
log "✅ File format verified (gzip)"

echo "✅ Download completed successfully"
echo "> Installing new channels..."

# Backup existing channels
backup_old_channels

# Clean old files (more selective)
log "> Cleaning old channel files..."
safe_remove "/etc/enigma2/lamedb"
safe_remove "/etc/enigma2/lamedb5"

# Remove user bouquets but keep any custom ones
safe_remove "/etc/enigma2/userbouquet.*"
safe_remove "/etc/enigma2/userbouquet.*.tv"
safe_remove "/etc/enigma2/userbouquet.*.radio"

# Keep bouquet files that aren't user bouquets
# Only remove if they are in the archive
log "> Removing old bouquet files..."

# Extract archive to temp location first to inspect
TEMP_EXTRACT="/tmp/channels_extract_$$"
mkdir -p "$TEMP_EXTRACT"

if ! tar -xzf "$LOCAL_PATH" -C "$TEMP_EXTRACT"; then
    echo "❌ Extraction failed"
    log "ERROR: Extraction failed"
    rm -rf "$TEMP_EXTRACT"
    exit 1
fi
log "✅ Archive extracted successfully to $TEMP_EXTRACT"

# Now copy files from temp to actual location
if [ -d "$TEMP_EXTRACT/etc/enigma2" ]; then
    # Remove old files but keep important ones
    find /etc/enigma2 -type f -name "*.tv" -not -name "*_custom*" -exec rm -f {} \; 2>/dev/null || true
    find /etc/enigma2 -type f -name "*.radio" -not -name "*_custom*" -exec rm -f {} \; 2>/dev/null || true
    
    # Copy new files
    cp -r "$TEMP_EXTRACT/etc/enigma2"/* /etc/enigma2/ 2>/dev/null || true
    log "✅ New files copied to /etc/enigma2"
else
    echo "❌ No enigma2 directory found in archive"
    log "ERROR: Archive structure invalid"
    rm -rf "$TEMP_EXTRACT"
    exit 1
fi

# Cleanup
rm -rf "$TEMP_EXTRACT"
rm -f "$LOCAL_PATH"
log "✅ Temporary files cleaned"

# Verify installation
verify_installation

echo "✅ Channels installed successfully"

# Reload services
restart_enigma2

# Print completion
print_header "✅ Completed Successfully"
echo "* $channel $version channels are ready"
echo "* Backup location: $BACKUP_DIR"
echo "* Log file: $LOG_FILE"
echo ""
echo "📋 Installation Summary:"
echo "   - Channels installed: $channel $version"
echo "   - Backup created: $BACKUP_DIR"
echo "   - Disk space used: $((local_size/1024))KB"
echo ""

log "✅ Script completed successfully"
exit 0