-- Add SMS Queue table to existing database
-- Run this in Supabase SQL Editor only if table doesn't exist

-- Check if table exists, if not create it
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'sms_queue') THEN
    CREATE TABLE sms_queue (
      id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      phone_number    TEXT        NOT NULL,
      message         TEXT        NOT NULL,
      type            TEXT        NOT NULL CHECK (type IN ('emergency', 'alighting', 'other', 'card_reserved', 'card_claimed')),
      priority        INTEGER     DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),
      related_id      UUID,
      trip_id         UUID,
      status          TEXT        DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'cancelled')),
      created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      sent_at         TIMESTAMPTZ,
      failed_at       TIMESTAMPTZ,
      error_message   TEXT,
      retry_count     INTEGER     DEFAULT 0,
      max_retries     INTEGER     DEFAULT 3
    );

    -- Enable RLS
    ALTER TABLE sms_queue ENABLE ROW LEVEL SECURITY;

    -- Create policy for service role access
    CREATE POLICY "Service role SMS queue access" ON sms_queue FOR ALL
      USING (true)
      WITH CHECK (true);

    -- Create indexes
    CREATE INDEX idx_sms_queue_status ON sms_queue(status, created_at);
    CREATE INDEX idx_sms_queue_priority ON sms_queue(priority, created_at);

    -- Add to realtime publication
    ALTER PUBLICATION supabase_realtime ADD TABLE sms_queue;

    RAISE NOTICE 'sms_queue table created successfully';
  ELSE
    RAISE NOTICE 'sms_queue table already exists';
  END IF;
END $$;

-- If table already exists, update the check constraint to include missing types
DO $$
BEGIN
  -- Drop existing constraint if it exists
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sms_queue_type_check'
  ) THEN
    ALTER TABLE sms_queue DROP CONSTRAINT sms_queue_type_check;
  END IF;

  -- Add updated constraint with all required types
  ALTER TABLE sms_queue
  ADD CONSTRAINT sms_queue_type_check
  CHECK (type IN ('emergency', 'alighting', 'other', 'card_reserved', 'card_claimed'));

  RAISE NOTICE 'sms_queue type check constraint updated';
END $$;
