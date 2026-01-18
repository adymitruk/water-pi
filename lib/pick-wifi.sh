#!/bin/bash

# Pick WiFi network
# This script should be sourced after common.sh

# Function to scan for WiFi networks on the Pi
discover_wifi_networks_on_pi() {
    local pi_user="$1"
    local pi_ip="$2"
    local networks=()
    
    echo "  Scanning for Wi-Fi networks on the Pi..." >&2
    
    # First, ensure WiFi interface is up and ready
    echo "  Ensuring WiFi interface is ready..." >&2
    ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
        "sudo ip link set wlan0 up 2>/dev/null || sudo ip link set wlp* up 2>/dev/null || true" 2>/dev/null || true
    
    # Trigger a fresh scan on the Pi
    echo "  Triggering fresh Wi-Fi scan on Pi (this may take a few seconds)..." >&2
    local scan_result
    scan_result=$(ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
        "sudo nmcli device wifi rescan 2>&1" 2>/dev/null)
    
    if echo "$scan_result" | grep -qi "error\|failed\|unavailable"; then
        echo "  [Warning] Scan command had issues. Trying alternative method..." >&2
        # Try bringing interface up explicitly
        ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
            "sudo nmcli device set wlan0 managed yes 2>/dev/null || sudo nmcli device set wlp* managed yes 2>/dev/null || true" 2>/dev/null || true
    fi
    
    sleep 3  # Give more time for scan to complete
    
    echo "  Reading available Wi-Fi networks from Pi..." >&2
    
    # Use nmcli on the Pi to get networks
    local scan_output
    scan_output=$(ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
        "nmcli --terse --fields SSID,SIGNAL,SECURITY device wifi list 2>&1" 2>/dev/null)
    
    if [ -z "$scan_output" ]; then
        echo "  [Warning] No output from WiFi scan. Checking WiFi status..." >&2
        # Check WiFi radio status
        local radio_status
        radio_status=$(ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
            "nmcli radio wifi 2>/dev/null" 2>/dev/null)
        if [ "$radio_status" != "enabled" ]; then
            echo "  [Error] WiFi radio is not enabled. Attempting to enable..." >&2
            ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
                "sudo nmcli radio wifi on 2>&1" 2>/dev/null || true
            sleep 2
            # Try scan again
            scan_output=$(ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
                "nmcli --terse --fields SSID,SIGNAL,SECURITY device wifi list 2>&1" 2>/dev/null)
        fi
    fi
    
    while IFS= read -r line; do
        # Skip error messages and empty lines
        if echo "$line" | grep -qi "error\|failed\|unavailable" || [ -z "$line" ]; then
            continue
        fi
        
        # Parse the terse format: SSID:SIGNAL:SECURITY (colon-separated)
        local ssid=$(echo "$line" | cut -d':' -f1)
        local signal=$(echo "$line" | cut -d':' -f2)
        local security=$(echo "$line" | cut -d':' -f3)
        
        # Skip empty SSIDs (hidden networks show as "--")
        if [ -n "$ssid" ] && [ "$ssid" != "--" ] && [ "$ssid" != "" ]; then
            if [ -n "$security" ] && [ "$security" != "--" ]; then
                networks+=("$ssid (${signal}% signal, $security)")
            else
                networks+=("$ssid (${signal}% signal)")
            fi
        fi
    done <<< "$scan_output"
    
    printf '%s\n' "${networks[@]}"
}

