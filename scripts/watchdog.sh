#!/bin/bash
# bbctrl watchdog — auto-restarts bbctrl if it stops responding.
# Deploy once to the Pi:
#   scp scripts/watchdog.sh pi@onefinity.local:/home/pi/watchdog.sh
#   ssh pi@onefinity.local "chmod +x /home/pi/watchdog.sh && sudo /home/pi/watchdog.sh &"
#
# Or add to /etc/rc.local before "exit 0":
#   /home/pi/watchdog.sh >> /var/log/bbctrl-watchdog.log 2>&1 &

# Logging: this script is the SINGLE writer of the log file — it appends
# directly. Historically log() piped through `tee -a` while the launcher ALSO
# redirected stdout to the same file, so every line was written twice. Do not
# reintroduce a redirect in the systemd unit; ExecStart runs this script plain.
LOG="/var/log/bbctrl-watchdog.log"
FAIL_COUNT=0
CHECK_INTERVAL=15   # seconds between health checks
RESTART_THRESHOLD=2 # consecutive failures before restart
RESTART_COOLDOWN=45 # seconds to wait after restart before checking again

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

log "bbctrl watchdog started (pid $$)"

while true; do
    if curl -s --connect-timeout 5 http://localhost/ > /dev/null 2>&1; then
        FAIL_COUNT=0
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log "WARN: bbctrl not responding (fail $FAIL_COUNT/$RESTART_THRESHOLD)"

        if [ "$FAIL_COUNT" -ge "$RESTART_THRESHOLD" ]; then
            log "ACTION: Restarting bbctrl..."
            service bbctrl restart >> "$LOG" 2>&1
            FAIL_COUNT=0
            log "Waiting ${RESTART_COOLDOWN}s for service to stabilize..."
            sleep "$RESTART_COOLDOWN"
            continue
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
