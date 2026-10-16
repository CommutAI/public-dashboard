-- ============================================
-- CommutAI Database Schema
-- One Manolo Fortich Transport System
-- ============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- 1. BUSES TABLE
-- Stores information about buses in the fleet
-- ============================================
CREATE TABLE buses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bus_number VARCHAR(20) UNIQUE NOT NULL,
    plate_number VARCHAR(20) UNIQUE NOT NULL,
    seat_capacity INTEGER NOT NULL CHECK (seat_capacity > 0),
    bus_type VARCHAR(50) NOT NULL, -- e.g., 'Standard', 'Air-conditioned', 'Deluxe'
    manufacturer VARCHAR(100),
    model_year INTEGER,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'maintenance', 'retired')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for bus lookups
CREATE INDEX idx_buses_bus_number ON buses(bus_number);
CREATE INDEX idx_buses_status ON buses(status);

-- ============================================
-- 2. BUS_STOPS TABLE
-- Stores information about bus stops along the route
-- ============================================
CREATE TABLE bus_stops (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    stop_code VARCHAR(20) UNIQUE NOT NULL, -- e.g., 'STOP 01'
    name VARCHAR(100) NOT NULL, -- e.g., 'Manolo Fortich Terminal'
    location VARCHAR(100) NOT NULL, -- e.g., 'Manolo Fortich Terminal'
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    stop_type VARCHAR(20) NOT NULL CHECK (stop_type IN ('terminal', 'regular', 'transit')),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    sequence_order INTEGER NOT NULL, -- Order along the route
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for stop lookups
CREATE INDEX idx_bus_stops_code ON bus_stops(stop_code);
CREATE INDEX idx_bus_stops_sequence ON bus_stops(sequence_order);
CREATE INDEX idx_bus_stops_status ON bus_stops(status);

-- ============================================
-- 3. ROUTES TABLE
-- Defines bus routes between terminals
-- ============================================
CREATE TABLE routes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_code VARCHAR(20) UNIQUE NOT NULL, -- e.g., 'MF-AGORA'
    name VARCHAR(100) NOT NULL, -- e.g., 'Manolo Fortich to Agora Terminal'
    start_stop_id UUID NOT NULL REFERENCES bus_stops(id),
    end_stop_id UUID NOT NULL REFERENCES bus_stops(id),
    total_distance_km DECIMAL(8, 2),
    estimated_duration_minutes INTEGER,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for route lookups
CREATE INDEX idx_routes_code ON routes(route_code);
CREATE INDEX idx_routes_status ON routes(status);

-- ============================================
-- 4. TRIP_SCHEDULES TABLE
-- Defines scheduled trips with departure/arrival times
-- ============================================
CREATE TABLE trip_schedules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_id UUID NOT NULL REFERENCES routes(id),
    trip_number INTEGER NOT NULL,
    departure_time_start TIME NOT NULL, -- Scheduled departure from start terminal
    arrival_time_start TIME NOT NULL, -- Scheduled arrival at end terminal
    arrival_time_end TIME NOT NULL, -- Latest arrival time
    days_of_operation VARCHAR(20) NOT NULL DEFAULT 'daily', -- e.g., 'daily', 'weekdays', 'weekends'
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(route_id, trip_number)
);

-- Index for schedule lookups
CREATE INDEX idx_trip_schedules_route ON trip_schedules(route_id);
CREATE INDEX idx_trip_schedules_status ON trip_schedules(status);

-- ============================================
-- 5. TRIPS TABLE
-- Represents actual trip instances (real-time tracking)
-- ============================================
CREATE TABLE trips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    schedule_id UUID REFERENCES trip_schedules(id),
    bus_id UUID NOT NULL REFERENCES buses(id),
    route_id UUID NOT NULL REFERENCES routes(id),
    trip_number INTEGER NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'in_progress', 'completed', 'cancelled')),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    current_lat DECIMAL(10, 8), -- Current GPS latitude
    current_lng DECIMAL(11, 8), -- Current GPS longitude
    gps_updated_at TIMESTAMP WITH TIME ZONE, -- Last GPS update timestamp
    current_stop_id UUID REFERENCES bus_stops(id), -- Nearest stop
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for trip tracking
CREATE INDEX idx_trips_status ON trips(status);
CREATE INDEX idx_trips_bus ON trips(bus_id);
CREATE INDEX idx_trips_route ON trips(route_id);
CREATE INDEX idx_trips_started_at ON trips(started_at DESC);

