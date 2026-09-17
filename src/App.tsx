import { useState, useEffect } from 'react'
import { MapContainer, TileLayer, Marker, Popup, Polyline, useMap } from 'react-leaflet'
import L from 'leaflet'
import { Menu, Clock, X, Map, CreditCard, Ticket, Shield, Mail, Phone, MapPin, Lock, FileText, LogIn } from 'lucide-react'
import { supabase } from '@commutai/supabase'
import 'leaflet/dist/leaflet.css'

// Fix for default marker icons in Leaflet
delete (L.Icon.Default.prototype as any)._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon-2x.png',
  iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png',
})

// Custom marker icons for different stop types
const createCustomIcon = (color: string, size: number = 16) => {
  return L.divIcon({
    className: 'custom-marker',
    html: `<div style="background-color: ${color}; width: ${size}px; height: ${size}px; border-radius: 50%; border: 2px solid white; box-shadow: 0 2px 4px rgba(0,0,0,0.3);"></div>`,
    iconSize: [size, size],
    iconAnchor: [size/2, size/2],
    popupAnchor: [0, -size/2]
  })
}

const startIcon = createCustomIcon('#22c55e') // Green for start
const endIcon = createCustomIcon('#ef4444') // Red for end
const activeIcon = createCustomIcon('#f59e0b') // Amber for active stops
const nearIcon = createCustomIcon('#3b82f6') // Blue for stops near bus

// Hardcoded bus stops data (using directly instead of fetching from OSM)
const busStopsData: Array<{ stop: string; location: string; status: string; coordinates: [number, number] }> = [
  { stop: 'STOP 01', location: 'Manolo Fortich Terminal', status: 'START', coordinates: [8.366308873785245, 124.86500795847] },
  { stop: 'STOP 02', location: 'Gaisano CDO', status: 'ACTIVE', coordinates: [8.4867, 124.6500] },
  { stop: 'STOP 03', location: 'Gusa', status: 'ACTIVE', coordinates: [8.4757, 124.6823] },
  { stop: 'STOP 04', location: 'Tablon Baloi', status: 'ACTIVE', coordinates: [8.4819, 124.7286] },
  { stop: 'STOP 05', location: 'Tablon', status: 'ACTIVE', coordinates: [8.4819, 124.7286] },
  { stop: 'STOP 06', location: 'Agusan', status: 'ACTIVE', coordinates: [8.4886, 124.7382] },
  { stop: 'STOP 07', location: 'Puerto', status: 'ACTIVE', coordinates: [8.5010, 124.7505] },
  { stop: 'STOP 08', location: 'Bae Upper Puerto', status: 'ACTIVE', coordinates: [8.4264, 124.8092] },
  // Stops 9-11 (Mambatangan, Balubal, Maitum) excluded as they are outside the route
  { stop: 'STOP 09', location: 'Alae', status: 'ACTIVE', coordinates: [8.4244, 124.8128] },
  { stop: 'STOP 10', location: 'Lunocan', status: 'ACTIVE', coordinates: [8.4143, 124.8231] },
  // Cawayanon excluded as it is outside the route
  { stop: 'STOP 11', location: 'San Miguel', status: 'ACTIVE', coordinates: [8.3890, 124.8332] },
  { stop: 'STOP 12', location: 'Dicklum', status: 'ACTIVE', coordinates: [8.3740, 124.8480] },
  { stop: 'STOP 13', location: 'Tankulan', status: 'ACTIVE', coordinates: [8.3688, 124.8641] },
  // Sankanan and Kalugmanan excluded as they are not on the main route
  { stop: 'STOP 14', location: 'Agora Terminal', status: 'END', coordinates: [8.489074818449854, 124.65762898250219] }
]

// Custom terminal icons
const manoloFortichIcon = L.divIcon({
  className: 'terminal-marker',
  html: `<div style="background-color: #22c55e; width: 24px; height: 24px; border-radius: 50%; border: 3px solid white; box-shadow: 0 2px 8px rgba(34,197,94,0.6); display: flex; align-items: center; justify-content: center; font-weight: bold; font-size: 12px; color: white;">M</div>`,
  iconSize: [24, 24],
  iconAnchor: [12, 12],
  popupAnchor: [0, -12]
})

const agoraIcon = L.divIcon({
  className: 'terminal-marker',
  html: `<div style="background-color: #ef4444; width: 24px; height: 24px; border-radius: 50%; border: 3px solid white; box-shadow: 0 2px 8px rgba(239,68,68,0.6); display: flex; align-items: center; justify-content: center; font-weight: bold; font-size: 12px; color: white;">A</div>`,
  iconSize: [24, 24],
  iconAnchor: [12, 12],
  popupAnchor: [0, -12]
})
const createBusIcon = (location?: string) => {
  const locationText = location || 'Bus Location';
  return L.divIcon({
    className: 'bus-marker',
    html: `
      <div style="display: flex; flex-direction: column; align-items: center;">
        <div style="background-color: rgba(0,0,0,0.8); color: white; padding: 4px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; white-space: nowrap; margin-bottom: 4px; border: 1px solid rgba(255,255,255,0.2);">
          ${locationText}
        </div>
        <div style="background-color: #22c55e; width: 20px; height: 20px; border-radius: 50%; border: 3px solid white; box-shadow: 0 2px 8px rgba(34,197,94,0.6); animation: busPulse 1.5s infinite;"></div>
      </div>
    `,
    iconSize: [80, 40],
    iconAnchor: [40, 20],
    popupAnchor: [0, -20]
  })
}

// Hide Leaflet attribution and logo (only once)
if (!document.getElementById('leaflet-style-override')) {
  const style = document.createElement('style')
  style.id = 'leaflet-style-override'
  style.textContent = `
    .leaflet-control-attribution {
      display: none !important;
    }
    .leaflet-bottom {
      display: none !important;
    }
    .pulse-dot {
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.5; }
    }
    @keyframes busPulse {
      0%, 100% { transform: scale(1); opacity: 1; }
      50% { transform: scale(1.2); opacity: 0.8; }
    }
  `
  document.head.appendChild(style)
}

const MapRouteFitter = ({ coordinates, busStops }: { coordinates: [number, number][], busStops: Array<{ coordinates: [number, number] }> }) => {
  const map = useMap()
  
  useEffect(() => {
    if (coordinates.length > 0) {
      const bounds = L.latLngBounds(coordinates)
      map.fitBounds(bounds, { padding: [50, 50] })
    } else if (busStops.length > 0) {
      const allCoordinates = busStops.map(stop => stop.coordinates as [number, number])
      const bounds = L.latLngBounds(allCoordinates)
      map.fitBounds(bounds, { padding: [50, 50] })
    }
  }, [coordinates, busStops, map])
  
  return null
}

