# GPS Integration Guide

This document explains how the GPS integration works in the CommutAI Public Dashboard.

## Backend Configuration

The application fetches GPS data from the backend URL configured in your environment variables:

```env
VITE_GPS_BACKEND_URL=https://sys-admin-my13.onrender.com
```

## API Endpoints

### Get Latest GPS Location

**Endpoint:** `GET /api/gps/latest`

**Response Format:**
```json
{
  "latitude": 8.366308873785245,
  "longitude": 124.86500795847,
  "recorded_at": "2024-11-10T12:30:00Z",
  "trip_id": "trip-123",
  "speed": 45.5,
  "heading": 180
}
```

Or alternative format:
```json
{
  "lat": 8.366308873785245,
  "lng": 124.86500795847,
  "timestamp": "2024-11-10T12:30:00Z",
  "trip_id": "trip-123"
}
```

### Get GPS Location for Specific Trip

**Endpoint:** `GET /api/gps/trip/{tripId}`

**Response Format:** Same as above

## How It Works

### 1. Data Flow

1. **Primary Source:** The dashboard fetches GPS data from `https://sys-admin-my13.onrender.com/api/gps/latest`
2. **Fallback Sources:** If the backend is unavailable, the app falls back to:
   - Supabase `gps_locations` table
   - Supabase `trips` table (for in-progress trips)

### 2. Real-time Updates

The application updates GPS data through multiple mechanisms:

- **Polling:** Fetches new GPS data every 10 seconds from the backend
- **Real-time Subscriptions:** Listens to Supabase database changes as backup
- **Automatic Retry:** If one source fails, automatically tries fallback sources

### 3. GPS Processing

The `gpsApi.ts` utility module handles:

- **Data Normalization:** Converts different GPS data formats into a standard format
- **Validation:** Ensures latitude/longitude values are valid numbers
- **Distance Calculation:** Calculates distances between coordinates using the Haversine formula

## Features

### Bus Location Tracking

- Displays real-time bus position on the map
- Shows GPS connection status (connecting/active/error)
- Updates every 10 seconds

### Stop Proximity Detection

- Detects when the bus is near a stop (within ~1km)
- Updates the "Current Location" status
- Highlights nearby stops on the map

### Estimated Arrival Time

- Calculates time to next stop based on:
  - Current distance to stop
  - Average speed (40 km/h assumed)
- Updates dynamically as bus moves

### GPS Status Indicators

- **Green pulse dot:** GPS is active and receiving data
- **Amber dot:** Connecting to GPS
- **Red dot:** GPS error or no data available

## Configuration

### Environment Variables

Add to your `.env` file:

```env
VITE_GPS_BACKEND_URL=https://sys-admin-my13.onrender.com
VITE_SUPABASE_URL=your_supabase_project_url
VITE_SUPABASE_ANON_KEY=your_supabase_anon_key
```

### Backend Requirements

Your backend server should:

1. Expose a `/api/gps/latest` endpoint
2. Return JSON with GPS coordinates
3. Include either:
   - `latitude` and `longitude` fields, OR
   - `lat` and `lng` fields
4. Optionally include `timestamp` or `recorded_at` field
5. Support CORS for browser requests

## Troubleshooting

### GPS Not Showing

1. **Check backend URL:**
   - Verify `VITE_GPS_BACKEND_URL` in `.env`
   - Test the endpoint: `curl https://sys-admin-my13.onrender.com/api/gps/latest`

2. **Check browser console:**
   - Open Developer Tools → Console
   - Look for GPS-related errors or warnings

3. **Verify data format:**
   - Ensure backend returns valid JSON
   - Check that lat/lng fields are present

### GPS Shows "Error"

- Backend is not responding
- Invalid data format from backend
- Network connectivity issues

### GPS Shows "Connecting..."

- Initial connection to backend in progress
- Should resolve within a few seconds
- If persists, check backend availability

### GPS Shows "Schedule coming soon"

- No GPS data available from any source
- Backend and Supabase both have no data
- Normal state when no trips are active

## API Integration Example

### Testing the GPS Endpoint

```bash
# Test backend GPS endpoint
curl https://sys-admin-my13.onrender.com/api/gps/latest

# Expected response:
{
  "latitude": 8.366308873785245,
  "longitude": 124.86500795847,
  "recorded_at": "2024-11-10T12:30:00Z"
}
```

### Sample Backend Implementation (Node.js/Express)

```javascript
app.get('/api/gps/latest', async (req, res) => {
  try {
    // Fetch latest GPS from your data source
    const gpsData = await getLatestGPS()
    
    res.json({
      latitude: gpsData.lat,
      longitude: gpsData.lng,
      recorded_at: gpsData.timestamp,
      trip_id: gpsData.tripId
    })
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch GPS data' })
  }
})
```

## File Structure

```
src/
├── App.tsx                    # Main app with GPS integration
├── utils/
│   ├── gpsApi.ts             # GPS API utilities
│   └── smsQueue.ts           # SMS utilities
└── ...

.env                           # Environment configuration
GPS-INTEGRATION.md            # This file
```

## Utility Functions

### `fetchLatestGPSLocation()`

Fetches the latest GPS location from the backend.

```typescript
import { fetchLatestGPSLocation } from './utils/gpsApi'

const gpsData = await fetchLatestGPSLocation()
if (gpsData) {
  console.log(`Bus at: ${gpsData.latitude}, ${gpsData.longitude}`)
}
```

### `normalizeGPSData()`

Normalizes GPS data to a standard format.

```typescript
import { normalizeGPSData } from './utils/gpsApi'

const normalized = normalizeGPSData(rawGpsData)
if (normalized) {
  const { lat, lng, timestamp } = normalized
}
```

### `calculateDistance()`

Calculates distance between two coordinates in kilometers.

```typescript
import { calculateDistance } from './utils/gpsApi'

const distanceKm = calculateDistance(lat1, lng1, lat2, lng2)
console.log(`Distance: ${distanceKm} km`)
```

## Next Steps

1. **Ensure your backend is running** at `https://sys-admin-my13.onrender.com`
2. **Implement the `/api/gps/latest` endpoint** if not already done
3. **Test the integration** by opening the dashboard and checking the Live Map section
4. **Monitor the console** for any GPS-related errors

## Support

For issues or questions:
- Check the browser console for error messages
- Verify backend is responding: `curl https://sys-admin-my13.onrender.com/api/gps/latest`
- Ensure environment variables are set correctly
- Check that GPS data format matches expected structure
