-- ============================================================
-- Enterprise Carpooling Platform — Supabase Schema
-- Run this ONCE in the Supabase SQL Editor (Dashboard → SQL).
-- Assumes the `profiles` table from Phase 1 already exists.
-- ============================================================

-- ---------- ORGANIZATIONS ----------
CREATE TABLE IF NOT EXISTS organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  industry TEXT,
  address TEXT,
  admin_contact TEXT,
  fuel_cost_per_liter NUMERIC DEFAULT 100,
  cost_per_km NUMERIC DEFAULT 12,
  travel_cost_per_km NUMERIC DEFAULT 15,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  is_deleted BOOLEAN DEFAULT FALSE
);

-- ---------- VEHICLES ----------
CREATE TABLE IF NOT EXISTS vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  org_id UUID REFERENCES organizations(id),
  model TEXT NOT NULL,
  registration_number TEXT NOT NULL UNIQUE,
  seating_capacity INT NOT NULL DEFAULT 4 CHECK (seating_capacity BETWEEN 1 AND 10),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  is_deleted BOOLEAN DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_vehicles_owner ON vehicles(owner_id) WHERE NOT is_deleted;

-- ---------- RIDES ----------
CREATE TABLE IF NOT EXISTS rides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  vehicle_id UUID NOT NULL REFERENCES vehicles(id),
  org_id UUID REFERENCES organizations(id),
  pickup_address TEXT NOT NULL,
  pickup_lat DOUBLE PRECISION NOT NULL,
  pickup_lng DOUBLE PRECISION NOT NULL,
  destination_address TEXT NOT NULL,
  destination_lat DOUBLE PRECISION NOT NULL,
  destination_lng DOUBLE PRECISION NOT NULL,
  route_polyline TEXT,
  distance_km NUMERIC,
  duration_minutes INT,
  departure_time TIMESTAMPTZ NOT NULL,
  total_seats INT NOT NULL CHECK (total_seats BETWEEN 1 AND 7),
  available_seats INT NOT NULL CHECK (available_seats >= 0),
  fare_per_seat NUMERIC NOT NULL CHECK (fare_per_seat > 0),
  is_recurring BOOLEAN DEFAULT FALSE,
  recurring_days TEXT,
  status TEXT NOT NULL DEFAULT 'published'
    CHECK (status IN ('published', 'in_progress', 'completed', 'cancelled')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  is_deleted BOOLEAN DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_rides_search
  ON rides(status, departure_time) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_rides_driver ON rides(driver_id, status) WHERE NOT is_deleted;

-- ---------- BOOKINGS ----------
CREATE TABLE IF NOT EXISTS bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  passenger_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  seats_booked INT NOT NULL CHECK (seats_booked >= 1),
  total_fare NUMERIC NOT NULL,
  status TEXT NOT NULL DEFAULT 'booked'
    CHECK (status IN ('booked', 'in_progress', 'completed', 'cancelled',
                      'payment_pending', 'payment_completed')),
  booked_at TIMESTAMPTZ DEFAULT NOW(),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  cancellation_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  is_deleted BOOLEAN DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_bookings_passenger ON bookings(passenger_id, status) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_bookings_ride ON bookings(ride_id, status) WHERE NOT is_deleted;

-- ---------- WALLETS ----------
CREATE TABLE IF NOT EXISTS wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  balance NUMERIC NOT NULL DEFAULT 0 CHECK (balance >= 0),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('credit', 'debit')),
  amount NUMERIC NOT NULL CHECK (amount > 0),
  balance_after NUMERIC NOT NULL,
  description TEXT,
  reference_id UUID,
  reference_type TEXT CHECK (reference_type IN ('recharge', 'ride_payment', 'refund')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_wallet_txn ON wallet_transactions(wallet_id, created_at DESC);

-- Auto-create wallet when a profile is created
CREATE OR REPLACE FUNCTION create_wallet_for_profile()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO wallets (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_create_wallet ON profiles;
CREATE TRIGGER trg_create_wallet
  AFTER INSERT ON profiles
  FOR EACH ROW EXECUTE FUNCTION create_wallet_for_profile();

-- Backfill wallets for existing profiles
INSERT INTO wallets (user_id)
SELECT id FROM profiles
ON CONFLICT (user_id) DO NOTHING;

-- ---------- PAYMENTS ----------
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  payer_id UUID NOT NULL REFERENCES profiles(id),
  amount NUMERIC NOT NULL CHECK (amount > 0),
  method TEXT NOT NULL CHECK (method IN ('cash', 'card', 'upi', 'wallet')),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded')),
  transaction_id TEXT,
  gateway_response TEXT,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_payments_booking ON payments(booking_id);

-- ---------- RIDE LOCATIONS (live tracking history) ----------
CREATE TABLE IF NOT EXISTS ride_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  speed DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ride_locations ON ride_locations(ride_id, recorded_at DESC);

-- ---------- CHAT MESSAGES ----------
CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES profiles(id),
  content TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  sent_at TIMESTAMPTZ DEFAULT NOW(),
  read_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_chat_booking ON chat_messages(booking_id, sent_at);

-- ---------- SAVED PLACES ----------
CREATE TABLE IF NOT EXISTS saved_places (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  address TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  is_deleted BOOLEAN DEFAULT FALSE
);

-- ---------- NOTIFICATIONS ----------
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT,
  data JSONB,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  read_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, is_read, created_at DESC);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE rides ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ride_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_places ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Profiles: allow authenticated users to read co-worker basics (driver names on ride cards)
DROP POLICY IF EXISTS "Authenticated can read profiles" ON profiles;
CREATE POLICY "Authenticated can read profiles" ON profiles
  FOR SELECT TO authenticated USING (true);

-- Organizations: readable by all authenticated; admins update
CREATE POLICY "org read" ON organizations FOR SELECT TO authenticated USING (true);
CREATE POLICY "org update by admin" ON organizations FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));

