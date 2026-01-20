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

# Web directory on Pi
PI_WEB_HOME="${PI_SCRIPTS_HOME}/kiosk/web"

echo "Deploying web site to Raspberry Pi..."
echo "  Target: ${PI_CONNECTION}:${PI_WEB_HOME}"

# Create web directory on Pi
ssh -o ConnectTimeout=100 ${PI_CONNECTION} "mkdir -p ${PI_WEB_HOME}"

# Deploy web files
echo "  Copying web files..."
scp -o ConnectTimeout=100 web/app.js ${PI_CONNECTION}:${PI_WEB_HOME}/app.js
scp -o ConnectTimeout=100 web/index.html ${PI_CONNECTION}:${PI_WEB_HOME}/index.html
scp -o ConnectTimeout=100 web/package.json ${PI_CONNECTION}:${PI_WEB_HOME}/package.json

# Check if Node.js is installed on Pi
echo "  Checking for Node.js..."
NODE_CHECK=$(ssh -o ConnectTimeout=10 ${PI_CONNECTION} "which node || which nodejs || echo 'not_found'")

if [ "$NODE_CHECK" = "not_found" ]; then
    echo ""
    echo "  [Warning] Node.js is not installed on the Pi."
    echo "  To install Node.js, run on the Pi:"
    echo "    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
    echo "    sudo apt-get install -y nodejs"
    echo ""
    echo "  Or install via apt (may be older version):"
    echo "    sudo apt-get update && sudo apt-get install -y nodejs npm"
    echo ""
else
    # Install npm dependencies on Pi
    echo "  Installing npm dependencies..."
    ssh -o ConnectTimeout=1000 ${PI_CONNECTION} "cd ${PI_WEB_HOME} && npm install"
    
    if [ $? -eq 0 ]; then
        echo "  Dependencies installed successfully!"
    else
        echo "  [Warning] Failed to install dependencies. You may need to run 'npm install' manually on the Pi."
    fi
    
    # Deploy and install systemd service
    echo "  Deploying systemd service..."
    
    # Find node path on Pi
    NODE_PATH=$(ssh -o ConnectTimeout=10 ${PI_CONNECTION} "which node || which nodejs || echo '/usr/bin/node'")
    echo "  Using Node.js at: $NODE_PATH"
    
    # Create service file with correct node path
    ssh -o ConnectTimeout=100 ${PI_CONNECTION} "cat > /tmp/water-pi-kiosk.service << EOFSERVICE
[Unit]
Description=Water Pi Kiosk Web Server
After=network.target

[Service]
Type=simple
User=adam
WorkingDirectory=${PI_WEB_HOME}
Environment=\"NODE_ENV=production\"
Environment=\"PORT=3000\"
ExecStart=${NODE_PATH} ${PI_WEB_HOME}/app.js
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSERVICE
"
    
    echo "  Installing systemd service..."
    ssh -o ConnectTimeout=10 ${PI_CONNECTION} "sudo mv /tmp/water-pi-kiosk.service /etc/systemd/system/water-pi-kiosk.service && sudo systemctl daemon-reload && sudo systemctl enable water-pi-kiosk.service"
    
    if [ $? -eq 0 ]; then
        echo "  Service installed and enabled!"
        echo ""
        echo "  To start the service now, run on the Pi:"
        echo "    sudo systemctl start water-pi-kiosk"
        echo ""
        echo "  To check service status:"
        echo "    sudo systemctl status water-pi-kiosk"
        echo ""
        echo "  To view logs:"
        echo "    journalctl -u water-pi-kiosk -f"
    else
        echo "  [Warning] Failed to install systemd service. You may need to do this manually."
    fi
fi

echo ""
echo "Web site deployed successfully!"
echo ""
echo "The service is configured to start automatically on boot."
echo "To start the server manually, run on the Pi:"
echo "  sudo systemctl start water-pi-kiosk"
echo ""
echo "Or start it manually without systemd:"
echo "  cd ${PI_WEB_HOME} && npm start"
