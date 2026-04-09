#!/bin/bash
# deploy-ssh.sh
# Pushes index.html directly to the Pi via SSH — zero downtime, no bbctrl restart.
# Requires: ssh key auth OR sshpass installed ("sudo apt install sshpass")
#
# Usage:
#   ./deploy-ssh.sh                     # uses key auth (recommended)
#   SSH_PASS=raspberry ./deploy-ssh.sh  # uses password auth via sshpass

set -e

PI_HOST="${CNC_HOST:-192.168.1.130}"
PI_USER="${CNC_USER:-bbmc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/index.html"
MANIFEST="$SCRIPT_DIR/manifest.json"
BOOT_PNG="$SCRIPT_DIR/rift-boot.png"
SHUTDOWN_PNG="$SCRIPT_DIR/rift-shutdown.png"

# Discover bbctrl http directory on the Pi
echo "Locating bbctrl http directory on $PI_USER@$PI_HOST..."

SSH_CMD="ssh"
SCP_CMD="scp"

if [ -n "$SSH_PASS" ]; then
    if ! command -v sshpass &>/dev/null; then
        echo "ERROR: sshpass not installed. Run: sudo apt install sshpass"
        exit 1
    fi
    SSH_CMD="sshpass -p '$SSH_PASS' ssh"
    SCP_CMD="sshpass -p '$SSH_PASS' scp"
fi

HTTP_DIR=$(eval "$SSH_CMD -o StrictHostKeyChecking=no $PI_USER@$PI_HOST \
    'find /usr/local/lib/ -type d -name http 2>/dev/null | head -1'")

if [ -z "$HTTP_DIR" ]; then
    echo "ERROR: Could not find bbctrl http directory on Pi"
    exit 1
fi

echo "Found: $HTTP_DIR"

# Backup original only once
eval "$SSH_CMD -o StrictHostKeyChecking=no $PI_USER@$PI_HOST \
    'if [ ! -e \"$HTTP_DIR/index.html.orig\" ]; then
        cp \"$HTTP_DIR/index.html\" \"$HTTP_DIR/index.html.orig\"
        echo \"Backup created: index.html.orig\"
     fi'"

# Copy via /tmp then sudo mv (http dir is root-owned)
echo "Copying index.html, manifest.json, and splash PNGs..."
eval "$SCP_CMD -o StrictHostKeyChecking=no $SRC $PI_USER@$PI_HOST:/tmp/rift-index.html"
eval "$SCP_CMD -o StrictHostKeyChecking=no $MANIFEST $PI_USER@$PI_HOST:/tmp/rift-manifest.json"
eval "$SCP_CMD -o StrictHostKeyChecking=no $BOOT_PNG $PI_USER@$PI_HOST:/tmp/rift-boot.png"
eval "$SCP_CMD -o StrictHostKeyChecking=no $SHUTDOWN_PNG $PI_USER@$PI_HOST:/tmp/rift-shutdown.png"
eval "$SSH_CMD -o StrictHostKeyChecking=no $PI_USER@$PI_HOST \
    'echo ${SSH_PASS} | sudo -S bash -c \"
        cp /tmp/rift-index.html \\\"$HTTP_DIR/index.html\\\" &&
        chmod 644 \\\"$HTTP_DIR/index.html\\\" &&
        touch \\\"$HTTP_DIR/index.html\\\" &&
        cp /tmp/rift-manifest.json \\\"$HTTP_DIR/manifest.json\\\" &&
        chmod 644 \\\"$HTTP_DIR/manifest.json\\\" &&
        PLYMOUTH=/usr/share/plymouth/themes/onefinity &&
        [ ! -e \\\"\\\$PLYMOUTH/boot.png.orig\\\" ] && cp \\\"\\\$PLYMOUTH/boot.png\\\" \\\"\\\$PLYMOUTH/boot.png.orig\\\" || true &&
        cp /tmp/rift-boot.png \\\"\\\$PLYMOUTH/boot.png\\\" &&
        cp /tmp/rift-shutdown.png \\\"\\\$PLYMOUTH/shutdown.png\\\" &&
        update-initramfs -u 2>/dev/null || true &&
        rm /tmp/rift-index.html /tmp/rift-manifest.json /tmp/rift-boot.png /tmp/rift-shutdown.png
    \"'"

echo ""
echo "Done. Hard-refresh your browser at http://$PI_HOST/"
echo "No bbctrl restart needed."
