#!/bin/bash

# Source environment variables
if [ -f "../env.sh" ]; then
    source ../env.sh
elif [ -f "../env" ]; then
    source ../env
else
    echo "Error: env file not found. Please create ../env or ../env.sh"
    exit 1
fi

PI_KIOSK_HOME="${PI_SCRIPTS_HOME}/kiosk"

echo "Deploying kiosk to Raspberry Pi..."
echo "  Target: ${PI_CONNECTION}:${PI_KIOSK_HOME}"

# Deploy script
ssh ${PI_CONNECTION} "mkdir -p ${PI_KIOSK_HOME}"
scp run_kiosk.sh ${PI_CONNECTION}:${PI_KIOSK_HOME}/run_kiosk.sh
ssh ${PI_CONNECTION} "chmod +x ${PI_KIOSK_HOME}/run_kiosk.sh"

# Remove old script if it exists
ssh ${PI_CONNECTION} "rm -f ~/run_kiosk.sh"

# Set up systemd user service
echo "  Setting up systemd service..."
ssh ${PI_CONNECTION} "mkdir -p ~/.config/systemd/user && cat > ~/.config/systemd/user/kiosk.service << 'EOFSERVICE'
[Unit]
Description=Chromium Kiosk Mode
After=graphical-session.target

[Service]
Type=simple
ExecStart=${PI_KIOSK_HOME}/run_kiosk.sh
Restart=on-failure
RestartSec=5
Environment=\"DISPLAY=:0\"

[Install]
WantedBy=default.target
EOFSERVICE
"

# Enable service
ssh ${PI_CONNECTION} "systemctl --user daemon-reload && systemctl --user enable kiosk.service"

echo ""
echo "Kiosk deployed! Restart the service to apply changes:"
echo "  ssh ${PI_CONNECTION} 'systemctl --user restart kiosk.service'"
