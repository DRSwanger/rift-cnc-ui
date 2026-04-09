#!/bin/bash
# bbctrl watchdog — auto-restarts bbctrl if it stops responding.
# Deploy once to the Pi:
#   scp scripts/watchdog.sh pi@192.168.1.130:/home/pi/watchdog.sh
#   ssh pi@192.168.1.130 "chmod +x /home/pi/watchdog.sh && sudo /home/pi/watchdog.sh &"
#
# Or add to /etc/rc.local before "exit 0":
#   /home/pi/watchdog.sh >> /var/log/bbctrl-watchdog.log 2>&1 &

LOG="/var/log/bbctrl-watchdog.log"
FAIL_COUNT=0
CHECK_INTERVAL=15   # seconds between health checks
RESTART_THRESHOLD=2 # consecutive failures before restart
RESTART_COOLDOWN=45 # seconds to wait after restart before checking again

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"
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
            service bbctrl restart 2>&1 | tee -a "$LOG"
            FAIL_COUNT=0
            log "Waiting ${RESTART_COOLDOWN}s for service to stabilize..."
            sleep "$RESTART_COOLDOWN"
            continue
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
