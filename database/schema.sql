-- ============================================================
-- CommutAI · Public Dashboard Schema
-- One Manolo Fortich Transport System
-- Public-facing information and services
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 0. Custom Enum Types
-- ============================================================

-- Bus status
DO $$ BEGIN
  CREATE TYPE bus_status AS ENUM ('active', 'maintenance', 'inactive', 'out_of_service');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Trip status
DO $$ BEGIN
  CREATE TYPE trip_status AS ENUM ('scheduled', 'in_progress', 'completed', 'cancelled', 'delayed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Card types with discounts
DO $$ BEGIN
  CREATE TYPE card_type AS ENUM ('regular', 'student', 'senior_citizen', 'pwd');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 1. BUSES
-- Fleet information for public display
-- ============================================================
CREATE TABLE IF NOT EXISTS buses (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  plate_number           TEXT        NOT NULL UNIQUE,
  bus_number             INTEGER     UNIQUE,
  route                  TEXT        NOT NULL,
  seat_capacity          INTEGER     NOT NULL DEFAULT 50,
  status                 bus_status  NOT NULL DEFAULT 'active',
  bus_type               TEXT        DEFAULT 'standard', -- 'standard', 'deluxe', 'air-conditioned'
  manufacturer           TEXT,
  model_year             INTEGER,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION update_buses_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_buses_updated_at_trigger ON buses;
CREATE TRIGGER update_buses_updated_at_trigger
  BEFORE UPDATE ON buses
  FOR EACH ROW EXECUTE FUNCTION update_buses_updated_at();

-- ============================================================
-- 2. BUS STOPS
-- Physical locations along routes
-- ============================================================
CREATE TABLE IF NOT EXISTS bus_stops (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  stop_code       VARCHAR(20) UNIQUE NOT NULL,
  name            VARCHAR(100) NOT NULL,
  location        VARCHAR(100) NOT NULL,
  latitude        DECIMAL(10, 8) NOT NULL,
  longitude       DECIMAL(11, 8) NOT NULL,
  stop_type       VARCHAR(20) NOT NULL CHECK (stop_type IN ('terminal', 'regular', 'transit')),
  status          VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  sequence_order  INTEGER     NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 3. ROUTES
-- Bus routes between terminals
-- ============================================================
CREATE TABLE IF NOT EXISTS routes (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  route_code          VARCHAR(20) UNIQUE NOT NULL,
  name                VARCHAR(100) NOT NULL,
  start_stop_id       UUID        NOT NULL REFERENCES bus_stops (id),
  end_stop_id         UUID        NOT NULL REFERENCES bus_stops (id),
  total_distance_km   DECIMAL(8, 2),
  estimated_duration_minutes INTEGER,
  status              VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 4. TRIP SCHEDULES
-- Scheduled trips with departure/arrival times
-- ============================================================
CREATE TABLE IF NOT EXISTS trip_schedules (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  route_id               UUID        NOT NULL REFERENCES routes (id),
  trip_number            INTEGER     NOT NULL,
  departure_time_start   TIME        NOT NULL,
  arrival_time_start     TIME        NOT NULL,
  arrival_time_end       TIME        NOT NULL,
  departure_time_end     TIME        NOT NULL,
  days_of_operation      VARCHAR(20) NOT NULL DEFAULT 'daily',
  status                 VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(route_id, trip_number)
);

-- ============================================================
-- 5. CARD TYPES
-- Defines available card types and benefits
-- ============================================================
CREATE TABLE IF NOT EXISTS card_types (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name                VARCHAR(50) UNIQUE NOT NULL,
  card_type           VARCHAR(20) NOT NULL CHECK (card_type IN ('permanent', 'temporary')),
  discount_percentage DECIMAL(5, 2) NOT NULL DEFAULT 0,
  validity_days       INTEGER,
  description         TEXT,
  image_url           VARCHAR(255),
  status              VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 6. CARD RESERVATIONS
-- Online card reservation requests
-- ============================================================
CREATE TABLE IF NOT EXISTS card_reservations (
  id                BIGSERIAL   PRIMARY KEY,
  reservation_id    VARCHAR(50) UNIQUE NOT NULL,
  name              VARCHAR(100) NOT NULL,
  contact           VARCHAR(20) NOT NULL,
  card_type         VARCHAR(50) NOT NULL,
  pickup_terminal   VARCHAR(100) NOT NULL,
  status            VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'claimed', 'expired', 'cancelled')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at        TIMESTAMPTZ NOT NULL,
  claimed_at        TIMESTAMPTZ
);

-- ============================================================
-- 7. FARE MATRIX
-- Fare rates between stops
-- ============================================================
CREATE TABLE IF NOT EXISTS fare_matrix (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  route_from      TEXT        NOT NULL,
  route_to        TEXT        NOT NULL,
  km_distance     NUMERIC     NOT NULL,
  regular_fare    NUMERIC     NOT NULL,
  discounted_fare NUMERIC     NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT unique_route UNIQUE (route_from, route_to)
);

-- ============================================================
-- 8. BAGGAGE FEE MATRIX
-- Baggage fee structure
-- ============================================================
CREATE TABLE IF NOT EXISTS baggage_fee_matrix (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  category        TEXT        NOT NULL,
  max_weight_kg   NUMERIC     NOT NULL,
  fee             NUMERIC     NOT NULL,
  remarks         TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 9. SMS QUEUE
-- SMS queue for Raspberry Pi processing
-- ============================================================
CREATE TABLE IF NOT EXISTS sms_queue (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number    TEXT        NOT NULL,
  message         TEXT        NOT NULL,
  sms_type        TEXT        NOT NULL CHECK (sms_type IN ('emergency', 'alighting', 'other')),
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

-- ============================================================
-- 10. ANNOUNCEMENTS
-- System announcements
-- ============================================================
CREATE TABLE IF NOT EXISTS announcements (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title           TEXT        NOT NULL,
  message         TEXT        NOT NULL,
  priority        TEXT        NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'emergency')),
  is_public       BOOLEAN     NOT NULL DEFAULT TRUE,
  start_date      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_date        TIMESTAMPTZ,
  status          TEXT        NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'archived')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================

-- Buses
CREATE INDEX IF NOT EXISTS idx_buses_plate_number ON buses(plate_number);
CREATE INDEX IF NOT EXISTS idx_buses_bus_number ON buses(bus_number);
CREATE INDEX IF NOT EXISTS idx_buses_status ON buses(status);

-- Bus stops
CREATE INDEX IF NOT EXISTS idx_bus_stops_code ON bus_stops(stop_code);
CREATE INDEX IF NOT EXISTS idx_bus_stops_sequence ON bus_stops(sequence_order);
CREATE INDEX IF NOT EXISTS idx_bus_stops_status ON bus_stops(status);

-- Routes
CREATE INDEX IF NOT EXISTS idx_routes_code ON routes(route_code);
CREATE INDEX IF NOT EXISTS idx_routes_status ON routes(status);

-- Trip schedules
CREATE INDEX IF NOT EXISTS idx_trip_schedules_route ON trip_schedules(route_id);
CREATE INDEX IF NOT EXISTS idx_trip_schedules_status ON trip_schedules(status);

-- Card reservations
CREATE INDEX IF NOT EXISTS idx_card_reservations_id ON card_reservations(reservation_id);
CREATE INDEX IF NOT EXISTS idx_card_reservations_contact ON card_reservations(contact);
CREATE INDEX IF NOT EXISTS idx_card_reservations_status ON card_reservations(status);
CREATE INDEX IF NOT EXISTS idx_card_reservations_expires ON card_reservations(expires_at);

-- Fare matrix
CREATE INDEX IF NOT EXISTS idx_fare_matrix_route ON fare_matrix(route_from, route_to);

-- Baggage fee matrix
CREATE INDEX IF NOT EXISTS idx_baggage_fee_matrix_category ON baggage_fee_matrix(category);

-- SMS queue
CREATE INDEX IF NOT EXISTS idx_sms_queue_status ON sms_queue(status, created_at);
CREATE INDEX IF NOT EXISTS idx_sms_queue_priority ON sms_queue(priority, created_at);

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE buses ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE card_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE card_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE fare_matrix ENABLE ROW LEVEL SECURITY;
ALTER TABLE baggage_fee_matrix ENABLE ROW LEVEL SECURITY;
ALTER TABLE sms_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;

-- =====================
-- PUBLIC DASHBOARD POLICIES
-- Public read access to basic information
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'buses' AND policyname = 'Public read access on buses') THEN
    CREATE POLICY "Public read access on buses" ON buses FOR SELECT USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bus_stops' AND policyname = 'Public read access on bus_stops') THEN
    CREATE POLICY "Public read access on bus_stops" ON bus_stops FOR SELECT USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'routes' AND policyname = 'Public read access on routes') THEN
    CREATE POLICY "Public read access on routes" ON routes FOR SELECT USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'trip_schedules' AND policyname = 'Public read access on trip_schedules') THEN
    CREATE POLICY "Public read access on trip_schedules" ON trip_schedules FOR SELECT USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'fare_matrix' AND policyname = 'Public read access on fare_matrix') THEN
    CREATE POLICY "Public read access on fare_matrix" ON fare_matrix FOR SELECT USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'baggage_fee_matrix' AND policyname = 'Public read access on baggage_fee_matrix') THEN
    CREATE POLICY "Public read access on baggage_fee_matrix" ON baggage_fee_matrix FOR SELECT USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sms_queue' AND policyname = 'Service role SMS queue access') THEN
    CREATE POLICY "Service role SMS queue access" ON sms_queue FOR ALL
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'announcements' AND policyname = 'Public read access on announcements') THEN
    CREATE POLICY "Public read access on announcements" ON announcements FOR SELECT USING (is_public = true AND status = 'active');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'card_types' AND policyname = 'Public read access on card_types') THEN
    CREATE POLICY "Public read access on card_types" ON card_types FOR SELECT USING (true);
  END IF;