-- ============================================
-- 6. GPS_LOGS TABLE
-- Stores GPS location history for tracking
-- ============================================
CREATE TABLE gps_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id UUID NOT NULL REFERENCES trips(id),
    bus_id UUID NOT NULL REFERENCES buses(id),
    lat DECIMAL(10, 8) NOT NULL,
    lng DECIMAL(11, 8) NOT NULL,
    speed_kmh DECIMAL(6, 2), -- Speed in km/h
    heading DECIMAL(5, 2), -- Direction in degrees
    recorded_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for GPS queries
CREATE INDEX idx_gps_logs_trip ON gps_logs(trip_id);
CREATE INDEX idx_gps_logs_bus ON gps_logs(bus_id);
CREATE INDEX idx_gps_logs_recorded_at ON gps_logs(recorded_at DESC);

-- ============================================
-- 7. CARD_TYPES TABLE
-- Defines available card types and their benefits
-- ============================================
CREATE TABLE card_types (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) UNIQUE NOT NULL, -- e.g., 'Regular', 'Student', 'Senior Citizen', 'PWD'
    card_type VARCHAR(20) NOT NULL CHECK (card_type IN ('permanent', 'temporary')),
    discount_percentage DECIMAL(5, 2) NOT NULL DEFAULT 0, -- e.g., 20 for 20% discount
    validity_days INTEGER, -- Days the card is valid (NULL for permanent cards)
    description TEXT,
    image_url VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for card type lookups
CREATE INDEX idx_card_types_name ON card_types(name);
CREATE INDEX idx_card_types_status ON card_types(status);

-- ============================================
-- 8. CARDS TABLE
-- Stores issued QR cards
-- ============================================
CREATE TABLE cards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_number VARCHAR(50) UNIQUE NOT NULL, -- Unique QR card identifier
    card_type_id UUID NOT NULL REFERENCES card_types(id),
    holder_name VARCHAR(100) NOT NULL,
    contact_number VARCHAR(20),
    email VARCHAR(100),
    balance DECIMAL(10, 2) NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'lost', 'stolen', 'expired')),
    issued_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE, -- Card expiration date
    last_used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for card lookups
CREATE INDEX idx_cards_number ON cards(card_number);
CREATE INDEX idx_cards_holder ON cards(holder_name);
CREATE INDEX idx_cards_status ON cards(status);
CREATE INDEX idx_cards_contact ON cards(contact_number);

-- ============================================
-- 9. CARD_RESERVATIONS TABLE
-- Stores online card reservation requests
-- ============================================
CREATE TABLE card_reservations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_id VARCHAR(50) UNIQUE NOT NULL, -- Human-readable reservation ID
    name VARCHAR(100) NOT NULL,
    contact VARCHAR(20) NOT NULL,
    card_type VARCHAR(50) NOT NULL, -- Card type name
    pickup_terminal VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'claimed', 'expired', 'cancelled')),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL, -- 7 days from creation
    claimed_at TIMESTAMP WITH TIME ZONE,
    card_id UUID REFERENCES cards(id) -- Set when card is claimed
);

-- Index for reservation lookups
CREATE INDEX idx_card_reservations_id ON card_reservations(reservation_id);
CREATE INDEX idx_card_reservations_contact ON card_reservations(contact);
CREATE INDEX idx_card_reservations_status ON card_reservations(status);
CREATE INDEX idx_card_reservations_expires ON card_reservations(expires_at);

