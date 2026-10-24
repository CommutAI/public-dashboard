-- ============================================================
-- CommutAI · Unified Database Schema
-- One Manolo Fortich Transport System
-- Supports: Public Dashboard, Customer Service, Driver, Conductor, System Admin, Terminal Operator
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 0. Custom Enum Types
-- ============================================================

-- Staff roles across all applications
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'staff_role') THEN
    CREATE TYPE staff_role AS ENUM ('admin', 'operator', 'driver', 'conductor', 'cs_desk', 'supervisor');
  END IF;
END $$;

-- Bus status
DO $$ BEGIN
  CREATE TYPE bus_status AS ENUM ('active', 'maintenance', 'inactive', 'out_of_service');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Trip status
DO $$ BEGIN
  CREATE TYPE trip_status AS ENUM ('scheduled', 'in_progress', 'completed', 'cancelled', 'delayed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- QR card status
DO $$ BEGIN
  CREATE TYPE qr_card_status AS ENUM ('active', 'lost', 'replaced', 'deactivated', 'expired');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Card types with discounts
DO $$ BEGIN
  CREATE TYPE card_type AS ENUM ('regular', 'student', 'senior_citizen', 'pwd');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Temporary ticket status
DO $$ BEGIN
  CREATE TYPE ticket_status AS ENUM ('issued', 'validated', 'expired', 'refunded');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Transaction types
DO $$ BEGIN
  CREATE TYPE transaction_type AS ENUM ('fare_validation', 'balance_topup', 'card_issuance', 'baggage_fee', 'refund');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Fare irregularity types
DO $$ BEGIN
  CREATE TYPE irregularity_type AS ENUM ('double_scan', 'count_mismatch', 'fare_evasion', 'hardware_error', 'other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Customer service action types
DO $$ BEGIN
  CREATE TYPE cs_action_type AS ENUM ('complaint', 'inquiry', 'refund', 'lost_card', 'other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Shift status for operators
DO $$ BEGIN
  CREATE TYPE shift_status AS ENUM ('scheduled', 'active', 'completed', 'missed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Task status
DO $$ BEGIN
  CREATE TYPE task_status AS ENUM ('pending', 'in_progress', 'completed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Task priority
DO $$ BEGIN
  CREATE TYPE task_priority AS ENUM ('low', 'normal', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Notification types
DO $$ BEGIN
  CREATE TYPE notification_type AS ENUM ('info', 'warning', 'alert', 'task', 'incident');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Emergency alert types
DO $$ BEGIN
  CREATE TYPE alert_type AS ENUM ('medical', 'accident', 'breakdown', 'security', 'other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 1. STAFF USERS
-- Central user management for all roles
-- ============================================================
CREATE TABLE IF NOT EXISTS staff_users (
  id                UUID        PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  full_name         TEXT        NOT NULL,
  email             TEXT        NOT NULL UNIQUE,
  role              staff_role  NOT NULL DEFAULT 'conductor',
  phone             TEXT,
  employee_id       TEXT        UNIQUE,
  is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
  bus_id            UUID,       -- Will add foreign key after buses table is created
  license_number    TEXT,       -- For drivers
  license_expiry    DATE,       -- For drivers
  emergency_contact TEXT,       -- Emergency contact person
  emergency_phone   TEXT,       -- Emergency contact phone
  last_login_at     TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-create staff_users row when a new auth user is created
CREATE OR REPLACE FUNCTION handle_new_staff_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  user_role TEXT;
BEGIN
  user_role := COALESCE(NEW.raw_user_meta_data->>'role', 'conductor');
  
  IF user_role NOT IN ('admin', 'operator', 'driver', 'conductor', 'cs_desk', 'supervisor') THEN
    user_role := 'conductor';
  END IF;
  
  INSERT INTO staff_users (id, full_name, email, role, phone, employee_id)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    NEW.email,
    user_role::staff_role,
    COALESCE(NEW.raw_user_meta_data->>'phone', NULL),
    COALESCE(NEW.raw_user_meta_data->>'employee_id', NULL)
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    email     = EXCLUDED.email,
    role      = EXCLUDED.role,
    phone     = EXCLUDED.phone,
    employee_id = EXCLUDED.employee_id,
    updated_at = NOW();
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG 'Error creating staff_users record for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_staff_user();

-- Update last_login_at on successful authentication
CREATE OR REPLACE FUNCTION update_last_login()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE staff_users
  SET last_login_at = NOW()
  WHERE id = auth.uid();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_login ON auth.users;
CREATE TRIGGER on_auth_login
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION update_last_login();

-- ============================================================
-- 2. BUSES
-- Fleet management with driver/conductor assignments
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
  assigned_driver_id     UUID        REFERENCES staff_users (id) ON DELETE SET NULL,
  assigned_conductor_id  UUID        REFERENCES staff_users (id) ON DELETE SET NULL,
  assigned_operator_id   UUID        REFERENCES staff_users (id) ON DELETE SET NULL,
  last_maintenance_date  DATE,
  next_maintenance_date  DATE,
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

-- Add foreign key constraint to staff_users.bus_id after buses table exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'staff_users' AND constraint_name = 'staff_users_bus_id_fkey'
  ) THEN
    ALTER TABLE staff_users
    ADD CONSTRAINT staff_users_bus_id_fkey
    FOREIGN KEY (bus_id) REFERENCES buses (id) ON DELETE SET NULL;
  END IF;
END $$;

-- Add missing columns to buses table if it already exists (for migration from older schema)
DO $$
BEGIN
  -- Add id if missing (unlikely but possible)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'id'
  ) THEN
    ALTER TABLE buses ADD COLUMN id UUID PRIMARY KEY DEFAULT gen_random_uuid();
  END IF;
  
  -- Add plate_number if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'plate_number'
  ) THEN
    ALTER TABLE buses ADD COLUMN plate_number TEXT NOT NULL UNIQUE DEFAULT '';
  END IF;
  
  -- Add bus_number if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'bus_number'
  ) THEN
    ALTER TABLE buses ADD COLUMN bus_number INTEGER UNIQUE;
  END IF;
  
  -- Add route if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'route'
  ) THEN
    ALTER TABLE buses ADD COLUMN route TEXT NOT NULL DEFAULT '';
  END IF;
  
  -- Add seat_capacity if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'seat_capacity'
  ) THEN
    ALTER TABLE buses ADD COLUMN seat_capacity INTEGER NOT NULL DEFAULT 50;
  END IF;
  
  -- Add status if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'status'
  ) THEN
    ALTER TABLE buses ADD COLUMN status bus_status NOT NULL DEFAULT 'active';
  END IF;
  
  -- Add assigned_driver_id if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'assigned_driver_id'
  ) THEN
    ALTER TABLE buses ADD COLUMN assigned_driver_id UUID REFERENCES staff_users (id) ON DELETE SET NULL;
  END IF;
  
  -- Add assigned_conductor_id if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'assigned_conductor_id'
  ) THEN
    ALTER TABLE buses ADD COLUMN assigned_conductor_id UUID REFERENCES staff_users (id) ON DELETE SET NULL;
  END IF;
  
  -- Add assigned_operator_id if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'assigned_operator_id'
  ) THEN
    ALTER TABLE buses ADD COLUMN assigned_operator_id UUID REFERENCES staff_users (id) ON DELETE SET NULL;
  END IF;
  
  -- Add bus_type if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'bus_type'
  ) THEN
    ALTER TABLE buses ADD COLUMN bus_type TEXT DEFAULT 'standard';
  END IF;
  
  -- Add manufacturer if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'manufacturer'
  ) THEN
    ALTER TABLE buses ADD COLUMN manufacturer TEXT;
  END IF;
  
  -- Add model_year if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'model_year'
  ) THEN
    ALTER TABLE buses ADD COLUMN model_year INTEGER;
  END IF;
  
  -- Add last_maintenance_date if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'last_maintenance_date'
  ) THEN
    ALTER TABLE buses ADD COLUMN last_maintenance_date DATE;
  END IF;
  
  -- Add next_maintenance_date if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'next_maintenance_date'
  ) THEN
    ALTER TABLE buses ADD COLUMN next_maintenance_date DATE;
  END IF;
  
  -- Add updated_at if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'buses' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE buses ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;