-- Vehicles: everyone authenticated can read (shown on ride cards); owner manages
CREATE POLICY "vehicles read" ON vehicles FOR SELECT TO authenticated USING (true);
CREATE POLICY "vehicles insert own" ON vehicles FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid());
CREATE POLICY "vehicles update own" ON vehicles FOR UPDATE TO authenticated
  USING (owner_id = auth.uid() OR EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));
CREATE POLICY "vehicles delete own" ON vehicles FOR DELETE TO authenticated
  USING (owner_id = auth.uid());

-- Rides: all authenticated can read; driver manages own
CREATE POLICY "rides read" ON rides FOR SELECT TO authenticated USING (true);
CREATE POLICY "rides insert own" ON rides FOR INSERT TO authenticated
  WITH CHECK (driver_id = auth.uid());
CREATE POLICY "rides update own" ON rides FOR UPDATE TO authenticated
  USING (driver_id = auth.uid());

-- Bookings: passenger reads own; driver reads bookings on their rides
CREATE POLICY "bookings read" ON bookings FOR SELECT TO authenticated
  USING (passenger_id = auth.uid()
    OR EXISTS (SELECT 1 FROM rides r WHERE r.id = ride_id AND r.driver_id = auth.uid()));
CREATE POLICY "bookings update" ON bookings FOR UPDATE TO authenticated
  USING (passenger_id = auth.uid()
    OR EXISTS (SELECT 1 FROM rides r WHERE r.id = ride_id AND r.driver_id = auth.uid()));
-- (inserts happen only through the book_ride RPC below)

-- Wallets: owner only (mutations via RPCs)
CREATE POLICY "wallet read own" ON wallets FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "wallet txn read own" ON wallet_transactions FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM wallets w WHERE w.id = wallet_id AND w.user_id = auth.uid()));

-- Payments: payer + ride driver can read; payer inserts/updates
CREATE POLICY "payments read" ON payments FOR SELECT TO authenticated
  USING (payer_id = auth.uid()
    OR EXISTS (SELECT 1 FROM bookings b JOIN rides r ON r.id = b.ride_id
               WHERE b.id = booking_id AND r.driver_id = auth.uid()));
CREATE POLICY "payments insert own" ON payments FOR INSERT TO authenticated
  WITH CHECK (payer_id = auth.uid());
CREATE POLICY "payments update own" ON payments FOR UPDATE TO authenticated
  USING (payer_id = auth.uid());

