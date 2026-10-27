#!/usr/bin/env python3
"""
SMS Queue Processor for CommuteAI
Polls Supabase for pending SMS messages and sends them via SIM900A
"""

import os
import sys
import time
import logging
from datetime import datetime
from typing import Dict, List, Optional
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/sms-processor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Try to import required modules
try:
    import serial
    SERIAL_AVAILABLE = True
except ImportError:
    SERIAL_AVAILABLE = False
    logger.error("pyserial not installed. Install with: pip install pyserial")

try:
    from supabase import create_client
    SUPABASE_AVAILABLE = True
except ImportError:
    SUPABASE_AVAILABLE = False
    logger.error("supabase not installed. Install with: pip install supabase")


class SMSQueueProcessor:
    """Processes SMS queue from Supabase"""

    def __init__(self):
        self.serial_connection = None
        self.connected = False
        self.supabase = None

        # Configuration
        self.port = os.getenv('SIM900A_PORT', '/dev/ttyUSB0')
        self.baudrate = int(os.getenv('SIM900A_BAUDRATE', '9600'))
        self.supabase_url = os.getenv('SUPABASE_URL')
        self.supabase_key = os.getenv('SUPABASE_KEY')
        self.poll_interval = int(os.getenv('SMS_POLL_INTERVAL', '30'))  # seconds
        self.max_concurrent = int(os.getenv('MAX_CONCURRENT_SMS', '3'))

        # Initialize
        self._init_supabase()
        self._connect_hardware()

    def _init_supabase(self):
        """Initialize Supabase client"""
        if not SUPABASE_AVAILABLE:
            logger.warning("Supabase client not available")
            return

        if not self.supabase_url or not self.supabase_key:
            logger.warning("Supabase credentials not configured")
            return

        try:
            self.supabase = create_client(self.supabase_url, self.supabase_key)
            logger.info("Supabase client initialized")
        except Exception as e:
            logger.error(f"Failed to initialize Supabase: {e}")

    def _connect_hardware(self) -> bool:
        """Connect to SIM900A module"""
        if not SERIAL_AVAILABLE:
            logger.error("Serial library not available")
            return False

        try:
            self.serial_connection = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                timeout=2
            )

            # Test connection
            self.serial_connection.write(b'AT\r')
            time.sleep(0.5)
            response = self.serial_connection.read(100).decode('utf-8', errors='ignore')

            if 'OK' in response:
                self.connected = True
                logger.info(f"SIM900A connected on {self.port} @ {self.baudrate} baud")
                return True
            else:
                logger.error(f"SIM900A did not respond with OK. Response: {response}")
                return False

        except serial.SerialException as e:
            logger.error(f"Failed to connect to SIM900A: {e}")
            return False
        except Exception as e:
            logger.error(f"Hardware connection error: {e}")
            return False

    def _normalize_phone_number(self, phone_number: str) -> str:
        """Normalize phone number to international format"""
        phone_number = phone_number.replace(' ', '').replace('-', '').replace('(', '').replace(')', '')

        if phone_number.startswith('0'):
            phone_number = '+63' + phone_number[1:]
        elif phone_number.startswith('63') and not phone_number.startswith('+'):
            phone_number = '+' + phone_number
        elif not phone_number.startswith('+'):
            phone_number = '+63' + phone_number

        return phone_number

    def _send_at_command(self, command: str, timeout: float = 1.0) -> str:
        """Send AT command and return response"""
        if not self.connected or not self.serial_connection:
            logger.error("SIM900A not connected")
            return ""

        try:
            self.serial_connection.write((command + '\r').encode())
            time.sleep(timeout)
            response = self.serial_connection.read(200).decode('utf-8', errors='ignore').strip()
            return response
        except Exception as e:
            logger.error(f"AT command error: {e}")
            return ""

    def send_sms(self, phone_number: str, message: str) -> tuple[bool, Optional[str]]:
        """Send SMS via SIM900A
        Returns (success, error_message)
        """
        if not self.connected:
            error_msg = "Cannot send SMS - SIM900A not connected"
            logger.error(error_msg)
            return False, error_msg

        try:
            normalized_phone = self._normalize_phone_number(phone_number)
            logger.info(f"Sending SMS to {normalized_phone}: {message[:50]}...")

            # Check SIM registration
            reg_check = self._send_at_command('AT+CREG?')
            logger.debug(f"SIM Registration: {reg_check}")

            # Check signal strength
            csq_check = self._send_at_command('AT+CSQ')
            logger.debug(f"Signal Quality: {csq_check}")

            # Set SMS mode to text
            self._send_at_command('AT+CMGF=1')
            time.sleep(0.5)

            # Set recipient
            self._send_at_command(f'AT+CMGS="{normalized_phone}"')
            time.sleep(0.5)

            # Send message
            self.serial_connection.write(f'{message}\x1A'.encode())
            time.sleep(5)

            # Read response
            response = ""
            for _ in range(10):
                if self.serial_connection.in_waiting > 0:
                    response += self.serial_connection.read(self.serial_connection.in_waiting).decode('utf-8', errors='ignore')
                time.sleep(0.5)

            response = response.strip()
            logger.info(f"SIM900A response: {response}")

            if 'OK' in response or '+CMGS:' in response:
                logger.info(f"SMS sent successfully to {normalized_phone}")
                return True, None
            else:
                error_msg = f"Failed to send SMS to {normalized_phone}: {response}"
                logger.error(error_msg)
                return False, error_msg

        except Exception as e:
            error_msg = f"SMS sending error: {e}"
            logger.error(error_msg)
            return False, error_msg

    def fetch_pending_sms(self) -> List[Dict]:
        """Fetch pending SMS from Supabase"""
        if not self.supabase:
            logger.warning("Cannot fetch SMS - Supabase not initialized")
            return []

        try:
            response = self.supabase.table('sms_queue').select('*').eq('status', 'pending').order('priority', desc=True).order('created_at', asc=True).limit(self.max_concurrent).execute()

            if response.data:
                logger.info(f"Fetched {len(response.data)} pending SMS messages")
                return response.data
            else:
                logger.debug("No pending SMS messages")
                return []

        except Exception as e:
            logger.error(f"Failed to fetch pending SMS: {e}")
            return []

    def update_sms_status(self, sms_id: str, status: str, error_message: Optional[str] = None):
        """Update SMS status in Supabase"""
        if not self.supabase:
            return

        try:
            # Get current retry_count
            current = self.supabase.table('sms_queue').select('retry_count').eq('id', sms_id).execute()
            current_attempts = current.data[0]['retry_count'] if current.data else 0

            update_data = {
                'status': status,
                'retry_count': current_attempts + 1
            }

            if status == 'sent':
                update_data['sent_at'] = datetime.now().isoformat()

            if status == 'failed':
                update_data['failed_at'] = datetime.now().isoformat()

            if error_message:
                update_data['error_message'] = error_message

            self.supabase.table('sms_queue').update(update_data).eq('id', sms_id).execute()
            logger.debug(f"Updated SMS {sms_id} status to {status} (attempt {current_attempts + 1})")

        except Exception as e:
            logger.error(f"Failed to update SMS status: {e}")

    def process_queue(self):
        """Process pending SMS messages"""
        pending_sms = self.fetch_pending_sms()

        for sms in pending_sms:
            sms_id = sms['id']
            phone_number = sms['phone_number']
            message = sms['message']
            sms_type = sms.get('type', 'other')
            max_attempts = sms.get('max_retries', 3)
            current_attempts = sms.get('retry_count', 0)

            logger.info(f"Processing SMS {sms_id} ({sms_type}) - attempt {current_attempts + 1}/{max_attempts}")

            # Check if max attempts reached
            if current_attempts >= max_attempts:
                logger.warning(f"SMS {sms_id} reached max attempts ({max_attempts}), marking as failed")
                self.update_sms_status(sms_id, 'failed', 'Max retry attempts reached')
                continue

            # Send SMS
            success, error = self.send_sms(phone_number, message)

            # Update status
            if success:
                self.update_sms_status(sms_id, 'sent')
            else:
                # Check if should permanently fail
                if current_attempts + 1 >= max_attempts:
                    self.update_sms_status(sms_id, 'failed', error)
                else:
                    # Keep as pending for retry
                    try:
                        self.supabase.table('sms_queue').update({
                            'error_message': error,
                            'retry_count': current_attempts + 1
                        }).eq('id', sms_id).execute()
                        logger.warning(f"SMS {sms_id} failed (attempt {current_attempts + 1}/{max_attempts}), will retry")
                    except Exception as e:
                        logger.error(f"Failed to update retry info: {e}")

            # Small delay between messages
            time.sleep(2)

    def cleanup_old_messages(self):
        """Clean up old sent/failed messages (optional)"""
        if not self.supabase:
            return

        try:
            # Delete messages older than 30 days that are sent or failed
            from datetime import timedelta
            cutoff_date = datetime.now() - timedelta(days=30)

            response = self.supabase.table('sms_queue').delete().lt('created_at', cutoff_date.isoformat()).in_('status', ['sent', 'failed']).execute()

            if response.data:
                logger.info(f"Cleaned up {len(response.data)} old SMS messages")

        except Exception as e:
            logger.error(f"Error cleaning up old messages: {e}")

    def run(self):
        """Main loop - continuously poll and process SMS queue"""
        logger.info("Starting SMS queue processor...")

        if not self.supabase:
            logger.error("Cannot start - Supabase not initialized")
            return

        if not self.connected:
            logger.warning("Starting without SIM900A - will fail to send SMS")

        logger.info(f"Poll interval: {self.poll_interval} seconds")
        logger.info(f"Max concurrent SMS: {self.max_concurrent}")

        try:
            while True:
                self.process_queue()

                # Run cleanup every hour
                if int(time.time()) % 3600 < self.poll_interval:
                    self.cleanup_old_messages()

                logger.debug(f"Sleeping for {self.poll_interval} seconds...")
                time.sleep(self.poll_interval)

        except KeyboardInterrupt:
            logger.info("Shutting down...")
            return
        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            time.sleep(self.poll_interval)

    def disconnect(self):
        """Disconnect from hardware"""
        if self.serial_connection:
            self.serial_connection.close()
            self.connected = False
            logger.info("SIM900A disconnected")


def main():
    """Main entry point"""
    print("=" * 70)
    print("📱 SMS Queue Processor - CommuteAI")
    print("=" * 70)
    print()

    processor = SMSQueueProcessor()

    # Check status
    print("Status:")
    print(f"  Supabase: {'Connected' if processor.supabase else 'Not connected'}")
    print(f"  SIM900A: {'Connected' if processor.connected else 'Not connected'}")
    print(f"  Poll Interval: {processor.poll_interval} seconds")
    print(f"  Max Concurrent: {processor.max_concurrent}")
    print()

    try:
        processor.run()
    finally:
        processor.disconnect()


if __name__ == "__main__":
    main()
