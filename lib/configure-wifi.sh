
# Configure WiFi connection on Pi
# This script should be sourced after common.sh

configure_wifi() {
    local pi_user="$1"
    local pi_ip="$2"
    local wifi_ssid="${3:-}"
    local wifi_pass="${4:-}"
    
    echo "[Step 3/3] Configuring Wi-Fi..."
    echo "  Checking if Wi-Fi is available on the Pi..."
    
    # Check if WiFi hardware exists and is enabled on the Pi
    local wifi_check
    wifi_check=$(ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
        "if command -v nmcli >/dev/null 2>&1; then \
            nmcli -t -f TYPE,STATE device status 2>/dev/null | grep -q '^wifi:connected\|^wifi:disconnected\|^wifi:unavailable' && echo 'wifi_available'; \
        elif [ -d /sys/class/net ] && ls /sys/class/net/wlan* >/dev/null 2>&1; then \
            echo 'wifi_available'; \
        else \
            echo 'wifi_not_found'; \
        fi" 2>/dev/null)
    
    if [ "$wifi_check" != "wifi_available" ]; then
        echo "  [Error] Wi-Fi hardware not found or not available on the Pi."
        echo "  The Pi may not have Wi-Fi capability, or Wi-Fi may be disabled."
        echo "  You can skip this step and configure Wi-Fi manually later."
        log_entry "ERROR: Wi-Fi not available on Pi"
        return 1
    fi
    
    echo "  Wi-Fi hardware detected."
    echo "  Ensuring Wi-Fi is enabled and ready..."
    
    # Enable WiFi radio if disabled
    ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
        "sudo nmcli radio wifi on >/dev/null 2>&1" 2>/dev/null || true
    
    # Unblock WiFi if blocked by rfkill
    ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
        "sudo rfkill unblock wifi >/dev/null 2>&1" 2>/dev/null || true
    
    # Bring up WiFi interface if it's down
    ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
        "sudo ip link set wlan0 up 2>/dev/null || sudo ip link set wlp* up 2>/dev/null" 2>/dev/null || true
    
    # Check if WLAN country is set (required for WiFi to work properly)
    local country_set
    country_set=$(ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
        "if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then \
            grep -q '^country=' /etc/wpa_supplicant/wpa_supplicant.conf && echo 'set' || echo 'not_set'; \
        elif command -v raspi-config >/dev/null 2>&1; then \
            [ -f /etc/default/crda ] && grep -q 'REGDOMAIN=' /etc/default/crda && echo 'set' || echo 'not_set'; \
        else \
            echo 'unknown'; \
        fi" 2>/dev/null)
    
    if [ "$country_set" = "not_set" ]; then
        echo "  [Warning] WLAN country code not set. This may prevent WiFi scanning."
        echo "  Please set it using: sudo raspi-config → Localization Options → WLAN Country"
        echo "  Or edit /etc/wpa_supplicant/wpa_supplicant.conf and add: country=US (or your country)"
        echo "  Continuing anyway..."
    fi
    
    sleep 1
    
    # If SSID not provided, scan and pick from Pi's networks
    if [ -z "$wifi_ssid" ]; then
        echo ""
        echo "  Scanning for Wi-Fi networks on the Pi..."
        # Source pick-wifi.sh if not already sourced
        if ! declare -f pick_wifi >/dev/null 2>&1; then
            local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            source "$script_dir/pick-wifi.sh" 2>/dev/null || true
        fi
        
        wifi_ssid=$(pick_wifi "$pi_user" "$pi_ip")
        if [ $? -ne 0 ] || [ -z "$wifi_ssid" ]; then
            log_entry "ERROR: Failed to select WiFi SSID"
            return 1
        fi
        
        # Get WiFi password
        echo ""
        echo "Now enter the password for the Wi-Fi network you selected."
        # Temporarily disable history during password entry
        set +o history 2>/dev/null
        if ! read -s -p "Enter Wi-Fi Password: " wifi_pass; then
            echo ""
            set -o history 2>/dev/null
            cleanup_passwords
            exit 130
        fi
        echo ""
        set -o history 2>/dev/null
    fi
    
    echo ""
    echo "  Connecting to network: $wifi_ssid..."
    
    # SECURITY: Pass password via stdin to avoid exposure in process list or command history
    # -tt forces pseudo-terminal allocation even when stdin is not a terminal (needed when piping)
    # Escape SSID properly for remote shell execution
    local escaped_ssid
    escaped_ssid=$(printf '%q' "$wifi_ssid")
    
    # Trigger a fresh scan on the Pi to ensure networks are visible
    echo "  Scanning for network..." >&2
    ssh -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
        "sudo nmcli device wifi rescan >/dev/null 2>&1" 2>/dev/null || true
    sleep 2
    
    echo "  Attempting connection (this may take 10-30 seconds)..." >&2
    
    # Verify password is set
    if [ -z "$wifi_pass" ]; then
        echo "  [Error] WiFi password is empty."
        log_entry "ERROR: WiFi password not provided"
        return 1
    fi
    
    # Pass password via environment variable
    # Use timeout to prevent hanging (60 seconds should be enough for Wi-Fi connection)
    # Try -T first (no pseudo-terminal), fall back to -tt if sudo needs it
    # Escape both SSID and password for safe shell execution
    local escaped_pass
    escaped_pass=$(printf '%q' "$wifi_pass")
    
    # Run the command with timeout
    # Use -T (no pseudo-terminal) first to avoid hanging, fall back to -tt if sudo needs it
    local ssh_exit
    
    # Try without pseudo-terminal first (faster, no hanging)
    timeout 60 ssh -T -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
        "WIFI_PASS=$escaped_pass sudo -n -E nmcli dev wifi connect $escaped_ssid password \"\$WIFI_PASS\" 2>&1; RC=\$?; unset WIFI_PASS; exit \$RC" 2>&1 | \
        sed -u 's/.*[Pp]assword[^:]*:[[:space:]]*//g' | \
        grep --line-buffered -v -i -E '^(WIFI_PASS|password)' || ssh_exit=$?
    
    # If that failed (sudo needs terminal), try with -tt
    if [ ${ssh_exit:-1} -ne 0 ]; then
        timeout 60 ssh -tt -o LogLevel=ERROR -o ConnectTimeout=10 "$pi_user@$pi_ip" \
            "WIFI_PASS=$escaped_pass sudo -E nmcli dev wifi connect $escaped_ssid password \"\$WIFI_PASS\" 2>&1; RC=\$?; unset WIFI_PASS; exit \$RC" 2>&1 | \
            sed -u 's/.*[Pp]assword[^:]*:[[:space:]]*//g' | \
            grep --line-buffered -v -i -E '^(WIFI_PASS|password)' || ssh_exit=$?
    fi
    
    # Ensure ssh_exit is set
    ssh_exit=${ssh_exit:-${PIPESTATUS[0]:-1}}
    
    # Handle timeout specifically
    if [ $ssh_exit -eq 124 ]; then
        echo "  [Error] Connection timed out. The Wi-Fi configuration may have taken too long."
        log_entry "ERROR: Wi-Fi configuration timed out for: $wifi_ssid"
        return 1
    fi
    
    # If SSH was interrupted (exit code 130 for SIGINT/CTRL-C), propagate it
    if [ $ssh_exit -eq 130 ]; then
        exit 130
    fi
    
    # Clean up password variable
    unset wifi_pass
    
    if [ $ssh_exit -eq 0 ]; then
        echo "  [OK] Wi-Fi configured."
        log_entry "Wi-Fi configured successfully: $wifi_ssid"
        echo ""
        echo "  -------------------------------------"
        echo "  SUCCESS! Your Pi is ready."
        echo "  1. Unplug Ethernet."
        echo "  2. Wait 10-20 seconds."
        echo "  3. SSH into the new Wi-Fi IP."
        echo "  -------------------------------------"
        return 0
    else
        echo "  [Error] Could not connect to Wi-Fi."
        echo "  Possible reasons:"
        echo "    - Network not visible from Pi's location"
        echo "    - Incorrect password"
        echo "    - Wi-Fi hardware issue"
        echo "    - Network requires additional configuration"
        log_entry "ERROR: Failed to configure Wi-Fi: $wifi_ssid"
        return 1
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
        LOG_FILE="$LOG_DIR/configure-wifi-$(date +%Y%m%d-%H%M%S).log"
    fi
    
    # Set up signal handler for CTRL-C
    cleanup_script() {
        cleanup_passwords
        log_entry "Script interrupted by user (CTRL-C)"
        exit 130
    }
    trap cleanup_script INT TERM
    
    # Check if minimum required arguments are provided
    if [ $# -lt 2 ]; then
        echo "Usage: $0 <pi_user> <pi_ip> [wifi_ssid] [wifi_password]"
        echo ""
        echo "If wifi_ssid and wifi_password are not provided, the script will"
        echo "scan for networks on the Pi and prompt for selection and password."
        echo ""
        echo "Example: $0 pi 192.168.1.100"
        echo "Example: $0 pi 192.168.1.100 MyNetwork mypassword"
        exit 1
    fi
    
    # Run the main function with provided arguments (SSID and password are optional)
    configure_wifi "$1" "$2" "${3:-}" "${4:-}"
    exit_code=$?
    cleanup_passwords
    exit $exit_code
fi