-- Ride locations: driver inserts; participants read
CREATE POLICY "locations insert by driver" ON ride_locations FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM rides r WHERE r.id = ride_id AND r.driver_id = auth.uid()));
CREATE POLICY "locations read by participants" ON ride_locations FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM rides r WHERE r.id = ride_id AND r.driver_id = auth.uid())
    OR EXISTS (SELECT 1 FROM bookings b WHERE b.ride_id = ride_id AND b.passenger_id = auth.uid()));

-- Chat: booking participants only
CREATE POLICY "chat read" ON chat_messages FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM bookings b JOIN rides r ON r.id = b.ride_id
                 WHERE b.id = booking_id AND (b.passenger_id = auth.uid() OR r.driver_id = auth.uid())));
CREATE POLICY "chat insert" ON chat_messages FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid()
    AND EXISTS (SELECT 1 FROM bookings b JOIN rides r ON r.id = b.ride_id
                WHERE b.id = booking_id AND (b.passenger_id = auth.uid() OR r.driver_id = auth.uid())));
CREATE POLICY "chat update read-status" ON chat_messages FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM bookings b JOIN rides r ON r.id = b.ride_id
                 WHERE b.id = booking_id AND (b.passenger_id = auth.uid() OR r.driver_id = auth.uid())));

-- Saved places / notifications: owner only
CREATE POLICY "places all own" ON saved_places FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "notifications read own" ON notifications FOR SELECT TO authenticated
  USING (user_id = auth.uid());
CREATE POLICY "notifications update own" ON notifications FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

-- ============================================================
-- RPC FUNCTIONS
-- ============================================================

-- ---------- SEARCH RIDES (haversine proximity) ----------
CREATE OR REPLACE FUNCTION search_rides(
  p_pickup_lat DOUBLE PRECISION,
  p_pickup_lng DOUBLE PRECISION,
  p_dest_lat DOUBLE PRECISION,
  p_dest_lng DOUBLE PRECISION,
  p_date DATE,
  p_seats INT DEFAULT 1,
  p_radius_km NUMERIC DEFAULT 5
)
RETURNS SETOF JSON
LANGUAGE sql SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'id', r.id,
    'driver_id', r.driver_id,
    'driver_name', p.name,
    'driver_avatar', p.avatar_url,
    'driver_phone', p.phone,
    'vehicle_id', v.id,
    'vehicle_model', v.model,
    'vehicle_registration', v.registration_number,
    'pickup_address', r.pickup_address,
    'pickup_lat', r.pickup_lat,
    'pickup_lng', r.pickup_lng,
    'destination_address', r.destination_address,
    'destination_lat', r.destination_lat,
    'destination_lng', r.destination_lng,
    'route_polyline', r.route_polyline,
    'distance_km', r.distance_km,
    'duration_minutes', r.duration_minutes,
    'departure_time', r.departure_time,
    'total_seats', r.total_seats,
    'available_seats', r.available_seats,
    'fare_per_seat', r.fare_per_seat,
    'is_recurring', r.is_recurring,
    'recurring_days', r.recurring_days,
    'status', r.status
  )
  FROM rides r
  JOIN profiles p ON p.id = r.driver_id
  JOIN vehicles v ON v.id = r.vehicle_id
  WHERE r.status = 'published'
    AND NOT r.is_deleted
    AND r.driver_id <> auth.uid()
    AND r.available_seats >= p_seats
    AND r.departure_time::date = p_date
    AND r.departure_time > NOW()
    -- pickup proximity (haversine, km)
    AND (6371 * acos(LEAST(1.0,
          cos(radians(p_pickup_lat)) * cos(radians(r.pickup_lat))
          * cos(radians(r.pickup_lng) - radians(p_pickup_lng))
          + sin(radians(p_pickup_lat)) * sin(radians(r.pickup_lat))
        ))) <= p_radius_km
    -- destination proximity
    AND (6371 * acos(LEAST(1.0,
          cos(radians(p_dest_lat)) * cos(radians(r.destination_lat))
          * cos(radians(r.destination_lng) - radians(p_dest_lng))
          + sin(radians(p_dest_lat)) * sin(radians(r.destination_lat))
        ))) <= p_radius_km
  ORDER BY r.departure_time ASC;
$$;