END $$;

-- Public insert for card reservations
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'card_reservations' AND policyname = 'Public insert card reservations') THEN
    CREATE POLICY "Public insert card reservations" ON card_reservations FOR INSERT WITH CHECK (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'card_reservations' AND policyname = 'Public read own reservations') THEN
    CREATE POLICY "Public read own reservations" ON card_reservations FOR SELECT USING (true);
  END IF;
END $$;

-- ============================================================
-- SEED DATA
-- ============================================================

-- Insert card types
INSERT INTO card_types (name, card_type, discount_percentage, validity_days, description) VALUES
('Regular', 'permanent', 0, 365, 'Standard fare rates'),
('Student', 'permanent', 20, 365, '20% discount on all fares'),
('Senior Citizen', 'permanent', 20, 365, 'Special discounted rates'),
('PWD', 'permanent', 20, 365, 'Maximum discount benefits'),
('TEMP REGULAR', 'temporary', 0, 7, 'Standard fare rates'),
('TEMP STUDENT', 'temporary', 20, 7, '20% discount on all fares'),
('TEMP SENIOR', 'temporary', 20, 7, 'Special discounted rates'),
('TEMP PWD', 'temporary', 20, 7, 'Maximum discount benefits')
ON CONFLICT (name) DO NOTHING;

