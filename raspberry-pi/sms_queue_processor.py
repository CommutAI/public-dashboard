#!/usr/bin/env python3
"""
SMS Queue Processor for CommuteAI
Polls Supabase for pending SMS messages and sends them via SIM900
"""

import os
import sys
import time
import logging
from datetime import datetime
from typing import Dict, List
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
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

    def send_sms(self, phone_number: str, message: str) -> bool:
        """Send SMS via SIM900"""
        if not self.connected:
            logger.error("Cannot send SMS - SIM900A not connected")
            return False

        try:
            normalized_phone = self._normalize_phone_number(phone_number)
            logger.info(f"Sending SMS to {normalized_phone}: {message[:50]}...")

            # Check SIM registration
            reg_check = self._send_at_command('AT+CREG?')

            # Check signal strength
            csq_check = self._send_at_command('AT+CSQ')

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

            if 'OK' in response:
                logger.info(f"SMS sent successfully to {normalized_phone}")
                return True
            else:
                logger.error(f"Failed to send SMS to {normalized_phone}: {response}")
                return False

        except Exception as e:
            logger.error(f"SMS sending error: {e}")
            return False

    def fetch_pending_sms(self) -> List[Dict]:
        """Fetch pending SMS from Supabase"""
        if not self.supabase:
            logger.warning("Cannot fetch SMS - Supabase not initialized")
            return []

        try:
            response = self.supabase.table('sms_queue').select('*').eq('status', 'pending').order('created_at').limit(10).execute()

            if response.data:
                logger.info(f"Fetched {len(response.data)} pending SMS messages")
                return response.data
            else:
                return []

        except Exception as e:
            logger.error(f"Failed to fetch pending SMS: {e}")
            return []

    def update_sms_status(self, sms_id: str, status: str, error_message: str = None):
        """Update SMS status in Supabase"""
        if not self.supabase:
            return

        try:
            update_data = {'status': status}

            if status == 'sent':
                update_data['sent_at'] = datetime.now().isoformat()
            elif status == 'failed':
                update_data['failed_at'] = datetime.now().isoformat()
                if error_message:
                    update_data['error_message'] = error_message

            # Increment attempts
            current = self.supabase.table('sms_queue').select('attempts').eq('id', sms_id).execute()
            if current.data and len(current.data) > 0:
                current_attempts = current.data[0].get('attempts', 0)
                update_data['attempts'] = current_attempts + 1

            self.supabase.table('sms_queue').update(update_data).eq('id', sms_id).execute()
            logger.debug(f"Updated SMS {sms_id} status to {status}")

        except Exception as e:
            logger.error(f"Failed to update SMS status: {e}")

    def process_queue(self):
        """Process pending SMS messages"""
        pending_sms = self.fetch_pending_sms()

        for sms in pending_sms:
            sms_id = sms['id']
            phone_number = sms['phone_number']
            message = sms['message']
            sms_type = sms.get('sms_type', 'unknown')
            attempts = sms.get('attempts', 0)
            max_retries = sms.get('max_retries', 3)

            logger.info(f"Processing SMS {sms_id} ({sms_type})")

            # Check if exceeded max retries
            if attempts >= max_retries:
                logger.warning(f"SMS {sms_id} exceeded max retries, marking as failed")
                self.update_sms_status(sms_id, 'failed', 'Max retries exceeded')
                continue

            # Send SMS
            success = self.send_sms(phone_number, message)

            # Update status
            if success:
                self.update_sms_status(sms_id, 'sent')
            else:
                self.update_sms_status(sms_id, 'failed', 'Failed to send via SIM900')

            # Small delay between messages
            time.sleep(2)

    def run(self):
        """Main loop - continuously poll and process SMS queue"""
        logger.info("Starting SMS queue processor...")

        if not self.supabase:
            logger.error("Cannot start - Supabase not initialized")
            return

        if not self.connected:
            logger.warning("Starting without SIM900 - will fail to send SMS")

        while True:
            try:
                self.process_queue()
                logger.info(f"Sleeping for {self.poll_interval} seconds...")
                time.sleep(self.poll_interval)
            except KeyboardInterrupt:
                logger.info("Shutting down...")
                break
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
    print(f"  SIM900: {'Connected' if processor.connected else 'Not connected'}")
    print(f"  Poll Interval: {processor.poll_interval} seconds")
    print()

    try:
        processor.run()
    finally:
        processor.disconnect()


if __name__ == "__main__":
    main()
