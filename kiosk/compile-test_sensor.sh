#!/bin/bash

# Compile test_sensor.c for Raspberry Pi
# This script compiles directly on the Pi

# Source environment variables if available
if [ -f "../env.sh" ]; then
    source ../env.sh
elif [ -f "../env" ]; then
    source ../env
fi

PI_CONNECTION="${PI_CONNECTION:-adam@raspberrypi.local}"
PI_KIOSK_HOME="${PI_SCRIPTS_HOME:-/home/adam}/kiosk"

echo "Compiling test_sensor.c on Raspberry Pi..."
echo ""

# Copy source to Pi
echo "Copying source file to Pi..."
scp -o ConnectTimeout=10 test_sensor.c ${PI_CONNECTION}:/tmp/test_sensor.c

# Compile on Pi
echo "Compiling on Pi..."
ssh -o ConnectTimeout=10 ${PI_CONNECTION} "
    cd /tmp && \
    if gcc -o test_sensor test_sensor.c -lgpiod -Wall -O2 2>&1; then
        echo 'Compilation successful!'
        mv test_sensor ${PI_KIOSK_HOME}/test_sensor
        chmod +x ${PI_KIOSK_HOME}/test_sensor
        rm -f /tmp/test_sensor.c
        echo 'Binary installed at: ${PI_KIOSK_HOME}/test_sensor'
        exit 0
    else
        echo 'Compilation failed. Error output above.'
        exit 1
    fi
"

if [ $? -eq 0 ]; then
    echo ""
    echo "Compilation and deployment successful!"
    echo "Run on the Pi: sudo ${PI_KIOSK_HOME}/test_sensor"
else
    echo ""
    echo "Compilation failed. See error messages above."
    exit 1
fi