-- Insert buses
INSERT INTO buses (plate_number, bus_number, route, seat_capacity, status) VALUES
  ('BUS-001', 1001, 'Manolo Fortich Terminal ↔ Agora Terminal', 35, 'active'),
  ('BUS-002', 1002, 'Manolo Fortich Terminal ↔ Agora Terminal', 35, 'active'),
  ('BUS-003', 1003, 'Manolo Fortich Terminal ↔ Agora Terminal', 35, 'active'),
  ('BUS-004', 1004, 'Manolo Fortich Terminal ↔ Agora Terminal', 35, 'active'),
  ('BUS-005', 1005, 'Manolo Fortich Terminal ↔ Agora Terminal', 35, 'active'),
  ('BUS-006', 1006, 'Manolo Fortich Terminal ↔ Agora Terminal', 35, 'active'),
  ('BUS-007', 1007, 'Manolo Fortich Terminal ↔ Agora Terminal', 35, 'active'),
  ('BUS-008', 1008, 'Manolo Fortich Terminal ↔ Agora Terminal', 35, 'active'),
  ('BUS-009', 1009, 'Manolo Fortich Terminal ↔ Agora Terminal', 35, 'active'),
  ('BUS-010', 1010, 'Manolo Fortich Terminal ↔ Agora Terminal', 35, 'active')
ON CONFLICT (plate_number) DO UPDATE SET
  bus_number = EXCLUDED.bus_number,
  route = EXCLUDED.route,
  seat_capacity = EXCLUDED.seat_capacity,
  status = EXCLUDED.status;

