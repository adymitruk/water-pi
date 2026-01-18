#!/bin/bash

# Check and install required dependencies
# This script should be sourced after common.sh

check_and_install_dependencies() {
    echo ""
    echo "--- Checking Dependencies ---"
    echo "Checking required tools and installing missing ones if needed..."
    
    # Essential commands that should always be available
    echo "  Checking essential commands (ssh, ping, etc.)..."
    local essential_commands=("ssh" "ssh-keygen" "ssh-copy-id" "ping" "hostname" "ip" "getent")
    for cmd in "${essential_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "  Error: Essential command '$cmd' is not available."
            echo "  Please install required packages and try again."
            log_entry "ERROR: Essential command '$cmd' not found"
            exit 1
        fi
    done
    echo "  [OK] All essential commands are available."
    
    # Optional but recommended commands (install if missing)
    echo "  Checking optional tools (nmap, arp-scan, etc.)..."
    ensure_command "nmap" "nmap"
    
    # arp-scan requires sudo - install if sudo is available
    if command -v sudo >/dev/null 2>&1; then
        ensure_command "arp-scan" "arp-scan"
    fi
    
    # Check WiFi tools - prefer nmcli, but check iw and iwlist for fallback
    echo "  Checking Wi-Fi tools..."
    if ! command -v nmcli >/dev/null 2>&1; then
        ensure_command "nmcli" "network-manager"
    else
        echo "  [OK] nmcli is available for Wi-Fi scanning."
    fi
    
    # iw is used by iwlist fallback
    if ! command -v iw >/dev/null 2>&1; then
        ensure_command "iw" "iw"
    fi
    
    # iwlist is a fallback for WiFi scanning (requires sudo) - install if sudo is available
    if command -v sudo >/dev/null 2>&1 && ! command -v iwlist >/dev/null 2>&1; then
        ensure_command "iwlist" "wireless-tools"
    fi
    
    echo "  [OK] All dependencies checked and ready."
    log_entry "Dependencies checked and installed"
}

# If script is executed directly (not sourced), set up and run
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Determine script directory and source common.sh
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/common.sh"
    
    # Set up minimal logging if LOG_FILE is not set
    if [ -z "$LOG_FILE" ]; then
        LOG_DIR="$SCRIPT_DIR/../logs"
        mkdir -p "$LOG_DIR"
        LOG_FILE="$LOG_DIR/dependencies-$(date +%Y%m%d-%H%M%S).log"
    fi
    
    # Set up signal handler for CTRL-C
    cleanup_script() {
        cleanup_passwords
        log_entry "Script interrupted by user (CTRL-C)"
        exit 130
    }
    trap cleanup_script INT TERM
    
    # Run the main function
    check_and_install_dependencies
    exit_code=$?
    cleanup_passwords
    exit $exit_code
fi
