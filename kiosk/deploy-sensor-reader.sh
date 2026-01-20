#!/bin/bash

# Deploy and setup the sensor reader service on Raspberry Pi
# This script deploys run_sensor.sh and the systemd service

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

echo "Deploying sensor reader service to Raspberry Pi..."
echo "  Target: ${PI_CONNECTION}:${PI_KIOSK_HOME}"
echo ""

# Create kiosk directory on Pi
ssh -o ConnectTimeout=10 ${PI_CONNECTION} "mkdir -p ${PI_KIOSK_HOME}"

# Check if test_sensor binary exists
echo "  Checking if test_sensor binary exists..."
if ! ssh -o ConnectTimeout=10 ${PI_CONNECTION} "test -f ${PI_KIOSK_HOME}/test_sensor"; then
    echo "  Warning: test_sensor binary not found at ${PI_KIOSK_HOME}/test_sensor"
    echo "  You may need to run deploy-test_sensor.sh first"
    read -p "  Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Deploy run_sensor.sh script
echo "  Deploying run_sensor.sh..."
scp -o ConnectTimeout=10 run_sensor.sh ${PI_CONNECTION}:${PI_KIOSK_HOME}/run_sensor.sh
ssh -o ConnectTimeout=10 ${PI_CONNECTION} "chmod +x ${PI_KIOSK_HOME}/run_sensor.sh"

# Deploy systemd service file
echo "  Deploying systemd service file..."
scp -o ConnectTimeout=10 water-pi-sensor-reader.service ${PI_CONNECTION}:/tmp/water-pi-sensor-reader.service

# Install and start the service
echo "  Installing and starting systemd service..."
ssh -o ConnectTimeout=10 ${PI_CONNECTION} "
    sudo mv /tmp/water-pi-sensor-reader.service /etc/systemd/system/water-pi-sensor-reader.service && \
    sudo systemctl daemon-reload && \
    sudo systemctl enable water-pi-sensor-reader.service && \
    sudo systemctl restart water-pi-sensor-reader.service
"

if [ $? -eq 0 ]; then
    echo ""
    echo "Sensor reader service installed and started!"
    echo ""
    
    # Check service status
    echo "  Checking service status..."
    ssh -o ConnectTimeout=10 ${PI_CONNECTION} "sudo systemctl status water-pi-sensor-reader.service --no-pager -l"
    
    echo ""
    echo "Service management commands:"
    echo "  Check status:  ssh ${PI_CONNECTION} 'sudo systemctl status water-pi-sensor-reader.service'"
    echo "  View logs:     ssh ${PI_CONNECTION} 'sudo journalctl -u water-pi-sensor-reader.service -f'"
    echo "  Stop service:  ssh ${PI_CONNECTION} 'sudo systemctl stop water-pi-sensor-reader.service'"
    echo "  Start service: ssh ${PI_CONNECTION} 'sudo systemctl start water-pi-sensor-reader.service'"
    echo "  Restart:       ssh ${PI_CONNECTION} 'sudo systemctl restart water-pi-sensor-reader.service'"
else
    echo ""
    echo "[Error] Failed to install sensor reader service. Check error messages above."
    exit 1
fi
