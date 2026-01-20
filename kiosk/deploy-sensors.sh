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

# Kiosk directory on Pi
PI_KIOSK_HOME="${PI_SCRIPTS_HOME}/kiosk"

# Create kiosk directory on Pi
ssh -o ConnectTimeout=10 ${PI_CONNECTION} "mkdir -p ${PI_KIOSK_HOME}"

# Deploy sensors.sh on Raspberry Pi
echo "Deploying sensors.sh to Raspberry Pi..."
scp -o ConnectTimeout=10 sensors.sh ${PI_CONNECTION}:${PI_KIOSK_HOME}/sensors.sh
ssh -o ConnectTimeout=10 ${PI_CONNECTION} "chmod +x ${PI_KIOSK_HOME}/sensors.sh"

# Deploy and install systemd timer for sensors
echo "Deploying systemd timer for sensors..."
scp -o ConnectTimeout=10 water-pi-sensors.service ${PI_CONNECTION}:/tmp/water-pi-sensors.service
scp -o ConnectTimeout=10 water-pi-sensors.timer ${PI_CONNECTION}:/tmp/water-pi-sensors.timer

echo "Installing systemd timer..."
ssh -o ConnectTimeout=10 ${PI_CONNECTION} "sudo mv /tmp/water-pi-sensors.service /etc/systemd/system/water-pi-sensors.service && sudo mv /tmp/water-pi-sensors.timer /etc/systemd/system/water-pi-sensors.timer && sudo systemctl daemon-reload && sudo systemctl enable water-pi-sensors.timer && sudo systemctl start water-pi-sensors.timer"

if [ $? -eq 0 ]; then
    echo "Sensors timer installed and started!"
else
    echo "[Warning] Failed to install sensors timer. You may need to do this manually."
fi

echo ""
echo "sensors.sh deployed successfully!"
echo "The sensors script will run every 5 seconds to update readings."