# Function to scan for WiFi networks locally (fallback)
discover_wifi_networks() {
    local networks=()
    
    echo "  Scanning for Wi-Fi networks..." >&2
    
    # Use nmcli (preferred, no root needed)
    if command -v nmcli >/dev/null 2>&1; then
        # Trigger a fresh scan
        echo "  Triggering fresh Wi-Fi scan (this may take a few seconds)..." >&2
        nmcli device wifi rescan >/dev/null 2>&1
        sleep 1
        echo "  Reading available Wi-Fi networks..." >&2
        
        while IFS= read -r line; do
            # Parse the terse format: SSID:SIGNAL:SECURITY (colon-separated)
            local ssid=$(echo "$line" | cut -d':' -f1)
            local signal=$(echo "$line" | cut -d':' -f2)
            local security=$(echo "$line" | cut -d':' -f3)
            
            # Skip empty SSIDs (hidden networks show as "--")
            if [ -n "$ssid" ] && [ "$ssid" != "--" ]; then
                if [ -n "$security" ] && [ "$security" != "--" ]; then
                    networks+=("$ssid (${signal}% signal, $security)")
                else
                    networks+=("$ssid (${signal}% signal)")
                fi
            fi
        done < <(nmcli --terse --fields SSID,SIGNAL,SECURITY device wifi list 2>/dev/null || true)
    # Fallback to iwlist (requires sudo)
    elif command -v iwlist >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        local iface=$(iw dev | awk '/Interface/ {print $2}' | head -1)
        if [ -n "$iface" ]; then
            echo "  Using iwlist to scan for Wi-Fi networks (interface: $iface)..." >&2
            local current_essid=""
            while IFS= read -r line; do
                if [[ "$line" =~ ESSID:\"(.+)\" ]]; then
                    current_essid="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ Quality=([0-9]+)/([0-9]+) ]] && [ -n "$current_essid" ]; then
                    local quality="${BASH_REMATCH[1]}"
                    local max_quality="${BASH_REMATCH[2]}"
                    local signal=$(( quality * 100 / max_quality ))
                    networks+=("$current_essid (${signal}% signal)")
                    current_essid=""
                fi
            done < <(sudo iwlist "$iface" scan 2>/dev/null || true)
        fi
    fi
    
    printf '%s\n' "${networks[@]}"
}

# Main function to pick WiFi network
# If pi_user and pi_ip are provided, scan on the Pi; otherwise scan locally
pick_wifi() {
    local pi_user="${1:-}"
    local pi_ip="${2:-}"
    
    echo "" >&2
    echo "--- Wi-Fi Setup ---" >&2
    
    # Read WiFi networks into array properly (handle spaces in SSIDs)
    # If Pi credentials provided, scan on Pi; otherwise scan locally
    if [ -n "$pi_user" ] && [ -n "$pi_ip" ]; then
        mapfile -t wifi_list < <(discover_wifi_networks_on_pi "$pi_user" "$pi_ip")
    else
        mapfile -t wifi_list < <(discover_wifi_networks)
    fi
    
    # Log discovered WiFi networks
    if [ ${#wifi_list[@]} -eq 0 ]; then
        log_entry "Discovered 0 WiFi networks"
    else
        log_entry "Discovered ${#wifi_list[@]} WiFi network(s):"
        for network in "${wifi_list[@]}"; do
            log_entry "  - $network"
        done
    fi
    
    local wifi_ssid
    if [ ${#wifi_list[@]} -eq 0 ]; then
        echo "  No Wi-Fi networks found. You can enter a custom SSID." >&2
        wifi_ssid=$(select_from_menu "Select Wi-Fi Network:" "Enter custom value")
    else
        echo "  Found ${#wifi_list[@]} network(s)" >&2
        wifi_ssid=$(select_from_menu "Select Wi-Fi Network:" "${wifi_list[@]}")
    fi
    
    # Clean the SSID (remove any extra info from menu selection)
    wifi_ssid=$(echo "$wifi_ssid" | sed 's/ ([^)]*).*$//' | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//' | tr -d '\r\n')
    if [ -z "$wifi_ssid" ]; then
        echo "  Error: Invalid or empty SSID selected." >&2
        log_entry "ERROR: Invalid SSID selected"
        return 1
    fi
    echo "  Selected: $wifi_ssid" >&2
    log_entry "Selected WiFi SSID: $wifi_ssid"
    
    # Output only the SSID to stdout (for command substitution)
    echo "$wifi_ssid"
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
        LOG_FILE="$LOG_DIR/pick-wifi-$(date +%Y%m%d-%H%M%S).log"
    fi
    
    # Set up signal handler for CTRL-C
    cleanup_script() {
        cleanup_passwords
        log_entry "Script interrupted by user (CTRL-C)"
        exit 130
    }
    trap cleanup_script INT TERM
    
    # Run the main function
    pick_wifi
    exit_code=$?
    cleanup_passwords
    exit $exit_code
fi
