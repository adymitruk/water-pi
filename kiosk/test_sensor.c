/*
 * This program tests the sensor by reading the value from the sensor and printing it to the console.
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <wiringPi.h>

// array of pin numbers with a signal greater than 10 Hz
int pins[] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];

int main(void) {
    /// find all the gpio pins that have a greater that 10 Hz signal
    for (int i = 0; i < 28; i++) {
        int value = digitalRead(i);
        if (value > 10) {
            printf("Pin %d has a signal greater than 10 Hz\n", i);
        }
    }



    return 0;
}

int digitalRead(int pin) {
    // read the pin from the gpio pin
    int value = digitalRead(pin);
    return value;
    return 0;
}