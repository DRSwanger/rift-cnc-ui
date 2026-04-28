#!/bin/bash
# Custom CNC UI firmware update
# Replaces only index.html — leaves Python, AVR firmware, and all other files untouched.
#
# Note: bbctrl's update-bbctrl invokes us as `install.sh "$*" 2>&1 > $LOG` which
# (because of redirect ordering) sends ONLY stdout to the install log; stderr
# goes to journald, which on Stretch isn't persistent. So everything we want
# captured needs to print to stdout and we need to *not* rely on `set -e`'s
# silent exit — when a step fails, write a loud error to stdout first.

set -u
trap 'echo "ERROR: install.sh aborted at line $LINENO (last command exited $?)"; exit 1' ERR
set -e

SRC_INDEX="src/py/bbctrl/http/index.html"

# Pre-flight: verify the package extracted cleanly. If the bbctrl PUT upload
# was truncated (flaky wifi mid-upload is the common cause), `tar xf` on the
# bbctrl side may have produced scripts/ but missed src/, leaving us with a
# bogus install. Catch it here before clobbering anything.
if [ ! -f "$SRC_INDEX" ]; then
    echo "ERROR: $SRC_INDEX missing from extracted package."
    echo "       This usually means the firmware tarball was truncated during"
    echo "       upload (partial PUT to /api/firmware/update). Re-upload over"
    echo "       a stable connection, or pull the tarball server-side via curl"
    echo "       on the Pi. See README → Troubleshooting."
    ls -la . 2>&1 || true
    ls -la src 2>&1 || true
    exit 2
fi

SRC_BYTES=$(stat -c %s "$SRC_INDEX" 2>/dev/null || wc -c < "$SRC_INDEX")
SRC_VERSION=$(grep -m1 -oE "UI_VERSION[^,]*=[^,]*'[^']+'" "$SRC_INDEX" || echo "(unparseable)")
echo "Source index.html: $SRC_BYTES bytes — $SRC_VERSION"

HTTP_DIR=$(find /usr/local/lib/ -type d -name "http" 2>/dev/null | head -1)

if [ -z "$HTTP_DIR" ]; then
    echo "ERROR: Could not find bbctrl http directory under /usr/local/lib/"
    exit 1
fi

if [ ! -w "$HTTP_DIR" ]; then
    echo "ERROR: $HTTP_DIR is not writable (running as $(whoami), uid=$(id -u))"
    exit 1
fi

echo "Installing custom UI to $HTTP_DIR"

# Backup original if no backup exists yet
if [ ! -e "$HTTP_DIR/index.html.orig" ]; then
    cp "$HTTP_DIR/index.html" "$HTTP_DIR/index.html.orig"
    echo "Original index.html backed up as index.html.orig"
fi

# Install custom UI
cp "$SRC_INDEX" "$HTTP_DIR/index.html"
chmod 644 "$HTTP_DIR/index.html"

# Post-flight: confirm the new file size and version match what we shipped.
DST_BYTES=$(stat -c %s "$HTTP_DIR/index.html" 2>/dev/null || wc -c < "$HTTP_DIR/index.html")
DST_VERSION=$(grep -m1 -oE "UI_VERSION[^,]*=[^,]*'[^']+'" "$HTTP_DIR/index.html" || echo "(unparseable)")
echo "Installed index.html: $DST_BYTES bytes — $DST_VERSION"

if [ "$SRC_BYTES" != "$DST_BYTES" ] || [ "$SRC_VERSION" != "$DST_VERSION" ]; then
    echo "ERROR: post-install verification failed (src vs dst mismatch)"
    exit 3
fi

echo "Custom CNC UI installed successfully"

# Touch to update mtime — Tornado serves the new file on next request without a restart.
touch "$HTTP_DIR/index.html"

# ── Deploy watchdog ──
WATCHDOG_SRC="$(dirname "$0")/watchdog.sh"
WATCHDOG_DEST="/home/bbmc/watchdog.sh"

if [ -f "$WATCHDOG_SRC" ]; then
    cp "$WATCHDOG_SRC" "$WATCHDOG_DEST"
    chmod +x "$WATCHDOG_DEST"

    # Add to rc.local for persistence across reboots (only once)
    if ! grep -q watchdog "$WATCHDOG_DEST" /etc/rc.local 2>/dev/null; then
        python3 -c "
with open('/etc/rc.local', 'a') as f:
    f.write('\n# bbctrl watchdog\n/home/bbmc/watchdog.sh >> /var/log/bbctrl-watchdog.log 2>&1 &\n')
"
        echo "Watchdog added to /etc/rc.local"
    else
        echo "Watchdog already in /etc/rc.local"
    fi

    # Restart watchdog to pick up any updates
    pkill -f watchdog.sh 2>/dev/null || true
    nohup "$WATCHDOG_DEST" >> /var/log/bbctrl-watchdog.log 2>&1 &
    echo "Watchdog started (pid $!)"
fi

echo "Install complete — hard-refresh your browser to load the new UI"

# ── Deploy Plymouth splash ──
PLYMOUTH_DIR="/usr/share/plymouth/themes/onefinity"
BOOT_SRC="$(dirname "$0")/../rift-boot.png"
SHUTDOWN_SRC="$(dirname "$0")/../rift-shutdown.png"

if [ -f "$BOOT_SRC" ] && [ -d "$PLYMOUTH_DIR" ]; then
    if [ ! -e "$PLYMOUTH_DIR/boot.png.orig" ]; then
        cp "$PLYMOUTH_DIR/boot.png" "$PLYMOUTH_DIR/boot.png.orig"
        echo "Original boot splash backed up"
    fi
    cp "$BOOT_SRC" "$PLYMOUTH_DIR/boot.png"
    cp "$SHUTDOWN_SRC" "$PLYMOUTH_DIR/shutdown.png"
    update-initramfs -u 2>/dev/null && echo "Plymouth splash updated" || echo "Plymouth splash copied (initramfs update skipped)"
fi

# ── Patch .xinitrc kiosk watchdog ──
# Stock bbctrl 1.6.6 checks HDMI state 0x40001 every second. On HDMI DMT
# displays that check fails every iteration, which hammers chromium with
# reload IPCs (~5500 page reloads/day). Watchdog version only relaunches
# if chromium has actually exited.
XINITRC_SRC="$(dirname "$0")/../xinitrc"
if [ -f "$XINITRC_SRC" ]; then
    if [ ! -e /home/pi/.xinitrc.orig ]; then
        cp /home/pi/.xinitrc /home/pi/.xinitrc.orig
        echo "Original .xinitrc backed up as .xinitrc.orig"
    fi
    cp "$XINITRC_SRC" /home/pi/.xinitrc
    chown pi:pi /home/pi/.xinitrc
    chmod 644 /home/pi/.xinitrc
    echo ".xinitrc kiosk watchdog installed (takes effect on next X restart / reboot)"
fi
