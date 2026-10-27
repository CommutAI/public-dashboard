-- Add SMS trigger for card reservations
-- Run this in your Supabase SQL Editor

-- Step 1: Add missing columns to sms_queue table
DO $$
BEGIN
  -- Add priority column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'priority'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN priority INTEGER DEFAULT 5;
  END IF;

  -- Add related_id column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'related_id'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN related_id UUID;
  END IF;

  -- Add trip_id column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'trip_id'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN trip_id UUID;
  END IF;

  -- Add sent_at column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'sent_at'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN sent_at TIMESTAMPTZ;
  END IF;

  -- Add failed_at column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'failed_at'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN failed_at TIMESTAMPTZ;
  END IF;

  -- Add error_message column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'error_message'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN error_message TEXT;
  END IF;

  -- Add retry_count column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'retry_count'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN retry_count INTEGER DEFAULT 0;
  END IF;

  -- Add max_retries column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'max_retries'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN max_retries INTEGER DEFAULT 3;
  END IF;
END $$;

-- Step 2: Update existing rows to valid sms_type values if needed
UPDATE sms_queue
SET sms_type = 'other'
WHERE sms_type NOT IN ('emergency', 'alighting', 'other', 'admin', 'test', 'reservation_confirmation', 'card_approved', 'card_declined', 'emergency_bus', 'trip_completion', 'topup', 'card_reserved', 'card_claimed');

-- Step 3: Drop existing constraint if it exists
ALTER TABLE sms_queue
DROP CONSTRAINT IF EXISTS sms_queue_sms_type_check;

-- Step 4: Add the constraint with all types
ALTER TABLE sms_queue
ADD CONSTRAINT sms_queue_sms_type_check
CHECK (sms_type IN ('emergency', 'alighting', 'other', 'admin', 'test', 'reservation_confirmation', 'card_approved', 'card_declined', 'emergency_bus', 'trip_completion', 'topup', 'card_reserved', 'card_claimed'));

-- Step 5: Add priority constraint if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'sms_queue_priority_check'
  ) THEN
    ALTER TABLE sms_queue ADD CONSTRAINT sms_queue_priority_check CHECK (priority BETWEEN 1 AND 10);
  END IF;
END $$;

-- Step 6: Add status constraint if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'sms_queue_status_check'
  ) THEN
    ALTER TABLE sms_queue ADD CONSTRAINT sms_queue_status_check CHECK (status IN ('pending', 'sent', 'failed', 'cancelled'));
  END IF;
END $$;

-- Step 7: Create function to queue SMS when card reservation is created
CREATE OR REPLACE FUNCTION queue_sms_on_card_reserved()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Trigger on INSERT (new reservation)
  INSERT INTO sms_queue (phone_number, message, sms_type, priority, related_id)
  VALUES (
    NEW.contact,
    'Reservation Confirmed! ID: ' || NEW.reservation_id || '. Card Type: ' || NEW.card_type || '. Pickup: ' || NEW.pickup_terminal || '. Approval within 1-2 days. Thank you for using CommutAI!',
    'card_reserved',
    7, -- High priority for reservation confirmations
    gen_random_uuid()::UUID
  );
  RETURN NEW;
END;
$$;

-- Step 8: Create trigger
DROP TRIGGER IF EXISTS on_card_reservation_created ON card_reservations;
CREATE TRIGGER on_card_reservation_created
  AFTER INSERT ON card_reservations
  FOR EACH ROW EXECUTE FUNCTION queue_sms_on_card_reserved();
