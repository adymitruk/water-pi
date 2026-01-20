const express = require('express');
const path = require('path');
const fs = require('fs').promises;

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());
app.use(express.static(path.join(__dirname)));

// Serve index.html at root
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

// Path to sensor readings JSON file (relative to app.js location)
const READINGS_FILE = path.join(__dirname, '..', 'sensor_readings.json');

// Function to read pin data from the single JSON file
async function getPinData() {
    try {
        // Check if readings file exists
        try {
            await fs.access(READINGS_FILE);
        } catch {
            return []; // Return empty array if file doesn't exist
        }
        
        // Read and parse the JSON file
        const content = await fs.readFile(READINGS_FILE, 'utf8');
        const data = JSON.parse(content);
        
        // Convert the data format to match expected structure
        const pins = (data.pins || []).map(pin => ({
            pin: parseInt(pin.pin, 10),
            frequency: parseFloat(pin.frequency) || 0, // Frequency is already in kHz, ensure it's a number
            active: pin.active === true,
            unixTime: Math.floor(data.timestamp / 1000), // Convert ms to seconds
            timestamp: new Date(data.timestamp).toISOString()
        }));
        
        // Sort pins by pin number
        pins.sort((a, b) => a.pin - b.pin);
        
        return pins;
    } catch (err) {
        console.error('Error reading pin data:', err.message);
        return [];
    }
}

// API endpoint to get all pin data
app.get('/api/pins', async (req, res) => {
    try {
        const pins = await getPinData();
        console.log(`Returning ${pins.length} pins, sample pin 17:`, pins.find(p => p.pin === 17));
        res.json({ pins });
    } catch (error) {
        console.error('Error in /api/pins:', error);
        res.status(500).json({ error: 'Failed to read pin data' });
    }
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Start server - listen on all interfaces (0.0.0.0) to allow network access
app.listen(PORT, '0.0.0.0', () => {
    console.log(`Kiosk server running on http://0.0.0.0:${PORT}`);
    console.log(`Accessible at http://localhost:${PORT} or http://raspberrypi.local:${PORT}`);
    console.log(`Sensor readings file: ${READINGS_FILE}`);
});
