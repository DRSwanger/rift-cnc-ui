hostinfo.sh &

ratpoison &

xset -dpms
xset s off
xset s noblank

# Kiosk watchdog — replaces the stock bbctrl tvservice-based check, which
# only passes for HDMI state 0x40001 (original Pi modes). On newer HDMI DMT
# displays the check fails every second and chromium is re-invoked constantly,
# reloading the UI ~5500×/day. Patched to only relaunch when chromium has
# actually exited.
while true; do
    if ! pgrep -f "chromium-browser --no-first-run" >/dev/null; then
        # Clear browser errors
        PREFS="/home/pi/.config/chromium/Default/Preferences"
        sed -i "s/\"exited_cleanly\":false/\"exited_cleanly\":true/" $PREFS
        sed -i "s/\"exit_type\":\"Crashed\"/\"exit_type\":\"Normal\"/" $PREFS

        xrdb /home/pi/.Xresources

        # Start browser (--start-fullscreen: fills screen on boot, no browser chrome)
        /usr/local/bin/browser --no-first-run --disable-infobars \
         --noerrdialogs --disable-3d-apis --start-fullscreen http://localhost/
    fi

    sleep 5
done
