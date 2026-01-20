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

// Path to pin readings directory (relative to sensors.sh location)
const READINGS_DIR = path.join(__dirname, '..', 'pin_readings');

// Function to read all pin data from files
async function getPinData() {
    const pins = [];
    
    try {
        // Check if readings directory exists
        try {
            await fs.access(READINGS_DIR);
        } catch {
            return pins; // Return empty array if directory doesn't exist
        }
        
        // Read all pin directories
        const pinDirs = await fs.readdir(READINGS_DIR);
        
        for (const pinDir of pinDirs) {
            const pinPath = path.join(READINGS_DIR, pinDir);
            const stat = await fs.stat(pinPath);
            
            if (!stat.isDirectory()) {
                continue;
            }
            
            const pinNumber = parseInt(pinDir, 10);
            if (isNaN(pinNumber)) {
                continue;
            }
            
            // Find the most recent reading file
            try {
                const readingFiles = await fs.readdir(pinPath);
                const readingFilesWithTime = readingFiles
                    .filter(f => f.startsWith('reading_'))
                    .map(f => {
                        const match = f.match(/reading_(\d+)/);
                        return match ? { file: f, time: parseInt(match[1], 10) } : null;
                    })
                    .filter(f => f !== null)
                    .sort((a, b) => b.time - a.time);
                
                if (readingFilesWithTime.length === 0) {
                    continue;
                }
                
                // Read the most recent reading file
                const latestReading = readingFilesWithTime[0];
                const readingPath = path.join(pinPath, latestReading.file);
                const content = await fs.readFile(readingPath, 'utf8');
                
                // Parse the reading file
                const reading = {
                    pin: pinNumber,
                    unixTime: latestReading.time,
                    frequency: 0,
                    timestamp: '',
                    measurementTime: ''
                };
                
                // Parse file content
                const lines = content.split('\n');
                for (const line of lines) {
                    if (line.startsWith('Frequency:')) {
                        const match = line.match(/Frequency:\s*([\d.]+)\s*Hz/);
                        if (match) {
                            reading.frequency = parseFloat(match[1]);
                        }
                    } else if (line.startsWith('Timestamp:')) {
                        reading.timestamp = line.replace('Timestamp:', '').trim();
                    } else if (line.startsWith('Measurement time:')) {
                        const match = line.match(/Measurement time:\s*([\d.]+)ms/);
                        if (match) {
                            reading.measurementTime = match[1];
                        }
                    }
                }
                
                pins.push(reading);
            } catch (err) {
                console.error(`Error reading pin ${pinNumber}:`, err.message);
            }
        }
        
        // Sort pins by pin number
        pins.sort((a, b) => a.pin - b.pin);
        
    } catch (err) {
        console.error('Error reading pin data:', err.message);
    }
    
    return pins;
}

// API endpoint to get all pin data
app.get('/api/pins', async (req, res) => {
    try {
        const pins = await getPinData();
        res.json({ pins });
    } catch (error) {
        console.error('Error in /api/pins:', error);
        res.status(500).json({ error: 'Failed to read pin data' });
    }
});

// Webhook endpoint for sensors script to call after updating readings
app.post('/webhook/update', (req, res) => {
    // This endpoint can be called by the sensors script
    // Currently just acknowledges, but could be extended for real-time updates
    res.json({ 
        status: 'ok', 
        message: 'Webhook received',
        timestamp: new Date().toISOString()
    });
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Start server - listen on all interfaces (0.0.0.0) to allow network access
app.listen(PORT, '0.0.0.0', () => {
    console.log(`Kiosk server running on http://0.0.0.0:${PORT}`);
    console.log(`Accessible at http://localhost:${PORT} or http://raspberrypi.local:${PORT}`);
    console.log(`Pin readings directory: ${READINGS_DIR}`);
});
