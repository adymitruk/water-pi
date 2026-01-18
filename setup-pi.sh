#!/bin/bash

# Security: Disable history for this script to prevent password leakage
set +o history 2>/dev/null
HISTCONTROL=ignoreboth

# Setup logging - all scripts will append to the same log file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"

# Source common utilities (must be first)
source "$LIB_DIR/common.sh"

# Log that main script started
log_entry "Script started"

# Cleanup function to unset passwords and restore history
cleanup() {
    local exit_code=$?
    cleanup_passwords
    log_entry "Script execution completed (exit code: $exit_code)"
    # Exit with appropriate code: 130 for SIGINT (CTRL-C), preserve others
    if [ $exit_code -eq 130 ] || [ $exit_code -eq 2 ]; then
        exit 130
    fi
    exit ${exit_code:-0}
}
# Set up signal handlers - INT (CTRL-C) and TERM should exit
trap 'cleanup_passwords; log_entry "Script interrupted by user (CTRL-C)"; exit 130' INT
trap cleanup EXIT TERM

# Check if lib directory exists
if [ ! -d "$LIB_DIR" ]; then
    echo "Error: lib directory not found at $LIB_DIR"
    exit 1
fi

# Source all library scripts
source "$LIB_DIR/dependencies.sh"
source "$LIB_DIR/discover-pi.sh"
source "$LIB_DIR/pick-wifi.sh"
source "$LIB_DIR/configure-ssh.sh"
source "$LIB_DIR/change-password.sh"
source "$LIB_DIR/configure-wifi.sh"

# --- Main Logic Flow ---

# Step 1: Check Dependencies
log_entry "Checking dependencies..."
check_and_install_dependencies

# Step 2: Initial Setup
echo ""
echo "=========================================="
echo "   Raspberry Pi Headless Setup Assistant"
echo "=========================================="
log_entry "Starting configuration"

# Discover and select Pi IP/Hostname
echo ""
echo "First, we need to identify your Raspberry Pi on the network."
echo "The script will scan your network for devices and then ask you to select your Pi."
PI_IP=$(select_pi)
if [ $? -ne 0 ] || [ -z "$PI_IP" ]; then
    exit 1
fi

# Get username (needed for SSH configuration)
echo ""
echo "Next, we need your Pi username to connect via SSH."
while [ -z "$PI_USER" ]; do
    if ! read -p "Enter Pi Username: " PI_USER; then
        # read returns non-zero on CTRL-C
        echo ""
        cleanup_passwords
        exit 130
    fi
    if [ -z "$PI_USER" ]; then
        echo "  Error: Username cannot be empty. Please try again."
    fi
done
log_entry "Pi Username: $PI_USER"

# Step 3: Configure SSH
echo ""
echo "Now we'll set up SSH key authentication (no more passwords needed!)"
if ! configure_ssh "$PI_USER" "$PI_IP"; then
    cleanup_passwords
    exit 1
fi

# Step 4: Change Password
echo ""
echo "--- Security Setup ---"
echo "Now we'll set a new password for your Pi user account."
echo "This password will replace the current one."
# Temporarily disable history during password entry
set +o history 2>/dev/null
if ! read -s -p "Enter NEW Password for Pi: " NEW_PASS; then
    echo ""
    set -o history 2>/dev/null
    cleanup_passwords
    exit 130
fi
echo ""
if ! read -s -p "Confirm NEW Password: " NEW_PASS_CONFIRM; then
    echo ""
    set -o history 2>/dev/null
    cleanup_passwords
    exit 130
fi
echo ""
set -o history 2>/dev/null

if [ "$NEW_PASS" != "$NEW_PASS_CONFIRM" ]; then
    echo "Error: Passwords do not match!"
    log_entry "ERROR: Password confirmation failed"
    cleanup_passwords
    exit 1
fi
log_entry "New Pi password set (hash: $(hash_password "$NEW_PASS"))"

echo ""
echo "Changing your Pi user password..."
if ! change_password "$PI_USER" "$PI_IP" "$NEW_PASS"; then
    cleanup_passwords
    exit 1
fi
# Password is no longer needed - unset it immediately
unset NEW_PASS NEW_PASS_CONFIRM

# Step 5: Configure WiFi
echo ""
echo "Next, we'll set up Wi-Fi on your Pi."
echo "The script will scan for available networks on the Pi and ask you to select one."
if ! configure_wifi "$PI_USER" "$PI_IP"; then
    exit 1
fi

log_entry "All setup steps completed successfully"
