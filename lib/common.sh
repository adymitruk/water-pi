#!/bin/bash

# Common utilities and functions shared across scripts
# This file should be sourced by other scripts, not executed directly

# Logging function - appends to the log file specified by LOG_FILE variable and echoes to console
log_entry() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_line="[$timestamp] $message"
    
    # Always echo to console (stderr, so it doesn't interfere with command substitution)
    echo "$log_line" >&2
    
    # Also write to log file if specified
    if [ -n "$LOG_FILE" ]; then
        echo "$log_line" >> "$LOG_FILE"
    fi
}

# Function to hash password for logging (SHA256)
hash_password() {
    if [ -n "$1" ]; then
        echo -n "$1" | sha256sum | awk '{print $1}'
    else
        echo "empty"
    fi
}

# Cleanup function to unset passwords and restore history
cleanup_passwords() {
    unset NEW_PASS NEW_PASS_CONFIRM WIFI_PASS CURRENT_PASS
    set -o history 2>/dev/null
}

# Function to present menu and get selection
select_from_menu() {
    local prompt="$1"
    shift
    local options=("$@")
    local custom_option="Enter custom value"
    
    # Add custom option to the end
    options+=("$custom_option")
    
    echo "" >&2
    echo "$prompt" >&2
    echo "----------------------------------------" >&2
    
    # Set up signal handler to exit on CTRL-C during menu selection
    local sigint_handler
    sigint_handler() {
        echo "" >&2
        echo "  Cancelled by user" >&2
        exit 130  # Standard exit code for SIGINT
    }
    trap sigint_handler INT
    
    PS3="Select an option (1-${#options[@]}): "
    # Use select - the menu goes to stderr, choice variable is set correctly
    select choice in "${options[@]}"; do
        # Validate the selection number
        if [[ ! "$REPLY" =~ ^[0-9]+$ ]] || [ "$REPLY" -lt 1 ] || [ "$REPLY" -gt ${#options[@]} ]; then
            echo "Invalid selection. Please try again." >&2
            continue
        fi
        
        # Check if choice was set (bash select can leave it empty for invalid numbers)
        if [ -z "$choice" ]; then
            echo "Invalid selection. Please try again." >&2
            continue
        fi
        
        # Process the valid choice
        if [ "$choice" = "$custom_option" ]; then
            # read will naturally exit on CTRL-C, but ensure we restore handler after
            if ! read -p "Enter custom value: " custom_value; then
                # read returns non-zero on CTRL-C
                echo "" >&2
                echo "  Cancelled by user" >&2
                trap - INT
                exit 130
            fi
            echo "$custom_value"
            # Restore default INT handler before returning
            trap - INT
            return
        else
            # Extract the value, preferring .local hostnames from parentheses
            # Handle cases like "192.168.1.100 (raspberrypi.local)" or "SSID (signal, security)"
            local extracted=""
            
            # First, try to extract .local hostname from parentheses - prefer that
            extracted=$(echo "$choice" | sed -n 's/.*(\([^)]*\.local\)).*/\1/p' | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//')
            
            # If no .local hostname found, extract the part before parentheses (IP or hostname)
            if [ -z "$extracted" ]; then
                extracted=$(echo "$choice" | sed 's/ ([^)]*).*$//' | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//')
            fi
            
            # If extraction didn't change anything or is empty, try taking first word
            if [ -z "$extracted" ] || [ "$extracted" = "$choice" ]; then
                extracted=$(echo "$choice" | awk '{print $1}' | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//')
            fi
            
            # Final cleanup: remove any trailing whitespace, parentheses, or other invalid characters
            extracted=$(echo "$extracted" | sed 's/[[:space:]()]*$//' | sed 's/^[[:space:]()]*//' | tr -d '\r\n')
            # Validate we have something valid
            if [ -z "$extracted" ]; then
                echo "Error: Could not extract valid value from selection" >&2
                return 1
            fi
            # Additional validation: extracted value shouldn't be common prompt words
            if [[ "$extracted" =~ ^(Select|Enter|Invalid|Custom)$ ]]; then
                echo "Error: Extracted value appears to be invalid: '$extracted'. Please try again." >&2
                continue
            fi
            echo "$extracted"
            # Restore default INT handler before returning
            trap - INT
            return
        fi
    done
    # Restore default INT handler after loop (shouldn't normally reach here)
    trap - INT
}

# Ensure a command is installed, install if missing
ensure_command() {
    local cmd="$1"
    local package="${2:-$cmd}"
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "  Installing $package (required for $cmd)..."
        if command -v sudo >/dev/null 2>&1; then
            # Run sudo - it will prompt for password if needed
            if ! sudo apt-get update -qq >/dev/null 2>&1 || ! sudo apt-get install -y -qq "$package" >/dev/null 2>&1; then
                echo "  Error: Failed to install $package. Please install it manually: sudo apt install $package"
                return 1
            fi
        else
            echo "  Warning: $package is not installed and sudo is not available."
            echo "  Please install it manually: sudo apt install $package"
            return 1
        fi
    fi
    return 0
}
