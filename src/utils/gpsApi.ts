/**
 * GPS API utilities for fetching GPS data from backend
 */

const GPS_BACKEND_URL = import.meta.env.VITE_GPS_BACKEND_URL || 'https://sys-admin-my13.onrender.com'

export interface GPSLocation {
  latitude?: number
  lat?: number
  longitude?: number
  lng?: number
  recorded_at?: string
  timestamp?: string
  trip_id?: string
  speed?: number
  heading?: number
}

/**
 * Fetch the latest GPS location from the backend
 */
export async function fetchLatestGPSLocation(): Promise<GPSLocation | null> {
  try {
    const response = await fetch(`${GPS_BACKEND_URL}/api/gps/latest`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    if (!response.ok) {
      console.warn(`GPS API returned status ${response.status}`)
      return null
    }

    const data = await response.json()
    return data
  } catch (error) {
    console.error('Failed to fetch GPS location from backend:', error)
    return null
  }
}

/**
 * Fetch GPS location for a specific trip
 */
export async function fetchTripGPSLocation(tripId: string): Promise<GPSLocation | null> {
  try {
    const response = await fetch(`${GPS_BACKEND_URL}/api/gps/trip/${tripId}`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    if (!response.ok) {
      console.warn(`GPS API returned status ${response.status} for trip ${tripId}`)
      return null
    }

    const data = await response.json()
    return data
  } catch (error) {
    console.error(`Failed to fetch GPS location for trip ${tripId}:`, error)
    return null
  }
}

/**
 * Normalize GPS data to a standard format
 * Handles different field naming conventions (latitude vs lat, longitude vs lng)
 */
export function normalizeGPSData(gpsData: GPSLocation | null): {
  lat: number
  lng: number
  timestamp: string
  tripId?: string
} | null {
  if (!gpsData) return null

  const lat = gpsData.latitude ?? gpsData.lat
  const lng = gpsData.longitude ?? gpsData.lng
  const timestamp = gpsData.recorded_at ?? gpsData.timestamp ?? new Date().toISOString()
  const tripId = gpsData.trip_id

  if (typeof lat !== 'number' || typeof lng !== 'number') {
    console.warn('Invalid GPS data: missing or invalid lat/lng', gpsData)
    return null
  }

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    console.warn('Invalid GPS data: lat/lng not finite', { lat, lng })
    return null
  }

  return {
    lat,
    lng,
    timestamp,
    tripId,
  }
}

/**
 * Calculate distance between two coordinates in kilometers
 */
export function calculateDistance(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const R = 6371 // Earth's radius in kilometers
  const dLat = toRadians(lat2 - lat1)
  const dLng = toRadians(lng2 - lng1)
  
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2)
  
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return R * c
}

function toRadians(degrees: number): number {
  return degrees * (Math.PI / 180)
}
