# Rift CNC UI

**Custom control interface for the Onefinity CNC — by AlienWoodshop LLC**

Rift replaces the stock Onefinity web UI with a fast, dark-themed control panel built for real shop use. It runs entirely in your browser — phone, tablet, or desktop — with no app to install on your end.

---

## Features

- **Full DRO** — WCS + ABS positions for X, Y, Z at a glance
- **Jog controls** — XY pad + Z column with configurable step sizes
- **3D toolpath viewer** — G0/G1/G2/G3 arc support via Three.js
- **GCode viewer** — syntax highlighting with live line tracking during a job
- **File manager** — upload, drag-and-drop, folder support
- **Start / Pause / Stop / E-Stop** — with confirmation dialogs where it counts
- **Progress bar** — time remaining and ETA during a job
- **Water pump + vacuum toggles** — relay control from the DRO bar
- **Settings modal** — motor tuning, tool config, I/O indicators, WiFi, system clock, firmware update, and more
- **Kiosk mode** — optimized layout for a Pi-connected touchscreen
- **Dark + light theme** — persisted per browser
- **Revert to stock anytime** — one button, no tools required

---

## Requirements

- Onefinity CNC running **bbctrl 1.6.6** (BuildBotics controller)
- A browser on the same network (Chrome, Firefox, Safari, Edge)

> Rift targets the original BuildBotics-based Onefinity controller. It is **not** compatible with the Onefinity Redline controller at this time.

---

## Installation

### Option A — Firmware Update (Recommended)

No SSH, no tools. Done in under a minute.

1. **Download** the latest Rift firmware package:
   👉 **[rift-cnc-ui-v1.3.0.tar.bz2](https://github.com/DRSwanger/rift-cnc-ui/releases/download/v1.3.0/rift-cnc-ui-v1.3.0.tar.bz2)**

2. Open your Onefinity controller in a browser (usually `http://onefinity.local` or your machine's IP)

3. Go to **Settings → Admin → Software Update**

4. Click **Choose File**, select the downloaded `.tar.bz2`, and click **Update**

5. Wait ~30 seconds for the controller to reboot — then hard-refresh your browser

That's it. Rift is now your controller UI.

---

### Option B — SSH Deploy (Developers)

If you're developing or want zero-downtime updates:

```bash
git clone https://github.com/DRSwanger/rift-cnc-ui.git
cd rift-cnc-ui
SSH_PASS=bbmc ./deploy-ssh.sh
```

The script auto-discovers the bbctrl HTTP directory and backs up the original `index.html` before replacing it.

---

## Reverting to Stock Onefinity 1.6.6

Rift includes a one-click revert:

1. Download the official Onefinity 1.6.6 firmware from Onefinity's website
2. In Rift: **Settings → Firmware → Revert to Stock 1.6.6**
3. Select the downloaded `.tar.bz2` — the controller installs it and reboots

Everything is restored: the stock UI, splash screens, and all defaults.

---

## Running the Local Proxy (Optional)

Rift can be served from any machine on your network using the included proxy:

```bash
# Default (auto-detects controller at 192.168.1.130)
python3 proxy.py

# Custom controller IP
CNC_HOST=192.168.1.xxx python3 proxy.py
```

Then open `http://<your-machine-ip>:8888` in any browser.

---

## Project Structure

```
index.html          — Full UI (single file, zero dependencies except Three.js CDN)
proxy.py            — Local WebSocket + HTTP proxy for cross-origin access
deploy-ssh.sh       — SSH-based deploy to Pi (no bbctrl restart needed)
build_firmware.sh   — Packages index.html as a bbctrl-compatible .tar.bz2
manifest.json       — PWA manifest
rift-boot.png       — Boot splash screen
rift-shutdown.png   — Shutdown splash screen
scripts/            — Pi install helpers
```

---

## Known Limitations

- Resume-from-stop is implemented but disabled pending further testing (`ENABLE_RESUME = false`)
- Macro buttons are implemented but disabled pending the editor UI (`ENABLE_MACROS = false`)
- Not compatible with Onefinity Redline (proprietary API, not yet reverse engineered)

---

## License

MIT — use it, fork it, sell machines with it.

---

*Rift by AlienWoodshop LLC — CNC control from another world.*
