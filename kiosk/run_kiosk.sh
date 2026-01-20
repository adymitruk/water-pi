#!/bin/bash

# Wait for web server to be ready
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if curl -s -f http://localhost:3000/health >/dev/null 2>&1 || curl -s -f http://localhost:3000 >/dev/null 2>&1; then
        break
    fi
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# Disable screen blanking
xset s off 2>/dev/null || true
xset s noblank 2>/dev/null || true
xset -dpms 2>/dev/null || true

# Hide cursor
unclutter -idle 0.5 -root &

# Launch Chromium in kiosk mode with dedicated profile
KIOSK_DATA_DIR="$HOME/.config/chromium-kiosk"
chromium --kiosk --noerrdialogs --disable-infobars \
  --no-first-run --password-store=basic \
  --user-data-dir="$KIOSK_DATA_DIR" \
  http://localhost:3000