END $$;

-- ============================================================
-- 3. BUS STOPS
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

-- Add missing columns to bus_stops table if it already exists (for migration from older schema)
DO $$
BEGIN
  -- Add stop_code if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_stops' AND column_name = 'stop_code'
  ) THEN
    ALTER TABLE bus_stops ADD COLUMN stop_code VARCHAR(20) UNIQUE NOT NULL DEFAULT '';
  END IF;
  
  -- Add name if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_stops' AND column_name = 'name'
  ) THEN
    ALTER TABLE bus_stops ADD COLUMN name VARCHAR(100) NOT NULL DEFAULT '';
  END IF;
  
  -- Add location if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_stops' AND column_name = 'location'
  ) THEN
    ALTER TABLE bus_stops ADD COLUMN location VARCHAR(100) NOT NULL DEFAULT '';
  END IF;
  
  -- Add latitude if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_stops' AND column_name = 'latitude'
  ) THEN
    ALTER TABLE bus_stops ADD COLUMN latitude DECIMAL(10, 8) NOT NULL DEFAULT 0;
  END IF;
  
  -- Add longitude if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_stops' AND column_name = 'longitude'
  ) THEN
    ALTER TABLE bus_stops ADD COLUMN longitude DECIMAL(11, 8) NOT NULL DEFAULT 0;
  END IF;
  
  -- Add stop_type if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_stops' AND column_name = 'stop_type'
  ) THEN
    ALTER TABLE bus_stops ADD COLUMN stop_type VARCHAR(20) NOT NULL DEFAULT 'regular';
  END IF;
  
  -- Add status if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_stops' AND column_name = 'status'
  ) THEN
    ALTER TABLE bus_stops ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
  END IF;
  
  -- Add sequence_order if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_stops' AND column_name = 'sequence_order'
  ) THEN
    ALTER TABLE bus_stops ADD COLUMN sequence_order INTEGER NOT NULL DEFAULT 0;
  END IF;
  
  -- Add updated_at if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_stops' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE bus_stops ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;
END $$;

-- ============================================================
-- 4. ROUTES
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

-- Add missing columns to routes table if it already exists (for migration from older schema)
DO $$
BEGIN
  -- Add route_code if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'routes' AND column_name = 'route_code'
  ) THEN
    ALTER TABLE routes ADD COLUMN route_code VARCHAR(20) UNIQUE NOT NULL DEFAULT '';
  END IF;
  
  -- Add name if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'routes' AND column_name = 'name'
  ) THEN
    ALTER TABLE routes ADD COLUMN name VARCHAR(100) NOT NULL DEFAULT '';
  END IF;
  
  -- Add start_stop_id if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'routes' AND column_name = 'start_stop_id'
  ) THEN
    ALTER TABLE routes ADD COLUMN start_stop_id UUID NOT NULL DEFAULT gen_random_uuid();
  END IF;
  
  -- Add end_stop_id if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'routes' AND column_name = 'end_stop_id'
  ) THEN
    ALTER TABLE routes ADD COLUMN end_stop_id UUID NOT NULL DEFAULT gen_random_uuid();
  END IF;
  
  -- Add total_distance_km if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'routes' AND column_name = 'total_distance_km'
  ) THEN
    ALTER TABLE routes ADD COLUMN total_distance_km DECIMAL(8, 2);
  END IF;
  
  -- Add estimated_duration_minutes if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'routes' AND column_name = 'estimated_duration_minutes'
  ) THEN
    ALTER TABLE routes ADD COLUMN estimated_duration_minutes INTEGER;
  END IF;
  
  -- Add status if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'routes' AND column_name = 'status'
  ) THEN
    ALTER TABLE routes ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
  END IF;
  
  -- Add updated_at if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'routes' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE routes ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;
END $$;

-- ============================================================
-- 5. TRIP SCHEDULES
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

-- Add missing columns to trip_schedules table if it already exists (for migration from older schema)
DO $$
BEGIN
  -- Add departure_time_start if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trip_schedules' AND column_name = 'departure_time_start'
  ) THEN
    ALTER TABLE trip_schedules ADD COLUMN departure_time_start TIME NOT NULL DEFAULT '00:00:00';
  END IF;
  
  -- Add arrival_time_start if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trip_schedules' AND column_name = 'arrival_time_start'
  ) THEN
    ALTER TABLE trip_schedules ADD COLUMN arrival_time_start TIME NOT NULL DEFAULT '00:00:00';
  END IF;
  
  -- Add arrival_time_end if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trip_schedules' AND column_name = 'arrival_time_end'
  ) THEN
    ALTER TABLE trip_schedules ADD COLUMN arrival_time_end TIME NOT NULL DEFAULT '00:00:00';
  END IF;
  
  -- Add departure_time_end if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trip_schedules' AND column_name = 'departure_time_end'
  ) THEN
    ALTER TABLE trip_schedules ADD COLUMN departure_time_end TIME NOT NULL DEFAULT '00:00:00';
  END IF;
  
  -- Add days_of_operation if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trip_schedules' AND column_name = 'days_of_operation'
  ) THEN
    ALTER TABLE trip_schedules ADD COLUMN days_of_operation VARCHAR(20) NOT NULL DEFAULT 'daily';
  END IF;
  
  -- Add status if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trip_schedules' AND column_name = 'status'
  ) THEN
    ALTER TABLE trip_schedules ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
  END IF;
  
  -- Add updated_at if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trip_schedules' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE trip_schedules ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;
END $$;

-- ============================================================
-- 6. BUS SCHEDULES
-- Which bus runs which trip on which day
-- ============================================================
CREATE TABLE IF NOT EXISTS bus_schedules (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  bus_id      UUID        NOT NULL REFERENCES buses (id),
  day_number  INTEGER     NOT NULL CHECK (day_number BETWEEN 1 AND 10),
  trip_number INTEGER     NOT NULL CHECK (trip_number BETWEEN 1 AND 10),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT unique_bus_day_trip UNIQUE (bus_id, day_number, trip_number)
);

-- ============================================================
-- 7. OPERATOR SHIFTS
-- Shift management for terminal operators
-- ============================================================
CREATE TABLE IF NOT EXISTS operator_shifts (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id     UUID          NOT NULL REFERENCES staff_users (id) ON DELETE CASCADE,
  bus_id          UUID          REFERENCES buses (id),
  scheduled_start TIMESTAMPTZ   NOT NULL,
  scheduled_end   TIMESTAMPTZ   NOT NULL,
  actual_start    TIMESTAMPTZ,
  actual_end      TIMESTAMPTZ,
  status          shift_status  NOT NULL DEFAULT 'scheduled',
  notes           TEXT,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION update_operator_shifts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_operator_shifts_updated_at_trigger ON operator_shifts;
CREATE TRIGGER update_operator_shifts_updated_at_trigger
  BEFORE UPDATE ON operator_shifts
  FOR EACH ROW EXECUTE FUNCTION update_operator_shifts_updated_at();

-- ============================================================
-- 8. TRIPS
-- Actual trip instances with real-time tracking
-- ============================================================
CREATE TABLE IF NOT EXISTS trips (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id         UUID        REFERENCES trip_schedules (id),
  bus_id              UUID        NOT NULL REFERENCES buses (id),
  route_id            UUID        NOT NULL REFERENCES routes (id),
  trip_number         INTEGER     NOT NULL,
  conductor_id        UUID        NOT NULL REFERENCES staff_users (id),
  driver_id           UUID        REFERENCES staff_users (id),
  operator_id         UUID        REFERENCES staff_users (id),
  shift_id            UUID        REFERENCES operator_shifts (id),
  status              trip_status NOT NULL DEFAULT 'scheduled',
  started_at          TIMESTAMPTZ,
  ended_at            TIMESTAMPTZ,
  current_lat         DECIMAL(10, 8),
  current_lng         DECIMAL(11, 8),
  gps_updated_at      TIMESTAMPTZ,
  current_stop_id     UUID        REFERENCES bus_stops (id),
  starting_point      TEXT,
  end_point           TEXT,
  total_passengers    INTEGER     DEFAULT 0,
  total_fares         NUMERIC(10,2) DEFAULT 0,
  incidents           INTEGER     DEFAULT 0,
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add missing columns if table already exists (for migration from older schema)
DO $$
BEGIN
  -- Add conductor_id if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trips' AND column_name = 'conductor_id'
  ) THEN
    ALTER TABLE trips ADD COLUMN conductor_id UUID NOT NULL REFERENCES staff_users (id);
  END IF;
  
  -- Add driver_id if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trips' AND column_name = 'driver_id'
  ) THEN
    ALTER TABLE trips ADD COLUMN driver_id UUID REFERENCES staff_users (id);
  END IF;
  
  -- Add operator_id if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trips' AND column_name = 'operator_id'
  ) THEN
    ALTER TABLE trips ADD COLUMN operator_id UUID REFERENCES staff_users (id);
  END IF;
  
  -- Add shift_id if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trips' AND column_name = 'shift_id'
  ) THEN
    ALTER TABLE trips ADD COLUMN shift_id UUID REFERENCES operator_shifts (id);
  END IF;
  
  -- Add total_passengers if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trips' AND column_name = 'total_passengers'
  ) THEN
    ALTER TABLE trips ADD COLUMN total_passengers INTEGER DEFAULT 0;
  END IF;
  
  -- Add total_fares if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trips' AND column_name = 'total_fares'
  ) THEN
    ALTER TABLE trips ADD COLUMN total_fares NUMERIC(10,2) DEFAULT 0;
  END IF;
  
  -- Add incidents if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trips' AND column_name = 'incidents'
  ) THEN
    ALTER TABLE trips ADD COLUMN incidents INTEGER DEFAULT 0;
  END IF;
  
  -- Add updated_at if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'trips' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE trips ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;
