# SMS Queue System Setup

This document describes how to set up the database-driven SMS queue system for the CommutAI public dashboard.

## Overview

The SMS queue system decouples the frontend from the SMS sending infrastructure:
- **Frontend**: Queues SMS messages to Supabase `sms_queue` table
- **Raspberry Pi**: Polls the queue and sends SMS via GSM modem or SMS gateway
- **Benefits**: No direct API calls from frontend, better error handling, retry logic, and scalability

## Architecture

```
Frontend (React) → Supabase (sms_queue table) ← Raspberry Pi (SMS Processor) → GSM Modem/SMS Gateway
```

## Database Schema

The `sms_queue` table stores SMS messages with the following fields:

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| phone_number | TEXT | Recipient phone number |
| message | TEXT | SMS message content |
| type | TEXT | Message type (emergency, alighting, other) |
| priority | INTEGER | Priority level (1-10, higher = more important) |
| related_id | UUID | Optional related entity ID |
| trip_id | UUID | Optional trip ID |
| status | TEXT | pending, sent, failed, cancelled |
| created_at | TIMESTAMPTZ | Queue timestamp |
| sent_at | TIMESTAMPTZ | Sent timestamp |
| failed_at | TIMESTAMPTZ | Failed timestamp |
| error_message | TEXT | Error details if failed |
| retry_count | INTEGER | Number of retry attempts |
| max_retries | INTEGER | Maximum retry attempts (default: 3) |

## Raspberry Pi Setup

### 1. Install Dependencies

```bash
# Install Python 3 (if not already installed)
sudo apt update
sudo apt install python3 python3-pip

# Install required packages
pip3 install -r raspberry-pi-requirements.txt

# For GSM modem support (optional)
sudo apt install gammu gammu-smsd
```

### 2. Configure Environment Variables

Create `/home/pi/.sms-processor.env`:

```bash
# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key

# SMS Configuration
SMS_POLL_INTERVAL=5  # Poll interval in seconds
MAX_CONCURRENT_SMS=3  # Max SMS to process per poll

# SMS Gateway Configuration (if using external gateway)
SMS_GATEWAY_URL=https://your-sms-gateway.com/api/send
SMS_GATEWAY_API_KEY=your-gateway-api-key
```

Load environment variables:

```bash
# Add to ~/.bashrc
echo 'source /home/pi/.sms-processor.env' >> ~/.bashrc
source ~/.bashrc
```

### 3. GSM Modem Setup (Optional)

If using a GSM modem directly connected to the Raspberry Pi:

```bash
# Install GSM utilities
sudo apt install minicom

# Test modem connection
sudo minicom -D /dev/ttyUSB0 -b 115200

# Configure gammu (if using gammu)
sudo gammu-config
```

Create `/etc/gammurc`:

```ini
[gammu]
port = /dev/ttyUSB0
connection = at115200
model = auto
synchronizetime = yes
logfile = /var/log/gammu.log
logformat = textall
```

### 4. Set Up as System Service

Create `/etc/systemd/system/sms-processor.service`:

```ini
[Unit]
Description=SMS Queue Processor
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/public-dashboard
EnvironmentFile=/home/pi/.sms-processor.env
ExecStart=/usr/bin/python3 /home/pi/public-dashboard/raspberry-pi-sms-processor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable sms-processor
sudo systemctl start sms-processor
sudo systemctl status sms-processor
```

### 5. Monitor Logs

```bash
# View logs
tail -f /var/log/sms-processor.log

# Or use journalctl
sudo journalctl -u sms-processor -f
```

## Frontend Integration

### Queue SMS from React

```typescript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY
)

async function queueSMS(phoneNumber: string, message: string, type: 'emergency' | 'alighting' | 'other') {
  const { data, error } = await supabase
    .from('sms_queue')
    .insert({
      phone_number: phoneNumber,
      message: message,
      type: type,
      priority: type === 'emergency' ? 10 : 5,
      status: 'pending'
    })

  if (error) {
    console.error('Failed to queue SMS:', error)
    return false
  }

  console.log('SMS queued successfully:', data)
  return true
}
```

### Example: Emergency Alert

```typescript
async function sendEmergencyAlert(phoneNumber: string, location: string) {
  const message = `EMERGENCY ALERT: CommutAI bus needs assistance at ${location}. Please respond immediately.`

  await queueSMS(phoneNumber, message, 'emergency')
}
```

### Example: Alighting Notification

```typescript
async function sendAlightingNotification(phoneNumber: string, stopName: string) {
  const message = `Your bus is approaching ${stopName}. Please prepare to alight.`

  await queueSMS(phoneNumber, message, 'alighting')
}
```