-- ---------- BOOK RIDE (atomic, race-safe) ----------
CREATE OR REPLACE FUNCTION book_ride(p_ride_id UUID, p_seats INT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride rides%ROWTYPE;
  v_booking bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_ride FROM rides WHERE id = p_ride_id AND NOT is_deleted FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'RIDE_NOT_FOUND';
  END IF;
  IF v_ride.driver_id = auth.uid() THEN
    RAISE EXCEPTION 'CANNOT_BOOK_OWN_RIDE';
  END IF;
  IF v_ride.status <> 'published' THEN
    RAISE EXCEPTION 'RIDE_NOT_AVAILABLE';
  END IF;
  IF v_ride.available_seats < p_seats THEN
    RAISE EXCEPTION 'INSUFFICIENT_SEATS';
  END IF;
  IF EXISTS (SELECT 1 FROM bookings
             WHERE ride_id = p_ride_id AND passenger_id = auth.uid()
               AND status NOT IN ('cancelled')) THEN
    RAISE EXCEPTION 'ALREADY_BOOKED';
  END IF;

  UPDATE rides
  SET available_seats = available_seats - p_seats, updated_at = NOW()
  WHERE id = p_ride_id;

  INSERT INTO bookings (ride_id, passenger_id, seats_booked, total_fare)
  VALUES (p_ride_id, auth.uid(), p_seats, p_seats * v_ride.fare_per_seat)
  RETURNING * INTO v_booking;

  RETURN row_to_json(v_booking);
END $$;

-- ---------- CANCEL BOOKING (restores seats) ----------
CREATE OR REPLACE FUNCTION cancel_booking(p_booking_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR v_booking.passenger_id <> auth.uid() THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;
  IF v_booking.status NOT IN ('booked') THEN
    RAISE EXCEPTION 'CANNOT_CANCEL';
  END IF;

  UPDATE bookings
  SET status = 'cancelled', cancelled_at = NOW(),
      cancellation_reason = p_reason, updated_at = NOW()
  WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  UPDATE rides
  SET available_seats = available_seats + v_booking.seats_booked, updated_at = NOW()
  WHERE id = v_booking.ride_id;

  RETURN row_to_json(v_booking);
END $$;

-- ---------- WALLET: RECHARGE ----------
CREATE OR REPLACE FUNCTION recharge_wallet(p_amount NUMERIC, p_description TEXT DEFAULT 'Wallet recharge')
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet wallets%ROWTYPE;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT';
  END IF;
  SELECT * INTO v_wallet FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO wallets (user_id) VALUES (auth.uid()) RETURNING * INTO v_wallet;
  END IF;

  UPDATE wallets SET balance = balance + p_amount, updated_at = NOW()
  WHERE id = v_wallet.id RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions (wallet_id, type, amount, balance_after, description, reference_type)
  VALUES (v_wallet.id, 'credit', p_amount, v_wallet.balance, p_description, 'recharge');

  RETURN json_build_object('balance', v_wallet.balance);
END $$;

-- ---------- WALLET: PAY FOR BOOKING ----------
CREATE OR REPLACE FUNCTION pay_with_wallet(p_booking_id UUID)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet wallets%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_payment payments%ROWTYPE;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id AND passenger_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  SELECT * INTO v_wallet FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR v_wallet.balance < v_booking.total_fare THEN
    RAISE EXCEPTION 'INSUFFICIENT_BALANCE';
  END IF;

  UPDATE wallets SET balance = balance - v_booking.total_fare, updated_at = NOW()
  WHERE id = v_wallet.id RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions (wallet_id, type, amount, balance_after, description, reference_id, reference_type)
  VALUES (v_wallet.id, 'debit', v_booking.total_fare, v_wallet.balance, 'Ride payment', p_booking_id, 'ride_payment');

  INSERT INTO payments (booking_id, payer_id, amount, method, status, transaction_id, paid_at)
  VALUES (p_booking_id, auth.uid(), v_booking.total_fare, 'wallet', 'completed',
          'WLT-' || substr(gen_random_uuid()::text, 1, 8), NOW())
  RETURNING * INTO v_payment;

  UPDATE bookings SET status = 'payment_completed', updated_at = NOW() WHERE id = p_booking_id;

  RETURN json_build_object('payment_id', v_payment.id, 'balance', v_wallet.balance);
END $$;

-- ============================================================
-- REALTIME: enable for live tracking + chat tables
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE ride_locations;
ALTER PUBLICATION supabase_realtime ADD TABLE chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE bookings;
ALTER PUBLICATION supabase_realtime ADD TABLE rides;