END $$;

-- Enforce one active trip per conductor
CREATE UNIQUE INDEX IF NOT EXISTS idx_trips_conductor_one_active
  ON trips(conductor_id) WHERE status = 'in_progress';

-- ============================================================
-- 9. CARD TYPES
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

-- Add missing columns to card_types table if it already exists (for migration from older schema)
DO $$
BEGIN
  -- Add name if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'card_types' AND column_name = 'name'
  ) THEN
    ALTER TABLE card_types ADD COLUMN name VARCHAR(50) UNIQUE NOT NULL DEFAULT '';
  END IF;
  
  -- Add card_type if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'card_types' AND column_name = 'card_type'
  ) THEN
    ALTER TABLE card_types ADD COLUMN card_type VARCHAR(20) NOT NULL DEFAULT 'permanent';
  END IF;
  
  -- Add discount_percentage if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'card_types' AND column_name = 'discount_percentage'
  ) THEN
    ALTER TABLE card_types ADD COLUMN discount_percentage DECIMAL(5, 2) NOT NULL DEFAULT 0;
  END IF;
  
  -- Add validity_days if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'card_types' AND column_name = 'validity_days'
  ) THEN
    ALTER TABLE card_types ADD COLUMN validity_days INTEGER;
  END IF;
  
  -- Add description if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'card_types' AND column_name = 'description'
  ) THEN
    ALTER TABLE card_types ADD COLUMN description TEXT;
  END IF;
  
  -- Add image_url if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'card_types' AND column_name = 'image_url'
  ) THEN
    ALTER TABLE card_types ADD COLUMN image_url VARCHAR(255);
  END IF;
  
  -- Add status if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'card_types' AND column_name = 'status'
  ) THEN
    ALTER TABLE card_types ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
  END IF;
  
  -- Add updated_at if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'card_types' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE card_types ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;
END $$;

-- ============================================================
-- 10. QR CARDS
-- Issued QR cards for passengers
-- ============================================================
CREATE TABLE IF NOT EXISTS qr_cards (
  id              UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  card_uid        TEXT           NOT NULL UNIQUE,
  owner_name      TEXT           NOT NULL,
  contact_number  TEXT,
  email           TEXT,
  balance         NUMERIC(10,2)  NOT NULL DEFAULT 0,
  status          qr_card_status NOT NULL DEFAULT 'active',
  card_type       card_type      NOT NULL DEFAULT 'regular',
  purchase_price  NUMERIC(10,2)  NOT NULL DEFAULT 100.00,
  allowed_routes  TEXT[]         DEFAULT '{}',
  passenger_id    UUID,
  destination     TEXT,
  issued_by       UUID           REFERENCES staff_users (id),
  issued_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  expires_at      TIMESTAMPTZ,
  last_used_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 11. CARD RESERVATIONS
-- Online card reservation requests
-- ============================================================
CREATE TABLE IF NOT EXISTS card_reservations (
  id                BIGSERIAL   PRIMARY KEY,
  reservation_id    VARCHAR(50) UNIQUE NOT NULL,
  name              VARCHAR(100) NOT NULL,
  contact           VARCHAR(20) NOT NULL,
  card_type         VARCHAR(50) NOT NULL,
  pickup_terminal   VARCHAR(100) NOT NULL,
  id_file           TEXT,       -- Base64 encoded ID file for Student, PWD, Senior Citizen
  status            VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'claimed', 'expired', 'cancelled')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at        TIMESTAMPTZ NOT NULL,
  claimed_at        TIMESTAMPTZ,
  card_id           UUID        REFERENCES qr_cards (id)
);

-- Add missing columns to card_reservations table if it already exists (for migration from older schema)
DO $$
BEGIN
  -- Add id_file if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'card_reservations' AND column_name = 'id_file'
  ) THEN
    ALTER TABLE card_reservations ADD COLUMN id_file TEXT;
  END IF;
END $$;

-- ============================================================
-- 12. TEMPORARY TICKETS
-- One-time use tickets
-- ============================================================
CREATE TABLE IF NOT EXISTS temporary_tickets (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_uid      TEXT          NOT NULL UNIQUE,
  fare_amount     NUMERIC(10,2) NOT NULL DEFAULT 12,
  status          ticket_status NOT NULL DEFAULT 'issued',
  allowed_routes  TEXT[]        DEFAULT '{}',
  passenger_id    UUID,
  passenger_type  TEXT          DEFAULT 'regular',
  trip_id         UUID          REFERENCES trips (id),
  destination     TEXT,
  issued_by       UUID          REFERENCES staff_users (id),
  issued_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  validated_at    TIMESTAMPTZ
);

-- ============================================================
-- 13. TRANSACTIONS
-- All payment transactions
-- ============================================================
CREATE TABLE IF NOT EXISTS transactions (
  id               UUID             PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id          UUID             REFERENCES qr_cards (id),
  temp_ticket_id   UUID             REFERENCES temporary_tickets (id),
  trip_id          UUID             REFERENCES trips (id),
  type             transaction_type NOT NULL,
  amount           NUMERIC(10,2)    NOT NULL,
  channel          TEXT             NOT NULL,
  staff_id         UUID             REFERENCES staff_users (id),
  created_at       TIMESTAMPTZ      NOT NULL DEFAULT NOW(),
  from_stop_id     UUID             REFERENCES bus_stops (id),
  to_stop_id       UUID             REFERENCES bus_stops (id),
  fare_amount      NUMERIC(10,2),
  discount_amount  NUMERIC(10,2)    NOT NULL DEFAULT 0,
  final_amount     NUMERIC(10,2)    NOT NULL,
  payment_method   TEXT,
  baggage_category TEXT,
  baggage_weight   NUMERIC(10,2),
  baggage_fee      NUMERIC(10,2)
);