-- ============================================
-- 10. FARE_MATRIX TABLE
-- Stores fare rates between stops
-- ============================================
CREATE TABLE fare_matrix (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_id UUID NOT NULL REFERENCES routes(id),
    from_stop_id UUID NOT NULL REFERENCES bus_stops(id),
    to_stop_id UUID NOT NULL REFERENCES bus_stops(id),
    regular_fare DECIMAL(8, 2) NOT NULL,
    discounted_fare DECIMAL(8, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(route_id, from_stop_id, to_stop_id)
);

-- Index for fare calculations
CREATE INDEX idx_fare_matrix_route ON fare_matrix(route_id);
CREATE INDEX idx_fare_matrix_from_to ON fare_matrix(from_stop_id, to_stop_id);

-- ============================================
-- 11. PASSENGER_COUNTS TABLE
-- Stores real-time passenger occupancy data
-- ============================================
CREATE TABLE passenger_counts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id UUID NOT NULL REFERENCES trips(id),
    bus_id UUID NOT NULL REFERENCES buses(id),
    count INTEGER NOT NULL, -- Manual count
    ai_count INTEGER, -- AI-detected count (preferred if available)
    recorded_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for occupancy queries
CREATE INDEX idx_passenger_counts_trip ON passenger_counts(trip_id);
CREATE INDEX idx_passenger_counts_bus ON passenger_counts(bus_id);
CREATE INDEX idx_passenger_counts_recorded_at ON passenger_counts(recorded_at DESC);

-- ============================================
-- 12. TRANSACTIONS TABLE
-- Stores fare payment transactions
-- ============================================
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id UUID REFERENCES cards(id),
    trip_id UUID REFERENCES trips(id),
    passenger_name VARCHAR(100), -- For cash/ticket transactions
    from_stop_id UUID REFERENCES bus_stops(id),
    to_stop_id UUID REFERENCES bus_stops(id),
    fare_amount DECIMAL(8, 2) NOT NULL,
    discount_amount DECIMAL(8, 2) NOT NULL DEFAULT 0,
    final_amount DECIMAL(8, 2) NOT NULL,
    payment_method VARCHAR(20) NOT NULL CHECK (payment_method IN ('card', 'cash', 'ticket')),
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('fare', 'reload', 'refund')),
    status VARCHAR(20) NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
    recorded_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for transaction queries
CREATE INDEX idx_transactions_card ON transactions(card_id);
CREATE INDEX idx_transactions_trip ON transactions(trip_id);
CREATE INDEX idx_transactions_recorded_at ON transactions(recorded_at DESC);
CREATE INDEX idx_transactions_status ON transactions(status);

-- ============================================
-- 13. CARD_RELOADS TABLE
-- Stores card reload/top-up history
-- ============================================
CREATE TABLE card_reloads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id UUID NOT NULL REFERENCES cards(id),
    amount DECIMAL(10, 2) NOT NULL,
    reload_method VARCHAR(20) NOT NULL CHECK (reload_method IN ('cash', 'gcash', 'maya', 'bank')),
    reference_number VARCHAR(100),
    reload_location VARCHAR(100), -- e.g., terminal, kiosk
    status VARCHAR(20) NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed')),
    recorded_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for reload queries
CREATE INDEX idx_card_reloads_card ON card_reloads(card_id);
CREATE INDEX idx_card_reloads_recorded_at ON card_reloads(recorded_at DESC);

-- ============================================
-- FUNCTIONS AND TRIGGERS
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to relevant tables
CREATE TRIGGER update_buses_updated_at BEFORE UPDATE ON buses
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_bus_stops_updated_at BEFORE UPDATE ON bus_stops
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_routes_updated_at BEFORE UPDATE ON routes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_trip_schedules_updated_at BEFORE UPDATE ON trip_schedules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_trips_updated_at BEFORE UPDATE ON trips
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_card_types_updated_at BEFORE UPDATE ON card_types
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_cards_updated_at BEFORE UPDATE ON cards
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_fare_matrix_updated_at BEFORE UPDATE ON fare_matrix
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- INITIAL DATA SEEDING
-- ============================================

-- Insert card types
INSERT INTO card_types (name, card_type, discount_percentage, validity_days, description) VALUES
('Regular', 'permanent', 0, 365, 'Standard fare rates'),
('Student', 'permanent', 20, 365, '20% discount on all fares'),
('Senior Citizen', 'permanent', 20, 365, 'Special discounted rates'),
('PWD', 'permanent', 20, 365, 'Maximum discount benefits'),
('TEMP REGULAR', 'temporary', 0, 7, 'Standard fare rates'),
('TEMP STUDENT', 'temporary', 20, 7, '20% discount on all fares'),
('TEMP SENIOR', 'temporary', 20, 7, 'Special discounted rates'),
('TEMP PWD', 'temporary', 20, 7, 'Maximum discount benefits');

-- Insert buses
INSERT INTO buses (bus_number, plate_number, seat_capacity, bus_type, manufacturer, model_year, status) VALUES
('BUS-001', 'ABC-1234', 45, 'Air-conditioned', 'Hyundai', 2020, 'active'),
('BUS-002', 'DEF-5678', 45, 'Air-conditioned', 'Hyundai', 2021, 'active'),
('BUS-003', 'GHI-9012', 50, 'Deluxe', 'Toyota', 2022, 'active');