-- Insert bus stops
INSERT INTO bus_stops (stop_code, name, location, latitude, longitude, stop_type, sequence_order) VALUES
('STOP 01', 'Manolo Fortich Terminal', 'Manolo Fortich Terminal', 8.366308873785245, 124.86500795847, 'terminal', 1),
('STOP 02', 'Gaisano CDO', 'Gaisano CDO', 8.4867, 124.6500, 'regular', 2),
('STOP 03', 'Gusa', 'Gusa', 8.4757, 124.6823, 'regular', 3),
('STOP 04', 'Tablon Baloi', 'Tablon Baloi', 8.4819, 124.7286, 'regular', 4),
('STOP 05', 'Tablon', 'Tablon', 8.4819, 124.7286, 'regular', 5),
('STOP 06', 'Agusan', 'Agusan', 8.4886, 124.7382, 'regular', 6),
('STOP 07', 'Puerto', 'Puerto', 8.5010, 124.7505, 'regular', 7),
('STOP 08', 'Bae Upper Puerto', 'Bae Upper Puerto', 8.4264, 124.8092, 'regular', 8),
('STOP 09', 'Alae', 'Alae', 8.4244, 124.8128, 'regular', 9),
('STOP 10', 'Lunocan', 'Lunocan', 8.4143, 124.8231, 'regular', 10),
('STOP 11', 'San Miguel', 'San Miguel', 8.3890, 124.8332, 'regular', 11),
('STOP 12', 'Dicklum', 'Dicklum', 8.3740, 124.8480, 'regular', 12),
('STOP 13', 'Tankulan', 'Tankulan', 8.3688, 124.8641, 'regular', 13),
('STOP 14', 'Agora Terminal', 'Agora Terminal', 8.489074818449854, 124.65762898250219, 'terminal', 14)
ON CONFLICT (stop_code) DO NOTHING;

-- Insert route
INSERT INTO routes (route_code, name, start_stop_id, end_stop_id, total_distance_km, estimated_duration_minutes) VALUES
('MF-AGORA', 'Manolo Fortich to Agora Terminal',
 (SELECT id FROM bus_stops WHERE stop_code = 'STOP 01'),
 (SELECT id FROM bus_stops WHERE stop_code = 'STOP 14'),
 45.5, 90)
ON CONFLICT (route_code) DO NOTHING;

-- Insert trip schedules
INSERT INTO trip_schedules (route_id, trip_number, departure_time_start, arrival_time_start, arrival_time_end, departure_time_end) VALUES
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 1, '05:00:00', '06:30:00', '07:00:00', '05:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 2, '07:00:00', '08:30:00', '09:00:00', '07:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 3, '09:00:00', '10:30:00', '11:00:00', '09:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 4, '11:00:00', '12:30:00', '13:00:00', '11:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 5, '13:00:00', '14:30:00', '15:00:00', '13:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 6, '15:00:00', '16:30:00', '17:00:00', '15:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 7, '17:00:00', '18:30:00', '19:00:00', '17:00:00')
ON CONFLICT (route_id, trip_number) DO NOTHING;

-- Insert fare matrix
INSERT INTO fare_matrix (route_from, route_to, km_distance, regular_fare, discounted_fare) VALUES
  ('Agora Terminal', 'Puerto', 13, 34.75, 27.75),
  ('Agora Terminal', 'Ba-e', 16, 41.50, 33.00),
  ('Agora Terminal', 'Mambatangan', 20, 50.25, 40.25),
  ('Agora Terminal', 'Maitom', 24, 59.00, 47.25),
  ('Agora Terminal', 'Ala-e', 26, 63.50, 50.75),
  ('Agora Terminal', 'Lonocan', 27, 65.50, 52.50),
  ('Agora Terminal', 'San Miguel', 31, 74.50, 59.50),
  ('Agora Terminal', 'Diclum', 35, 83.25, 66.50),
  ('Agora Terminal', 'Manolo Fortich', 36, 85.50, 68.25),
  ('Puerto', 'Agora Terminal', 13, 34.75, 27.75),
  ('Ba-e', 'Agora Terminal', 16, 41.50, 33.00),
  ('Mambatangan', 'Agora Terminal', 20, 50.25, 40.25),
  ('Maitom', 'Agora Terminal', 24, 59.00, 47.25),
  ('Ala-e', 'Agora Terminal', 26, 63.50, 50.75),
  ('Lonocan', 'Agora Terminal', 27, 65.50, 52.50),
  ('San Miguel', 'Agora Terminal', 31, 74.50, 59.50),
  ('Diclum', 'Agora Terminal', 35, 83.25, 66.50),
  ('Manolo Fortich', 'Agora Terminal', 36, 85.50, 68.25)
ON CONFLICT (route_from, route_to) DO NOTHING;

-- Insert baggage fee matrix
INSERT INTO baggage_fee_matrix (category, max_weight_kg, fee, remarks) VALUES
  ('Free Carry-on', 7, 0, 'Included in passenger fare'),
  ('Small', 10, 20, 'Fits under seat or overhead area'),
  ('Medium', 20, 40, 'Stored in baggage compartment'),
  ('Large', 30, 60, 'Requires larger storage space'),
  ('Oversized', 31, 100, 'Subject to conductor approval')
ON CONFLICT DO NOTHING;

-- ============================================================
-- Schema complete.
-- ============================================================