-- ============================================================
-- 14. CARD RELOADS
-- Card top-up history
-- ============================================================
CREATE TABLE IF NOT EXISTS card_reloads (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id         UUID        NOT NULL REFERENCES qr_cards (id),
  amount          NUMERIC(10,2) NOT NULL,
  reload_method   TEXT        NOT NULL CHECK (reload_method IN ('cash', 'gcash', 'maya', 'bank')),
  reference_number TEXT,
  reload_location TEXT,
  status          TEXT        NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed')),
  recorded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 15. PASSENGER COUNTS
-- Real-time passenger occupancy (manual + AI)
-- ============================================================
CREATE TABLE IF NOT EXISTS passenger_counts (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id      UUID        NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
  bus_id       UUID        NOT NULL REFERENCES buses (id),
  count        INTEGER     NOT NULL,
  recorded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ai_count     INTEGER,
  source       TEXT        NOT NULL DEFAULT 'manual',
  latitude     DECIMAL(10, 8),
  longitude    DECIMAL(11, 8)
);

-- ============================================================
-- 16. BOARDED PASSENGERS
-- Successful boarding events
-- ============================================================
CREATE TABLE IF NOT EXISTS boarded_passengers (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id         UUID        NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
  passenger_id    UUID,
  card_id         UUID        REFERENCES qr_cards (id),
  temp_ticket_id  UUID        REFERENCES temporary_tickets (id),
  boarded_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  alighted_at     TIMESTAMPTZ,
  payment_method  TEXT,
  boarding_stop   TEXT,
  destination_stop TEXT,
  CONSTRAINT chk_boarding_source CHECK (card_id IS NOT NULL OR temp_ticket_id IS NOT NULL)
);

-- ============================================================
-- 17. GPS LOGS
-- GPS location history
-- ============================================================
CREATE TABLE IF NOT EXISTS gps_logs (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id      UUID        NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
  bus_id       UUID        NOT NULL REFERENCES buses (id),
  lat          FLOAT8      NOT NULL,
  lng          FLOAT8      NOT NULL,
  speed_kmh    DECIMAL(6, 2),
  heading      DECIMAL(5, 2),
  recorded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 18. GPS LOCATIONS
-- Detailed GPS with accuracy
-- ============================================================
CREATE TABLE IF NOT EXISTS gps_locations (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  latitude         DECIMAL(10, 8) NOT NULL,
  longitude        DECIMAL(11, 8) NOT NULL,
  altitude         DECIMAL(10, 2),
  speed            DECIMAL(10, 2),
  accuracy         DECIMAL(10, 2),
  source           TEXT        NOT NULL,
  trip_id          UUID        REFERENCES trips (id) ON DELETE CASCADE,
  satellite_count  INTEGER,
  fix_quality      INTEGER,
  recorded_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 19. FARE MATRIX
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

-- Add missing columns to fare_matrix table if it already exists (for migration from older schema)
DO $$
BEGIN
  -- Add route_from if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'fare_matrix' AND column_name = 'route_from'
  ) THEN
    ALTER TABLE fare_matrix ADD COLUMN route_from TEXT NOT NULL DEFAULT '';
  END IF;
  
  -- Add route_to if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'fare_matrix' AND column_name = 'route_to'
  ) THEN
    ALTER TABLE fare_matrix ADD COLUMN route_to TEXT NOT NULL DEFAULT '';
  END IF;
  
  -- Add km_distance if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'fare_matrix' AND column_name = 'km_distance'
  ) THEN
    ALTER TABLE fare_matrix ADD COLUMN km_distance NUMERIC NOT NULL DEFAULT 0;
  END IF;
  
  -- Add regular_fare if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'fare_matrix' AND column_name = 'regular_fare'
  ) THEN
    ALTER TABLE fare_matrix ADD COLUMN regular_fare NUMERIC NOT NULL DEFAULT 0;
  END IF;
  
  -- Add discounted_fare if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'fare_matrix' AND column_name = 'discounted_fare'
  ) THEN
    ALTER TABLE fare_matrix ADD COLUMN discounted_fare NUMERIC NOT NULL DEFAULT 0;
  END IF;
  
  -- Add updated_at if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'fare_matrix' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE fare_matrix ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;
END $$;

-- ============================================================
-- 20. BAGGAGE FEE MATRIX
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
-- 21. FARE IRREGULARITIES
-- Fare payment irregularities
-- ============================================================
CREATE TABLE IF NOT EXISTS fare_irregularities (
  id           UUID               PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id      UUID               NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
  type         irregularity_type  NOT NULL,
  description  TEXT               NOT NULL,
  detected_at  TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
  resolved     BOOLEAN            NOT NULL DEFAULT FALSE,
  resolved_by  UUID               REFERENCES staff_users (id),
  resolved_at  TIMESTAMPTZ
);

-- ============================================================
-- 22. EMERGENCY ALERTS
-- Emergency alerts from buses
-- ============================================================
CREATE TABLE IF NOT EXISTS emergency_alerts (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id          UUID        NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
  conductor_id     UUID        NOT NULL REFERENCES staff_users (id),
  bus_id           UUID        REFERENCES buses (id),
  alert_type       alert_type  NOT NULL,
  lat              FLOAT8,
  lng              FLOAT8,
  status           TEXT        NOT NULL DEFAULT 'active',
  notes            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acknowledged_at  TIMESTAMPTZ,
  resolved_at      TIMESTAMPTZ,
  triggered_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  location_lat     DECIMAL(10, 8),
  location_lng     DECIMAL(11, 8),
  location_source  TEXT,
  location_accuracy DECIMAL(10, 2),
  location_name    TEXT,
  resolved         BOOLEAN DEFAULT FALSE,
  resolved_by      UUID        REFERENCES staff_users (id) ON DELETE SET NULL,
  acknowledged_by  UUID        REFERENCES staff_users (id)
);

-- ============================================================
-- 23. EMERGENCY CONTACTS
-- Emergency contact information
-- ============================================================
CREATE TABLE IF NOT EXISTS emergency_contacts (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL,
  phone       TEXT        NOT NULL,
  email       TEXT,
  relationship TEXT,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 24. SMS LOGS
-- SMS notification logs
-- ============================================================
CREATE TABLE IF NOT EXISTS sms_logs (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number    TEXT        NOT NULL,
  message         TEXT        NOT NULL,
  sms_type        TEXT        NOT NULL,
  status          TEXT        NOT NULL DEFAULT 'sent',
  trip_id         UUID        REFERENCES trips (id) ON DELETE CASCADE,
  transaction_id  UUID,
  sent_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 25. SMS QUEUE
-- SMS queue for Raspberry Pi processing
-- ============================================================
CREATE TABLE IF NOT EXISTS sms_queue (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number    TEXT        NOT NULL,
  message         TEXT        NOT NULL,
  type            TEXT        NOT NULL CHECK (type IN ('emergency', 'alighting', 'card_reserved', 'card_claimed', 'other')),
  priority        INTEGER     DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),
  related_id      UUID,
  trip_id         UUID        REFERENCES trips (id),
  status          TEXT        DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'cancelled')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at         TIMESTAMPTZ,
  failed_at       TIMESTAMPTZ,
  error_message   TEXT,
  retry_count     INTEGER     DEFAULT 0,
  max_retries     INTEGER     DEFAULT 3
);

-- Trigger to queue SMS when card reservation is created
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

DROP TRIGGER IF EXISTS on_card_reservation_created ON card_reservations;
CREATE TRIGGER on_card_reservation_created
  AFTER INSERT ON card_reservations
  FOR EACH ROW EXECUTE FUNCTION queue_sms_on_card_reserved();