-- Insert bus stops (based on the hardcoded data in App.tsx)
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
('STOP 14', 'Agora Terminal', 'Agora Terminal', 8.489074818449854, 124.65762898250219, 'terminal', 14);

-- Insert route
INSERT INTO routes (route_code, name, start_stop_id, end_stop_id, total_distance_km, estimated_duration_minutes) VALUES
('MF-AGORA', 'Manolo Fortich to Agora Terminal',
 (SELECT id FROM bus_stops WHERE stop_code = 'STOP 01'),
 (SELECT id FROM bus_stops WHERE stop_code = 'STOP 14'),
 45.5, 90);

-- Insert trip schedules (based on hardcoded data in App.tsx)
INSERT INTO trip_schedules (route_id, trip_number, departure_time_start, arrival_time_start, arrival_time_end) VALUES
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 1, '05:00:00', '06:30:00', '07:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 2, '07:00:00', '08:30:00', '09:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 3, '09:00:00', '10:30:00', '11:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 4, '11:00:00', '12:30:00', '13:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 5, '13:00:00', '14:30:00', '15:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 6, '15:00:00', '16:30:00', '17:00:00'),
((SELECT id FROM routes WHERE route_code = 'MF-AGORA'), 7, '17:00:00', '18:30:00', '19:00:00');

-- ============================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================

-- Enable RLS on all tables
ALTER TABLE buses ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE gps_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE card_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE card_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE fare_matrix ENABLE ROW LEVEL SECURITY;
ALTER TABLE passenger_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE card_reloads ENABLE ROW LEVEL SECURITY;

-- Public read access for public dashboard
CREATE POLICY "Public read access on buses" ON buses FOR SELECT USING (true);
CREATE POLICY "Public read access on bus_stops" ON bus_stops FOR SELECT USING (true);
CREATE POLICY "Public read access on routes" ON routes FOR SELECT USING (true);
CREATE POLICY "Public read access on trip_schedules" ON trip_schedules FOR SELECT USING (true);
CREATE POLICY "Public read access on trips" ON trips FOR SELECT USING (true);
CREATE POLICY "Public read access on gps_logs" ON gps_logs FOR SELECT USING (true);
CREATE POLICY "Public read access on card_types" ON card_types FOR SELECT USING (true);
CREATE POLICY "Public read access on fare_matrix" ON fare_matrix FOR SELECT USING (true);
CREATE POLICY "Public read access on passenger_counts" ON passenger_counts FOR SELECT USING (true);

-- Allow public insert for card reservations (via anon key)
CREATE POLICY "Public insert card reservations" ON card_reservations FOR INSERT WITH CHECK (true);
CREATE POLICY "Public read own reservations" ON card_reservations FOR SELECT USING (true);

-- Service role or authenticated users can modify other tables
-- (These policies should be refined based on actual authentication setup)
CREATE POLICY "Service role full access on buses" ON buses FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on bus_stops" ON bus_stops FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on routes" ON routes FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on trip_schedules" ON trip_schedules FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on trips" ON trips FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on gps_logs" ON gps_logs FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on card_types" ON card_types FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on cards" ON cards FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on card_reservations" ON card_reservations FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on fare_matrix" ON fare_matrix FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on passenger_counts" ON passenger_counts FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on transactions" ON transactions FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on card_reloads" ON card_reloads FOR ALL USING (auth.role() = 'service_role');

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON TABLE buses IS 'Stores information about buses in the fleet';
COMMENT ON TABLE bus_stops IS 'Stores information about bus stops along the route';
COMMENT ON TABLE routes IS 'Defines bus routes between terminals';
COMMENT ON TABLE trip_schedules IS 'Defines scheduled trips with departure/arrival times';
COMMENT ON TABLE trips IS 'Represents actual trip instances for real-time tracking';
COMMENT ON TABLE gps_logs IS 'Stores GPS location history for tracking';
COMMENT ON TABLE card_types IS 'Defines available card types and their benefits';
COMMENT ON TABLE cards IS 'Stores issued QR cards';
COMMENT ON TABLE card_reservations IS 'Stores online card reservation requests';
COMMENT ON TABLE fare_matrix IS 'Stores fare rates between stops';
COMMENT ON TABLE passenger_counts IS 'Stores real-time passenger occupancy data';
COMMENT ON TABLE transactions IS 'Stores fare payment transactions';
COMMENT ON TABLE card_reloads IS 'Stores card reload/top-up history';
