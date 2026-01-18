#!/bin/bash

# Discover Pi on network and return IP/hostname
# This script should be sourced after common.sh

# Function to discover network devices (IPs and hostnames)
discover_network_devices() {
    local devices=()
    
    echo "  Scanning network for devices..." >&2
    
    # Get local subnet
    local subnet
    local my_ip=$(hostname -I | awk '{print $1}')
    if [ -n "$my_ip" ]; then
        # Extract subnet (assumes /24, could be improved)
        subnet=$(echo "$my_ip" | sed 's/\.[0-9]*$/\.0\/24/')
        echo "  Detected network: $subnet (this machine: $my_ip)" >&2
    else
        # Fallback: try to get from ip command
        subnet=$(ip route | grep -E '^[0-9]' | head -1 | awk '{print $1}')
        if [ -n "$subnet" ]; then
            echo "  Detected network: $subnet" >&2
        fi
    fi
    
    # Try nmap ping scan first (works without sudo, though less effective)
    # nmap -sn uses ARP on local networks which works without root
    if command -v nmap >/dev/null 2>&1 && [ -n "$subnet" ]; then
        echo "  Using nmap to scan for devices (this may take a moment)..." >&2
        while IFS= read -r line; do
            local ip=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            if [[ -n "$ip" ]] && [[ ! " ${devices[@]} " =~ " ${ip} " ]]; then
                # Try reverse DNS lookup
                local hostname=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}' | head -1)
                if [ -n "$hostname" ] && [ "$hostname" != "$ip" ]; then
                    # Check if .local version exists and prefer it for mDNS
                    if [[ ! "$hostname" =~ \.local$ ]]; then
                        if ping -c 1 -W 1 "${hostname}.local" >/dev/null 2>&1; then
                            # Show hostname.local first (preferred), IP in parentheses
                            devices+=("${hostname}.local ($ip)")
                        else
                            devices+=("$ip ($hostname)")
                        fi
                    else
                        # Already has .local, show it first
                        devices+=("$hostname ($ip)")
                    fi
                else
                    devices+=("$ip")
                fi
            fi
        done < <(nmap -sn "$subnet" 2>/dev/null | grep -E '^Nmap scan report' || true)
        
        # If no devices found and sudo is available, try with sudo for better results
        if [ ${#devices[@]} -eq 0 ] && sudo -n true 2>/dev/null; then
            echo "  No devices found with regular scan. Trying with elevated privileges..." >&2
            while IFS= read -r line; do
                local ip=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                if [[ -n "$ip" ]] && [[ ! " ${devices[@]} " =~ " ${ip} " ]]; then
                    local hostname=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}' | head -1)
                    if [ -n "$hostname" ] && [ "$hostname" != "$ip" ]; then
                        # Check if .local version exists and prefer it for mDNS
                        if [[ ! "$hostname" =~ \.local$ ]]; then
                            if ping -c 1 -W 1 "${hostname}.local" >/dev/null 2>&1; then
                                # Show hostname.local first (preferred), IP in parentheses
                                devices+=("${hostname}.local ($ip)")
                            else
                                devices+=("$ip ($hostname)")
                            fi
                        else
                            # Already has .local, show it first
                            devices+=("$hostname ($ip)")
                        fi
                    else
                        devices+=("$ip")
                    fi
                fi
            done < <(sudo nmap -sn "$subnet" 2>/dev/null | grep -E '^Nmap scan report' || true)
        fi
    fi
    
    # Try arp-scan if available (requires sudo, but very fast)
    if command -v arp-scan >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        local iface=$(ip route | grep default | awk '{print $5}' | head -1)
        if [ -n "$iface" ] && [ -n "$subnet" ]; then
            echo "  Using arp-scan for faster device discovery (interface: $iface)..." >&2
            while IFS= read -r line; do
                local ip=$(echo "$line" | awk '{print $1}')
                if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    # Only add if not already found
                    if [[ ! " ${devices[@]} " =~ " ${ip} " ]]; then
                        # Extract vendor info (everything after MAC address, handling both tabs and spaces)
                        local vendor=$(echo "$line" | sed 's/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\s\+[0-9A-Fa-f:]\+\s\+//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
                        if [ -n "$vendor" ] && [ "$vendor" != "Unknown" ]; then
                            devices+=("$ip ($vendor)")
                        else
                            devices+=("$ip")
                        fi
                    fi
                fi
            done < <(sudo arp-scan --interface="$iface" --localnet 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
        fi
    fi
    
    # Check common Raspberry Pi hostnames via avahi/mDNS
    echo "  Checking for common Raspberry Pi hostnames (mDNS/Avahi)..." >&2
    local common_hostnames=("raspberrypi.local" "raspberry.local" "pi.local")
    for hostname in "${common_hostnames[@]}"; do
        if ping -c 1 -W 1 "$hostname" >/dev/null 2>&1; then
            local ip=$(getent hosts "$hostname" 2>/dev/null | awk '{print $1}' | head -1)
            if [ -n "$ip" ]; then
                if [[ ! " ${devices[@]} " =~ " ${ip} " ]] && [[ ! " ${devices[@]} " =~ " ${hostname} " ]]; then
                    devices+=("$hostname ($ip)")
                fi
            fi
        fi
    done
    
    # If no devices found, add the local IP as a suggestion
    if [ ${#devices[@]} -eq 0 ] && [ -n "$my_ip" ]; then
        devices+=("$my_ip (this machine)")
    fi
    
    printf '%s\n' "${devices[@]}"
}

# Main function to discover and select Pi
select_pi() {
    echo "" >&2
    echo "--- Discovering Pi on Network ---" >&2
    # Read devices into array properly (handle spaces in device names)
    mapfile -t device_list < <(discover_network_devices)
    
    # Log discovered devices
    if [ ${#device_list[@]} -eq 0 ]; then
        log_entry "Discovered 0 network devices"
    else
        log_entry "Discovered ${#device_list[@]} network device(s):"
        for device in "${device_list[@]}"; do
            log_entry "  - $device"
        done
    fi
    
    local pi_ip
    if [ ${#device_list[@]} -eq 0 ]; then
        echo "  No devices found. You can enter a custom IP/hostname." >&2
        pi_ip=$(select_from_menu "Select Pi IP Address or Hostname:" "Enter custom value")
    else
        echo "  Found ${#device_list[@]} device(s)" >&2
        pi_ip=$(select_from_menu "Select Pi IP Address or Hostname:" "${device_list[@]}")
    fi
    
    # Clean and validate the selected IP/hostname
    pi_ip=$(echo "$pi_ip" | tr -d '\r\n' | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//' | sed 's/[\(\)].*$//' | sed 's/[[:space:]].*$//')
    if [ -z "$pi_ip" ]; then
        echo "  Error: Invalid or empty IP/hostname selected." >&2
        log_entry "ERROR: Invalid IP/hostname selected"
        return 1
    fi
    
    # If it's a hostname (not an IP address), try to use .local for mDNS resolution
    if [[ ! "$pi_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # It's a hostname, check if .local version resolves
        if [[ ! "$pi_ip" =~ \.local$ ]]; then
            # Try to resolve hostname.local
            if ping -c 1 -W 1 "${pi_ip}.local" >/dev/null 2>&1; then
                local resolved_ip=$(getent hosts "${pi_ip}.local" 2>/dev/null | awk '{print $1}' | head -1)
                if [ -n "$resolved_ip" ]; then
                    echo "  Using mDNS hostname: ${pi_ip}.local" >&2
                    log_entry "Converted hostname to mDNS: ${pi_ip} -> ${pi_ip}.local"
                    pi_ip="${pi_ip}.local"
                fi
            fi
        fi
    fi
    
    echo "  Selected: $pi_ip" >&2
    log_entry "Selected Pi IP/Hostname: $pi_ip"
    
    echo "$pi_ip"
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
        LOG_FILE="$LOG_DIR/discover-pi-$(date +%Y%m%d-%H%M%S).log"
    fi
    
    # Set up signal handler for CTRL-C
    cleanup_script() {
        cleanup_passwords
        log_entry "Script interrupted by user (CTRL-C)"
        exit 130
    }
    trap cleanup_script INT TERM
    
    # Run the main function
    select_pi
    exit_code=$?
    cleanup_passwords
    exit $exit_code
fi