-- ============================================================
-- 26. HARDWARE STATUS
-- Hardware component monitoring
-- ============================================================
CREATE TABLE IF NOT EXISTS hardware_status (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  component   TEXT        NOT NULL,
  status      TEXT        NOT NULL,
  details     JSONB,
  last_check  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 27. CUSTOMER SERVICE LOGS
-- CS desk interactions
-- ============================================================
CREATE TABLE IF NOT EXISTS customer_service_logs (
  id          UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id     UUID           REFERENCES trips (id),
  handled_by  UUID           REFERENCES staff_users (id),
  action      cs_action_type NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 28. GCASH TRANSACTIONS
-- GCash payment integration
-- ============================================================
CREATE TABLE IF NOT EXISTS gcash_transactions (
  id                BIGSERIAL PRIMARY KEY,
  phone_number      TEXT        NOT NULL,
  amount            NUMERIC     NOT NULL,
  status            TEXT        NOT NULL CHECK (status IN ('completed', 'failed', 'pending')),
  stripe_payment_id TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 29. NOTIFICATIONS
-- System notifications
-- ============================================================
CREATE TABLE IF NOT EXISTS notifications (
  id         BIGSERIAL PRIMARY KEY,
  message    TEXT        NOT NULL,
  type       TEXT        DEFAULT 'info' CHECK (type IN ('alert', 'success', 'info')),
  read       BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 30. AUDIT LOGS
-- System audit trail
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_logs (
  id          BIGSERIAL PRIMARY KEY,
  username    TEXT        NOT NULL,
  action      TEXT        DEFAULT 'info' CHECK (action IN ('CREATE', 'UPDATE', 'DELETE', 'LOGIN', 'LOGOUT', 'VIEW', 'EXPORT')),
  module      TEXT,
  details     TEXT,
  ip_address  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 31. VIDEO RECORDINGS
-- Video monitoring recordings
-- ============================================================
CREATE TABLE IF NOT EXISTS video_recordings (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id          UUID        REFERENCES trips (id) ON DELETE CASCADE,
  file_name        TEXT        NOT NULL,
  file_path        TEXT        NOT NULL,
  file_size        BIGINT,
  duration         INTEGER,
  format           TEXT        NOT NULL,
  recorded_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  storage_type     TEXT        NOT NULL DEFAULT 'local',
  status           TEXT        NOT NULL DEFAULT 'recording',
  metadata         JSONB
);

-- ============================================================
-- 32. OPERATOR PERFORMANCE
-- Performance metrics for operators
-- ============================================================
CREATE TABLE IF NOT EXISTS operator_performance (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id     UUID        NOT NULL REFERENCES staff_users (id) ON DELETE CASCADE,
  period_start    TIMESTAMPTZ NOT NULL,
  period_end      TIMESTAMPTZ NOT NULL,
  trips_completed INTEGER     NOT NULL DEFAULT 0,
  passengers_served INTEGER   NOT NULL DEFAULT 0,
  fares_collected NUMERIC(10,2) NOT NULL DEFAULT 0,
  on_time_rate    NUMERIC(5,2),
  customer_rating NUMERIC(3,2),
  incidents       INTEGER     NOT NULL DEFAULT 0,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 33. OPERATOR TASKS
-- Task management for operators
-- ============================================================
CREATE TABLE IF NOT EXISTS operator_tasks (
  id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
  title           TEXT            NOT NULL,
  description     TEXT,
  assigned_to     UUID            NOT NULL REFERENCES staff_users (id) ON DELETE CASCADE,
  assigned_by     UUID            REFERENCES staff_users (id),
  priority        task_priority   NOT NULL DEFAULT 'normal',
  status          task_status     NOT NULL DEFAULT 'pending',
  due_date        TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  trip_id         UUID            REFERENCES trips (id),
  bus_id          UUID            REFERENCES buses (id),
  created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION update_operator_tasks_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    NEW.completed_at = NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_operator_tasks_updated_at_trigger ON operator_tasks;
CREATE TRIGGER update_operator_tasks_updated_at_trigger
  BEFORE UPDATE ON operator_tasks
  FOR EACH ROW EXECUTE FUNCTION update_operator_tasks_updated_at();

-- ============================================================
-- 34. OPERATOR NOTIFICATIONS
-- Notifications for operators
-- ============================================================
CREATE TABLE IF NOT EXISTS operator_notifications (
  id              UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id     UUID              NOT NULL REFERENCES staff_users (id) ON DELETE CASCADE,
  type            notification_type NOT NULL,
  title           TEXT              NOT NULL,
  message         TEXT              NOT NULL,
  link            TEXT,
  is_read         BOOLEAN           NOT NULL DEFAULT FALSE,
  read_at         TIMESTAMPTZ,
  task_id         UUID              REFERENCES operator_tasks (id),
  trip_id         UUID              REFERENCES trips (id),
  created_at      TIMESTAMPTZ       NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 35. PERFORMANCE REPORTS
-- Generated performance reports
-- ============================================================
CREATE TABLE IF NOT EXISTS performance_reports (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  report_type     TEXT        NOT NULL,
  period_start    TIMESTAMPTZ NOT NULL,
  period_end      TIMESTAMPTZ NOT NULL,
  data            JSONB       NOT NULL,
  generated_by    UUID        REFERENCES staff_users (id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 36. ANNOUNCEMENTS
-- System announcements
-- ============================================================
CREATE TABLE IF NOT EXISTS announcements (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title           TEXT        NOT NULL,
  message         TEXT        NOT NULL,
  priority        TEXT        NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'emergency')),
  is_public       BOOLEAN     NOT NULL DEFAULT TRUE,
  created_by      UUID        REFERENCES staff_users (id),
  start_date      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_date        TIMESTAMPTZ,
  status          TEXT        NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'archived')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 37. PI DEVICES
-- Raspberry Pi device registry
-- ============================================================
CREATE TABLE IF NOT EXISTS pi_devices (
  bus_number   INTEGER     PRIMARY KEY,
  bus_id       UUID        REFERENCES buses (id) ON DELETE SET NULL,
  ip_address   TEXT        NOT NULL,
  port         INTEGER     NOT NULL DEFAULT 5000,
  last_seen    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  hostname     TEXT
);

-- ============================================================
-- 38. SYSTEM CONFIG
-- System configuration (admin only)
-- ============================================================
CREATE TABLE IF NOT EXISTS system_config (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  key         TEXT        NOT NULL UNIQUE,
  value       JSONB       NOT NULL,
  description TEXT,
  category    TEXT        NOT NULL DEFAULT 'general',
  is_public   BOOLEAN     NOT NULL DEFAULT FALSE,
  updated_by  UUID        REFERENCES staff_users (id),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 39. SECURITY EVENTS
-- Security event logging (admin only)
-- ============================================================
CREATE TABLE IF NOT EXISTS security_events (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type      TEXT        NOT NULL,
  severity        TEXT        NOT NULL DEFAULT 'info',
  user_id         UUID        REFERENCES staff_users (id),
  ip_address      TEXT        NOT NULL,
  user_agent      TEXT,
  resource        TEXT,
  action          TEXT,
  success         BOOLEAN    NOT NULL,
  details         JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 40. MAINTENANCE SCHEDULES
-- Maintenance task scheduling (admin/operator)
-- ============================================================
CREATE TABLE IF NOT EXISTS maintenance_schedules (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title           TEXT        NOT NULL,
  description     TEXT,
  component       TEXT        NOT NULL,
  component_id    UUID,
  scheduled_start TIMESTAMPTZ NOT NULL,
  scheduled_end   TIMESTAMPTZ NOT NULL,
  actual_start    TIMESTAMPTZ,
  actual_end      TIMESTAMPTZ,
  status          TEXT        NOT NULL DEFAULT 'scheduled',
  priority        TEXT        NOT NULL DEFAULT 'normal',
  assigned_to     UUID        REFERENCES staff_users (id),
  notes           TEXT,
  created_by      UUID        REFERENCES staff_users (id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 41. USER SESSIONS
-- Active session tracking (admin only)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_sessions (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID        NOT NULL REFERENCES staff_users (id) ON DELETE CASCADE,
  session_token   TEXT        NOT NULL,
  ip_address      TEXT        NOT NULL,
  user_agent      TEXT,
  device_type     TEXT,
  device_info     JSONB,
  location        JSONB,
  login_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_activity   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  logout_at       TIMESTAMPTZ,
  status          TEXT        NOT NULL DEFAULT 'active',
  terminated_by   UUID        REFERENCES staff_users (id),
  termination_reason TEXT
);

-- ============================================================
-- 42. SYSTEM INCIDENTS
-- System-wide incidents (admin/operator)
-- ============================================================
CREATE TABLE IF NOT EXISTS system_incidents (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_type   TEXT        NOT NULL,
  severity        TEXT        NOT NULL,
  title           TEXT        NOT NULL,
  description     TEXT,
  status          TEXT        NOT NULL DEFAULT 'open',
  affected_components TEXT[],
  detected_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at      TIMESTAMPTZ,
  resolved_by      UUID        REFERENCES staff_users (id),
  resolution_notes TEXT,
  root_cause      TEXT,
  created_by      UUID        REFERENCES staff_users (id),
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
CREATE INDEX IF NOT EXISTS idx_buses_assigned_driver ON buses(assigned_driver_id) WHERE assigned_driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_buses_assigned_conductor ON buses(assigned_conductor_id) WHERE assigned_conductor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_buses_assigned_operator ON buses(assigned_operator_id) WHERE assigned_operator_id IS NOT NULL;

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

-- Bus schedules
CREATE INDEX IF NOT EXISTS idx_bus_schedules_bus_day ON bus_schedules(bus_id, day_number);
CREATE INDEX IF NOT EXISTS idx_bus_schedules_day_trip ON bus_schedules(day_number, trip_number);

-- Operator shifts
CREATE INDEX IF NOT EXISTS idx_operator_shifts_operator ON operator_shifts(operator_id);
CREATE INDEX IF NOT EXISTS idx_operator_shifts_status ON operator_shifts(status);
CREATE INDEX IF NOT EXISTS idx_operator_shifts_scheduled_start ON operator_shifts(scheduled_start);

-- Trips
CREATE INDEX IF NOT EXISTS idx_trips_conductor_status ON trips(conductor_id, status) WHERE status = 'in_progress';
CREATE INDEX IF NOT EXISTS idx_trips_bus ON trips(bus_id);
CREATE INDEX IF NOT EXISTS idx_trips_route ON trips(route_id);
CREATE INDEX IF NOT EXISTS idx_trips_status ON trips(status);
CREATE INDEX IF NOT EXISTS idx_trips_started_at ON trips(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_trips_driver ON trips(driver_id) WHERE driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_trips_operator ON trips(operator_id) WHERE operator_id IS NOT NULL;

-- QR cards
CREATE INDEX IF NOT EXISTS idx_qr_cards_uid ON qr_cards(card_uid);
CREATE INDEX IF NOT EXISTS idx_qr_cards_holder ON qr_cards(owner_name);
CREATE INDEX IF NOT EXISTS idx_qr_cards_status ON qr_cards(status);
CREATE INDEX IF NOT EXISTS idx_qr_cards_contact ON qr_cards(contact_number);

-- Card reservations
CREATE INDEX IF NOT EXISTS idx_card_reservations_id ON card_reservations(reservation_id);
CREATE INDEX IF NOT EXISTS idx_card_reservations_contact ON card_reservations(contact);
CREATE INDEX IF NOT EXISTS idx_card_reservations_status ON card_reservations(status);
CREATE INDEX IF NOT EXISTS idx_card_reservations_expires ON card_reservations(expires_at);

-- Temporary tickets
CREATE INDEX IF NOT EXISTS idx_temp_tickets_uid ON temporary_tickets(ticket_uid);

-- Transactions
CREATE INDEX IF NOT EXISTS idx_transactions_card ON transactions(card_id);
CREATE INDEX IF NOT EXISTS idx_transactions_trip ON transactions(trip_id);
CREATE INDEX IF NOT EXISTS idx_transactions_recorded_at ON transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);

-- Card reloads
CREATE INDEX IF NOT EXISTS idx_card_reloads_card ON card_reloads(card_id);
CREATE INDEX IF NOT EXISTS idx_card_reloads_recorded_at ON card_reloads(recorded_at DESC);

-- Passenger counts
CREATE INDEX IF NOT EXISTS idx_passenger_counts_trip ON passenger_counts(trip_id);
CREATE INDEX IF NOT EXISTS idx_passenger_counts_bus ON passenger_counts(bus_id);
CREATE INDEX IF NOT EXISTS idx_passenger_counts_recorded_at ON passenger_counts(recorded_at DESC);

-- Boarded passengers
CREATE INDEX IF NOT EXISTS idx_boarded_passengers_trip ON boarded_passengers(trip_id);
CREATE INDEX IF NOT EXISTS idx_boarded_passengers_boarded_at ON boarded_passengers(boarded_at);

-- GPS logs
CREATE INDEX IF NOT EXISTS idx_gps_logs_trip ON gps_logs(trip_id);
CREATE INDEX IF NOT EXISTS idx_gps_logs_bus ON gps_logs(bus_id);

-- GPS locations
CREATE INDEX IF NOT EXISTS idx_gps_locations_trip_id ON gps_locations(trip_id);
CREATE INDEX IF NOT EXISTS idx_gps_locations_recorded_at ON gps_locations(recorded_at);
CREATE INDEX IF NOT EXISTS idx_gps_locations_source ON gps_locations(source);

-- Fare matrix
CREATE INDEX IF NOT EXISTS idx_fare_matrix_route ON fare_matrix(route_from, route_to);

-- Baggage fee matrix
CREATE INDEX IF NOT EXISTS idx_baggage_fee_matrix_category ON baggage_fee_matrix(category);

-- Fare irregularities
CREATE INDEX IF NOT EXISTS idx_fare_irregularities_trip ON fare_irregularities(trip_id);

-- Emergency alerts
CREATE INDEX IF NOT EXISTS idx_emergency_alerts_trip ON emergency_alerts(trip_id);
CREATE INDEX IF NOT EXISTS idx_emergency_alerts_status ON emergency_alerts(status);
CREATE INDEX IF NOT EXISTS idx_emergency_alerts_triggered_at ON emergency_alerts(triggered_at);

-- SMS logs
CREATE INDEX IF NOT EXISTS idx_sms_logs_phone_number ON sms_logs(phone_number);
CREATE INDEX IF NOT EXISTS idx_sms_logs_sms_type ON sms_logs(sms_type);
CREATE INDEX IF NOT EXISTS idx_sms_logs_sent_at ON sms_logs(sent_at);
CREATE INDEX IF NOT EXISTS idx_sms_logs_trip_id ON sms_logs(trip_id);
CREATE INDEX IF NOT EXISTS idx_sms_logs_status ON sms_logs(status);

-- SMS queue
CREATE INDEX IF NOT EXISTS idx_sms_queue_status ON sms_queue(status, created_at);
CREATE INDEX IF NOT EXISTS idx_sms_queue_trip ON sms_queue(trip_id);
CREATE INDEX IF NOT EXISTS idx_sms_queue_priority ON sms_queue(priority, created_at);

-- Hardware status
CREATE INDEX IF NOT EXISTS idx_hardware_status_component ON hardware_status(component);
CREATE INDEX IF NOT EXISTS idx_hardware_status_last_check ON hardware_status(last_check);

-- Video recordings
CREATE INDEX IF NOT EXISTS idx_video_recordings_trip_id ON video_recordings(trip_id);
CREATE INDEX IF NOT EXISTS idx_video_recordings_recorded_at ON video_recordings(recorded_at);
CREATE INDEX IF NOT EXISTS idx_video_recordings_status ON video_recordings(status);

-- Operator performance
CREATE INDEX IF NOT EXISTS idx_operator_performance_operator ON operator_performance(operator_id);
CREATE INDEX IF NOT EXISTS idx_operator_performance_period ON operator_performance(period_start, period_end);

-- Operator tasks
CREATE INDEX IF NOT EXISTS idx_operator_tasks_assigned_to ON operator_tasks(assigned_to);
CREATE INDEX IF NOT EXISTS idx_operator_tasks_status ON operator_tasks(status);
CREATE INDEX IF NOT EXISTS idx_operator_tasks_priority ON operator_tasks(priority);
CREATE INDEX IF NOT EXISTS idx_operator_tasks_due_date ON operator_tasks(due_date);

-- Operator notifications
CREATE INDEX IF NOT EXISTS idx_operator_notifications_operator ON operator_notifications(operator_id);
CREATE INDEX IF NOT EXISTS idx_operator_notifications_is_read ON operator_notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_operator_notifications_created_at ON operator_notifications(created_at);

-- Staff users
CREATE INDEX IF NOT EXISTS idx_staff_users_bus ON staff_users(bus_id) WHERE bus_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_staff_users_role ON staff_users(role);

-- Security events
CREATE INDEX IF NOT EXISTS idx_security_events_event_type ON security_events(event_type);
CREATE INDEX IF NOT EXISTS idx_security_events_severity ON security_events(severity);
CREATE INDEX IF NOT EXISTS idx_security_events_user_id ON security_events(user_id);
CREATE INDEX IF NOT EXISTS idx_security_events_created_at ON security_events(created_at);

-- Maintenance schedules
CREATE INDEX IF NOT EXISTS idx_maintenance_schedules_status ON maintenance_schedules(status);
CREATE INDEX IF NOT EXISTS idx_maintenance_schedules_scheduled_start ON maintenance_schedules(scheduled_start);
CREATE INDEX IF NOT EXISTS idx_maintenance_schedules_component ON maintenance_schedules(component);

-- System incidents
CREATE INDEX IF NOT EXISTS idx_system_incidents_status ON system_incidents(status);
CREATE INDEX IF NOT EXISTS idx_system_incidents_severity ON system_incidents(severity);
CREATE INDEX IF NOT EXISTS idx_system_incidents_incident_type ON system_incidents(incident_type);
CREATE INDEX IF NOT EXISTS idx_system_incidents_detected_at ON system_incidents(detected_at);

-- User sessions
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_status ON user_sessions(status);
CREATE INDEX IF NOT EXISTS idx_user_sessions_last_activity ON user_sessions(last_activity);

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE staff_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE buses ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE card_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE card_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE temporary_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE card_reloads ENABLE ROW LEVEL SECURITY;
ALTER TABLE passenger_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE boarded_passengers ENABLE ROW LEVEL SECURITY;
ALTER TABLE gps_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE gps_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE fare_matrix ENABLE ROW LEVEL SECURITY;
ALTER TABLE baggage_fee_matrix ENABLE ROW LEVEL SECURITY;
ALTER TABLE fare_irregularities ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE sms_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE sms_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE hardware_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_service_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE gcash_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_recordings ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_performance ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE performance_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE pi_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_incidents ENABLE ROW LEVEL SECURITY;

-- Helper function to get current user role
CREATE OR REPLACE FUNCTION current_user_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT role::TEXT FROM staff_users WHERE id = auth.uid();
$$;

-- Helper function to get active trip for conductor
CREATE OR REPLACE FUNCTION conductor_active_trip_id()
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT id FROM trips
  WHERE conductor_id = auth.uid()
    AND status = 'in_progress'
  ORDER BY started_at DESC
  LIMIT 1;
$$;

-- Helper function to get assigned bus
CREATE OR REPLACE FUNCTION get_assigned_bus()
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT bus_id FROM staff_users WHERE id = auth.uid();
$$;

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
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'announcements' AND policyname = 'Public read access on announcements') THEN
    CREATE POLICY "Public read access on announcements" ON announcements FOR SELECT USING (is_public = true AND status = 'active');
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

-- =====================
-- STAFF USERS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'staff_users' AND policyname = 'staff_users_self_select') THEN
    CREATE POLICY "staff_users_self_select" ON staff_users FOR SELECT
      USING (id = auth.uid() OR current_user_role() = 'admin');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'staff_users' AND policyname = 'staff_users_update_self') THEN
    CREATE POLICY "staff_users_update_self" ON staff_users FOR UPDATE
      USING (id = auth.uid() OR current_user_role() = 'admin')
      WITH CHECK (id = auth.uid() OR current_user_role() = 'admin');
  END IF;
END $$;

-- =====================
-- BUSES POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'buses' AND policyname = 'buses_read_all') THEN
    CREATE POLICY "buses_read_all" ON buses FOR SELECT
      USING (auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'buses' AND policyname = 'buses_update_admin') THEN
    CREATE POLICY "buses_update_admin" ON buses FOR UPDATE
      USING (current_user_role() = 'admin')
      WITH CHECK (current_user_role() = 'admin');
  END IF;
END $$;

-- =====================
-- TRIPS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'trips' AND policyname = 'trips_conductor_rw') THEN
    CREATE POLICY "trips_conductor_rw" ON trips FOR ALL
      USING (conductor_id = auth.uid() OR driver_id = auth.uid() OR operator_id = auth.uid() OR current_user_role() = 'admin')
      WITH CHECK (conductor_id = auth.uid() OR driver_id = auth.uid() OR operator_id = auth.uid());
  END IF;
END $$;

-- =====================
-- QR CARDS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'qr_cards' AND policyname = 'qr_cards_read_authenticated') THEN
    CREATE POLICY "qr_cards_read_authenticated" ON qr_cards FOR SELECT
      USING (auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'qr_cards' AND policyname = 'qr_cards_delete_authenticated') THEN
    CREATE POLICY "qr_cards_delete_authenticated" ON qr_cards FOR DELETE
      USING (auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'qr_cards' AND policyname = 'qr_cards_insert_authenticated') THEN
    CREATE POLICY "qr_cards_insert_authenticated" ON qr_cards FOR INSERT
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'qr_cards' AND policyname = 'qr_cards_update_authenticated') THEN
    CREATE POLICY "qr_cards_update_authenticated" ON qr_cards FOR UPDATE
      USING (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- CARD RESERVATIONS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'card_reservations' AND policyname = 'card_reservations_rw_authenticated') THEN
    CREATE POLICY "card_reservations_rw_authenticated" ON card_reservations FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- TEMPORARY TICKETS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'temporary_tickets' AND policyname = 'temp_tickets_rw_authenticated') THEN
    CREATE POLICY "temp_tickets_rw_authenticated" ON temporary_tickets FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- TRANSACTIONS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'transactions' AND policyname = 'transactions_insert_authenticated') THEN
    CREATE POLICY "transactions_insert_authenticated" ON transactions FOR INSERT
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'transactions' AND policyname = 'transactions_select_authenticated') THEN
    CREATE POLICY "transactions_select_authenticated" ON transactions FOR SELECT
      USING (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- PASSENGER COUNTS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'passenger_counts' AND policyname = 'passenger_counts_rw_authenticated') THEN
    CREATE POLICY "passenger_counts_rw_authenticated" ON passenger_counts FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- BOARDED PASSENGERS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'boarded_passengers' AND policyname = 'boarded_passengers_rw_authenticated') THEN
    CREATE POLICY "boarded_passengers_rw_authenticated" ON boarded_passengers FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- GPS LOGS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'gps_logs' AND policyname = 'gps_logs_rw_authenticated') THEN
    CREATE POLICY "gps_logs_rw_authenticated" ON gps_logs FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- FARE IRREGULARITIES POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'fare_irregularities' AND policyname = 'fare_irregularities_rw_authenticated') THEN
    CREATE POLICY "fare_irregularities_rw_authenticated" ON fare_irregularities FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- EMERGENCY ALERTS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'emergency_alerts' AND policyname = 'emergency_alerts_rw_authenticated') THEN
    CREATE POLICY "emergency_alerts_rw_authenticated" ON emergency_alerts FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- EMERGENCY CONTACTS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'emergency_contacts' AND policyname = 'emergency_contacts_rw_authenticated') THEN
    CREATE POLICY "emergency_contacts_rw_authenticated" ON emergency_contacts FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- SMS LOGS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sms_logs' AND policyname = 'sms_logs_rw_authenticated') THEN
    CREATE POLICY "sms_logs_rw_authenticated" ON sms_logs FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- SMS QUEUE POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sms_queue' AND policyname = 'sms_queue_rw_authenticated') THEN
    CREATE POLICY "sms_queue_rw_authenticated" ON sms_queue FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- GPS LOCATIONS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'gps_locations' AND policyname = 'gps_locations_rw_authenticated') THEN
    CREATE POLICY "gps_locations_rw_authenticated" ON gps_locations FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- HARDWARE STATUS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'hardware_status' AND policyname = 'hardware_status_rw_authenticated') THEN
    CREATE POLICY "hardware_status_rw_authenticated" ON hardware_status FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- CUSTOMER SERVICE LOGS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'customer_service_logs' AND policyname = 'cs_logs_rw_authenticated') THEN
    CREATE POLICY "cs_logs_rw_authenticated" ON customer_service_logs FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- GCASH TRANSACTIONS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'gcash_transactions' AND policyname = 'gcash_transactions_rw_authenticated') THEN
    CREATE POLICY "gcash_transactions_rw_authenticated" ON gcash_transactions FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- NOTIFICATIONS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'notifications' AND policyname = 'notifications_rw_authenticated') THEN
    CREATE POLICY "notifications_rw_authenticated" ON notifications FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- AUDIT LOGS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'audit_logs' AND policyname = 'audit_logs_rw_authenticated') THEN
    CREATE POLICY "audit_logs_rw_authenticated" ON audit_logs FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- VIDEO RECORDINGS POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'video_recordings' AND policyname = 'video_recordings_read_authenticated') THEN
    CREATE POLICY "video_recordings_read_authenticated" ON video_recordings FOR SELECT
      TO authenticated USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'video_recordings' AND policyname = 'video_recordings_insert_service_role') THEN
    CREATE POLICY "video_recordings_insert_service_role" ON video_recordings FOR INSERT
      TO service_role WITH CHECK (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'video_recordings' AND policyname = 'video_recordings_update_service_role') THEN
    CREATE POLICY "video_recordings_update_service_role" ON video_recordings FOR UPDATE
      TO service_role WITH CHECK (true);
  END IF;
