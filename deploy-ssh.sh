#!/bin/bash
# deploy-ssh.sh
# Pushes index.html directly to the Pi via SSH — zero downtime, no bbctrl restart.
# Requires: ssh key auth OR sshpass installed ("sudo apt install sshpass")
#
# Usage:
#   ./deploy-ssh.sh                     # uses key auth (recommended)
#   SSH_PASS=raspberry ./deploy-ssh.sh  # uses password auth via sshpass

set -e

# Default to the mDNS hostname stock Onefinity controllers ship with
# (`onefinity.local`). This works out-of-box on any un-modified Onefinity
# controller on a network with mDNS/avahi resolution — no need to know the IP.
# Override with `CNC_HOST=192.168.x.x ./deploy-ssh.sh` if mDNS isn't available
# on your network or you've renamed the Pi.
PI_HOST="${CNC_HOST:-onefinity.local}"
# Default SSH user matches stock Onefinity (`bbmc`). Override via CNC_USER.
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
JOURNALD_CONF="$SCRIPT_DIR/journald-rift.conf"
WATCHDOG="$SCRIPT_DIR/scripts/watchdog.sh"
WDUNIT="$SCRIPT_DIR/scripts/bbctrl-watchdog.service"
FAVICON="$SCRIPT_DIR/favicon.ico"
ICON192="$SCRIPT_DIR/rift-icon-192.png"
ICON512="$SCRIPT_DIR/rift-icon-512.png"

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
eval "$SCP_CMD -o StrictHostKeyChecking=no $JOURNALD_CONF $PI_USER@$PI_HOST:/tmp/rift-journald.conf"
eval "$SCP_CMD -o StrictHostKeyChecking=no $WATCHDOG $PI_USER@$PI_HOST:/tmp/rift-watchdog.sh"
eval "$SCP_CMD -o StrictHostKeyChecking=no $WDUNIT $PI_USER@$PI_HOST:/tmp/rift-watchdog.service"
eval "$SCP_CMD -o StrictHostKeyChecking=no $FAVICON $PI_USER@$PI_HOST:/tmp/rift-favicon.ico"
eval "$SCP_CMD -o StrictHostKeyChecking=no $ICON192 $PI_USER@$PI_HOST:/tmp/rift-icon-192.png"
eval "$SCP_CMD -o StrictHostKeyChecking=no $ICON512 $PI_USER@$PI_HOST:/tmp/rift-icon-512.png"
eval "$SSH_CMD -o StrictHostKeyChecking=no $PI_USER@$PI_HOST \
    'echo ${SSH_PASS} | sudo -S bash -c \"
        cp /tmp/rift-index.html \\\"$HTTP_DIR/index.html\\\" &&
        chmod 644 \\\"$HTTP_DIR/index.html\\\" &&
        touch \\\"$HTTP_DIR/index.html\\\" &&
        cp /tmp/rift-mobile.html \\\"$HTTP_DIR/mobile.html\\\" &&
        chmod 644 \\\"$HTTP_DIR/mobile.html\\\" &&
        cp /tmp/rift-manifest.json \\\"$HTTP_DIR/manifest.json\\\" &&
        chmod 644 \\\"$HTTP_DIR/manifest.json\\\" &&
        [ ! -e \\\"$HTTP_DIR/favicon.ico.orig\\\" ] && [ -e \\\"$HTTP_DIR/favicon.ico\\\" ] && cp \\\"$HTTP_DIR/favicon.ico\\\" \\\"$HTTP_DIR/favicon.ico.orig\\\" || true &&
        cp /tmp/rift-favicon.ico \\\"$HTTP_DIR/favicon.ico\\\" &&
        cp /tmp/rift-icon-192.png \\\"$HTTP_DIR/rift-icon-192.png\\\" &&
        cp /tmp/rift-icon-512.png \\\"$HTTP_DIR/rift-icon-512.png\\\" &&
        chmod 644 \\\"$HTTP_DIR/favicon.ico\\\" \\\"$HTTP_DIR/rift-icon-192.png\\\" \\\"$HTTP_DIR/rift-icon-512.png\\\" &&
        cp /tmp/rift-watchdog.sh /home/bbmc/watchdog.sh.new &&
        chmod +x /home/bbmc/watchdog.sh.new &&
        mv -f /home/bbmc/watchdog.sh.new /home/bbmc/watchdog.sh &&
        install -m 644 /tmp/rift-watchdog.service /etc/systemd/system/bbctrl-watchdog.service &&
        systemctl daemon-reload &&
        systemctl enable bbctrl-watchdog.service >/dev/null 2>&1 &&
        PLYMOUTH=/usr/share/plymouth/themes/onefinity &&
        [ ! -e \\\"\\\$PLYMOUTH/boot.png.orig\\\" ] && cp \\\"\\\$PLYMOUTH/boot.png\\\" \\\"\\\$PLYMOUTH/boot.png.orig\\\" || true &&
        cp /tmp/rift-boot.png \\\"\\\$PLYMOUTH/boot.png\\\" &&
        cp /tmp/rift-shutdown.png \\\"\\\$PLYMOUTH/shutdown.png\\\" &&
        update-initramfs -u 2>/dev/null || true &&
        [ ! -e /home/pi/.xinitrc.orig ] && cp /home/pi/.xinitrc /home/pi/.xinitrc.orig || true &&
        cp /tmp/rift-xinitrc /home/pi/.xinitrc &&
        chown pi:pi /home/pi/.xinitrc &&
        chmod 644 /home/pi/.xinitrc &&
        mkdir -p /etc/systemd/journald.conf.d &&
        install -m 644 /tmp/rift-journald.conf /etc/systemd/journald.conf.d/rift-persistent.conf &&
        mkdir -p /var/log/journal &&
        systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true &&
        systemctl restart systemd-journald &&
        rm /tmp/rift-index.html /tmp/rift-mobile.html /tmp/rift-manifest.json /tmp/rift-boot.png /tmp/rift-shutdown.png /tmp/rift-xinitrc /tmp/rift-journald.conf /tmp/rift-favicon.ico /tmp/rift-icon-192.png /tmp/rift-icon-512.png /tmp/rift-watchdog.sh /tmp/rift-watchdog.service
    \"'"

# Restart the watchdog so the new script is actually running.
eval "$SSH_CMD -o StrictHostKeyChecking=no $PI_USER@$PI_HOST \
    'echo ${SSH_PASS} | sudo -S systemctl restart bbctrl-watchdog.service' " \
    && echo "Watchdog restarted (systemd)" || echo "WARN: watchdog restart failed"

echo ""
echo "Done. Hard-refresh your browser at http://$PI_HOST/"
echo "No bbctrl restart needed."