## SMS Gateway Integration

If using an external SMS gateway instead of a GSM modem, configure the gateway API:

### Example Gateway: Twilio

```python
# In raspberry-pi-sms-processor.py
def send_sms_via_gateway(phone_number: str, message: str) -> tuple[bool, Optional[str]]:
    try:
        from twilio.rest import Client

        client = Client(
            os.getenv('TWILIO_ACCOUNT_SID'),
            os.getenv('TWILIO_AUTH_TOKEN')
        )

        message = client.messages.create(
            body=message,
            from_=os.getenv('TWILIO_PHONE_NUMBER'),
            to=phone_number
        )

        logger.info(f"SMS sent via Twilio: {message.sid}")
        return True, None

    except Exception as e:
        logger.error(f"Twilio error: {e}")
        return False, str(e)
```

Update requirements:

```txt
twilio>=8.0.0
```

## Monitoring and Maintenance

### Check Queue Status

```sql
-- View pending messages
SELECT * FROM sms_queue WHERE status = 'pending' ORDER BY priority DESC, created_at ASC;

-- View failed messages
SELECT * FROM sms_queue WHERE status = 'failed';

-- View success rate
SELECT
  status,
  COUNT(*) as count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM sms_queue
GROUP BY status;
```

### Manual Retry Failed Messages

```sql
UPDATE sms_queue
SET status = 'pending', retry_count = 0, error_message = NULL
WHERE status = 'failed' AND retry_count < max_retries;
```

### Cleanup Old Messages

The processor automatically cleans up messages older than 30 days. To manually clean up:

```sql
DELETE FROM sms_queue
WHERE created_at < NOW() - INTERVAL '30 days'
  AND status IN ('sent', 'failed');
```

## Troubleshooting

### Processor Not Starting

```bash
# Check service status
sudo systemctl status sms-processor

# View logs
sudo journalctl -u sms-processor -n 50

# Check Python syntax
python3 -m py_compile raspberry-pi-sms-processor.py
```

### GSM Modem Not Detected

```bash
# Check USB devices
lsusb

# Check serial ports
ls -l /dev/ttyUSB*

# Test modem with minicom
sudo minicom -D /dev/ttyUSB0 -b 115200
```

### SMS Not Sending

```bash
# Check if service is running
sudo systemctl status sms-processor

# Check for errors in logs
tail -f /var/log/sms-processor.log

# Test GSM manually
echo "Test message" | sudo gammu sendsms TEXT +639123456789
```

### Supabase Connection Issues

```bash
# Test connection
curl -H "apikey: YOUR_SERVICE_KEY" \
     -H "Authorization: Bearer YOUR_SERVICE_KEY" \
     YOUR_SUPABASE_URL/rest/sms_queue?select=*

# Check environment variables
echo $SUPABASE_URL
echo $SUPABASE_SERVICE_KEY
```

## Security Considerations

1. **Service Role Key**: The Raspberry Pi uses the service role key with full database access. Keep this key secure and never commit it to version control.

2. **Phone Number Validation**: Add validation to ensure only authorized phone numbers receive SMS.

3. **Rate Limiting**: Consider implementing rate limiting to prevent SMS spam.

4. **Logging**: Ensure logs don't contain sensitive information like full phone numbers or message content in production.

## Performance Tuning

### Adjust Poll Interval

```bash
# For high-volume SMS (every 1 second)
SMS_POLL_INTERVAL=1

# For low-volume SMS (every 30 seconds)
SMS_POLL_INTERVAL=30
```

### Adjust Concurrent SMS

```bash
# For powerful hardware
MAX_CONCURRENT_SMS=10

# For limited resources
MAX_CONCURRENT_SMS=1
```

### Database Indexes

The schema includes indexes on `status`, `priority`, and `created_at` for optimal query performance:

```sql
CREATE INDEX idx_sms_queue_status ON sms_queue(status, created_at);
CREATE INDEX idx_sms_queue_priority ON sms_queue(priority, created_at);
```

## Testing

### Test SMS Queue

```typescript
// In browser console or test script
await supabase.from('sms_queue').insert({
  phone_number: '+639123456789',
  message: 'Test message from queue',
  type: 'other',
  priority: 1,
  status: 'pending'
})
```

### Test Processor

```bash
# Run processor manually for testing
python3 raspberry-pi-sms-processor.py
```

## Future Enhancements

- Add SMS delivery receipts
- Implement two-way SMS (incoming messages)
- Add SMS templates
- Implement bulk SMS sending
- Add analytics dashboard for SMS metrics
- Support multiple SMS gateways with failover