END $$;

-- =====================
-- OPERATOR-SPECIFIC POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'operator_shifts' AND policyname = 'operator_shifts_self_all') THEN
    CREATE POLICY "operator_shifts_self_all" ON operator_shifts FOR ALL
      USING (operator_id = auth.uid() OR auth.role() = 'authenticated')
      WITH CHECK (operator_id = auth.uid() OR auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'operator_performance' AND policyname = 'operator_performance_self_all') THEN
    CREATE POLICY "operator_performance_self_all" ON operator_performance FOR ALL
      USING (operator_id = auth.uid() OR auth.role() = 'authenticated')
      WITH CHECK (operator_id = auth.uid() OR auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'operator_tasks' AND policyname = 'operator_tasks_assigned_all') THEN
    CREATE POLICY "operator_tasks_assigned_all" ON operator_tasks FOR ALL
      USING (assigned_to = auth.uid() OR assigned_by = auth.uid() OR auth.role() = 'authenticated')
      WITH CHECK (assigned_to = auth.uid() OR assigned_by = auth.uid() OR auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'operator_notifications' AND policyname = 'operator_notifications_self_all') THEN
    CREATE POLICY "operator_notifications_self_all" ON operator_notifications FOR ALL
      USING (operator_id = auth.uid())
      WITH CHECK (operator_id = auth.uid());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'performance_reports' AND policyname = 'performance_reports_rw_authenticated') THEN
    CREATE POLICY "performance_reports_rw_authenticated" ON performance_reports FOR ALL
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'announcements' AND policyname = 'announcements_read_authenticated') THEN
    CREATE POLICY "announcements_read_authenticated" ON announcements FOR SELECT
      USING (auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'announcements' AND policyname = 'announcements_insert_authenticated') THEN
    CREATE POLICY "announcements_insert_authenticated" ON announcements FOR INSERT
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'announcements' AND policyname = 'announcements_update_authenticated') THEN
    CREATE POLICY "announcements_update_authenticated" ON announcements FOR UPDATE
      USING (auth.role() = 'authenticated')
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END $$;

