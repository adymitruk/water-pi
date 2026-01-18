#!/bin/bash

# Change user password on Pi
# This script should be sourced after common.sh

change_password() {
    local pi_user="$1"
    local pi_ip="$2"
    local new_pass="$3"
    
    echo "[Step 2/3] Updating User Password..."
    log_entry "Changing password for user: $pi_user on $pi_ip"
    
    # Try SSH key authentication first
    ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$pi_user@$pi_ip" true >/dev/null 2>&1
    local ssh_key_check=$?
    log_entry "SSH key check result: exit code $ssh_key_check"
    
    if [ $ssh_key_check -eq 0 ]; then
        # SSH keys work - use them (no -t flag needed when piping)
        log_entry "SSH keys available - using key authentication for password change"
        local chpasswd_output
        chpasswd_output=$(printf '%s\n' "$pi_user:$new_pass" | ssh "$pi_user@$pi_ip" "sudo chpasswd" 2>&1)
        local chpasswd_exit=$?
        if [ $chpasswd_exit -ne 0 ]; then
            log_entry "ERROR: Failed to change password for user: $pi_user (exit code: $chpasswd_exit)"
            if [ -n "$chpasswd_output" ]; then
                log_entry "chpasswd error output: $chpasswd_output"
            fi
            return 1
        fi
        if [ -n "$chpasswd_output" ]; then
            log_entry "chpasswd output: $chpasswd_output"
        fi
    else
        # SSH keys don't work - need current password
        log_entry "SSH keys not available - will prompt for current password"
        echo "SSH keys not available. Enter current password:"
        set +o history 2>/dev/null
        read -s -p "Current password for $pi_user@$pi_ip: " CURRENT_PASS
        echo ""
        set -o history 2>/dev/null
        
        if [ -z "$CURRENT_PASS" ]; then
            log_entry "ERROR: Current password required but not provided"
            return 1
        fi
        
        local chpasswd_output
        if command -v sshpass >/dev/null 2>&1; then
            log_entry "Using sshpass for password authentication"
            chpasswd_output=$(printf '%s\n' "$pi_user:$new_pass" | sshpass -p "$CURRENT_PASS" ssh -o StrictHostKeyChecking=no "$pi_user@$pi_ip" "sudo chpasswd" 2>&1)
            local chpasswd_exit=$?
        else
            log_entry "Using interactive SSH for password authentication"
            chpasswd_output=$(printf '%s\n' "$pi_user:$new_pass" | ssh "$pi_user@$pi_ip" "sudo chpasswd" 2>&1)
            local chpasswd_exit=$?
        fi
        unset CURRENT_PASS
        
        if [ $chpasswd_exit -ne 0 ]; then
            log_entry "ERROR: Failed to change password for user: $pi_user (exit code: $chpasswd_exit)"
            if [ -n "$chpasswd_output" ]; then
                log_entry "chpasswd error output: $chpasswd_output"
            fi
            return 1
        fi
        if [ -n "$chpasswd_output" ]; then
            log_entry "chpasswd output: $chpasswd_output"
        fi
    fi
    
    log_entry "Password change command completed for user: $pi_user"
    
    # Verify with sshpass if available
    if command -v sshpass >/dev/null 2>&1; then
        log_entry "Verifying password change with sshpass"
        if sshpass -p "$new_pass" ssh -o StrictHostKeyChecking=no \
           -o PreferredAuthentications=password \
           -o PubkeyAuthentication=no \
           -o ConnectTimeout=5 \
           "$pi_user@$pi_ip" true >/dev/null 2>&1; then
            echo "  [OK] Password verified successfully"
            log_entry "Password verification successful"
            return 0
        else
            echo "  [Warning] Password change succeeded but verification failed"
            log_entry "WARNING: Password verification failed"
            return 1
        fi
    else
        log_entry "sshpass not available - skipping automatic password verification"
    fi
    
    return 0
}

# If script is executed directly (not sourced), show usage or run interactively
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/common.sh"
    
    if [ -z "$LOG_FILE" ]; then
        LOG_DIR="$SCRIPT_DIR/../logs"
        mkdir -p "$LOG_DIR"
        LOG_FILE="$LOG_DIR/change-password-$(date +%Y%m%d-%H%M%S).log"
    fi
    
    trap 'cleanup_passwords; log_entry "Script interrupted by user (CTRL-C)"; exit 130' INT TERM
    
    if [ $# -lt 3 ]; then
        echo "Usage: $0 <pi_user> <pi_ip> <new_password>"
        exit 1
    fi
    
    change_password "$1" "$2" "$3"
    exit_code=$?
    cleanup_passwords
    exit $exit_code
fi
