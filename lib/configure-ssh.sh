#!/bin/bash

# Configure SSH key access to Pi
# This script should be sourced after common.sh

configure_ssh() {
    local pi_user="$1"
    local pi_ip="$2"
    
    echo "[Step 1/3] Checking SSH Access..."
    
    # Validate PI_IP doesn't contain invalid characters
    pi_ip=$(echo "$pi_ip" | tr -d '\r\n' | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//')
    if [[ "$pi_ip" =~ [[:space:]] ]] || [[ "$pi_ip" =~ [\(\)] ]]; then
        echo "  [Error] Invalid hostname/IP detected: '$pi_ip'"
        echo "  Please ensure the hostname/IP doesn't contain spaces or parentheses."
        log_entry "ERROR: Invalid hostname/IP: $pi_ip"
        return 1
    fi
    
    # Check if we have an existing SSH key
    if [ -f ~/.ssh/id_ed25519.pub ]; then
        echo "  Found existing SSH key: ~/.ssh/id_ed25519.pub"
    else
        echo "  No existing SSH key found. Will generate one if needed."
    fi
    
    # Try to connect without password (using existing keys)
    # -o BatchMode=yes fails immediately if password is required
    echo "  Testing SSH key authentication (connecting to $pi_user@$pi_ip)..."
    ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$pi_user@$pi_ip" exit 2>/dev/null
    
    local ssh_test_result=$?
    if [ $ssh_test_result -eq 0 ]; then
        echo "  [OK] SSH key authentication is already working! No password needed."
        log_entry "SSH key authentication already working"
        return 0
    else
        echo "  [!] SSH key authentication is not set up yet."
        echo "      We'll set it up now so you won't need passwords for SSH in the future."
        echo "      (You will be asked for the CURRENT Pi password once during setup)"
        log_entry "Setting up SSH key authentication"
        
        # Generate key if it doesn't exist on laptop
        if [ ! -f ~/.ssh/id_ed25519 ]; then
            echo "  Generating new SSH keypair on this computer..."
            ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
            echo "  [OK] SSH keypair generated successfully."
            log_entry "Generated new SSH keypair"
        else
            echo "  Using existing SSH keypair."
        fi
        
        # Copy key to Pi (this will prompt for password)
        # Note: ssh-copy-id will propagate SIGINT, so CTRL-C should work
        echo "  Copying SSH public key to Pi ($pi_user@$pi_ip)..."
        if ssh-copy-id -i ~/.ssh/id_ed25519.pub "$pi_user@$pi_ip"; then
            echo "  [OK] SSH key installed successfully!"
            echo "       From now on, you can SSH to this Pi without entering a password."
            log_entry "SSH key installed successfully"
            return 0
        else
            echo "  [Error] Failed to copy SSH key."
            echo "  Possible causes:"
            echo "    - Invalid hostname/IP: '$pi_ip'"
            echo "    - Incorrect password"
            echo "    - Network connectivity issues"
            log_entry "ERROR: Failed to copy SSH key"
            return 1
        fi
    fi
}

# If script is executed directly (not sourced), show usage or run interactively
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Determine script directory and source common.sh
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/common.sh"
    
    # Set up minimal logging if LOG_FILE is not set
    if [ -z "$LOG_FILE" ]; then
        LOG_DIR="$SCRIPT_DIR/../logs"
        mkdir -p "$LOG_DIR"
        LOG_FILE="$LOG_DIR/configure-ssh-$(date +%Y%m%d-%H%M%S).log"
    fi
    
    # Set up signal handler for CTRL-C
    cleanup_script() {
        cleanup_passwords
        log_entry "Script interrupted by user (CTRL-C)"
        exit 130
    }
    trap cleanup_script INT TERM
    
    # Check if all required arguments are provided
    if [ $# -lt 2 ]; then
        echo "Usage: $0 <pi_user> <pi_ip>"
        echo ""
        echo "Example: $0 pi 192.168.1.100"
        exit 1
    fi
    
    # Run the main function with provided arguments
    configure_ssh "$1" "$2"
    exit_code=$?
    cleanup_passwords
    exit $exit_code
fi
