# Raspberry Pi SMS Service Setup

This service processes SMS notifications from the database queue using a SIM900A GSM module connected to Raspberry Pi. It supports both automatic queue processing and manual SMS sending.

## Architecture

```
Database (Supabase/PostgreSQL)
    ↓ (card_reservations INSERT - new reservation)
Trigger → sms_queue table
    ↓ (automatic polling in background)
Raspberry Pi Service → SIM900A → SMS to customer
```

## Features

- **Automatic Queue Processing**: Polls `sms_queue` table every 5 seconds (configurable)
- **Manual SMS Sending**: Command-line interface for sending specific SMS types
- **Emergency Alerts**: Send emergency notifications to contacts
- **Card Notifications**: Card approval/decline SMS
- **Trip Confirmations**: Trip completion SMS
- **Top-up Confirmations**: Reload confirmation SMS
- **Background Polling**: Runs in background thread without blocking manual commands

## Hardware Requirements

- Raspberry Pi (3, 4, or Zero W)
- SIM900A GSM Module
- Antenna for SIM900A
- SIM card with SMS enabled
- Jumper wires
- Power supply (5V 2A recommended)

## Wiring SIM900A to Raspberry Pi

### Serial Connection (UART)

| SIM900A Pin | Raspberry Pi GPIO |
|-------------|-------------------|
| VCC         | 5V                |
| GND         | GND               |
| TXD         | RXD (GPIO 15)     |
| RXD         | TXD (GPIO 14)     |

**Important:** The SIM900A operates at 5V while Raspberry Pi GPIO is 3.3V. Use a logic level converter or voltage divider on the RXD line.

### Alternative: USB-to-Serial Adapter

If using a USB-to-serial adapter (e.g., CP2102, FT232):
- Connect SIM900A TXD/RXD to adapter
- Mount USB to Raspberry Pi
- Update `SERIAL_PORT` in script to `/dev/ttyUSB0` or `/dev/ttyACM0`

## Software Setup

### 1. Enable Serial Port on Raspberry Pi

```bash
# Enable serial interface
sudo raspi-config
# Navigate to: Interface Options → Serial Port
# Enable serial port, disable serial console

# Reboot
sudo reboot
```

### 2. Install Dependencies

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Python dependencies
sudo apt install python3-pip python3-serial -y

# Install required Python packages
pip3 install supabase pyserial python-dotenv

# Or using requirements file
pip3 install -r raspberry-pi-requirements.txt
```

### 3. Deploy the Service

```bash
# Copy the service file to Raspberry Pi
scp raspberry-pi-sms-service.py pi@raspberry-pi-ip:~/

# SSH into Raspberry Pi
ssh pi@raspberry-pi-ip

# Make it executable
chmod +x raspberry-pi-sms-service.py
```

### 4. Configure Environment Variables

Create a `.env` file in the same directory as the service:

```bash
# SMS Service Configuration
SIM900A_PORT=/dev/ttyUSB0          # or /dev/ttyS0 for GPIO serial
SIM900A_BAUDRATE=9600
SMS_POLL_INTERVAL=5                # Seconds between queue checks

# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-key

# Emergency Contacts (fallback if database not available)
EMERGENCY_CONTACTS=09123456789,09987654321
ADMIN_CONTACTS=09123456789
```

Get your Supabase credentials from:
- **URL**: Project Settings → API → Project URL
- **Key**: Project Settings → API → anon/public key

### 5. Test SIM900A Connection

```bash
# Interactive test
python3 -c "
import serial
ser = serial.Serial('/dev/ttyS0', 9600, timeout=5)
ser.write(b'AT\r\n')
time.sleep(1)
print(ser.read(ser.in_waiting).decode())
ser.close()
"
```

Expected response: `OK`

### 6. Run the Service

```bash
# Run the service (starts queue processing automatically)
python3 raspberry-pi-sms-service.py

# Should see logs like:
# 2024-01-01 10:00:00 - INFO - SIM900A connected on /dev/ttyUSB0 @ 9600 baud
# 2024-01-01 10:00:00 - INFO - Supabase client initialized
# 2024-01-01 10:00:00 - INFO - Loaded 2 emergency contacts from database
# 2024-01-01 10:00:00 - INFO - Queue processor initialized
# 2024-01-01 10:00:00 - INFO - SIM900A connected on /dev/ttyUSB0 @ 9600 baud
# 2024-01-01 10:00:00 - INFO - Queue polling started (interval: 5s)
# 2024-01-01 10:00:00 - INFO - Automatic queue processing started
```

The service will now:
- Automatically poll the `sms_queue` table every 5 seconds
- Send SMS from the queue as they appear
- Keep running until you press Ctrl+C

## Set Up as System Service (Auto-start on Boot)

Create a systemd service file:

```bash
sudo nano /etc/systemd/system/sms-service.service
```

Add the following:

```ini
[Unit]
Description=SMS Service with Queue Processing
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi
Environment="SIM900A_PORT=/dev/ttyUSB0"
Environment="SIM900A_BAUDRATE=9600"
Environment="SMS_POLL_INTERVAL=5"
Environment="SUPABASE_URL=https://your-project.supabase.co"
Environment="SUPABASE_KEY=your-anon-key"
Environment="EMERGENCY_CONTACTS=09123456789,09987654321"
ExecStart=/usr/bin/python3 /home/pi/raspberry-pi-sms-service.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable auto-start on boot
sudo systemctl enable sms-service

