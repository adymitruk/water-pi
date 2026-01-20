#!/bin/bash
# Wrapper script to run test_sensor continuously and write readings to a single file
# Runs test_sensor with 70ms parameter and updates the output file every 80ms

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENSOR_BINARY="$SCRIPT_DIR/test_sensor"
OUTPUT_FILE="$SCRIPT_DIR/sensor_readings.json"

# Ensure the sensor binary exists and is executable
if [ ! -f "$SENSOR_BINARY" ]; then
    echo "Error: test_sensor binary not found at $SENSOR_BINARY" >&2
    exit 1
fi

if [ ! -x "$SENSOR_BINARY" ]; then
    chmod +x "$SENSOR_BINARY"
fi

# Function to parse test_sensor output and convert to JSON
parse_sensor_output() {
    local output="$1"
    local json_pins="["
    local first=true
    
    # Parse the output lines that contain pin data
    # Format: "  X |         Y.ZZZ | STATUS"
    while IFS= read -r line; do
        # Match lines with pin data (e.g., "  0 |         1.234 | ACTIVE")
        if [[ $line =~ ^[[:space:]]*([0-9]+)[[:space:]]*\|[[:space:]]*([0-9.]+)[[:space:]]*\|[[:space:]]*(ACTIVE|inactive) ]]; then
            local pin="${BASH_REMATCH[1]}"
            local freq="${BASH_REMATCH[2]}"
            local status="${BASH_REMATCH[3]}"
            local active="false"
            
            if [ "$status" = "ACTIVE" ]; then
                active="true"
            fi
            
            if [ "$first" = true ]; then
                first=false
            else
                json_pins+=","
            fi
            
            json_pins+="{\"pin\":$pin,\"frequency\":$freq,\"active\":$active}"
        fi
    done <<< "$output"
    
    json_pins+="]"
    echo "$json_pins"
}

# Write initial empty file
echo '{"pins":[],"timestamp":0}' > "$OUTPUT_FILE"

# Main loop: run test_sensor every 80ms
while true; do
    start_time=$(date +%s%N)
    
    # Run test_sensor with 70ms parameter and capture output
    # Redirect stderr to /dev/null to suppress error messages
    output=$("$SENSOR_BINARY" 70 2>/dev/null)
    exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -n "$output" ]; then
        # Parse the output and create JSON
        pins_json=$(parse_sensor_output "$output")
        
        # Only update if we got valid pin data
        if [ -n "$pins_json" ] && [ "$pins_json" != "[]" ]; then
            # Get timestamp in milliseconds (fallback if %3N not supported)
            if timestamp=$(date +%s%3N 2>/dev/null); then
                : # Success
            else
                # Fallback: use nanoseconds and convert to milliseconds
                timestamp_ns=$(date +%s%N)
                timestamp=$((timestamp_ns / 1000000))
            fi
            
            # Write JSON to file atomically
            {
                echo "{"
                echo "  \"pins\": $pins_json,"
                echo "  \"timestamp\": $timestamp"
                echo "}"
            } > "$OUTPUT_FILE.tmp"
            
            mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
        fi
    fi
    
    # Calculate elapsed time and sleep to maintain 80ms interval
    end_time=$(date +%s%N)
    elapsed_ns=$((end_time - start_time))
    elapsed_ms=$((elapsed_ns / 1000000))
    
    if [ $elapsed_ms -lt 80 ]; then
        sleep_ms=$((80 - elapsed_ms))
        sleep_ns=$((sleep_ms * 1000000))
        sleep "$(awk "BEGIN {printf \"%.6f\", $sleep_ns / 1000000000}")"
    fi
done
