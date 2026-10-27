-- Add SMS approval workflow
-- Run this in your Supabase SQL Editor

-- Step 1: Add approval columns to sms_queue table
DO $$
BEGIN
  -- Add approved_at column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'approved_at'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN approved_at TIMESTAMPTZ;
  END IF;

  -- Add approved_by column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'approved_by'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN approved_by TEXT;
  END IF;

  -- Add approval_deadline column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'approval_deadline'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN approval_deadline TIMESTAMPTZ;
  END IF;

  -- Add auto_approve_after_hours column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'sms_queue'
    AND column_name = 'auto_approve_after_hours'
  ) THEN
    ALTER TABLE sms_queue ADD COLUMN auto_approve_after_hours INTEGER DEFAULT 48;
  END IF;
END $$;

-- Step 2: Update status constraint to include approval statuses
ALTER TABLE sms_queue
DROP CONSTRAINT IF EXISTS sms_queue_status_check;

ALTER TABLE sms_queue
ADD CONSTRAINT sms_queue_status_check
CHECK (status IN ('awaiting_approval', 'approved', 'pending', 'sent', 'failed', 'cancelled'));

-- Step 3: Update existing pending SMS to approved (for backward compatibility)
UPDATE sms_queue
SET status = 'approved'
WHERE status = 'pending'
AND sent_at IS NOT NULL;

-- Step 4: Update existing pending SMS to awaiting_approval (for those not yet sent)
UPDATE sms_queue
SET status = 'awaiting_approval',
    approval_deadline = created_at + INTERVAL '48 hours'
WHERE status = 'pending'
AND sent_at IS NULL;