# Start service now
sudo systemctl start sms-service

# Check status
sudo systemctl status sms-service

# View logs
sudo journalctl -u sms-service -f
```

## Command-Line Usage

The service supports various commands for manual SMS sending:

```bash
# Send test SMS
python3 raspberry-pi-sms-service.py test 09123456789 "Test message"

# Send emergency alert
python3 raspberry-pi-sms-service.py emergency "Bus breakdown at location"

# Send admin alert
python3 raspberry-pi-sms-service.py admin "System maintenance notification"

# Send reservation confirmation
python3 raspberry-pi-sms-service.py reservation <phone> <id> <name> <route> <schedule> <seats> <fare>

# Send card approval/decline
python3 raspberry-pi-sms-service.py card <phone> <card_id> <holder> approved|declined [reason]

# Send trip completion
python3 raspberry-pi-sms-service.py trip <phone> <name> <bus> <route> <fare> <stop> [distance]

# Send top-up confirmation
python3 raspberry-pi-sms-service.py topup <phone> <card_id> <holder> <amount> <new_balance> [ref]

# Refresh contacts from database
python3 raspberry-pi-sms-service.py refresh

# Show service status
python3 raspberry-pi-sms-service.py status

# Process queue manually once
python3 raspberry-pi-sms-service.py queue
```

Note: Queue processing runs automatically in the background, so you don't need to manually trigger it for normal operation.

## Database Schema

The service uses the existing `sms_queue` table:

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

## How It Works

1. **Reservation Created**: When a customer submits a card reservation online, a database trigger automatically inserts an SMS job into `sms_queue` with confirmation details

2. **Polling**: The Raspberry Pi service polls the `sms_queue` table every 5 seconds (configurable)

3. **Processing**: It fetches pending SMS ordered by priority (highest first) and creation time

4. **Sending**: For each SMS, it sends via SIM900A using AT commands

5. **Status Update**: After sending, it updates the status to 'sent' or 'failed' with timestamp

6. **Retry Logic**: Failed SMS are retried up to 3 times before being marked as permanently failed

## Troubleshooting

### SIM900A Not Responding

```bash
# Check serial port permissions
ls -l /dev/ttyS0
# Should show crw-rw---- with dialout group

# Add user to dialout group
sudo usermod -a -G dialout pi

# Test with minicom
sudo apt install minicom
sudo minicom -D /dev/ttyS0 -b 9600
# Type 'AT' and press Enter, should get 'OK'
```

### Database Connection Issues

```bash
# Test connection
psql $DATABASE_URL -c "SELECT 1"

# Check if port is open
telnet db-host 5432
```

### SMS Not Sending

- Check SIM card has credit and SMS enabled
- Verify antenna is properly connected
- Check signal strength: Send `AT+CSQ` command
- Ensure phone number format is correct (e.g., `09123456789` for Philippines)

### Service Not Starting

```bash
# Check logs
sudo journalctl -u sms-service -n 50

# Test manually
sudo -u pi python3 /home/pi/raspberry-pi-sms-service.py
```

## Monitoring

View SMS queue status:

```sql
-- Check pending SMS
SELECT * FROM sms_queue WHERE status = 'pending' ORDER BY priority DESC, created_at;

-- Check failed SMS
SELECT * FROM sms_queue WHERE status = 'failed' ORDER BY failed_at DESC;

-- Check success rate
SELECT
  status,
  COUNT(*) as count,
  AVG(EXTRACT(EPOCH FROM (sent_at - created_at))) as avg_send_time_seconds
FROM sms_queue
WHERE sent_at IS NOT NULL
GROUP BY status;
```

## Security Considerations

1. **Database Credentials**: Use environment variables, never hardcode passwords
2. **Network**: If accessing remote database, use SSL/TLS
3. **Firewall**: Restrict database access to Raspberry Pi IP only
4. **SIM Card**: Enable PIN lock on SIM card to prevent unauthorized use

## Customization

### Change Poll Interval

Edit `POLL_INTERVAL` in the script (default: 5 seconds)

### Change Serial Port

Edit `SERIAL_PORT` if using USB adapter:
```python
SERIAL_PORT = '/dev/ttyUSB0'  # or '/dev/ttyACM0'
```

### Customize SMS Message

Edit the trigger in `database/schema.sql`:
```sql
'Reservation Confirmed! ID: ' || NEW.reservation_id || '. Card Type: ' || NEW.card_type || '. Pickup: ' || NEW.pickup_terminal || '. Claim within 7 days. Thank you for using CommutAI!'
```

## License

Part of CommutAI Public Dashboard project