-- =====================
-- ADMIN-ONLY POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'system_config' AND policyname = 'system_config_admin_only') THEN
    CREATE POLICY "system_config_admin_only" ON system_config FOR ALL
      USING (current_user_role() = 'admin')
      WITH CHECK (current_user_role() = 'admin');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'security_events' AND policyname = 'security_events_admin_only') THEN
    CREATE POLICY "security_events_admin_only" ON security_events FOR ALL
      USING (current_user_role() = 'admin')
      WITH CHECK (current_user_role() = 'admin');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'maintenance_schedules' AND policyname = 'maintenance_schedules_admin_operator') THEN
    CREATE POLICY "maintenance_schedules_admin_operator" ON maintenance_schedules FOR ALL
      USING (current_user_role() IN ('admin', 'operator'))
      WITH CHECK (current_user_role() IN ('admin', 'operator'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_sessions' AND policyname = 'user_sessions_admin_only') THEN
    CREATE POLICY "user_sessions_admin_only" ON user_sessions FOR ALL
      USING (current_user_role() = 'admin')
      WITH CHECK (current_user_role() = 'admin');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'system_incidents' AND policyname = 'system_incidents_admin_operator') THEN
    CREATE POLICY "system_incidents_admin_operator" ON system_incidents FOR ALL
      USING (current_user_role() IN ('admin', 'operator'))
      WITH CHECK (current_user_role() IN ('admin', 'operator'));
  END IF;
END $$;

-- =====================
-- PI DEVICES POLICIES
-- =====================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'pi_devices' AND policyname = 'pi_devices_service_role') THEN
    CREATE POLICY "pi_devices_service_role" ON pi_devices FOR ALL
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

