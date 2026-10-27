-- Add SMS Queue table to existing database
-- Run this in Supabase SQL Editor

-- Create sms_type enum if it doesn't exist
DO $$ BEGIN
  CREATE TYPE sms_type_enum AS ENUM ('emergency', 'alighting', 'other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Create sms_queue table
CREATE TABLE IF NOT EXISTS sms_queue (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number    TEXT        NOT NULL,
  message         TEXT        NOT NULL,
  sms_type        sms_type_enum NOT NULL,
  priority        INTEGER     DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),
  related_id      UUID,
  trip_id         UUID,
  status          TEXT        DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'cancelled')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at         TIMESTAMPTZ,
  failed_at       TIMESTAMPTZ,
  error_message   TEXT,
  attempts        INTEGER     DEFAULT 0,
  max_attempts    INTEGER     DEFAULT 3
);

-- Enable RLS
ALTER TABLE sms_queue ENABLE ROW LEVEL SECURITY;

-- Create policy for service role access
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sms_queue' AND policyname = 'Service role SMS queue access') THEN
    CREATE POLICY "Service role SMS queue access" ON sms_queue FOR ALL
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_sms_queue_status ON sms_queue(status, created_at);
CREATE INDEX IF NOT EXISTS idx_sms_queue_priority ON sms_queue(priority, created_at);

-- Add to realtime publication (optional)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'sms_queue') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE sms_queue;
  END IF;
END $$;
