#!/bin/bash
# build_firmware.sh — packages the custom CNC UI as a firmware update .tar.bz2
#
# Deploy options (fastest to slowest):
#
#   1. SSH (zero downtime, recommended):
#      ./deploy-ssh.sh
#
#   2. Firmware update API (triggers bbctrl update, ~30s, no reboot):
#      ./build_firmware.sh
#      curl -X PUT http://192.168.1.130/api/firmware/update \
#           -F "firmware=@$HOME/Documents/rift-cnc-ui-v<version>.tar.bz2"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_NAME="cnc-ui-custom"
BUILD_DIR="/tmp/${PKG_NAME}-build"

# Derive version from index.html's UI_VERSION so the release asset name matches
# the repo tag convention (rift-cnc-ui-v<version>.tar.bz2).
VERSION=$(grep -oE "UI_VERSION\s*=\s*'[^']+'" "$SCRIPT_DIR/index.html" | head -1 | sed -E "s/.*'([^']+)'.*/\1/")
if [ -z "$VERSION" ]; then
    echo "ERROR: could not parse UI_VERSION from index.html" >&2
    exit 1
fi
OUT_FILE="$HOME/Documents/rift-cnc-ui-v${VERSION}.tar.bz2"

echo "Building firmware package: $OUT_FILE"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$PKG_NAME/src/py/bbctrl/http"
mkdir -p "$BUILD_DIR/$PKG_NAME/scripts"

cp "$SCRIPT_DIR/index.html"           "$BUILD_DIR/$PKG_NAME/src/py/bbctrl/http/index.html"
cp "$SCRIPT_DIR/manifest.json"        "$BUILD_DIR/$PKG_NAME/src/py/bbctrl/http/manifest.json"
cp "$SCRIPT_DIR/rift-boot.png"        "$BUILD_DIR/$PKG_NAME/rift-boot.png"
cp "$SCRIPT_DIR/rift-shutdown.png"    "$BUILD_DIR/$PKG_NAME/rift-shutdown.png"
cp "$SCRIPT_DIR/xinitrc"              "$BUILD_DIR/$PKG_NAME/xinitrc"
cp "$SCRIPT_DIR/scripts/install.sh"  "$BUILD_DIR/$PKG_NAME/scripts/install.sh"
cp "$SCRIPT_DIR/scripts/watchdog.sh" "$BUILD_DIR/$PKG_NAME/scripts/watchdog.sh"
chmod +x "$BUILD_DIR/$PKG_NAME/scripts/install.sh"
chmod +x "$BUILD_DIR/$PKG_NAME/scripts/watchdog.sh"

cd "$BUILD_DIR"
tar cjf "$OUT_FILE" "$PKG_NAME"

echo "Done: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"
