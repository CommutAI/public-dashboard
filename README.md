# CommutAI Public Dashboard

A real-time public transportation dashboard for CommutAI featuring GPS tracking, card reservations, and SMS notification infrastructure.

## Features

- **Live GPS Tracking**: Real-time bus location tracking with fallback to Supabase
- **Interactive Map**: Leaflet-based map showing bus routes, stops, and current location
- **Card Reservations**: Online card reservation with automated SMS confirmations
- **SMS Queue Infrastructure**: Database-driven SMS notification system ready for queue processing
- **Raspberry Pi Integration**: Hardware support for SMS sending via SIM900A GSM module (optional)

## Tech Stack

- **Frontend**: React 19, TypeScript, Vite
- **Styling**: Tailwind CSS 4
- **Maps**: Leaflet, React Leaflet
- **Backend**: Supabase (PostgreSQL)
- **Hardware**: Raspberry Pi, SIM900A GSM Module

## Quick Start

### Prerequisites

- Node.js 18+
- Supabase project
- (Optional) Raspberry Pi with SIM900A for SMS

### Installation

```bash
# Clone the repository
git clone https://github.com/CommutAI/public-dashboard.git
cd public-dashboard

# Install dependencies
npm install

# Copy environment file
cp .env.example .env

# Configure your environment variables (see below)
nano .env

# Start development server
npm run dev
```

### Environment Variables

Create a `.env` file in the root directory:

```env
# Supabase Configuration
VITE_SUPABASE_URL=your_supabase_project_url
VITE_SUPABASE_ANON_KEY=your_supabase_anon_key

# GPS Backend Configuration
VITE_GPS_BACKEND_URL=https://sys-admin-my13.onrender.com
```

Get your Supabase credentials from:
- **URL**: Project Settings → API → Project URL
- **Key**: Project Settings → API → anon/public key

## Documentation

- [GPS Integration Guide](GPS-INTEGRATION.md) - Detailed GPS tracking setup and configuration
- [Quick Start GPS](QUICK-START-GPS.md) - Fast-track GPS setup guide
- [SMS Queue Setup](SMS-QUEUE-SETUP.md) - Database-driven SMS queue system configuration
- [Raspberry Pi SMS Setup](RASPBERRY-PI-SMS-SETUP.md) - Hardware SMS service setup guide
- [GPS Changes Log](CHANGES-GPS-INTEGRATION.md) - Recent GPS integration changes

## Database Setup

The database schema is located in `database/schema.sql`. Run the following SQL files in order:

1. `database/schema.sql` - Main database schema
2. `database/add-sms-queue.sql` - SMS queue table
3. `database/add-sms-approval.sql` - SMS approval workflow
4. `database/add-sms-trigger.sql` - Automated SMS triggers

## Raspberry Pi Setup (Optional)

For SMS functionality, set up a Raspberry Pi with SIM900A:

```bash
# On Raspberry Pi
ssh pi@raspberry-pi-ip

# Install dependencies
sudo apt update
sudo apt install python3 python3-pip python3-serial
pip3 install -r raspberry-pi-requirements.txt

# Configure environment
nano .env
# Add your Supabase credentials and SIM900A configuration

# Run SMS service
python3 raspberry-pi-sms-service.py

# Or set up as system service
sudo systemctl enable sms-service
sudo systemctl start sms-service
```

See [RASPBERRY-PI-SMS-SETUP.md](RASPBERRY-PI-SMS-SETUP.md) for detailed instructions.

## Project Structure

```
public-dashboard/
├── src/
│   ├── App.tsx              # Main application component
│   ├── index.css            # Global styles
│   └── utils/
│       ├── gpsApi.ts        # GPS API utilities
│       └── smsQueue.ts      # SMS queue utilities
├── database/
│   ├── schema.sql           # Main database schema
│   ├── add-sms-queue.sql    # SMS queue table
│   ├── add-sms-approval.sql # SMS approval workflow
│   └── add-sms-trigger.sql  # SMS triggers
├── raspberry-pi/
│   ├── raspberry-pi-sms-service.py    # SMS service with queue processing
│   └── raspberry-pi-sms-processor.py  # Advanced SMS queue processor
├── GPS-INTEGRATION.md       # GPS documentation
├── SMS-QUEUE-SETUP.md       # SMS queue documentation
└── RASPBERRY-PI-SMS-SETUP.md # Raspberry Pi setup guide
```

## Dashboard Sections

The public dashboard includes the following sections:

- **Live Map**: Real-time GPS tracking with interactive map showing bus routes, stops, and current bus location
- **QR Card Guide**: Information about getting and using CommutAI QR fare cards for cashless boarding
- **About**: Company information and FAQ section covering common questions about the service
- **Card Reservation**: Online form to reserve QR cards with automated SMS confirmation (requires SMS infrastructure setup)

## Development

```bash
# Start development server
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

## GPS Integration

The dashboard supports real-time GPS tracking with multiple data sources:

1. **Primary**: Backend API at `VITE_GPS_BACKEND_URL`
2. **Fallback 1**: Supabase `gps_locations` table
3. **Fallback 2**: Supabase `trips` table

GPS data updates every 10 seconds with automatic failover. The Live Map section displays:
- Real-time bus position with animated marker
- All bus stops along the route
- Route path visualization
- GPS connection status indicator

See [GPS-INTEGRATION.md](GPS-INTEGRATION.md) for detailed configuration.

## SMS System

The SMS infrastructure uses a queue-based architecture for card reservation confirmations:

```
Frontend → Supabase (sms_queue) → Raspberry Pi → SIM900A → SMS
```

Current Implementation:
- Card reservations automatically queue SMS confirmations via database triggers
- SMS queue table with priority-based processing
- Infrastructure supports multiple SMS types (emergency, alighting, card notifications)
- Requires Raspberry Pi with SIM900A for actual SMS sending

See [SMS-QUEUE-SETUP.md](SMS-QUEUE-SETUP.md) for setup instructions.

## Troubleshooting

### GPS Not Showing
- Check `VITE_GPS_BACKEND_URL` in `.env`
- Test backend: `curl https://sys-admin-my13.onrender.com/api/gps/latest`
- Check browser console for errors

### SMS Not Sending
- SMS requires Raspberry Pi with SIM900A hardware setup
- Verify Raspberry Pi service is running: `sudo systemctl status sms-service`
- Check SIM900A connection: `ls -l /dev/ttyUSB*`
- Review logs: `sudo journalctl -u sms-service -f`

### Database Connection
- Verify Supabase URL and key in `.env`
- Check Supabase project is active
- Ensure RLS policies allow anonymous access

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## License

Part of the CommutAI project.
