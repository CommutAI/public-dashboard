#!/usr/bin/env python3
"""
SMS Queue Processor for Raspberry Pi
Polls Supabase for SMS messages and sends them via GSM modem or SMS gateway
"""

import os
import time
import logging
from datetime import datetime
from typing import Optional
import requests
from supabase import create_client, Client

# Configuration
SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_SERVICE_KEY = os.getenv('SUPABASE_SERVICE_KEY')
POLL_INTERVAL = int(os.getenv('SMS_POLL_INTERVAL', '5'))  # seconds
MAX_CONCURRENT_SMS = int(os.getenv('MAX_CONCURRENT_SMS', '3'))

# SMS Gateway Configuration (if using external gateway)
SMS_GATEWAY_URL = os.getenv('SMS_GATEWAY_URL')
SMS_GATEWAY_API_KEY = os.getenv('SMS_GATEWAY_API_KEY')

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/sms-processor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Initialize Supabase client
supabase: Optional[Client] = None

def init_supabase():
    """Initialize Supabase client with service role key"""
    global supabase
    try:
        if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
            raise ValueError("SUPABASE_URL and SUPABASE_SERVICE_KEY must be set")

        supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
        logger.info("Supabase client initialized successfully")
        return True
    except Exception as e:
        logger.error(f"Failed to initialize Supabase: {e}")
        return False

def send_sms_via_gateway(phone_number: str, message: str) -> tuple[bool, Optional[str]]:
    """
    Send SMS via external SMS gateway API
    Returns (success, error_message)
    """
    try:
        if not SMS_GATEWAY_URL or not SMS_GATEWAY_API_KEY:
            raise ValueError("SMS gateway not configured")

        response = requests.post(
            SMS_GATEWAY_URL,
            json={
                'api_key': SMS_GATEWAY_API_KEY,
                'phone_number': phone_number,
                'message': message
            },
            timeout=30
        )

        if response.status_code == 200:
            logger.info(f"SMS sent successfully to {phone_number}")
            return True, None
        else:
            error_msg = f"SMS gateway returned status {response.status_code}: {response.text}"
            logger.error(error_msg)
            return False, error_msg

    except requests.exceptions.Timeout:
        error_msg = "SMS gateway request timed out"
        logger.error(error_msg)
        return False, error_msg
    except Exception as e:
        error_msg = f"Error sending SMS via gateway: {e}"
        logger.error(error_msg)
        return False, error_msg

def send_sms_via_gsm(phone_number: str, message: str) -> tuple[bool, Optional[str]]:
    """
    Send SMS via GSM modem connected to Raspberry Pi
    Requires: gammu-smsd or pyserial
    Returns (success, error_message)
    """
    try:
        # Try using gammu library if available
        try:
            import gammu
            sm = gammu.StateMachine()
            sm.ReadConfig()
            sm.Init()

            sms = {
                'Number': phone_number,
                'SMS': {'Text': message}
            }
            sm.SendSMS(sms)
            logger.info(f"SMS sent via GSM to {phone_number}")
            return True, None

        except ImportError:
            # Fallback to serial communication
            import serial

            # Configure serial port for GSM modem
            ser = serial.Serial(
                port='/dev/ttyUSB0',  # Change based on your setup
                baudrate=115200,
                timeout=5
            )

            # Send AT commands
            ser.write(b'ATZ\r')  # Reset modem
            time.sleep(1)
            ser.write(b'AT+CMGF=1\r')  # Set text mode
            time.sleep(1)
            ser.write(f'AT+CMGS="{phone_number}"\r'.encode())
            time.sleep(1)
            ser.write(f'{message}\x1A'.encode())  # Send message with Ctrl+Z
            time.sleep(5)

            response = ser.read_all().decode()
            ser.close()

            if 'OK' in response or '+CMGS:' in response:
                logger.info(f"SMS sent via GSM serial to {phone_number}")
                return True, None
            else:
                error_msg = f"GSM modem error: {response}"
                logger.error(error_msg)
                return False, error_msg

    except Exception as e:
        error_msg = f"Error sending SMS via GSM: {e}"
        logger.error(error_msg)
        return False, error_msg