-- ============================================================
-- REALTIME PUBLICATIONS
-- ============================================================

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'passenger_counts') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE passenger_counts;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'fare_irregularities') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE fare_irregularities;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'emergency_alerts') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE emergency_alerts;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'trips') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE trips;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'boarded_passengers') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE boarded_passengers;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'emergency_contacts') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE emergency_contacts;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'sms_logs') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE sms_logs;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'gps_locations') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE gps_locations;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'hardware_status') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE hardware_status;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'system_incidents') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE system_incidents;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'security_events') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE security_events;
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
-- VIEWS FOR DASHBOARDS
-- ============================================================

CREATE OR REPLACE VIEW trip_statistics AS
SELECT
  trip_id,
  COUNT(*) as total_recordings,
  AVG(count) as average_passengers,
  MAX(count) as max_passengers,
  MIN(count) as min_passengers,
  MIN(recorded_at) as first_recording,
  MAX(recorded_at) as last_recording
FROM passenger_counts
GROUP BY trip_id;

CREATE OR REPLACE VIEW sms_statistics AS
SELECT
  DATE(sent_at) as date,
  sms_type,
  COUNT(*) as total_sent,
  COUNT(*) FILTER (WHERE status = 'sent') as successful,
  COUNT(*) FILTER (WHERE status = 'failed') as failed,
  COUNT(*) FILTER (WHERE status = 'pending') as pending
FROM sms_logs
GROUP BY DATE(sent_at), sms_type
ORDER BY date DESC, sms_type;

CREATE OR REPLACE VIEW emergency_statistics AS
SELECT
  COALESCE(DATE(triggered_at), DATE(created_at)) as date,
  COUNT(*) as total_emergencies,
  COUNT(*) FILTER (WHERE resolved = TRUE) as resolved,
  COUNT(*) FILTER (WHERE resolved = FALSE) as unresolved,
  COUNT(*) FILTER (WHERE status = 'active') as active,
  COUNT(*) FILTER (WHERE status = 'acknowledged') as acknowledged
FROM emergency_alerts
GROUP BY COALESCE(DATE(triggered_at), DATE(created_at))
ORDER BY date DESC;

CREATE OR REPLACE VIEW operator_dashboard_summary AS
SELECT
  s.id,
  s.full_name,
  s.email,
  s.role,
  s.is_active,
  s.last_login_at,
  COUNT(DISTINCT t.id) as total_trips,
  COUNT(DISTINCT CASE WHEN t.status = 'in_progress' THEN t.id END) as active_trips,
  COUNT(DISTINCT CASE WHEN os.status = 'active' THEN os.id END) as active_shifts,
  COUNT(DISTINCT CASE WHEN ot.status = 'pending' THEN ot.id END) as pending_tasks,
  COUNT(DISTINCT CASE WHEN onn.is_read = FALSE THEN onn.id END) as unread_notifications
FROM staff_users s
LEFT JOIN trips t ON s.id = t.operator_id
LEFT JOIN operator_shifts os ON s.id = os.operator_id
LEFT JOIN operator_tasks ot ON s.id = ot.assigned_to
LEFT JOIN operator_notifications onn ON s.id = onn.operator_id
WHERE s.is_active = TRUE
GROUP BY s.id, s.full_name, s.email, s.role, s.is_active, s.last_login_at;

-- ============================================================
-- Schema complete.
-- ============================================================
 