function App() {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const [currentTime, setCurrentTime] = useState('')
  const [routeCoordinates, setRouteCoordinates] = useState<[number, number][]>([])
  const [selectedStartStop, setSelectedStartStop] = useState<number>(0)
  const [selectedEndStop, setSelectedEndStop] = useState<number>(0)

  // Reservation form state
  const [showReservationForm, setShowReservationForm] = useState(false)
  const [reservationData, setReservationData] = useState({
    name: '',
    contact: '',
    cardType: '',
    terminal: '',
    reservationId: ''
  })
  const [showReceipt, setShowReceipt] = useState(false)

  // Carousel state
  const [cardIndex, setCardIndex] = useState(0)

  // Modal state
  const [showPrivacyModal, setShowPrivacyModal] = useState(false)
  const [showPolicyModal, setShowPolicyModal] = useState(false)
  const [busStops, setBusStops] = useState<Array<{ stop: string; location: string; status: string; coordinates: [number, number] }>>(busStopsData)
  const [loadingStops, setLoadingStops] = useState(true)
  const [busCoordinates, setBusCoordinates] = useState<[number, number] | null>(null)
  const [nearbyStopIndex, setNearbyStopIndex] = useState<number | null>(null)
  const [busLocationName, setBusLocationName] = useState<string>('Bus Location')
  const [gpsStatus, setGpsStatus] = useState<'connecting' | 'active' | 'error'>('connecting')
  const [lastGpsUpdate, setLastGpsUpdate] = useState<string | null>(null)
  const [occupancyData, setOccupancyData] = useState<{ current: number; capacity: number; percentage: number } | null>(null)
  const [estimatedArrival, setEstimatedArrival] = useState<string>('Calculating...')
  const [tripSchedules, setTripSchedules] = useState<any[]>([
    {
      id: 1,
      trip_number: 1,
      departure_time_start: '05:00',
      arrival_time_start: '06:30',
      arrival_time_end: '07:00'
    },
    {
      id: 2,
      trip_number: 2,
      departure_time_start: '07:00',
      arrival_time_start: '08:30',
      arrival_time_end: '09:00'
    },
    {
      id: 3,
      trip_number: 3,
      departure_time_start: '09:00',
      arrival_time_start: '10:30',
      arrival_time_end: '11:00'
    },
    {
      id: 4,
      trip_number: 4,
      departure_time_start: '11:00',
      arrival_time_start: '12:30',
      arrival_time_end: '13:00'
    },
    {
      id: 5,
      trip_number: 5,
      departure_time_start: '13:00',
      arrival_time_start: '14:30',
      arrival_time_end: '15:00'
    },
    {
      id: 6,
      trip_number: 6,
      departure_time_start: '15:00',
      arrival_time_start: '16:30',
      arrival_time_end: '17:00'
    },
    {
      id: 7,
      trip_number: 7,
      departure_time_start: '17:00',
      arrival_time_start: '18:30',
      arrival_time_end: '19:00'
    }
  ])

  const allCards = [
    { name: 'REGULAR', image: '/assets/REGULAR.png', color: 'bg-amber/10', textColor: 'text-amber', benefit: 'Standard fare rates', type: 'Permanent' },
    { name: 'STUDENT', image: '/assets/STUDENT.png', color: 'bg-green-500/20', textColor: 'text-green-400', benefit: '20% discount on all fares', type: 'Permanent' },
    { name: 'SENIOR CITIZEN', image: '/assets/SENIOR-CITIZIEN.png', color: 'bg-purple-500/20', textColor: 'text-purple-400', benefit: 'Special discounted rates', type: 'Permanent' },
    { name: 'PWD', image: '/assets/PWD.png', color: 'bg-red-500/20', textColor: 'text-red-400', benefit: 'Maximum discount benefits', type: 'Permanent' },
    { name: 'TEMP REGULAR', image: '/assets/TEMP-REG.png', color: 'bg-amber/10', textColor: 'text-amber', benefit: 'Standard fare rates', type: 'Temporary' },
    { name: 'TEMP STUDENT', image: '/assets/TEMP-STUD.png', color: 'bg-green-500/20', textColor: 'text-green-400', benefit: '20% discount on all fares', type: 'Temporary' },
    { name: 'TEMP SENIOR', image: '/assets/temp-senior.png', color: 'bg-purple-500/20', textColor: 'text-purple-400', benefit: 'Special discounted rates', type: 'Temporary' },
    { name: 'TEMP PWD', image: '/assets/TEMP-PWD.png', color: 'bg-red-500/20', textColor: 'text-red-400', benefit: 'Maximum discount benefits', type: 'Temporary' }
  ]

  // Load complete fare matrix from proper fare metrics data
  const fareMatrix: Record<string, Record<string, { regular: number; discounted: number }>> = {
    'Manolo Fortich Terminal': {
      'Gaisano CDO': { regular: 110, discounted: 100 },
      'Gusa': { regular: 110, discounted: 100 },
      'Tablon Baloi': { regular: 105, discounted: 95 },
      'Tablon': { regular: 100, discounted: 90 },
      'Agusan': { regular: 95, discounted: 85 },
      'Puerto': { regular: 90, discounted: 80 },
      'Bae Upper Puerto': { regular: 85, discounted: 75 },
      'Alae': { regular: 65, discounted: 55 },
      'Lunocan': { regular: 60, discounted: 50 },
      'San Miguel': { regular: 55, discounted: 45 },
      'Dicklum': { regular: 50, discounted: 40 },
      'Tankulan': { regular: 35, discounted: 25 },
      'Agora Terminal': { regular: 110, discounted: 100 }
    },
    'Gaisano CDO': {
      'Manolo Fortich Terminal': { regular: 110, discounted: 100 },
      'Gusa': { regular: 15, discounted: 15 },
      'Tablon Baloi': { regular: 25, discounted: 20 },
      'Tablon': { regular: 25, discounted: 20 },
      'Agusan': { regular: 30, discounted: 20 },
      'Puerto': { regular: 30, discounted: 25 },
      'Bae Upper Puerto': { regular: 45, discounted: 25 },
      'Alae': { regular: 55, discounted: 45 },
      'Lunocan': { regular: 65, discounted: 55 },
      'San Miguel': { regular: 65, discounted: 55 },
      'Dicklum': { regular: 75, discounted: 65 },
      'Tankulan': { regular: 75, discounted: 65 },
      'Agora Terminal': { regular: 15, discounted: 15 }
    },
    'Gusa': {
      'Manolo Fortich Terminal': { regular: 110, discounted: 100 },
      'Gaisano CDO': { regular: 15, discounted: 15 },
      'Tablon Baloi': { regular: 15, discounted: 15 },
      'Tablon': { regular: 15, discounted: 15 },
      'Agusan': { regular: 20, discounted: 15 },
      'Puerto': { regular: 23, discounted: 20 },
      'Bae Upper Puerto': { regular: 35, discounted: 30 },
      'Alae': { regular: 52, discounted: 45 },
      'Lunocan': { regular: 55, discounted: 55 },
      'San Miguel': { regular: 65, discounted: 55 },
      'Dicklum': { regular: 75, discounted: 65 },
      'Tankulan': { regular: 75, discounted: 65 },
      'Agora Terminal': { regular: 15, discounted: 15 }
    },
    'Tablon Baloi': {
      'Manolo Fortich Terminal': { regular: 105, discounted: 95 },
      'Gaisano CDO': { regular: 25, discounted: 20 },
      'Gusa': { regular: 15, discounted: 15 },
      'Tablon': { regular: 15, discounted: 15 },
      'Agusan': { regular: 15, discounted: 15 },
      'Puerto': { regular: 15, discounted: 15 },
      'Bae Upper Puerto': { regular: 25, discounted: 20 },
      'Alae': { regular: 40, discounted: 30 },
      'Lunocan': { regular: 50, discounted: 40 },
      'San Miguel': { regular: 55, discounted: 45 },
      'Dicklum': { regular: 60, discounted: 50 },
      'Tankulan': { regular: 70, discounted: 50 },
      'Agora Terminal': { regular: 25, discounted: 20 }
    },
    'Tablon': {
      'Manolo Fortich Terminal': { regular: 100, discounted: 90 },
      'Gaisano CDO': { regular: 25, discounted: 20 },
      'Gusa': { regular: 15, discounted: 15 },
      'Tablon Baloi': { regular: 15, discounted: 15 },
      'Agusan': { regular: 15, discounted: 15 },
      'Puerto': { regular: 15, discounted: 15 },
      'Bae Upper Puerto': { regular: 24, discounted: 20 },
      'Alae': { regular: 40, discounted: 35 },
      'Lunocan': { regular: 45, discounted: 40 },
      'San Miguel': { regular: 55, discounted: 45 },
      'Dicklum': { regular: 60, discounted: 50 },
      'Tankulan': { regular: 63, discounted: 50 },
      'Agora Terminal': { regular: 25, discounted: 20 }
    },
    'Agusan': {
      'Manolo Fortich Terminal': { regular: 95, discounted: 85 },
      'Gaisano CDO': { regular: 30, discounted: 20 },
      'Gusa': { regular: 20, discounted: 15 },
      'Tablon Baloi': { regular: 15, discounted: 15 },
      'Tablon': { regular: 15, discounted: 15 },
      'Puerto': { regular: 15, discounted: 15 },
      'Bae Upper Puerto': { regular: 20, discounted: 15 },
      'Alae': { regular: 35, discounted: 25 },
      'Lunocan': { regular: 40, discounted: 35 },
      'San Miguel': { regular: 50, discounted: 40 },
      'Dicklum': { regular: 55, discounted: 45 },
      'Tankulan': { regular: 58, discounted: 45 },
      'Agora Terminal': { regular: 30, discounted: 20 }
    },
    'Puerto': {
      'Manolo Fortich Terminal': { regular: 90, discounted: 80 },
      'Gaisano CDO': { regular: 30, discounted: 25 },
      'Gusa': { regular: 23, discounted: 20 },
      'Tablon Baloi': { regular: 15, discounted: 15 },
      'Tablon': { regular: 15, discounted: 15 },
      'Agusan': { regular: 15, discounted: 15 },
      'Bae Upper Puerto': { regular: 20, discounted: 15 },
      'Alae': { regular: 30, discounted: 25 },
      'Lunocan': { regular: 40, discounted: 35 },
      'San Miguel': { regular: 45, discounted: 35 },
      'Dicklum': { regular: 55, discounted: 45 },
      'Tankulan': { regular: 55, discounted: 45 },
      'Agora Terminal': { regular: 30, discounted: 25 }
    },
    'Bae Upper Puerto': {
      'Manolo Fortich Terminal': { regular: 85, discounted: 75 },
      'Gaisano CDO': { regular: 45, discounted: 25 },
      'Gusa': { regular: 35, discounted: 30 },
      'Tablon Baloi': { regular: 25, discounted: 20 },
      'Tablon': { regular: 24, discounted: 20 },
      'Agusan': { regular: 20, discounted: 15 },
      'Puerto': { regular: 20, discounted: 15 },
      'Alae': { regular: 25, discounted: 20 },
      'Lunocan': { regular: 30, discounted: 25 },
      'San Miguel': { regular: 35, discounted: 30 },
      'Dicklum': { regular: 40, discounted: 30 },
      'Tankulan': { regular: 40, discounted: 30 },
      'Agora Terminal': { regular: 45, discounted: 25 }
    },
    'Alae': {
      'Manolo Fortich Terminal': { regular: 65, discounted: 55 },
      'Gaisano CDO': { regular: 55, discounted: 45 },
      'Gusa': { regular: 52, discounted: 45 },
      'Tablon Baloi': { regular: 40, discounted: 30 },
      'Tablon': { regular: 40, discounted: 35 },
      'Agusan': { regular: 35, discounted: 25 },
      'Puerto': { regular: 30, discounted: 25 },
      'Bae Upper Puerto': { regular: 25, discounted: 20 },
      'Lunocan': { regular: 15, discounted: 15 },
      'San Miguel': { regular: 20, discounted: 15 },
      'Dicklum': { regular: 30, discounted: 20 },
      'Tankulan': { regular: 30, discounted: 20 },
      'Agora Terminal': { regular: 55, discounted: 45 }
    },
    'Lunocan': {
      'Manolo Fortich Terminal': { regular: 60, discounted: 50 },
      'Gaisano CDO': { regular: 65, discounted: 55 },
      'Gusa': { regular: 55, discounted: 55 },
      'Tablon Baloi': { regular: 50, discounted: 40 },
      'Tablon': { regular: 45, discounted: 40 },
      'Agusan': { regular: 40, discounted: 35 },
      'Puerto': { regular: 40, discounted: 35 },
      'Bae Upper Puerto': { regular: 30, discounted: 25 },
      'Alae': { regular: 15, discounted: 15 },
      'San Miguel': { regular: 20, discounted: 15 },
      'Dicklum': { regular: 20, discounted: 20 },
      'Tankulan': { regular: 25, discounted: 20 },
      'Agora Terminal': { regular: 65, discounted: 55 }
    },
    'San Miguel': {
      'Manolo Fortich Terminal': { regular: 55, discounted: 45 },
      'Gaisano CDO': { regular: 65, discounted: 55 },
      'Gusa': { regular: 65, discounted: 55 },
      'Tablon Baloi': { regular: 55, discounted: 45 },
      'Tablon': { regular: 55, discounted: 45 },
      'Agusan': { regular: 50, discounted: 40 },
      'Puerto': { regular: 45, discounted: 35 },
      'Bae Upper Puerto': { regular: 35, discounted: 30 },
      'Alae': { regular: 20, discounted: 15 },
      'Lunocan': { regular: 20, discounted: 15 },
      'Dicklum': { regular: 15, discounted: 15 },
      'Tankulan': { regular: 20, discounted: 15 },
      'Agora Terminal': { regular: 65, discounted: 55 }
    },
    'Dicklum': {
      'Manolo Fortich Terminal': { regular: 50, discounted: 40 },
      'Gaisano CDO': { regular: 75, discounted: 65 },
      'Gusa': { regular: 75, discounted: 65 },
      'Tablon Baloi': { regular: 60, discounted: 50 },
      'Tablon': { regular: 60, discounted: 50 },
      'Agusan': { regular: 55, discounted: 45 },
      'Puerto': { regular: 55, discounted: 45 },
      'Bae Upper Puerto': { regular: 40, discounted: 30 },
      'Alae': { regular: 30, discounted: 20 },
      'Lunocan': { regular: 20, discounted: 20 },
      'San Miguel': { regular: 15, discounted: 15 },
      'Tankulan': { regular: 15, discounted: 15 },
      'Agora Terminal': { regular: 75, discounted: 65 }
    },
    'Tankulan': {
      'Manolo Fortich Terminal': { regular: 35, discounted: 25 },
      'Gaisano CDO': { regular: 75, discounted: 65 },
      'Gusa': { regular: 75, discounted: 65 },
      'Tablon Baloi': { regular: 70, discounted: 50 },
      'Tablon': { regular: 63, discounted: 50 },
      'Agusan': { regular: 58, discounted: 45 },
      'Puerto': { regular: 55, discounted: 45 },
      'Bae Upper Puerto': { regular: 40, discounted: 30 },
      'Alae': { regular: 30, discounted: 20 },
      'Lunocan': { regular: 25, discounted: 20 },
      'San Miguel': { regular: 20, discounted: 15 },
      'Dicklum': { regular: 15, discounted: 15 },
      'Agora Terminal': { regular: 75, discounted: 65 }
    },
    'Agora Terminal': {
      'Manolo Fortich Terminal': { regular: 110, discounted: 100 },
      'Gaisano CDO': { regular: 15, discounted: 15 },
      'Gusa': { regular: 15, discounted: 15 },
      'Tablon Baloi': { regular: 25, discounted: 20 },
      'Tablon': { regular: 25, discounted: 20 },
      'Agusan': { regular: 30, discounted: 20 },
      'Puerto': { regular: 30, discounted: 25 },
      'Bae Upper Puerto': { regular: 45, discounted: 25 },
      'Alae': { regular: 55, discounted: 45 },
      'Lunocan': { regular: 65, discounted: 55 },
      'San Miguel': { regular: 65, discounted: 55 },
      'Dicklum': { regular: 75, discounted: 65 },
      'Tankulan': { regular: 75, discounted: 65 }
    }
  }

  // Calculate fare between two stops using the fare matrix
  const calculateFare = (startIndex: number, endIndex: number) => {
    if (startIndex === endIndex || !busStops[startIndex] || !busStops[endIndex]) {
      return { regular: 0, discounted: 0 }
    }

    const fromStop = busStops[startIndex].location
    const toStop = busStops[endIndex].location

    console.log('Calculating fare:', { fromStop, toStop, startIndex, endIndex })

    // Check if fare exists in matrix (forward direction)
    if (fareMatrix[fromStop] && fareMatrix[fromStop][toStop]) {
      console.log('Found fare in forward direction:', fareMatrix[fromStop][toStop])
      return fareMatrix[fromStop][toStop]
    }

    // Check reverse direction (if matrix is bidirectional)
    if (fareMatrix[toStop] && fareMatrix[toStop][fromStop]) {
      console.log('Found fare in reverse direction:', fareMatrix[toStop][fromStop])
      return fareMatrix[toStop][fromStop]
    }

    // Fallback: estimate fare based on distance between stops
    console.log('Fare not found in matrix, estimating based on stop distance')
    const stopDistance = Math.abs(endIndex - startIndex)
    const estimatedFare = Math.min(15 + (stopDistance * 5), 110) // Base fare + distance factor, max 110
    const estimatedDiscounted = Math.max(estimatedFare - 10, 15) // Discounted fare
    
    return { 
      regular: estimatedFare, 
      discounted: estimatedDiscounted 
    }
  }

  // Handle reservation form submission
  const handleReservationSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    // Generate unique reservation ID
    const reservationId = `RES-${Date.now().toString().slice(-6)}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`

    // Calculate expiration date (7 days from now)
    const expirationDate = new Date()
    expirationDate.setDate(expirationDate.getDate() + 7)

    try {
      // Insert reservation into database
      const { data, error } = await supabase
        .from('card_reservations')
        .insert({
          reservation_id: reservationId,
          name: reservationData.name,
          contact: reservationData.contact,
          card_type: reservationData.cardType,
          pickup_terminal: reservationData.terminal,
          status: 'pending',
          created_at: new Date().toISOString(),
          expires_at: expirationDate.toISOString()
        } as any)
        .select()

      if (error) {
        console.error('Error creating reservation:', error)
        alert(`Failed to create reservation: ${error.message || 'Please try again.'}`)
        return
      }

      console.log('Reservation created successfully:', data)

      setReservationData({
        ...reservationData,
        reservationId
      })

      setShowReceipt(true)
      setShowReservationForm(false)
      
      // Show success notification
      alert(`Reservation successful! Your reservation ID is ${reservationId}. Please claim your card within 7 days (by ${expirationDate.toLocaleDateString()}).`)
    } catch (error) {
      console.error('Error:', error)
      alert(`An error occurred: ${error instanceof Error ? error.message : 'Please try again.'}`)
    }
  }

  // Reset reservation form
  const resetReservation = () => {
    setReservationData({
      name: '',
      contact: '',
      cardType: '',
      terminal: '',
      reservationId: ''
    })
    setShowReceipt(false)
    setShowReservationForm(false)
  }

  useEffect(() => {
    const updateTime = () => {
      const now = new Date()
      let hours = now.getHours()
      const minutes = now.getMinutes().toString().padStart(2, '0')
      const seconds = now.getSeconds().toString().padStart(2, '0')
      const ampm = hours >= 12 ? 'PM' : 'AM'
      
      hours = hours % 12
      hours = hours ? hours : 12 // the hour '0' should be '12'
      
      setCurrentTime(`${hours}:${minutes}:${seconds} ${ampm}`)
    }
    updateTime()
    const interval = setInterval(updateTime, 1000)
    
    return () => clearInterval(interval)
  }, [])

  // Fetch route when bus stops are loaded
  useEffect(() => {
    if (busStops.length > 0) {
      setSelectedEndStop(busStops.length - 1)
      fetchRoute()
    }
  }, [busStops])

  const fetchRoute = async () => {
    if (busStops.length === 0) return
    
    try {
      const startCoords = busStops[0].coordinates as [number, number]
      const endCoords = busStops[busStops.length - 1].coordinates as [number, number]
      
      // Use OSRM routing service to get actual road route between terminals
      const response = await fetch(
        `https://router.project-osrm.org/route/v1/driving/${startCoords[1]},${startCoords[0]};${endCoords[1]},${endCoords[0]}?overview=full&geometries=geojson`
      )
      const data = await response.json()
      
      if (data.routes && data.routes[0]) {
        const coordinates = data.routes[0].geometry.coordinates.map(
          (coord: [number, number]) => [coord[1], coord[0]] // Convert [lng, lat] to [lat, lng]
        )
        setRouteCoordinates(coordinates)
      }
    } catch (error) {
      console.error('Error fetching route:', error)
      // Fallback to straight line if routing fails
      if (busStops.length > 0) {
        setRouteCoordinates([
          busStops[0].coordinates as [number, number],
          busStops[busStops.length - 1].coordinates as [number, number]
        ])
      }
    } finally {
      setLoadingStops(false)
    }
  }

  // Fetch actual GPS data for bus location
  useEffect(() => {
    const fetchBusGPS = async () => {
      try {
        setGpsStatus('connecting')
        setEstimatedArrival('Connecting...')
        
        // First try to fetch from gps_logs table
        const { data: gpsLogsData, error: logsError } = await supabase
          .from('gps_logs')
          .select('lat, lng, recorded_at, trip_id')
          .order('recorded_at', { ascending: false })
          .limit(1)
          .maybeSingle()

        let gpsData: any = gpsLogsData
        let dataSource = 'gps_logs'

        // If no data in gps_logs, try trips table as fallback
        if (!gpsData) {
          const { data: tripsData, error: tripsError } = await supabase
            .from('trips')
            .select('current_lat, current_lng, gps_updated_at, id')
            .eq('status', 'in_progress')
            .order('started_at', { ascending: false })
            .limit(1)
            .maybeSingle() as any

          if (tripsData && tripsData.current_lat && tripsData.current_lng) {
            gpsData = {
              lat: tripsData.current_lat,
              lng: tripsData.current_lng,
              recorded_at: tripsData.gps_updated_at,
              trip_id: tripsData.id
            } as any
            dataSource = 'trips'
          }
        }

        if (logsError && !gpsData) {
          console.error('Error fetching GPS data from gps_logs:', logsError)
        }

        if (gpsData) {
          const lat = parseFloat((gpsData as any).lat)
          const lng = parseFloat((gpsData as any).lng)

          if (Number.isFinite(lat) && Number.isFinite(lng)) {
            setBusCoordinates([lat, lng])
            setGpsStatus('active')
            setLastGpsUpdate((gpsData as any).recorded_at)

            // Check if near any stop
            let nearestIndex = null
            let minDistance = Infinity

            busStops.forEach((stop, index) => {
              const distance = Math.sqrt(
                Math.pow(lat - stop.coordinates[0], 2) + 
                Math.pow(lng - stop.coordinates[1], 2)
              )

              // Consider "near" if within 0.01 degrees (approximately 1km)
              if (distance < 0.01 && distance < minDistance) {
                minDistance = distance
                nearestIndex = index
              }
            })

            setNearbyStopIndex(nearestIndex)
            
            // Set bus location name
            if (nearestIndex !== null) {
              setBusLocationName(busStops[nearestIndex]?.location || 'Bus Location')
              
              // Calculate estimated arrival time to next stop
              const nextStopIndex = nearestIndex + 1
              if (nextStopIndex < busStops.length) {
                const nextStop = busStops[nextStopIndex]
                const distance = Math.sqrt(
                  Math.pow(lat - nextStop.coordinates[0], 2) + 
                  Math.pow(lng - nextStop.coordinates[1], 2)
                )
                
                // Assume average speed of 40 km/h (approximately 0.011 degrees per minute)
                // Distance in degrees * (111 km per degree) / 40 km/h * 60 minutes
                const distanceKm = distance * 111
                const averageSpeedKmh = 40
                const timeMinutes = Math.round((distanceKm / averageSpeedKmh) * 60)
                
                setEstimatedArrival(`${timeMinutes} min`)
              } else {
                setEstimatedArrival('Arrived')
              }
            } else {
              setBusLocationName('En route')
              
              // Find the nearest stop for arrival estimation
              let nearestIndexForArrival = null
              let minDistanceForArrival = Infinity

              busStops.forEach((stop, index) => {
                const distance = Math.sqrt(
                  Math.pow(lat - stop.coordinates[0], 2) + 
                  Math.pow(lng - stop.coordinates[1], 2)
                )

                if (distance < minDistanceForArrival) {
                  minDistanceForArrival = distance
                  nearestIndexForArrival = index
                }
              })

              if (nearestIndexForArrival !== null) {
                const distanceKm = minDistanceForArrival * 111
                const averageSpeedKmh = 40
                const timeMinutes = Math.round((distanceKm / averageSpeedKmh) * 60)
                setEstimatedArrival(`${timeMinutes} min`)
              } else {
                setEstimatedArrival('Schedule check')
              }
            }
          } else {
            setGpsStatus('error')
            setBusLocationName('GPS Error')
            setEstimatedArrival('Schedule check')
          }
        } else {
          // No GPS data available from any source
          setGpsStatus('error')
          setBusLocationName('Schedule coming soon')
          setEstimatedArrival('Schedule check')
        }
      } catch (error) {
        console.error('Error fetching bus GPS:', error)
        setGpsStatus('error')
        setBusLocationName('Schedule coming soon')
        setEstimatedArrival('Schedule check')
      }
    }

    // Initial fetch
    fetchBusGPS()

    // Set up real-time subscription for GPS updates from both tables
    const gpsLogsSubscription = supabase
      .channel('public-dashboard-gps-logs-channel')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'gps_logs' }, () => {
        fetchBusGPS()
      })
      .subscribe()

    const tripsSubscription = supabase
      .channel('public-dashboard-trips-channel')
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'trips' }, () => {
        fetchBusGPS()
      })
      .subscribe()

    // Poll for updates every 10 seconds as fallback
    const pollingInterval = setInterval(fetchBusGPS, 10000)

    return () => {
      gpsLogsSubscription.unsubscribe()
      tripsSubscription.unsubscribe()
      clearInterval(pollingInterval)
    }
  }, [busStops])

  // Fetch occupancy data from database
  useEffect(() => {
    const fetchOccupancyData = async () => {
      try {
        // Fetch the latest passenger count
        const { data: passengerCountData, error: countError } = await supabase
          .from('passenger_counts')
          .select('count, ai_count, trip_id')
          .order('recorded_at', { ascending: false })
          .limit(1)
          .maybeSingle()

        if (countError) {
          console.error('Error fetching passenger count:', countError)
          return
        }

        if (passengerCountData) {
          const countData = passengerCountData as any
          // Use AI count if available, otherwise use manual count
          const currentCount = countData.ai_count || countData.count

          // Fetch bus capacity from the trips table
          if (countData.trip_id) {
            const { data: tripData, error: tripError } = await supabase
              .from('trips')
              .select('bus_id')
              .eq('id', countData.trip_id)
              .single()

            if (tripError) {
              console.error('Error fetching trip data:', tripError)
              return
            }

            if (tripData && (tripData as any).bus_id) {
              const tripDataAny = tripData as any
              const { data: busData, error: busError } = await supabase
                .from('buses')
                .select('seat_capacity')
                .eq('id', tripDataAny.bus_id)
                .single()

              if (busError) {
                console.error('Error fetching bus data:', busError)
                return
              }

              if (busData && (busData as any).seat_capacity) {
                const busDataAny = busData as any
                const capacity = busDataAny.seat_capacity
                const percentage = Math.round((currentCount / capacity) * 100)

                setOccupancyData({
                  current: currentCount,
                  capacity: capacity,
                  percentage: percentage
                })
              }
            }
          }
        }
      } catch (error) {
        console.error('Error fetching occupancy data:', error)
      }
    }

    // Initial fetch
    fetchOccupancyData()

    // Set up real-time subscription for passenger count updates
    const occupancySubscription = supabase
      .channel('public-dashboard-occupancy-channel')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'passenger_counts' }, () => {
        fetchOccupancyData()
      })
      .subscribe()

    // Poll for updates every 30 seconds as fallback
    const pollingInterval = setInterval(fetchOccupancyData, 30000)

    return () => {
      occupancySubscription.unsubscribe()
      clearInterval(pollingInterval)
    }
  }, [])



  return (
    <div className="min-h-screen bg-platform text-mist">
      <a href="#main" className="skip-link">Skip to main content</a>

      {/* Header */}
      <header className="sticky top-0 z-40 bg-signal text-mist border-b border-signal/10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <a href="#top" className="flex items-center gap-2.5 font-signage font-700 text-xl">
              <img src="/assets/logo.png" alt="CommutAI Logo" className="h-8 w-auto" />
              <span className="text-amber">CommutAI</span>
            </a>

            <nav className="hidden md:flex items-center gap-7 text-sm font-medium" aria-label="Primary">
              <a href="#live-map" className="hover:text-amber transition-colors">Live Map</a>
              <a href="#routes" className="hover:text-amber transition-colors">Routes</a>
              <a href="#qr-guide" className="hover:text-amber transition-colors">QR Card</a>
              <a href="#about" className="hover:text-amber transition-colors">About</a>
            </nav>

            <div className="flex items-center gap-3">
              <div className="hidden sm:flex items-center gap-1.5 text-xs font-mono text-mist/70" aria-live="off">
                <Clock size={14} />
                {currentTime}
              </div>
              <a 
                href="http://localhost:3012/login"
                target="_blank"
                rel="noopener noreferrer"
                className="hidden sm:flex items-center gap-2 px-4 py-2 bg-amber-500 hover:bg-amber-600 text-white text-sm font-medium rounded transition-colors"
              >
                <LogIn size={16} />
                Staff Login
              </a>
              <button 
                onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
                className="md:hidden p-2 rounded hover:bg-white/10" 
                aria-expanded={mobileMenuOpen}
                aria-controls="mobileMenu" 
                aria-label="Toggle menu"
              >
                {mobileMenuOpen ? <X size={24} /> : <Menu size={24} />}
              </button>
            </div>
          </div>

          {mobileMenuOpen && (
            <nav id="mobileMenu" className="md:hidden pb-4 flex flex-col gap-3 text-sm font-medium" aria-label="Mobile">
              <a href="#live-map" className="hover:text-amber" onClick={() => setMobileMenuOpen(false)}>Live Map</a>
              <a href="#routes" className="hover:text-amber" onClick={() => setMobileMenuOpen(false)}>Routes</a>
              <a href="#qr-guide" className="hover:text-amber" onClick={() => setMobileMenuOpen(false)}>QR Card</a>
              <a href="#about" className="hover:text-amber" onClick={() => setMobileMenuOpen(false)}>About</a>
              <a 
                href="http://localhost:3012/login"
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-2 px-4 py-2 bg-amber-500 hover:bg-amber-600 text-white text-sm font-medium rounded transition-colors"
                onClick={() => setMobileMenuOpen(false)}
              >
                <LogIn size={16} />
                Staff Login
              </a>
            </nav>
          )}
        </div>
      </header>

      <main id="main">
        {/* Live Map Section */}
        <section id="live-map" className="bg-platform text-mist">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
            <p className="text-xs font-mono uppercase tracking-widest text-amber-dim mb-1">[ Live map ]</p>
            <h2 className="font-signage font-700 text-3xl mb-8">Track the bus on route</h2>
            <p className="text-mist/70 max-w-xl mb-8">
              {loadingStops
                ? 'Loading route data...'
                : `Real-time GPS tracking shows the exact location of buses traveling between ${busStops[0]?.location || 'terminals'}. Watch the live map for current position, estimated arrival times, and occupancy updates.`
              }
            </p>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
              <div className="lg:col-span-2 relative rounded-xl border border-white/10 bg-signal overflow-hidden aspect-[4/3] sm:aspect-[16/9]">
                {loadingStops ? (
                  <div className="w-full h-full flex items-center justify-center">
                    <div className="text-center">
                      <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-amber mb-4"></div>
                      <p className="text-sm text-mist/70">Loading route data...</p>
                    </div>
                  </div>
                ) : (
                  <div id="map-container" className="w-full h-full">
                    <MapContainer 
                      center={busStops[0]?.coordinates || [8.366308873785245, 124.86500795847]} 
                      zoom={11} 
                      style={{ height: '100%', width: '100%' }}
                      dragging={false}
                      scrollWheelZoom={false}
                      doubleClickZoom={false}
                      touchZoom={false}
                    >
                      <TileLayer
                        attribution=""
                        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                      />
                      <MapRouteFitter coordinates={routeCoordinates} busStops={busStops} />
                      
                      {/* Bus GPS marker */}
                      {busCoordinates && (
                        <Marker 
                          position={busCoordinates}
                          icon={createBusIcon(busLocationName)}
                        />
                      )}
                      
                      {/* All bus stops markers (including terminals) */}
                      {busStops.map((stop, index) => (
                        <Marker
                          key={index}
                          position={stop.coordinates}
                          icon={
                            stop.status === 'START' ? manoloFortichIcon :
                            stop.status === 'END' ? agoraIcon :
                            nearbyStopIndex === index ? nearIcon :
                            activeIcon
                          }
                        >
                          <Popup>
                            <div>
                              <b>{stop.stop}</b><br />
                              <span className="text-xs">{stop.location}</span>
                              {stop.status === 'START' && <span className="text-xs text-green-400"> · Route Start</span>}
                              {stop.status === 'END' && <span className="text-xs text-red-400"> · Route End</span>}
                            </div>
                          </Popup>
                        </Marker>
                      ))}

                      {/* Only show route line if we have OSRM data */}
                      {routeCoordinates.length > 0 && (
                        <Polyline 
                          positions={routeCoordinates} 
                          color="#FF6A1A" 
                          weight={4} 
                          opacity={0.9} 
                        />
                      )}
                    </MapContainer>
                  </div>
                )}
                <p className="absolute bottom-2 left-2 z-[1000] text-[10px] font-mono text-mist/40 pointer-events-none">
                  {busStops.length > 0 
                    ? `${busStops[0].location} → ${busStops[busStops.length - 1].location}`
                    : 'Loading route data...'
                  }
                </p>
              </div>

              <div className="rounded-xl border border-white/10 bg-signal p-6">
                <div className="mb-4">
                  <h3 className="font-signage font-700 text-lg mb-1">Arrival Board</h3>
                  <p className="text-xs text-mist/50">Real-time arrival information</p>
                </div>

                {/* Terminal Billboard */}
                <div className="bg-black/40 rounded-lg p-5 border border-white/10">
                  <div className="flex items-center justify-between mb-4">
                    <div className="flex items-center gap-3">
                      <div>
                        <p className="text-mist/80 text-sm font-medium">
                          {loadingStops ? 'Loading route...' : busStops.length > 0 
                            ? `${busStops[0].location} → ${busStops[busStops.length - 1].location}`
                            : 'Route information unavailable'
                          }
                        </p>
                        <p className="text-mist/50 text-xs">Route Status: <span className="text-go">● Active</span></p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p className="text-xs text-mist/50 mb-1">Next Arrival</p>
                      <div className="flap-board flap-sm text-amber" aria-live="polite">{estimatedArrival}</div>
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-4 mt-4 pt-4 border-t border-dashed border-white/10">
                    <div>
                      <p className="text-xs text-mist/50 mb-1">Current Location</p>
                      <p className="text-mist font-medium text-sm">
                        {gpsStatus === 'connecting' ? 'Connecting to GPS...' :
                         gpsStatus === 'error' ? 'GPS unavailable' :
                         nearbyStopIndex !== null 
                          ? `Approaching ${busStops[nearbyStopIndex]?.location || 'next stop'}`
                          : busCoordinates 
                            ? 'En route'
                            : 'Waiting for GPS data...'}
                      </p>
                    </div>
                    <div>
                      <p className="text-xs text-mist/50 mb-1">Occupancy</p>
                      <div className="flex items-center gap-2">
                        <div className="flex-1 bg-white/10 rounded-full h-2">
                          <div className="bg-amber h-2 rounded-full" style={{ width: `${occupancyData?.percentage || 0}%` }}></div>
                        </div>
                        <span className="text-mist font-medium text-sm">
                          {occupancyData ? `${occupancyData.current}/${occupancyData.capacity}` : 'Loading...'}
                        </span>
                      </div>
                      <p className="text-xs text-mist/50 mt-1">
                        {occupancyData ? `${occupancyData.percentage}% Full` : 'Loading...'}
                      </p>
                    </div>
                  </div>

                  <div className="mt-4 pt-4 border-t border-dashed border-white/10 flex items-center justify-between text-xs font-mono text-mist/50">
                    <span>Bus: BUS-001</span>
                    <span className="flex items-center gap-1.5">
                      <span className={`w-1.5 h-1.5 rounded-full ${
                        gpsStatus === 'active' ? 'bg-go pulse-dot' : 
                        gpsStatus === 'connecting' ? 'bg-amber' : 
                        'bg-red-500'
                      }`}></span>
                      {gpsStatus === 'active' ? 'Live GPS' : 
                       gpsStatus === 'connecting' ? 'Connecting...' : 
                       'GPS Error'}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Bus Stops Section */}
        <section id="routes" className="bg-platform text-mist">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
          <p className="text-xs font-mono uppercase tracking-widest text-amber-dim mb-1">[ Bus stops & fares ]</p>
          <h2 className="font-signage font-700 text-3xl mb-2">
            {loadingStops ? 'Loading Route...' : busStops.length > 0
              ? `${busStops[0].location} → ${busStops[busStops.length - 1].location}`
              : 'Route Information'
            }
          </h2>
          <p className="text-mist/60 max-w-xl mb-8">
            {loadingStops
              ? 'Fetching real-time bus stop data...'
              : `Bus stops with fare information. Select your starting point and destination to calculate your fare.`
            }
          </p>

          {/* Fare Calculator */}
          <div className="bg-signal rounded-xl border border-white/10 overflow-hidden mb-4">
            <div className="grid grid-cols-1 md:grid-cols-2">
              {/* Bus Image Side */}
              <div className="relative h-8 md:h-auto">
                <img
                  src="/assets/checkfare-section.jpg"
                  alt="Bus"
                  className="w-full h-full object-cover"
                />
                <div className="absolute inset-0 bg-gradient-to-r from-transparent to-signal/90 md:bg-gradient-to-t md:from-transparent md:to-signal/90" />
              </div>

              {/* Fare Calculator Side */}
              <div className="p-4">
                <h3 className="font-signage font-600 text-base mb-3">Check our fare</h3>
                {loadingStops ? (
                  <div className="text-center py-8">
                    <div className="inline-block animate-spin rounded-full h-6 w-6 border-b-2 border-amber mb-3"></div>
                    <p className="text-sm text-mist/70">Loading bus stops...</p>
                  </div>
                ) : busStops.length === 0 ? (
                  <div className="text-center py-8">
                    <p className="text-sm text-mist/70">No bus stops available</p>
                  </div>
                ) : (
                  <>
                    <div className="space-y-4">
                      <div>
                        <label htmlFor="start-stop" className="block text-sm font-medium text-mist/70 mb-2">From</label>
                        <select
                          id="start-stop"
                          className="w-full px-4 py-2 rounded-lg border border-white/20 bg-black/40 text-mist focus:outline-none focus:ring-2 focus:ring-amber [&_option]:bg-signal [&_option]:text-mist"
                          value={selectedStartStop}
                          onChange={(e) => setSelectedStartStop(Number(e.target.value))}
                        >
                          {busStops.map((stop, index) => (
                            <option key={index} value={index}>{stop.location}</option>
                          ))}
                        </select>
                      </div>
                      <div>
                        <label htmlFor="end-stop" className="block text-sm font-medium text-mist/70 mb-2">To</label>
                        <select
                          id="end-stop"
                          className="w-full px-4 py-2 rounded-lg border border-white/20 bg-black/40 text-mist focus:outline-none focus:ring-2 focus:ring-amber [&_option]:bg-signal [&_option]:text-mist"
                          value={selectedEndStop}
                          onChange={(e) => setSelectedEndStop(Number(e.target.value))}
                        >
                          {busStops.map((stop, index) => (
                            <option key={index} value={index}>{stop.location}</option>
                          ))}
                        </select>
                      </div>
                    </div>

                    {(() => {
                      const fare = calculateFare(selectedStartStop, selectedEndStop)
                      return (
                        <div className="mt-4 pt-4 border-t border-white/10">
                          <div className="flex items-center justify-between">
                            <div>
                              <p className="text-sm text-mist/70">Selected Route</p>
                              <p className="font-signage font-600 text-sm">
                                {busStops[selectedStartStop]?.location || 'N/A'} → {busStops[selectedEndStop]?.location || 'N/A'}
                              </p>
                            </div>
                            <div className="text-right">
                              <p className="text-sm text-mist/70">Fare</p>
                              <p className="font-signage font-700 text-2xl text-amber">
                                ₱{fare.regular.toFixed(2)}
                              </p>
                              <p className="text-xs text-mist/50">Discounted: ₱{fare.discounted.toFixed(2)}</p>
                            </div>
                          </div>

                          {/* Full Route Schedule */}
                          <div className="mt-4 pt-4 border-t border-white/10">
                            <div className="bg-black/30 rounded-lg p-4">
                              <div className="flex items-center gap-2 mb-3">
                                <svg className="w-5 h-5 text-amber" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                                  <path strokeLinecap="round" strokeLinejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                                </svg>
                                <p className="text-sm font-semibold text-mist/70">Full Route Schedule</p>
                              </div>
                              <div className="space-y-3">
                                {tripSchedules.length > 0 ? (
                                  tripSchedules.map((schedule) => {
                                    const formatTime = (time: string) => {
                                      const [hours, minutes] = time.split(':')
                                      const hour = parseInt(hours)
                                      const ampm = hour >= 12 ? 'PM' : 'AM'
                                      const displayHour = hour % 12 || 12
                                      return `${displayHour}:${minutes} ${ampm}`
                                    }

                                    return (
                                      <div key={schedule.id} className="flex items-center justify-between">
                                        <div>
                                          <p className="font-signage font-600 text-sm mb-1">Manolo Fortich Terminal → Agora Terminal</p>
                                          <div className="flex items-center gap-2">
                                            <svg className="w-4 h-4 text-mist/50" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                                              <path strokeLinecap="round" strokeLinejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                                            </svg>
                                            <p className="text-xs text-mist/50">
                                              {formatTime(schedule.arrival_time_start)} - {formatTime(schedule.arrival_time_end)}
                                            </p>
                                          </div>
                                        </div>
                                        <div className="text-right">
                                          <div className="inline-flex items-center gap-2 bg-amber/10 px-3 py-1 rounded-full">
                                            <div className="w-2 h-2 rounded-full bg-amber animate-pulse"></div>
                                            <p className="font-signage font-700 text-lg text-amber">
                                              Departure: {formatTime(schedule.departure_time_start)}
                                            </p>
                                          </div>
                                        </div>
                                      </div>
                                    )
                                  })
                                ) : (
                                  <p className="text-sm text-mist/50">Loading schedule...</p>
                                )}
                              </div>
                            </div>
                          </div>
                        </div>
                      )
                    })()}
                  </>
                )}
              </div>
            </div>
          </div>
          </div>
        </section>

        <section id="qr-guide" className="bg-platform text-mist">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
            <p className="text-xs font-mono uppercase tracking-widest text-amber-dim mb-1">[ QR card guide ]</p>
            <h2 className="font-signage font-700 text-3xl mb-2">Ride with your QR card</h2>
            <p className="text-mist/60 max-w-xl mb-10">Get your CommutAI QR fare card from customer service and enjoy cashless, instant boarding. Here's how the system works.</p>

            {/* Promote Card */}
            <div className="bg-signal rounded-xl border border-white/10 overflow-hidden mb-8">
              <img
                src="/assets/promote-card.jpg"
                alt="Get your CommutAI QR card"
                className="w-full h-auto"
              />
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-12">
              {/* How to Get Your Card */}
              <div className="bg-signal rounded-xl border border-white/10 p-6">
                <h3 className="font-signage font-700 text-xl mb-4">How to Get Your Card</h3>
                <div className="space-y-4">
                  <div className="flex items-start gap-4">
                    <div className="w-8 h-8 rounded-full bg-amber text-mist flex items-center justify-center font-bold text-sm shrink-0">1</div>
                    <div>
                      <h4 className="font-semibold mb-1">Visit Customer Service</h4>
                      <p className="text-sm text-mist/70">Go to any terminal booth or partner kiosk. Our customer service staff will help you register.</p>
                    </div>
                  </div>
                  <div className="flex items-start gap-4">
                    <div className="w-8 h-8 rounded-full bg-amber text-mist flex items-center justify-center font-bold text-sm shrink-0">2</div>
                    <div>
                      <h4 className="font-semibold mb-1">Provide Your Information</h4>
                      <p className="text-sm text-mist/70">Show valid ID and provide your contact details. Choose your card type (Regular, Student, Senior Citizen, or PWD).</p>
                    </div>
                  </div>
                  <div className="flex items-start gap-4">
                    <div className="w-8 h-8 rounded-full bg-amber text-mist flex items-center justify-center font-bold text-sm shrink-0">3</div>
                    <div>
                      <h4 className="font-semibold mb-1">Receive Your Card</h4>
                      <p className="text-sm text-mist/70">Get your personalized QR card with unique ID and initial ₱100 balance. Cards are issued instantly.</p>
                    </div>
                  </div>
                  <div className="flex items-start gap-4">
                    <div className="w-8 h-8 rounded-full bg-amber text-mist flex items-center justify-center font-bold text-sm shrink-0">4</div>
                    <div>
                      <h4 className="font-semibold mb-1">Top Up Balance</h4>
                      <p className="text-sm text-mist/70">Add fare credit at terminal kiosks, partner stores, or through customer service. Balance updates immediately.</p>
                    </div>
                  </div>
                </div>

                <div className="mt-6 pt-6 border-t border-white/10">
                  <p className="text-sm text-mist/70 mb-4">Want to skip the line? Pre-reserve your card online and pick it up at your preferred terminal.</p>
                  <button
                    onClick={() => setShowReservationForm(true)}
                    className="w-full px-6 py-3 bg-amber text-mist font-semibold rounded-lg hover:bg-amber/90 transition-colors"
                  >
                    Reserve Your Card Online
                  </button>
                </div>
              </div>

              {/* Card Types */}
              <div className="bg-signal rounded-xl border border-white/10 p-6">
                <h3 className="font-signage font-700 text-xl mb-4">Card Types & Benefits</h3>

                {/* Combined Cards Carousel */}
                <div className="relative">
                  <div className="flex items-center justify-center">
                    <button
                      onClick={() => setCardIndex((prev) => (prev === 0 ? allCards.length - 1 : prev - 1))}
                      className="p-2 rounded-full bg-white/10 hover:bg-white/20 transition-colors mr-2"
                    >
                      <svg className="w-5 h-5 text-mist" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                        <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
                      </svg>
                    </button>
                    <div className="flex-1 max-w-xs">
                      <div className="bg-signal rounded-lg p-4 border border-white/10">
                        <img src={allCards[cardIndex].image} alt={allCards[cardIndex].name} className="w-full h-auto rounded-lg mb-3" />
                        <div className="text-center mb-2">
                          <span className={`text-xs font-semibold ${allCards[cardIndex].color} px-2 py-1 rounded`}>{allCards[cardIndex].name}</span>
                        </div>
                        <div className="text-center mb-2">
                          <p className="text-sm text-mist/70">{allCards[cardIndex].benefit}</p>
                        </div>
                        <div className="text-center">
                          <span className="text-xs text-mist/50">{allCards[cardIndex].type} Card</span>
                        </div>
                      </div>
                    </div>
                    <button
                      onClick={() => setCardIndex((prev) => (prev === allCards.length - 1 ? 0 : prev + 1))}
                      className="p-2 rounded-full bg-white/10 hover:bg-white/20 transition-colors ml-2"
                    >
                      <svg className="w-5 h-5 text-mist" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                        <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
                      </svg>
                    </button>
                  </div>
                  <div className="flex justify-center gap-2 mt-4">
                    {allCards.map((_, index) => (
                      <button
                        key={index}
                        onClick={() => setCardIndex(index)}
                        className={`w-2 h-2 rounded-full transition-colors ${index === cardIndex ? 'bg-amber' : 'bg-white/30'}`}
                      />
                    ))}
                  </div>
                  <div className="text-center mt-4">
                    <p className="text-xs text-mist/50">
                      {allCards[cardIndex].type === 'Permanent' ? 'Long-term cards for regular commuters. Valid for 1 year.' : 'Short-term cards for visitors or first-time users.'}
                    </p>
                  </div>
                </div>
              </div>
            </div>

            {/* How to Use */}
            <div className="bg-signal rounded-xl border border-white/10 p-6 mb-12">
              <h3 className="font-signage font-700 text-xl mb-4">How to Use Your Card</h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div className="text-center">
                  <div className="w-16 h-16 mx-auto mb-3 rounded-full bg-amber/10 flex items-center justify-center">
                    <svg className="w-8 h-8 text-amber" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M15 5v2m0 4v2m0 4v2M5 5a2 2 0 00-2 2v3a2 2 0 002 2v2a2 2 0 002 2v2a2 2 0 002 2v2a2 2 0 002 2v2a2 2 0 002 2v2a2 2 0 002 2v2a2 2 0 002 2v2a2 2 0 01-2 2 2 2 0 01-2-2V5a2 2 0 012-2V3a2 2 0 012-2z" />
                    </svg>
                  </div>
                  <h4 className="font-semibold mb-2">Approach Bus</h4>
                  <p className="text-sm text-mist/70">When the bus arrives, approach the front door where the conductor is stationed.</p>
                </div>
                <div className="text-center">
                  <div className="w-16 h-16 mx-auto mb-3 rounded-full bg-amber/10 flex items-center justify-center">
                    <svg className="w-8 h-8 text-amber" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                    </svg>
                  </div>
                  <h4 className="font-semibold mb-2">Show Card to Conductor</h4>
                  <p className="text-sm text-mist/70">Present your QR card to the conductor. They will validate it using their handheld reader.</p>
                </div>
                <div className="text-center">
                  <div className="w-16 h-16 mx-auto mb-3 rounded-full bg-amber/10 flex items-center justify-center">
                    <svg className="w-8 h-8 text-amber" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  </div>
                  <h4 className="font-semibold mb-2">Board & Go</h4>
                  <p className="text-sm text-mist/70">Conductor confirms fare deduction. Find a seat and enjoy your ride.</p>
                </div>
              </div>
            </div>

            {/* Reservation Modal */}
            {showReservationForm && (
              <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
                <div className="bg-signal rounded-xl max-w-lg w-full max-h-[90vh] overflow-y-auto border border-white/10">
                  <div className="p-6">
                    <div className="flex items-center justify-between mb-6">
                      <h3 className="font-signage font-700 text-xl">Reserve Your QR Card</h3>
                      <button
                        onClick={() => setShowReservationForm(false)}
                        className="text-mist/50 hover:text-mist transition-colors"
                      >
                        <X className="w-6 h-6" />
                      </button>
                    </div>

                    {!showReceipt ? (
                      <form onSubmit={handleReservationSubmit} className="space-y-4">
                        <div>
                          <label className="block text-sm font-medium text-mist/70 mb-2">Full Name</label>
                          <input
                            type="text"
                            required
                            value={reservationData.name}
                            onChange={(e) => setReservationData({ ...reservationData, name: e.target.value })}
                            className="w-full px-4 py-2 border border-white/20 bg-black/40 rounded-lg focus:outline-none focus:ring-2 focus:ring-amber text-mist"
                            placeholder="Enter your full name"
                          />
                        </div>

                        <div>
                          <label className="block text-sm font-medium text-mist/70 mb-2">Contact Number</label>
                          <input
                            type="tel"
                            required
                            value={reservationData.contact}
                            onChange={(e) => setReservationData({ ...reservationData, contact: e.target.value })}
                            className="w-full px-4 py-2 border border-white/20 bg-black/40 rounded-lg focus:outline-none focus:ring-2 focus:ring-amber text-mist"
                            placeholder="09XX-XXX-XXXX"
                          />
                        </div>

                        <div>
                          <label className="block text-sm font-medium text-mist/70 mb-2">Card Type</label>
                          <select
                            required
                            value={reservationData.cardType}
                            onChange={(e) => setReservationData({ ...reservationData, cardType: e.target.value })}
                            className="w-full px-4 py-2 border border-white/20 bg-black/40 rounded-lg focus:outline-none focus:ring-2 focus:ring-amber text-mist [&_option]:bg-signal [&_option]:text-mist"
                          >
                            <option value="">Select card type</option>
                            <option value="Regular">Regular</option>
                            <option value="Student">Student</option>
                            <option value="Senior Citizen">Senior Citizen</option>
                            <option value="PWD">PWD</option>
                          </select>
                        </div>

                        <div>
                          <label className="block text-sm font-medium text-mist/70 mb-2">Pickup Terminal</label>
                          <select
                            required
                            value={reservationData.terminal}
                            onChange={(e) => setReservationData({ ...reservationData, terminal: e.target.value })}
                            className="w-full px-4 py-2 border border-white/20 bg-black/40 rounded-lg focus:outline-none focus:ring-2 focus:ring-amber text-mist [&_option]:bg-signal [&_option]:text-mist"
                          >
                            <option value="">Select pickup location</option>
                            {busStops.length > 0 && (
                              <>
                                <option value={busStops[0].location}>{busStops[0].location}</option>
                                <option value={busStops[busStops.length - 1].location}>{busStops[busStops.length - 1].location}</option>
                              </>
                            )}
                          </select>
                        </div>

                        <div className="flex gap-3 pt-4">
                          <button
                            type="submit"
                            className="flex-1 px-6 py-3 bg-amber text-mist font-semibold rounded-lg hover:bg-amber/90 transition-colors"
                          >
                            Submit Reservation
                          </button>
                          <button
                            type="button"
                            onClick={() => setShowReservationForm(false)}
                            className="px-6 py-3 bg-white/10 text-mist font-semibold rounded-lg hover:bg-white/20 transition-colors"
                          >
                            Cancel
                          </button>
                        </div>
                      </form>
                    ) : (
                      <div className="bg-amber/10 border border-amber/30 rounded-lg p-6">
                        <div className="text-center mb-6">
                          <div className="w-16 h-16 mx-auto mb-3 rounded-full bg-amber flex items-center justify-center">
                            <svg className="w-8 h-8 text-mist" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                              <path strokeLinecap="round" strokeLinejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                            </svg>
                          </div>
                          <h4 className="font-signage font-700 text-xl mb-2">Reservation Confirmed!</h4>
                          <p className="text-sm text-mist/70">Please present this receipt at customer service</p>
                        </div>

                        <div className="bg-signal rounded-lg p-4 mb-4 border border-white/10">
                          <div className="space-y-3">
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-mist/60">Reservation ID:</span>
                              <span className="font-mono font-semibold text-amber text-lg">{reservationData.reservationId}</span>
                            </div>
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-mist/60">Name:</span>
                              <span className="font-medium text-mist">{reservationData.name}</span>
                            </div>
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-mist/60">Contact:</span>
                              <span className="font-medium text-mist">{reservationData.contact}</span>
                            </div>
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-mist/60">Card Type:</span>
                              <span className="font-medium text-mist">{reservationData.cardType}</span>
                            </div>
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-mist/60">Pickup Location:</span>
                              <span className="font-medium text-mist">{reservationData.terminal}</span>
                            </div>
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-mist/60">Date:</span>
                              <span className="font-medium text-mist">{new Date().toLocaleDateString()}</span>
                            </div>
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-mist/60">Expires:</span>
                              <span className="font-medium text-amber">{new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toLocaleDateString()}</span>
                            </div>
                          </div>
                        </div>

                        <div className="bg-signal/50 rounded-lg p-4 mb-4 border border-white/10">
                          <h5 className="font-semibold mb-2">Instructions:</h5>
                          <ol className="text-sm text-mist/70 space-y-1 list-decimal list-inside">
                            <li>Visit {reservationData.terminal || 'your preferred terminal'} customer service booth</li>
                            <li>Show this reservation ID: <span className="font-mono font-semibold text-amber">{reservationData.reservationId}</span></li>
                            <li>Claim your card within 7 days (by {new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toLocaleDateString()})</li>
                            <li>Present valid ID for verification</li>
                            <li>Receive your QR card and top up balance</li>
                          </ol>
                        </div>

                        <div className="flex gap-3">
                          <button
                            onClick={resetReservation}
                            className="flex-1 px-6 py-3 bg-amber text-mist font-semibold rounded-lg hover:bg-amber/90 transition-colors"
                          >
                            Make Another Reservation
                          </button>
                          <button
                            onClick={() => window.print()}
                            className="px-6 py-3 bg-white/10 text-mist font-semibold rounded-lg hover:bg-white/20 transition-colors"
                          >
                            Print Receipt
                          </button>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            )}
          </div>
        </section>

        {/* Help & Information */}
        {/* About Section */}
        <section id="about" className="bg-platform text-mist">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
            <p className="text-xs font-mono uppercase tracking-widest text-amber-dim mb-1">[ About Us ]</p>
            <h2 className="font-signage font-700 text-3xl mb-8">ONE MANOLO FORTICH TRANSPORT</h2>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 items-start">
              {/* Image Side */}
              <div className="order-2 lg:order-1">
                <img
                  src="/assets/about.jpg"
                  alt="One Manolo Fortich Transport"
                  className="w-full h-auto rounded-xl border border-white/10"
                />
              </div>

              {/* Content Side */}
              <div className="order-1 lg:order-2 space-y-8">
                {/* FAQ Section */}
                <div className="bg-signal rounded-xl border border-white/10 p-6">
                  <h3 className="font-signage font-700 text-xl mb-4">Frequently Asked Questions</h3>
                  <div className="space-y-6">
                    {/* Getting Started */}
                    <div>
                      <h4 className="font-semibold text-amber mb-3 flex items-center gap-2">
                        <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                          <path strokeLinecap="round" strokeLinejoin="round" d="M13 10V3L4 14h7v7l9-11h-7z" />
                        </svg>
                        Getting Started
                      </h4>
                      <div className="space-y-2 ml-6">
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>Do I need an account?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">No. Live tracking and fare info are open to everyone. You only need a QR card for boarding.</p>
                        </details>
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>How do I get a QR card?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">Visit any terminal customer service booth. Bring valid ID, fill out registration, and receive your card instantly with ₱100 initial balance.</p>
                        </details>
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>What card types are available?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">Regular, Student, Senior Citizen, and PWD cards. Each type has different fare discounts. Permanent cards valid for 1 year, temporary cards for short-term use.</p>
                        </details>
                      </div>
                    </div>

                    {/* Card Management */}
                    <div>
                      <h4 className="font-semibold text-amber mb-3 flex items-center gap-2">
                        <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                          <path strokeLinecap="round" strokeLinejoin="round" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
                        </svg>
                        Card Management
                      </h4>
                      <div className="space-y-2 ml-6">
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>How do I reload my card?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">Visit customer service at any terminal to reload your card. Balance updates immediately. You can also reload through GCash at partner locations.</p>
                        </details>
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>How do I check my card balance?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">Ask the conductor when boarding or visit customer service. You'll also receive SMS notifications for transactions.</p>
                        </details>
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>What if I lose my card?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">Report lost cards immediately to customer service. They'll deactivate the old card and issue a replacement with your remaining balance transferred.</p>
                        </details>
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>What if my card doesn't work?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">Visit customer service for card troubleshooting. If the card is damaged, it can be replaced with your balance transferred to the new card.</p>
                        </details>
                      </div>
                    </div>

                    {/* Using the System */}
                    <div>
                      <h4 className="font-semibold text-amber mb-3 flex items-center gap-2">
                        <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                          <path strokeLinecap="round" strokeLinejoin="round" d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
                        </svg>
                        Using the System
                      </h4>
                      <div className="space-y-2 ml-6">
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>How does the live tracking work?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">Each bus has GPS that sends real-time location updates. The dashboard shows bus position, estimated arrival times, and current occupancy.</p>
                        </details>
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>How accurate are ETAs?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">Within 1-2 minutes under normal conditions. Real-time GPS tracking shows exact bus location on the live map.</p>
                        </details>
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>What are the fare rates?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">Fares depend on distance traveled. Use the fare calculator above to check rates between any two stops. Maximum fare is ₱110 for the full route.</p>
                        </details>
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>Can I use cash for payment?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">We encourage cashless payments via QR cards for faster boarding. However, temporary tickets are available for one-time use if needed.</p>
                        </details>
                        <details className="group">
                          <summary className="flex items-center justify-between cursor-pointer text-sm font-medium hover:text-amber transition-colors">
                            <span>What discounts are available?</span>
                            <svg className="w-4 h-4 text-mist/50 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7"/></svg>
                          </summary>
                          <p className="mt-2 text-sm text-mist/70 pl-4">Students, Senior Citizens, and PWD cardholders receive discounted fares. Discounts are automatically applied when using your registered card type.</p>
                        </details>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Contact Section */}
        <section className="bg-platform text-mist">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
            <p className="text-xs font-mono uppercase tracking-widest text-amber-dim mb-1">[ Contact Us ]</p>
            <h2 className="font-signage font-700 text-3xl mb-4">Get in Touch</h2>
            <p className="text-sm text-mist/70 mb-8">Use our contact information for inquiries and support</p>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="bg-signal rounded-xl border border-white/10 p-6 hover:border-amber/30 transition-colors">
                <div className="flex items-center gap-4 mb-4">
                  <div className="w-12 h-12 rounded-full bg-amber/20 flex items-center justify-center">
                    <Mail className="w-6 h-6 text-amber" />
                  </div>
                  <div>
                    <h3 className="font-semibold text-lg">Email</h3>
                    <p className="text-xs text-mist/50">Send us a message</p>
                  </div>
                </div>
                <a href="mailto:omanfortsco@gmail.com" className="text-mist hover:text-amber transition-colors font-medium">omanfortsco@gmail.com</a>
              </div>

              <div className="bg-signal rounded-xl border border-white/10 p-6 hover:border-amber/30 transition-colors">
                <div className="flex items-center gap-4 mb-4">
                  <div className="w-12 h-12 rounded-full bg-amber/20 flex items-center justify-center">
                    <Phone className="w-6 h-6 text-amber" />
                  </div>
                  <div>
                    <h3 className="font-semibold text-lg">Phone</h3>
                    <p className="text-xs text-mist/50">Call us directly</p>
                  </div>
                </div>
                <a href="tel:09778560019" className="text-mist hover:text-amber transition-colors font-medium">0977 856 0019</a>
              </div>

              <div className="bg-signal rounded-xl border border-white/10 p-6 hover:border-amber/30 transition-colors">
                <div className="flex items-center gap-4 mb-4">
                  <div className="w-12 h-12 rounded-full bg-amber/20 flex items-center justify-center">
                    <MapPin className="w-6 h-6 text-amber" />
                  </div>
                  <div>
                    <h3 className="font-semibold text-lg">Location</h3>
                    <p className="text-xs text-mist/50">Our service areas</p>
                  </div>
                </div>
                <p className="text-mist">Manolo Fortich, Philippines · Cagayan de Oro, Philippines</p>
              </div>

              <div className="bg-signal rounded-xl border border-white/10 p-6 hover:border-amber/30 transition-colors">
                <div className="flex items-center gap-4 mb-4">
                  <div className="w-12 h-12 rounded-full bg-amber/20 flex items-center justify-center">
                    <svg className="w-6 h-6 text-amber" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
                    </svg>
                  </div>
                  <div>
                    <h3 className="font-semibold text-lg">Facebook</h3>
                    <p className="text-xs text-mist/50">Follow us on social media</p>
                  </div>
                </div>
                <a href="https://web.facebook.com/p/One-Manolo-Fortich-Transport-Service-Cooperative-Omanfortsco-100063888020431/" target="_blank" rel="noopener noreferrer" className="text-mist hover:text-amber transition-colors font-medium">One Manolo Fortich Transport Service Cooperative -Omanfortsco</a>
              </div>
            </div>
          </div>
        </section>

        {/* Privacy Modal */}
        {showPrivacyModal && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-signal rounded-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto border border-white/10">
              <div className="p-6">
                <div className="flex items-center justify-between mb-6">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full bg-amber/10 flex items-center justify-center">
                      <Lock className="w-5 h-5 text-amber" />
                    </div>
                    <h3 className="font-signage font-700 text-xl">Data Privacy</h3>
                  </div>
                  <button
                    onClick={() => setShowPrivacyModal(false)}
                    className="text-mist/50 hover:text-mist transition-colors"
                  >
                    <X className="w-6 h-6" />
                  </button>
                </div>

                <div className="space-y-4 text-sm text-mist/70">
                  <p className="leading-relaxed">
                    At CommutAI, we take your privacy seriously. We collect and process personal data only for the purposes of providing our transportation services, including QR card registration, fare payments, and account management.
                  </p>
                  <div className="space-y-2">
                    <h4 className="font-semibold">What We Collect:</h4>
                    <ul className="list-disc list-inside space-y-1">
                      <li>Name and contact information for QR card registration</li>
                      <li>Transaction history for fare payments</li>
                      <li>Route and usage data for service improvement</li>
                    </ul>
                  </div>
                  <div className="space-y-2">
                    <h4 className="font-semibold">How We Protect Your Data:</h4>
                    <ul className="list-disc list-inside space-y-1">
                      <li>Encryption of all sensitive data in transit and at rest</li>
                      <li>Strict access controls for authorized personnel only</li>
                      <li>Regular security audits and compliance with data protection laws</li>
                      <li>No sharing of personal data with third parties without consent</li>
                    </ul>
                  </div>
                  <p className="leading-relaxed">
                    You have the right to access, correct, or delete your personal data. Contact our privacy officer at privacy@commutai.ph for any data-related concerns.
                  </p>
                </div>

                <div className="mt-6 flex justify-end">
                  <button
                    onClick={() => setShowPrivacyModal(false)}
                    className="px-6 py-2 bg-amber text-mist font-semibold rounded-lg hover:bg-amber/90 transition-colors"
                  >
                    Close
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Policy Modal */}
        {showPolicyModal && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-signal rounded-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto border border-white/10">
              <div className="p-6">
                <div className="flex items-center justify-between mb-6">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full bg-amber/10 flex items-center justify-center">
                      <FileText className="w-5 h-5 text-amber" />
                    </div>
                    <h3 className="font-signage font-700 text-xl">Company Policy</h3>
                  </div>
                  <button
                    onClick={() => setShowPolicyModal(false)}
                    className="text-mist/50 hover:text-mist transition-colors"
                  >
                    <X className="w-6 h-6" />
                  </button>
                </div>

                <div className="space-y-4 text-sm text-mist/70">
                  <div className="space-y-2">
                    <h4 className="font-semibold">QR Card Usage Policy:</h4>
                    <ul className="list-disc list-inside space-y-1">
                      <li>Cards are non-transferable and must be used only by the registered owner</li>
                      <li>Lost or stolen cards must be reported immediately to prevent unauthorized use</li>
                      <li>Temporary cards are valid for 7 days from issuance</li>
                      <li>Permanent cards must be renewed annually</li>
                      <li>Balance refunds are available within 30 days of card deactivation</li>
                    </ul>
                  </div>
                  <div className="space-y-2">
                    <h4 className="font-semibold">Fare Policy:</h4>
                    <ul className="list-disc list-inside space-y-1">
                      <li>Fares are calculated based on distance traveled between stops</li>
                      <li>Discounted rates apply to Student, Senior Citizen, and PWD cardholders with valid IDs</li>
                      <li>Fare adjustments will be announced 30 days in advance</li>
                      <li>No refunds for completed trips except in cases of service disruption</li>
                    </ul>
                  </div>
                  <div className="space-y-2">
                    <h4 className="font-semibold">Code of Conduct:</h4>
                    <ul className="list-disc list-inside space-y-1">
                      <li>Passengers must behave respectfully towards conductors and fellow passengers</li>
                      <li>Smoking, eating, and drinking are prohibited on board</li>
                      <li>Priority seating must be offered to elderly, pregnant women, and persons with disabilities</li>
                      <li>Violation of policies may result in card suspension or service denial</li>
                    </ul>
                  </div>
                </div>

                <div className="mt-6 flex justify-end">
                  <button
                    onClick={() => setShowPolicyModal(false)}
                    className="px-6 py-2 bg-amber text-mist font-semibold rounded-lg hover:bg-amber/90 transition-colors"
                  >
                    Close
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="bg-signal text-mist/60">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-10">
          <div className="barcode text-mist mb-4" aria-hidden="true"></div>
          <div className="flex flex-col sm:flex-row items-center justify-between gap-4 text-xs">
            <p className="font-mono">© 2026 CommutAI · Public dashboard · No login required</p>
            <div className="flex gap-5">
              <a href="#top" className="hover:text-amber">Back to top</a>
              <a href="#about" className="hover:text-amber">About</a>
              <button 
                onClick={() => setShowPrivacyModal(true)}
                className="hover:text-amber transition-colors text-left"
              >
                Data Privacy
              </button>
              <button 
                onClick={() => setShowPolicyModal(true)}
                className="hover:text-amber transition-colors text-left"
              >
                Company Policy
              </button>
            </div>
          </div>
        </div>
      </footer>
    </div>
  )
}

export default App