def send_sms(phone_number: str, message: str) -> tuple[bool, Optional[str]]:
    """
    Send SMS using configured method (gateway or GSM)
    Returns (success, error_message)
    """
    # Try SMS gateway first if configured
    if SMS_GATEWAY_URL and SMS_GATEWAY_API_KEY:
        success, error = send_sms_via_gateway(phone_number, message)
        if success:
            return True, None
        logger.warning(f"SMS gateway failed, trying GSM: {error}")

    # Fallback to GSM modem
    return send_sms_via_gsm(phone_number, message)

def process_sms_queue():
    """Fetch and process pending SMS messages from queue"""
    try:
        # Fetch pending SMS messages, ordered by priority and creation time
        response = supabase.table('sms_queue').select('*').eq('status', 'pending').order('priority', desc=True).order('created_at', asc=True).limit(MAX_CONCURRENT_SMS).execute()

        messages = response.data

        if not messages:
            logger.debug("No pending SMS messages in queue")
            return

        logger.info(f"Found {len(messages)} pending SMS messages")

        for msg in messages:
            try:
                # Send the SMS
                success, error = send_sms(msg['phone_number'], msg['message'])

                if success:
                    # Update status to sent
                    supabase.table('sms_queue').update({
                        'status': 'sent',
                        'sent_at': datetime.utcnow().isoformat()
                    }).eq('id', msg['id']).execute()
                    logger.info(f"SMS {msg['id']} marked as sent")
                else:
                    # Update status to failed and increment retry count
                    retry_count = msg.get('retry_count', 0) + 1
                    max_retries = msg.get('max_retries', 3)

                    if retry_count >= max_retries:
                        # Mark as permanently failed
                        supabase.table('sms_queue').update({
                            'status': 'failed',
                            'failed_at': datetime.utcnow().isoformat(),
                            'error_message': error,
                            'retry_count': retry_count
                        }).eq('id', msg['id']).execute()
                        logger.error(f"SMS {msg['id']} permanently failed after {retry_count} retries")
                    else:
                        # Keep as pending for retry
                        supabase.table('sms_queue').update({
                            'error_message': error,
                            'retry_count': retry_count
                        }).eq('id', msg['id']).execute()
                        logger.warning(f"SMS {msg['id']} failed (attempt {retry_count}/{max_retries}): {error}")

            except Exception as e:
                logger.error(f"Error processing SMS {msg['id']}: {e}")
                # Update with error but keep as pending for retry
                try:
                    supabase.table('sms_queue').update({
                        'error_message': str(e),
                        'retry_count': msg.get('retry_count', 0) + 1
                    }).eq('id', msg['id']).execute()
                except:
                    pass

    except Exception as e:
        logger.error(f"Error fetching SMS queue: {e}")

def cleanup_old_messages():
    """Clean up old sent/failed messages (optional)"""
    try:
        # Delete messages older than 30 days that are sent or failed
        cutoff_date = datetime.utcnow().replace(day=datetime.utcnow().day - 30)

        response = supabase.table('sms_queue').delete().lt('created_at', cutoff_date.isoformat()).in_('status', ['sent', 'failed']).execute()

        if response.data:
            logger.info(f"Cleaned up {len(response.data)} old SMS messages")

    except Exception as e:
        logger.error(f"Error cleaning up old messages: {e}")

def main():
    """Main processing loop"""
    logger.info("Starting SMS Queue Processor")

    if not init_supabase():
        logger.error("Failed to initialize Supabase, exiting")
        return

    logger.info(f"Polling interval: {POLL_INTERVAL} seconds")
    logger.info(f"Max concurrent SMS: {MAX_CONCURRENT_SMS}")

    try:
        while True:
            process_sms_queue()

            # Run cleanup every hour (3600 seconds / poll_interval)
            if int(time.time()) % 3600 < POLL_INTERVAL:
                cleanup_old_messages()

            time.sleep(POLL_INTERVAL)

    except KeyboardInterrupt:
        logger.info("Shutting down SMS Queue Processor")
    except Exception as e:
        logger.error(f"Fatal error in main loop: {e}")

if __name__ == '__main__':
    main()
