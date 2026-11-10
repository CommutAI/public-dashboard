# Quick Start: GPS Integration

## ✅ What's Done

Your dashboard is now configured to fetch GPS data from:
```
https://sys-admin-my13.onrender.com/api/gps/latest
```

## 🚀 Getting Started

### Step 1: Test Your Backend

Open a terminal and run:
```bash
curl https://sys-admin-my13.onrender.com/api/gps/latest
```

**Expected Response:**
```json
{
  "latitude": 8.366308873785245,
  "longitude": 124.86500795847,
  "recorded_at": "2024-11-10T12:30:00Z"
}
```

Or:
```json
{
  "lat": 8.366308873785245,
  "lng": 124.86500795847,
  "timestamp": "2024-11-10T12:30:00Z"
}
```

### Step 2: Run the Dashboard

```bash
# Install dependencies (if not already done)
npm install

# Start development server
npm run dev
```

### Step 3: View in Browser

1. Open http://localhost:5173
2. Navigate to the "Live Map" section
3. You should see:
   - 🟢 Green pulsing dot = GPS active
   - 🟡 Amber dot = Connecting
   - 🔴 Red dot = Error

### Step 4: Check Console

Open Browser DevTools (F12) → Console

Look for:
```
GPS fetch result from backend: {...}
Bus coordinates set: [8.366..., 124.865...]
```

## 📋 Backend Implementation Checklist

If your backend doesn't have the endpoint yet, implement it:

### Node.js/Express Example

```javascript
const express = require('express')
const cors = require('cors')
const app = express()

// Enable CORS
app.use(cors())

// GPS endpoint
app.get('/api/gps/latest', async (req, res) => {
  try {
    // Replace with your actual GPS data source
    const gpsData = {
      latitude: 8.366308873785245,  // From your GPS device
      longitude: 124.86500795847,   // From your GPS device
      recorded_at: new Date().toISOString(),
      trip_id: 'current-trip-id'
    }
    
    res.json(gpsData)
  } catch (error) {
    console.error('GPS error:', error)
    res.status(500).json({ error: 'Failed to fetch GPS' })
  }
})

app.listen(3000, () => {
  console.log('GPS backend running on port 3000')
})
```

### Python/Flask Example

```python
from flask import Flask, jsonify
from flask_cors import CORS
from datetime import datetime

app = Flask(__name__)
CORS(app)

@app.route('/api/gps/latest')
def get_gps():
    try:
        # Replace with your actual GPS data source
        gps_data = {
            'latitude': 8.366308873785245,
            'longitude': 124.86500795847,
            'recorded_at': datetime.utcnow().isoformat() + 'Z',
            'trip_id': 'current-trip-id'
        }
        return jsonify(gps_data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(port=3000)
```

## 🔍 How to Verify GPS is Working

### In the Dashboard

1. **Live Map Section**
   - Bus marker appears on map
   - Marker moves as GPS updates

2. **Arrival Board**
   - Shows "Current Location"
   - Displays estimated arrival time
   - GPS status shows green dot

3. **Browser Console**
   - No errors
   - Shows GPS coordinates being received

## 🐛 Troubleshooting

### GPS shows "Connecting..." for more than 10 seconds

**Cause:** Backend not responding

**Fix:**
```bash
# Check if backend is accessible
curl https://sys-admin-my13.onrender.com/api/gps/latest

# Check your backend logs
# Verify the server is running
```

### GPS shows "Error"

**Cause:** Invalid data format or backend error

**Fix:**
1. Check backend returns valid JSON
2. Verify lat/lng fields exist
3. Check CORS is enabled
4. Look at browser console for details

### GPS shows "Schedule coming soon"

**Cause:** No GPS data available from any source

**Fix:** This is normal when:
- No trips are currently active
- GPS device hasn't sent data yet
- This is the first load

### Bus marker doesn't appear on map

**Cause:** GPS coordinates invalid or missing

**Fix:**
1. Verify backend returns valid numbers for lat/lng
2. Check coordinates are in valid range:
   - Latitude: -90 to 90
   - Longitude: -180 to 180
3. Check browser console for errors

## 📊 Data Flow Diagram

```
GPS Device → Backend (sys-admin-my13.onrender.com)
                    ↓
              /api/gps/latest
                    ↓
    Dashboard fetches every 10 seconds
                    ↓
         Updates map with bus location
                    ↓
      Calculates nearest stop & arrival time
```

## 🔄 Update Frequency

- **Backend Polling:** Every 10 seconds
- **Supabase Real-time:** Instant (fallback)
- **Map Updates:** Immediate when data received

## 📁 Configuration Files

```
.env                          # Contains backend URL
src/utils/gpsApi.ts          # GPS utility functions
src/App.tsx                  # Main GPS integration logic
```

## 🎯 What Happens Next

1. **Every 10 seconds**, dashboard calls your backend
2. **Backend returns** latest GPS coordinates
3. **Dashboard displays** bus on map
4. **Calculates** nearest stop and arrival time
5. **Updates** all GPS-related UI elements

## ✨ Features Now Available

- ✅ Real-time bus tracking on map
- ✅ GPS status indicator
- ✅ Estimated arrival times
- ✅ Current location display
- ✅ Stop proximity detection
- ✅ Automatic fallback to Supabase
- ✅ Error handling and retry logic

## 📞 Need Help?

Check these files for more details:
- `GPS-INTEGRATION.md` - Complete integration guide
- `CHANGES-GPS-INTEGRATION.md` - Summary of changes
- Browser DevTools Console - Real-time debugging

## 🎉 You're All Set!

Your dashboard is ready to display GPS data from your backend. Just make sure:
1. ✅ Backend is running
2. ✅ `/api/gps/latest` endpoint works
3. ✅ Returns valid GPS coordinates
4. ✅ CORS is configured

**Test it now:** `npm run dev`
