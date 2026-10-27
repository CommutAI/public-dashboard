# SMS Queue Processor - Database-Driven System

## Overview

This is a database-driven SMS notification system where:
- **Frontend** queues SMS to Supabase `sms_queue` table
- **Raspberry Pi** polls the table and sends SMS via SIM900A
- No direct frontend-to-Raspberry Pi communication needed

## Architecture

```
Frontend (React)
    ↓ (queueSMS)
Supabase (sms_queue table)
    ↓ (polling every 5s)
Raspberry Pi (sms_queue_processor.py)
    ↓ (AT commands)
SIM900A GSM Module
    ↓
Customer receives SMS
```

## Files

- `sms_queue_processor.py` - Main polling service for Raspberry Pi
- `../src/utils/smsQueue.ts` - Frontend utility to queue SMS

## Setup on Raspberry Pi

### 1. Install Dependencies

```bash
pip3 install supabase pyserial python-dotenv
```

### 2. Configure Environment

Create `.env` file:

```bash
# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-key

# SIM900A Configuration
SIM900A_PORT=/dev/ttyUSB0
SIM900A_BAUDRATE=9600
SMS_POLL_INTERVAL=5
```

### 3. Run the Processor

```bash
python3 sms_queue_processor.py
```

### 4. Set as System Service (Auto-start)

```bash
sudo nano /etc/systemd/system/sms-queue.service
```

Add:

```ini
[Unit]
Description=SMS Queue Processor
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/raspberry-pi
Environment="SUPABASE_URL=https://your-project.supabase.co"
Environment="SUPABASE_KEY=your-anon-key"
Environment="SIM900A_PORT=/dev/ttyUSB0"
Environment="SIM900A_BAUDRATE=9600"
Environment="SMS_POLL_INTERVAL=5"
ExecStart=/usr/bin/python3 /home/pi/raspberry-pi/sms_queue_processor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable sms-queue
sudo systemctl start sms-queue
sudo systemctl status sms-queue
```

## Frontend Usage

```typescript
import { queueCardReservationSMS, queueEmergencySMS, queueTripCompletionSMS } from './utils/smsQueue'

// Card reservation confirmation
await queueCardReservationSMS(
  '09123456789',
  'Juan Dela Cruz',
  'RES-123456',
  'Regular',
  'Manolo Fortich Terminal'
)

// Emergency alert
await queueEmergencySMS(
  ['09123456789', '09987654321'],
  'Bus breakdown',
  { lat: 8.366, lng: 124.865 }
)

// Trip completion
await queueTripCompletionSMS(
  '09123456789',
  'Juan Dela Cruz',
  'Bus 1',
  'Manolo Fortich - Agora',
  110,
  'Agora Terminal'
)
```

## Database Schema

The `sms_queue` table structure:

```sql
CREATE TABLE sms_queue (
  id              UUID        PRIMARY KEY,
  phone_number    TEXT        NOT NULL,
  message         TEXT        NOT NULL,
  type            TEXT        CHECK (type IN ('emergency', 'alighting', 'card_reserved', 'card_claimed', 'other')),
  priority        INTEGER     DEFAULT 5,
  related_id      UUID,
  trip_id         UUID        REFERENCES trips (id),
  status          TEXT        DEFAULT 'pending',
  created_at      TIMESTAMPTZ NOT NULL,
  sent_at         TIMESTAMPTZ,
  failed_at       TIMESTAMPTZ,
  error_message   TEXT,
  retry_count     INTEGER     DEFAULT 0,
  max_retries     INTEGER     DEFAULT 3
);
```

## Important Notes

1. **Row Level Security**: Ensure RLS is disabled on `sms_queue` table for the Raspberry Pi to read/write
   ```sql
   ALTER TABLE sms_queue DISABLE ROW LEVEL SECURITY;
   ```

2. **SIM Card Balance**: The SIM card in SIM900A must have load to send SMS. Check balance by inserting SIM into a phone and dialing *143# (TM) or *888# (Globe).

3. **Message Length**: Keep messages under 160 bytes to avoid encoding issues. Use "P" instead of "₱" for peso symbol.

4. **Polling Interval**: Default is 5 seconds. Adjust via `SMS_POLL_INTERVAL` environment variable.

## Troubleshooting

### SMS not sending but showing "sent" in logs
- Check SIM card balance
- Verify antenna is connected
- Check signal strength: `AT+CSQ` command

### Raspberry Pi not fetching from queue
- Check Supabase credentials in .env
- Verify RLS is disabled on sms_queue
- Check network connectivity

### Frontend SMS not queuing
- Check Supabase credentials in .env
- Verify Supabase URL and key are correct
- Check browser console for errors

## Monitoring

View SMS queue status:

```sql
-- Check pending SMS
SELECT * FROM sms_queue WHERE status = 'pending';

-- Check failed SMS
SELECT * FROM sms_queue WHERE status = 'failed';

-- Check success rate
SELECT
  status,
  COUNT(*) as count
FROM sms_queue
GROUP BY status;
```

View processor logs:

```bash
sudo journalctl -u sms-queue -f
```
