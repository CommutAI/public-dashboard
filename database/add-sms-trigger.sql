-- Add SMS trigger for card reservations
-- Run this in your Supabase SQL Editor

-- Update sms_queue type to include 'card_reserved'
ALTER TABLE sms_queue
DROP CONSTRAINT IF EXISTS sms_queue_type_check;

ALTER TABLE sms_queue
ADD CONSTRAINT sms_queue_type_check
CHECK (type IN ('emergency', 'alighting', 'card_reserved', 'card_claimed', 'other'));

-- Create function to queue SMS when card reservation is created
CREATE OR REPLACE FUNCTION queue_sms_on_card_reserved()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Trigger on INSERT (new reservation)
  INSERT INTO sms_queue (phone_number, message, type, priority, related_id)
  VALUES (
    NEW.contact,
    'Reservation Confirmed! ID: ' || NEW.reservation_id || '. Card Type: ' || NEW.card_type || '. Pickup: ' || NEW.pickup_terminal || '. Claim within 7 days. Thank you for using CommutAI!',
    'card_reserved',
    7, -- High priority for reservation confirmations
    gen_random_uuid()::UUID
  );
  RETURN NEW;
END;
$$;

-- Create trigger
DROP TRIGGER IF EXISTS on_card_reservation_created ON card_reservations;
CREATE TRIGGER on_card_reservation_created
  AFTER INSERT ON card_reservations
  FOR EACH ROW EXECUTE FUNCTION queue_sms_on_card_reserved();
