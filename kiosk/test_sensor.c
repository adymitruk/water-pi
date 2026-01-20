/*
 * This program measures and displays GPIO frequencies in real time.
 * It continuously samples all pins in a tight loop, counts transitions,
 * and updates frequencies every 100ms.
 * 
 * Usage:
 *   test_sensor              - Run continuously, update every 100ms
 *   test_sensor <milliseconds> - Run for specified duration, output once and exit
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <termios.h>
#include <fcntl.h>
#include <gpiod.h>

#define NUM_PINS 28
#define UPDATE_INTERVAL_MS 100  // Update frequency every 100ms
#define UPDATE_INTERVAL_NS (UPDATE_INTERVAL_MS * 1000000LL)  // Convert to nanoseconds

// Clear screen and move cursor to top-left
void clear_screen() {
    printf("\033[2J\033[H");
}

// Check if a key has been pressed (non-blocking)
// Note: terminal must already be in non-blocking mode
int kbhit(void) {
    int ch = getchar();
    if (ch != EOF) {
        return 1;
    }
    return 0;
}

int main(int argc, char *argv[]) {
    // Parse command line argument for duration
    int duration_ms = -1;  // -1 means run continuously
    if (argc > 1) {
        duration_ms = atoi(argv[1]);
        if (duration_ms <= 0) {
            fprintf(stderr, "Invalid duration: %s. Must be a positive number of milliseconds.\n", argv[1]);
            return 1;
        }
    }
    // Open GPIO chip (Pi 5: gpiochip4 is symlink to gpiochip0, which has 54 lines)
    struct gpiod_chip *chip = gpiod_chip_open("/dev/gpiochip0");
    if (!chip) {
        fprintf(stderr, "Failed to open /dev/gpiochip0 (try running with sudo)\n");
        return 1;
    }
    
    // Prepare line offsets array
    unsigned int offsets[NUM_PINS];
    for (int i = 0; i < NUM_PINS; i++) {
        offsets[i] = i;
    }
    
    // Create request and line configs for libgpiod v2
    struct gpiod_request_config *req_cfg = gpiod_request_config_new();
    if (!req_cfg) {
        fprintf(stderr, "Failed to create request config\n");
        gpiod_chip_close(chip);
        return 1;
    }
    gpiod_request_config_set_consumer(req_cfg, "test_sensor");
    
    struct gpiod_line_config *line_cfg = gpiod_line_config_new();
    if (!line_cfg) {
        fprintf(stderr, "Failed to create line config\n");
        gpiod_request_config_free(req_cfg);
        gpiod_chip_close(chip);
        return 1;
    }
    
    // Create line settings for input
    struct gpiod_line_settings *settings = gpiod_line_settings_new();
    if (!settings) {
        fprintf(stderr, "Failed to create line settings\n");
        gpiod_line_config_free(line_cfg);
        gpiod_request_config_free(req_cfg);
        gpiod_chip_close(chip);
        return 1;
    }
    gpiod_line_settings_set_direction(settings, GPIOD_LINE_DIRECTION_INPUT);
    
    // Add all line offsets with the same input settings
    gpiod_line_config_add_line_settings(line_cfg, offsets, NUM_PINS, settings);
    
    // Free settings (they're copied into line_cfg)
    gpiod_line_settings_free(settings);
    
    // Request all lines
    struct gpiod_line_request *request = gpiod_chip_request_lines(chip, req_cfg, line_cfg);
    if (!request) {
        fprintf(stderr, "Failed to request lines (may need sudo)\n");
        gpiod_line_config_free(line_cfg);
        gpiod_request_config_free(req_cfg);
        gpiod_chip_close(chip);
        return 1;
    }
    
    // Arrays to track pin states and flip counts
    int previous_value[NUM_PINS];
    unsigned long long flip_count[NUM_PINS];
    
    // Initialize arrays
    for (int i = 0; i < NUM_PINS; i++) {
        previous_value[i] = -1;  // -1 means uninitialized
        flip_count[i] = 0;
    }
    
    // Get initial time
    struct timespec start_time, current_time;
    clock_gettime(CLOCK_MONOTONIC, &start_time);
    long long start_nanos = start_time.tv_sec * 1000000000LL + start_time.tv_nsec;
    long long next_update_nanos = start_nanos + UPDATE_INTERVAL_NS;
    long long end_nanos = -1;
    if (duration_ms > 0) {
        end_nanos = start_nanos + (duration_ms * 1000000LL);
    }
    
    // Set terminal to non-canonical mode for key detection (only if running continuously)
    struct termios old_termios, new_termios;
    int old_flags;
    int terminal_configured = 0;
    
    if (duration_ms < 0) {
        // Continuous mode: configure terminal for key detection
        tcgetattr(STDIN_FILENO, &old_termios);
        new_termios = old_termios;
        new_termios.c_lflag &= ~(ICANON | ECHO);
        tcsetattr(STDIN_FILENO, TCSANOW, &new_termios);
        old_flags = fcntl(STDIN_FILENO, F_GETFL, 0);
        fcntl(STDIN_FILENO, F_SETFL, old_flags | O_NONBLOCK);
        terminal_configured = 1;
        
        clear_screen();
        printf("GPIO Frequency Monitor - Real Time\n");
        printf("Press Ctrl+C or any key to exit\n");
        printf("===================================\n");
        printf("Pin | Frequency (kHz) | Status\n");
        printf("----|-----------------|--------\n");
        fflush(stdout);
    } else {
        // Duration mode: just print header
        printf("GPIO Frequency Monitor - Measuring for %d ms\n", duration_ms);
        printf("============================================\n");
        printf("Pin | Frequency (kHz) | Status\n");
        printf("----|-----------------|--------\n");
        fflush(stdout);
    }
    
    // Main loop: continuously read all pins as fast as possible
    while (1) {
        // Check if duration has elapsed (for duration mode)
        if (duration_ms > 0) {
            clock_gettime(CLOCK_MONOTONIC, &current_time);
            long long current_nanos = current_time.tv_sec * 1000000000LL + current_time.tv_nsec;
            if (current_nanos >= end_nanos) {
                // Duration elapsed, output frequencies and exit
                double measurement_seconds = duration_ms / 1000.0;
                
                printf("\n");
                for (int i = 0; i < NUM_PINS; i++) {
                    // Calculate frequency: flips per second, then convert to kHz
                    double frequency_hz = (double)flip_count[i] / measurement_seconds;
                    double frequency_khz = frequency_hz / 1000.0;  // Convert to kHz
                    
                    // If no flips, report 0Hz (0kHz)
                    if (flip_count[i] == 0) {
                        frequency_khz = 0.0;
                    }
                    
                    int active = (frequency_khz > 0.0001) ? 1 : 0;  // 0.0001 kHz = 0.1 Hz
                    
                    printf("%3d | %14.3f | %s\n", i, frequency_khz, active ? "ACTIVE" : "inactive");
                }
                
                // Cleanup and exit
                gpiod_line_request_release(request);
                gpiod_line_config_free(line_cfg);
                gpiod_request_config_free(req_cfg);
                gpiod_chip_close(chip);
                return 0;
            }
        }
        
        // Check for key press (non-blocking) - only in continuous mode
        if (terminal_configured && kbhit()) {
            // Cleanup GPIO lines
            gpiod_line_request_release(request);
            gpiod_line_config_free(line_cfg);
            gpiod_request_config_free(req_cfg);
            gpiod_chip_close(chip);
            
            // Restore terminal settings
            tcsetattr(STDIN_FILENO, TCSANOW, &old_termios);
            fcntl(STDIN_FILENO, F_SETFL, old_flags);
            clear_screen();
            printf("Exiting...\n");
            return 0;
        }
        // Read all pins once (as fast as possible)
        for (int i = 0; i < NUM_PINS; i++) {
            enum gpiod_line_value val = gpiod_line_request_get_value(request, offsets[i]);
            int current_value = (val == GPIOD_LINE_VALUE_ACTIVE) ? 1 : 0;
            
            // Count flips (any transition: 0->1 or 1->0)
            if (previous_value[i] != -1 && previous_value[i] != current_value) {
                flip_count[i]++;
            }
            
            previous_value[i] = current_value;
        }
        
        // Check if 100ms has passed (only update display in continuous mode)
        if (duration_ms < 0) {
            clock_gettime(CLOCK_MONOTONIC, &current_time);
            long long current_nanos = current_time.tv_sec * 1000000000LL + current_time.tv_nsec;
            
            if (current_nanos >= next_update_nanos) {
                // Move cursor to beginning of table data (line 5, after header on line 4)
                printf("\033[5;1H");  // Move to line 5, column 1 (start of data rows)
                
                double measurement_seconds = UPDATE_INTERVAL_MS / 1000.0;
                
                for (int i = 0; i < NUM_PINS; i++) {
                    // Calculate frequency: flips per second, then convert to kHz
                    // Each flip is a transition, so frequency = flips / time
                    double frequency_hz = (double)flip_count[i] / measurement_seconds;
                    double frequency_khz = frequency_hz / 1000.0;  // Convert to kHz
                    
                    // If no flips, report 0Hz (0kHz)
                    if (flip_count[i] == 0) {
                        frequency_khz = 0.0;
                    }
                    
                    int active = (frequency_khz > 0.0001) ? 1 : 0;  // 0.0001 kHz = 0.1 Hz
                    
                    // Overwrite the line
                    printf("\033[K");  // Clear to end of line
                    printf("%3d | %14.3f | %s\n", i, frequency_khz, active ? "ACTIVE" : "inactive");
                    
                    // Reset flip count for next measurement period
                    flip_count[i] = 0;
                }
                
                // Update status line
                printf("\033[K");  // Clear to end of line
                printf("[Updating every %dms, sampling continuously] - Press Ctrl+C to exit\n", UPDATE_INTERVAL_MS);
                fflush(stdout);
                
                // Set next update time
                next_update_nanos = current_nanos + UPDATE_INTERVAL_NS;
            }
        }
    }
    
    // Cleanup: release lines and close chip
    gpiod_line_request_release(request);
    gpiod_line_config_free(line_cfg);
    gpiod_request_config_free(req_cfg);
    gpiod_chip_close(chip);
    
    // Restore terminal settings (shouldn't reach here, but just in case)
    if (terminal_configured) {
        tcsetattr(STDIN_FILENO, TCSANOW, &old_termios);
        fcntl(STDIN_FILENO, F_SETFL, old_flags);
    }
    return 0;
}