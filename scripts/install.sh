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

# ── Static assets (manifest + Rift favicon/icons) ──
# bbctrl ships an Onefinity favicon.ico at the http root; bookmarks / PWA
# installs fetch /favicon.ico (not the in-page data-URI), so it must be
# replaced here too — not just via deploy-ssh. Back up the stock favicon once.
SRC_HTTP="$(dirname "$SRC_INDEX")"
if [ -f "$SRC_HTTP/favicon.ico" ] && [ -e "$HTTP_DIR/favicon.ico" ] && [ ! -e "$HTTP_DIR/favicon.ico.orig" ]; then
    cp "$HTTP_DIR/favicon.ico" "$HTTP_DIR/favicon.ico.orig"
    echo "Original favicon.ico backed up as favicon.ico.orig"
fi
for asset in manifest.json favicon.ico rift-icon-192.png rift-icon-512.png; do
    if [ -f "$SRC_HTTP/$asset" ]; then
        cp "$SRC_HTTP/$asset" "$HTTP_DIR/$asset"
        chmod 644 "$HTTP_DIR/$asset"
        echo "Installed $asset"
    fi
done

# ── Deploy watchdog ──
WATCHDOG_SRC="$(dirname "$0")/watchdog.sh"
WATCHDOG_DEST="/home/bbmc/watchdog.sh"

if [ -f "$WATCHDOG_SRC" ]; then
    cp "$WATCHDOG_SRC" "$WATCHDOG_DEST"
    chmod +x "$WATCHDOG_DEST"

    # Install as a systemd unit. The old rc.local approach never worked: the
    # guard grepped $WATCHDOG_DEST (which contains the word "watchdog") as well
    # as /etc/rc.local, so it always matched and the line was never appended —
    # and /etc/rc.local does not exist on this controller anyway.
    UNIT_SRC="$(dirname "$0")/bbctrl-watchdog.service"
    if [ -f "$UNIT_SRC" ]; then
        install -m 644 "$UNIT_SRC" /etc/systemd/system/bbctrl-watchdog.service
        systemctl daemon-reload
        systemctl enable bbctrl-watchdog.service >/dev/null 2>&1
        echo "Watchdog systemd unit installed + enabled"
    fi

    # Restart via systemd so the new script is picked up
    systemctl restart bbctrl-watchdog.service 2>/dev/null \
        && echo "Watchdog restarted (systemd)" \
        || echo "WARN: could not restart bbctrl-watchdog.service"
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

# ── Persist systemd journal across reboots ──
# Stock journald defaults to volatile /run/log/journal (tmpfs), so a Pi crash
# wipes all forensic evidence on the next boot. Drop in a 200MB-capped
# persistent journal config so future crashes leave traces queryable via
# `journalctl -b -1`.
JOURNALD_SRC="$(dirname "$0")/../journald-rift.conf"
if [ -f "$JOURNALD_SRC" ]; then
    mkdir -p /etc/systemd/journald.conf.d
    install -m 644 "$JOURNALD_SRC" /etc/systemd/journald.conf.d/rift-persistent.conf
    mkdir -p /var/log/journal
    systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true
    systemctl restart systemd-journald && echo "Persistent journald installed (200MB cap)" || echo "WARN: journald restart failed"
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
