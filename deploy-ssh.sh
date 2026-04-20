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

# Preflight: refuse to deploy while a job is running. Peek at xx via websocket.
# Override with FORCE=1 to deploy anyway, SKIP_STATE_CHECK=1 to skip the probe entirely.
if [ -z "$SKIP_STATE_CHECK" ]; then
    STATE=$(PI_HOST="$PI_HOST" python3 - <<'PY' 2>/dev/null
import os, sys
try:
    import websocket, json
    ws = websocket.create_connection(f"ws://{os.environ['PI_HOST']}/websocket", timeout=3)
    msg = json.loads(ws.recv()); ws.close()
    print(str(msg.get("xx","")).upper())
except Exception:
    sys.exit(1)
PY
    )
    case "$STATE" in
        RUNNING|HOMING|JOGGING|HOLDING|STOPPING|PAUSED|PAUSING)
            echo "⚠  Machine is $STATE — a job appears to be in progress."
            if [ "$FORCE" != "1" ]; then
                read -r -p "Deploy anyway? Type 'yes' to proceed: " ans
                [ "$ans" = "yes" ] || { echo "Aborted. Use FORCE=1 to skip this prompt."; exit 1; }
            else
                echo "FORCE=1 — proceeding."
            fi
            ;;
        "")
            echo "WARN: could not read machine state (install python3-websocket or set SKIP_STATE_CHECK=1)"
            [ "$FORCE" = "1" ] || { echo "Aborting for safety. FORCE=1 or SKIP_STATE_CHECK=1 to override."; exit 1; }
            ;;
        *)
            echo "Machine state: $STATE — safe to deploy"
            ;;
    esac
fi

SRC="$SCRIPT_DIR/index.html"
MOBILE="$SCRIPT_DIR/mobile.html"
MANIFEST="$SCRIPT_DIR/manifest.json"
BOOT_PNG="$SCRIPT_DIR/rift-boot.png"
SHUTDOWN_PNG="$SCRIPT_DIR/rift-shutdown.png"
XINITRC="$SCRIPT_DIR/xinitrc"

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
echo "Copying index.html, mobile.html, manifest.json, splash PNGs, and .xinitrc..."
eval "$SCP_CMD -o StrictHostKeyChecking=no $SRC $PI_USER@$PI_HOST:/tmp/rift-index.html"
eval "$SCP_CMD -o StrictHostKeyChecking=no $MOBILE $PI_USER@$PI_HOST:/tmp/rift-mobile.html"
eval "$SCP_CMD -o StrictHostKeyChecking=no $MANIFEST $PI_USER@$PI_HOST:/tmp/rift-manifest.json"
eval "$SCP_CMD -o StrictHostKeyChecking=no $BOOT_PNG $PI_USER@$PI_HOST:/tmp/rift-boot.png"
eval "$SCP_CMD -o StrictHostKeyChecking=no $SHUTDOWN_PNG $PI_USER@$PI_HOST:/tmp/rift-shutdown.png"
eval "$SCP_CMD -o StrictHostKeyChecking=no $XINITRC $PI_USER@$PI_HOST:/tmp/rift-xinitrc"
eval "$SSH_CMD -o StrictHostKeyChecking=no $PI_USER@$PI_HOST \
    'echo ${SSH_PASS} | sudo -S bash -c \"
        cp /tmp/rift-index.html \\\"$HTTP_DIR/index.html\\\" &&
        chmod 644 \\\"$HTTP_DIR/index.html\\\" &&
        touch \\\"$HTTP_DIR/index.html\\\" &&
        cp /tmp/rift-mobile.html \\\"$HTTP_DIR/mobile.html\\\" &&
        chmod 644 \\\"$HTTP_DIR/mobile.html\\\" &&
        cp /tmp/rift-manifest.json \\\"$HTTP_DIR/manifest.json\\\" &&
        chmod 644 \\\"$HTTP_DIR/manifest.json\\\" &&
        PLYMOUTH=/usr/share/plymouth/themes/onefinity &&
        [ ! -e \\\"\\\$PLYMOUTH/boot.png.orig\\\" ] && cp \\\"\\\$PLYMOUTH/boot.png\\\" \\\"\\\$PLYMOUTH/boot.png.orig\\\" || true &&
        cp /tmp/rift-boot.png \\\"\\\$PLYMOUTH/boot.png\\\" &&
        cp /tmp/rift-shutdown.png \\\"\\\$PLYMOUTH/shutdown.png\\\" &&
        update-initramfs -u 2>/dev/null || true &&
        [ ! -e /home/pi/.xinitrc.orig ] && cp /home/pi/.xinitrc /home/pi/.xinitrc.orig || true &&
        cp /tmp/rift-xinitrc /home/pi/.xinitrc &&
        chown pi:pi /home/pi/.xinitrc &&
        chmod 644 /home/pi/.xinitrc &&
        rm /tmp/rift-index.html /tmp/rift-mobile.html /tmp/rift-manifest.json /tmp/rift-boot.png /tmp/rift-shutdown.png /tmp/rift-xinitrc
    \"'"

echo ""
echo "Done. Hard-refresh your browser at http://$PI_HOST/"
echo "No bbctrl restart needed."
