#!/bin/bash
# Custom CNC UI firmware update
# Replaces only index.html — leaves Python, AVR firmware, and all other files untouched.

set -e

HTTP_DIR=$(find /usr/local/lib/ -type d -name "http" 2>/dev/null | head -1)

if [ -z "$HTTP_DIR" ]; then
    echo "ERROR: Could not find bbctrl http directory"
    exit 1
fi

echo "Installing custom UI to $HTTP_DIR"

# Backup original if no backup exists yet
if [ ! -e "$HTTP_DIR/index.html.orig" ]; then
    cp "$HTTP_DIR/index.html" "$HTTP_DIR/index.html.orig"
    echo "Original index.html backed up as index.html.orig"
fi

# Install custom UI
cp src/py/bbctrl/http/index.html "$HTTP_DIR/index.html"
chmod 644 "$HTTP_DIR/index.html"

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
