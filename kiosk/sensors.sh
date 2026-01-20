#!/bin/bash
## find gpio pins that have a khz signal

## read each pin one by one and detect if it's toggling (kHz signal)

# Configuration constants
PIN_START=0
PIN_END=27
INITIAL_DETECTION_SAMPLES=10
INITIAL_DETECTION_SAMPLE_DELAY_SECONDS=0.0001
FREQUENCY_MEASUREMENT_TIME_SECONDS=0.1
FREQUENCY_MEASUREMENT_TIME_NANOSECONDS=100000000
FREQUENCY_SAMPLE_DELAY_MICROSECONDS=5
FREQUENCY_SAMPLE_DELAY_FALLBACK_SECONDS=0.000005
GPIO_CHIP="gpiochip0"
FREQUENCY_DECIMAL_PLACES=2
WEBHOOK_URL="${WEBHOOK_URL:-http://localhost:3000/webhook/update}"

# Create directory for pin readings
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READINGS_DIR="$SCRIPT_DIR/pin_readings"
mkdir -p "$READINGS_DIR"

# Function to measure frequency over configured time period
measure_frequency() {
    local pin=$1
    local start_nanos=$(date +%s%N)
    local target_nanos=$((start_nanos + FREQUENCY_MEASUREMENT_TIME_NANOSECONDS))
    local samples=()
    local previous_value=""
    local rising_edges=0
    
    # Sample the pin rapidly over the measurement period
    while true; do
        local current_nanos=$(date +%s%N)
        if [ "$current_nanos" -ge "$target_nanos" ]; then
            break
        fi
        
        output=$(gpioget -c "$GPIO_CHIP" "$pin" 2>/dev/null)
        if [ $? -eq 0 ]; then
            # Parse output to get 0 or 1
            local value=""
            if echo "$output" | grep -q "=active"; then
                value="1"
            elif echo "$output" | grep -q "=inactive"; then
                value="0"
            else
                # Try to extract numeric value
                value=$(echo "$output" | grep -oE '[01]' | head -1)
            fi
            
            if [ -n "$value" ]; then
                samples+=("$value")
                
                # Count rising edges (0 -> 1 transitions)
                if [ -n "$previous_value" ] && [ "$previous_value" = "0" ] && [ "$value" = "1" ]; then
                    rising_edges=$((rising_edges + 1))
                fi
                previous_value="$value"
            fi
        fi
        
        # Small delay to allow multiple samples
        # Use usleep if available, otherwise try sleep with minimal delay
        usleep "$FREQUENCY_SAMPLE_DELAY_MICROSECONDS" 2>/dev/null || sleep "$FREQUENCY_SAMPLE_DELAY_FALLBACK_SECONDS" 2>/dev/null || true
    done
    
    # Calculate frequency: rising edges per second
    local frequency=$(awk "BEGIN {printf \"%.${FREQUENCY_DECIMAL_PLACES}f\", $rising_edges / $FREQUENCY_MEASUREMENT_TIME_SECONDS}")
    
    echo "$frequency"
}

# Function to call webhook (non-blocking, doesn't fail script if webhook is unavailable)
call_webhook() {
    local pin="${1:-}"
    if [ -n "$pin" ]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"pin\": $pin, \"timestamp\": $(date +%s)}" \
            >/dev/null 2>&1 || true
    else
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"timestamp\": $(date +%s)}" \
            >/dev/null 2>&1 || true
    fi
}

active_pins=()

for pin in $(seq "$PIN_START" "$PIN_END"); do
    echo "Reading pin $pin"
    
    # Try to read the GPIO pin using gpioget
    # Use configured GPIO chip and the pin number as the line offset
    # Sample multiple times to detect kHz signals (toggling)
    samples=()
    for i in $(seq 1 "$INITIAL_DETECTION_SAMPLES"); do
        output=$(gpioget -c "$GPIO_CHIP" "$pin" 2>/dev/null)
        if [ $? -eq 0 ]; then
            # Parse output: "0"=active or "0"=inactive
            if echo "$output" | grep -q "=active"; then
                samples+=("1")
            elif echo "$output" | grep -q "=inactive"; then
                samples+=("0")
            else
                samples+=("$output")
            fi
        else
            # If we can't read the pin, skip it
            break
        fi
        # Small delay between samples
        sleep "$INITIAL_DETECTION_SAMPLE_DELAY_SECONDS" 2>/dev/null 
    done
    
    # Check if we got valid samples
    if [ ${#samples[@]} -eq 0 ]; then
        echo "  Pin $pin: Not accessible or error reading"
        continue
    fi
    
    # Check if pin is toggling (has a kHz signal)
    # Compare first and last samples, and check for variation
    first_value="${samples[0]}"
    last_value="${samples[-1]}"
    has_variation=false
    
    # Check if any sample differs from the first
    for sample in "${samples[@]}"; do
        if [ "$sample" != "$first_value" ]; then
            has_variation=true
            break
        fi
    done
    
    # If pin is toggling or showing variation, it's likely active
    if [ "$has_variation" = true ] || [ "$first_value" != "$last_value" ]; then
        echo "  Pin $pin: ACTIVE (detected signal variation)"
        active_pins+=("$pin")
        
        # Measure frequency over configured time period
        measurement_time_ms=$(awk "BEGIN {printf \"%.1f\", $FREQUENCY_MEASUREMENT_TIME_SECONDS * 1000}")
        echo "  Measuring frequency over ${measurement_time_ms}ms..."
        frequency=$(measure_frequency "$pin")
        echo "  Frequency: ${frequency} Hz"
        
        # Create directory matching the pin number
        pin_dir="$READINGS_DIR/$pin"
        mkdir -p "$pin_dir"
        
        # Save frequency reading to file named reading_<unix_time>
        unix_time=$(date +%s)
        reading_file="$pin_dir/reading_${unix_time}"
        {
            echo "Pin: $pin"
            echo "Frequency: ${frequency} Hz"
            echo "Measurement time: ${measurement_time_ms}ms"
            echo "Unix timestamp: $unix_time"
            echo "Timestamp: $(date -Iseconds)"
        } > "$reading_file"
        echo "  Reading saved to: $reading_file"
        
        # Call webhook to notify that a new reading is available
        call_webhook "$pin"
    else
        echo "  Pin $pin: Inactive (value: $first_value)"
    fi
done

echo ""
echo "Active pins: ${active_pins[@]}"

# Call webhook one final time to indicate all readings are complete
call_webhook
