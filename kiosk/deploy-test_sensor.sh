#!/bin/bash

# Deploy and compile test_sensor.c for Raspberry Pi
# This script compiles directly on the Pi and deploys the binary

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

echo "Deploying and compiling test_sensor.c on Raspberry Pi..."
echo "  Target: ${PI_CONNECTION}:${PI_KIOSK_HOME}"
echo ""

# Create kiosk directory on Pi
ssh -o ConnectTimeout=10 ${PI_CONNECTION} "mkdir -p ${PI_KIOSK_HOME}"

# Copy source file to Pi
echo "  Copying source file to Pi..."
scp -o ConnectTimeout=10 test_sensor.c ${PI_CONNECTION}:/tmp/test_sensor.c

# Compile on Pi
echo "  Compiling on Pi..."
ssh -o ConnectTimeout=10 ${PI_CONNECTION} "
    cd /tmp && \
    if gcc -o test_sensor test_sensor.c -lgpiod -Wall -O2 2>&1; then
        echo '  Compilation successful!'
        mv test_sensor ${PI_KIOSK_HOME}/test_sensor
        chmod +x ${PI_KIOSK_HOME}/test_sensor
        rm -f /tmp/test_sensor.c
        echo '  Binary installed at: ${PI_KIOSK_HOME}/test_sensor'
        exit 0
    else
        echo '  Compilation failed. Error output above.'
        exit 1
    fi
"

if [ $? -eq 0 ]; then
    echo ""
    echo "Deployment and compilation successful!"
    echo ""
    echo "  To run continuously:"
    echo "    ssh -t ${PI_CONNECTION} \"sudo ${PI_KIOSK_HOME}/test_sensor\""
    echo ""
    echo "  To run for a specific duration (e.g., 1000ms):"
    echo "    ssh -t ${PI_CONNECTION} \"sudo ${PI_KIOSK_HOME}/test_sensor 1000\""
    echo ""
else
    echo ""
    echo "Deployment/compilation failed. See error messages above."
    exit 1
fi
