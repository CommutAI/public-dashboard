-- Update SMS queue type constraint to include all needed types
-- Run this in Supabase SQL editor

-- Step 1: Check what types currently exist in the table
SELECT DISTINCT type FROM sms_queue;

-- Step 2: Update any existing rows with invalid types to 'other'
-- This ensures all existing rows will satisfy the new constraint
UPDATE sms_queue
SET type = 'other'
WHERE type NOT IN ('emergency', 'alighting', 'other', 'admin', 'test', 'reservation_confirmation', 'card_approved', 'card_declined', 'emergency_bus', 'trip_completion', 'topup');

-- Step 3: Drop the existing constraint if it exists
ALTER TABLE sms_queue DROP CONSTRAINT IF EXISTS sms_queue_type_check;

-- Step 4: Add the updated constraint with all types
ALTER TABLE sms_queue
ADD CONSTRAINT sms_queue_type_check
CHECK (type IN ('emergency', 'alighting', 'other', 'admin', 'test', 'reservation_confirmation', 'card_approved', 'card_declined', 'emergency_bus', 'trip_completion', 'topup'));

-- Step 5: Verify the constraint was added successfully
SELECT constraint_name, check_clause
FROM information_schema.check_constraints
WHERE constraint_name = 'sms_queue_type_check';
