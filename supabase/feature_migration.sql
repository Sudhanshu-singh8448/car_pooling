-- ============================================================
-- Feature Migration — All new features (Phases 1-6)
-- Run AFTER schema.sql AND schema_updates.sql in the Supabase SQL Editor.
-- ============================================================

-- ============================================================
-- 1. EXTEND BOOKINGS STATUS ENUM
-- ============================================================
-- Add 'pending', 'accepted', 'rejected' to the bookings status check.
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_status_check;
ALTER TABLE bookings ADD CONSTRAINT bookings_status_check
  CHECK (status IN (
    'pending',           -- passenger requested, awaiting driver response
    'accepted',          -- driver accepted the request
    'booked',            -- legacy: instant booking (kept for backward compat)
    'in_progress',       -- ride has started
    'completed',         -- ride completed, payment pending
    'cancelled',         -- cancelled by passenger or driver
    'rejected',          -- driver rejected the request
    'payment_pending',   -- awaiting payment
    'payment_completed'  -- payment done
  ));

-- ============================================================
-- 2. TRIP LIFECYCLE TABLE — event log for every status transition
-- ============================================================
CREATE TABLE IF NOT EXISTS trip_lifecycle (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  booking_id UUID REFERENCES bookings(id) ON DELETE CASCADE,
  event TEXT NOT NULL,
  actor_id UUID REFERENCES profiles(id),
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_lifecycle_ride ON trip_lifecycle(ride_id, created_at);
CREATE INDEX IF NOT EXISTS idx_lifecycle_booking ON trip_lifecycle(booking_id, created_at);

-- ============================================================
-- 3. FEEDBACK TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  reviewer_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reviewee_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(booking_id, reviewer_id)  -- one review per booking per reviewer
);
CREATE INDEX IF NOT EXISTS idx_feedback_reviewee ON feedback(reviewee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_ride ON feedback(ride_id);

-- ============================================================
-- 4. DEVICE TOKENS TABLE (for push notifications)
-- ============================================================
CREATE TABLE IF NOT EXISTS device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, token)
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);

-- ============================================================
-- 5. ENHANCE NOTIFICATIONS TABLE
-- ============================================================
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS sender_id UUID REFERENCES profiles(id);
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'system';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS deep_link TEXT;

-- Add insert policy for notifications (triggers use SECURITY DEFINER,
-- but we also allow authenticated users to insert their own)
DROP POLICY IF EXISTS "notifications insert own" ON notifications;
CREATE POLICY "notifications insert own" ON notifications
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Allow delete for own notifications
DROP POLICY IF EXISTS "notifications delete own" ON notifications;
CREATE POLICY "notifications delete own" ON notifications
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ============================================================
-- 6. RLS FOR NEW TABLES
-- ============================================================

-- Trip lifecycle: ride participants can read
ALTER TABLE trip_lifecycle ENABLE ROW LEVEL SECURITY;

CREATE POLICY "lifecycle read by driver" ON trip_lifecycle
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM rides r WHERE r.id = ride_id AND r.driver_id = auth.uid()
  ));

CREATE POLICY "lifecycle read by passenger" ON trip_lifecycle
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.ride_id = ride_id AND b.passenger_id = auth.uid()
  ));

CREATE POLICY "lifecycle insert by participant" ON trip_lifecycle
  FOR INSERT TO authenticated
  WITH CHECK (actor_id = auth.uid());

-- Feedback: reviewer can insert; both parties can read
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "feedback read own" ON feedback
  FOR SELECT TO authenticated
  USING (reviewer_id = auth.uid() OR reviewee_id = auth.uid());

CREATE POLICY "feedback insert own" ON feedback
  FOR INSERT TO authenticated
  WITH CHECK (reviewer_id = auth.uid());

-- Device tokens: owner only
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "device_tokens read own" ON device_tokens
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "device_tokens insert own" ON device_tokens
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "device_tokens update own" ON device_tokens
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "device_tokens delete own" ON device_tokens
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ============================================================
-- 7. RPC: REQUEST BOOKING (pending state)
-- ============================================================
CREATE OR REPLACE FUNCTION request_booking(p_ride_id UUID, p_seats INT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride rides%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_passenger_name TEXT;
  v_driver_id UUID;
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
               AND status NOT IN ('cancelled', 'rejected')) THEN
    RAISE EXCEPTION 'ALREADY_BOOKED';
  END IF;

  -- Create booking with PENDING status (seats NOT decremented yet)
  INSERT INTO bookings (ride_id, passenger_id, seats_booked, total_fare, status)
  VALUES (p_ride_id, auth.uid(), p_seats, p_seats * v_ride.fare_per_seat, 'pending')
  RETURNING * INTO v_booking;

  -- Log lifecycle event
  INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
  VALUES (p_ride_id, v_booking.id, 'booking_requested', auth.uid(),
          jsonb_build_object('seats', p_seats));

  -- Notify driver
  SELECT name INTO v_passenger_name FROM profiles WHERE id = auth.uid();
  INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    v_ride.driver_id,
    auth.uid(),
    'New Booking Request',
    COALESCE(v_passenger_name, 'A passenger') || ' wants to book ' ||
    p_seats || ' seat(s) on your ride.',
    'booking_request',
    'booking',
    jsonb_build_object('ride_id', p_ride_id, 'booking_id', v_booking.id,
                       'passenger_name', v_passenger_name, 'seats', p_seats),
    '/trip-details'
  );

  RETURN row_to_json(v_booking);
END $$;

-- ============================================================
-- 8. RPC: ACCEPT BOOKING
-- ============================================================
CREATE OR REPLACE FUNCTION accept_booking(p_booking_id UUID)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_ride rides%ROWTYPE;
  v_driver_name TEXT;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  SELECT * INTO v_ride FROM rides WHERE id = v_booking.ride_id FOR UPDATE;
  IF v_ride.driver_id <> auth.uid() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_booking.status <> 'pending' THEN
    RAISE EXCEPTION 'BOOKING_NOT_PENDING';
  END IF;
  IF v_ride.available_seats < v_booking.seats_booked THEN
    RAISE EXCEPTION 'INSUFFICIENT_SEATS';
  END IF;

  -- Accept: update booking status and decrement seats
  UPDATE bookings
  SET status = 'accepted', updated_at = NOW()
  WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  UPDATE rides
  SET available_seats = available_seats - v_booking.seats_booked, updated_at = NOW()
  WHERE id = v_booking.ride_id;

  -- Log lifecycle event
  INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
  VALUES (v_booking.ride_id, p_booking_id, 'booking_accepted', auth.uid(),
          jsonb_build_object('seats', v_booking.seats_booked));

  -- Notify passenger
  SELECT name INTO v_driver_name FROM profiles WHERE id = auth.uid();
  INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    v_booking.passenger_id,
    auth.uid(),
    'Booking Accepted! 🎉',
    COALESCE(v_driver_name, 'The driver') || ' accepted your booking request.',
    'booking_accepted',
    'booking',
    jsonb_build_object(
      'ride_id', v_booking.ride_id, 'booking_id', p_booking_id,
      'driver_name', v_driver_name,
      'vehicle_model', v_ride.id,
      'pickup_address', v_ride.pickup_address,
      'destination_address', v_ride.destination_address,
      'fare', v_booking.total_fare
    ),
    '/trip-details'
  );

  RETURN row_to_json(v_booking);
END $$;

-- ============================================================
-- 9. RPC: REJECT BOOKING
-- ============================================================
CREATE OR REPLACE FUNCTION reject_booking(p_booking_id UUID)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_ride rides%ROWTYPE;
  v_driver_name TEXT;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  SELECT * INTO v_ride FROM rides WHERE id = v_booking.ride_id;
  IF v_ride.driver_id <> auth.uid() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_booking.status <> 'pending' THEN
    RAISE EXCEPTION 'BOOKING_NOT_PENDING';
  END IF;

  -- Reject: update status (seats were never decremented for pending)
  UPDATE bookings
  SET status = 'rejected', updated_at = NOW()
  WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  -- Log lifecycle event
  INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
  VALUES (v_booking.ride_id, p_booking_id, 'booking_rejected', auth.uid(), NULL);

  -- Notify passenger
  SELECT name INTO v_driver_name FROM profiles WHERE id = auth.uid();
  INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    v_booking.passenger_id,
    auth.uid(),
    'Booking Rejected',
    'Your booking request has been rejected by ' || COALESCE(v_driver_name, 'the driver') || '.',
    'booking_rejected',
    'booking',
    jsonb_build_object('ride_id', v_booking.ride_id, 'booking_id', p_booking_id),
    '/my-trips'
  );

  RETURN row_to_json(v_booking);
END $$;

-- ============================================================
-- 10. RPC: SUBMIT FEEDBACK
-- ============================================================
CREATE OR REPLACE FUNCTION submit_feedback(
  p_ride_id UUID,
  p_booking_id UUID,
  p_reviewee_id UUID,
  p_rating INT,
  p_comment TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_feedback feedback%ROWTYPE;
  v_reviewer_name TEXT;
BEGIN
  IF p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'INVALID_RATING';
  END IF;

  -- Verify the reviewer is a participant of this booking
  IF NOT EXISTS (
    SELECT 1 FROM bookings b
    JOIN rides r ON r.id = b.ride_id
    WHERE b.id = p_booking_id
      AND (b.passenger_id = auth.uid() OR r.driver_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  INSERT INTO feedback (ride_id, booking_id, reviewer_id, reviewee_id, rating, comment)
  VALUES (p_ride_id, p_booking_id, auth.uid(), p_reviewee_id, p_rating, p_comment)
  RETURNING * INTO v_feedback;

  -- Log lifecycle event
  INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
  VALUES (p_ride_id, p_booking_id, 'feedback_submitted', auth.uid(),
          jsonb_build_object('rating', p_rating));

  -- Notify the reviewee
  SELECT name INTO v_reviewer_name FROM profiles WHERE id = auth.uid();
  INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    p_reviewee_id,
    auth.uid(),
    'New Review ⭐',
    COALESCE(v_reviewer_name, 'Someone') || ' gave you a ' || p_rating || '-star review.',
    'feedback_received',
    'system',
    jsonb_build_object('ride_id', p_ride_id, 'booking_id', p_booking_id,
                       'rating', p_rating, 'comment', p_comment),
    '/my-trips'
  );

  RETURN row_to_json(v_feedback);
END $$;

-- ============================================================
-- 11. RPC: END RIDE EARLY (Half Ride)
-- ============================================================
CREATE OR REPLACE FUNCTION request_early_exit(p_booking_id UUID)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_ride rides%ROWTYPE;
  v_passenger_name TEXT;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR v_booking.passenger_id <> auth.uid() THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;
  IF v_booking.status <> 'in_progress' THEN
    RAISE EXCEPTION 'RIDE_NOT_IN_PROGRESS';
  END IF;

  SELECT * INTO v_ride FROM rides WHERE id = v_booking.ride_id;

  -- Log lifecycle event
  INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
  VALUES (v_booking.ride_id, p_booking_id, 'early_exit_requested', auth.uid(), NULL);

  -- Notify driver
  SELECT name INTO v_passenger_name FROM profiles WHERE id = auth.uid();
  INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    v_ride.driver_id,
    auth.uid(),
    'Early Exit Request',
    COALESCE(v_passenger_name, 'A passenger') || ' wants to end the ride early.',
    'early_exit_request',
    'ride',
    jsonb_build_object('ride_id', v_booking.ride_id, 'booking_id', p_booking_id),
    '/trip-details'
  );

  RETURN row_to_json(v_booking);
END $$;

-- Accept early exit with new fare set by the driver
CREATE OR REPLACE FUNCTION accept_early_exit(p_booking_id UUID, p_new_fare NUMERIC)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_ride rides%ROWTYPE;
  v_driver_name TEXT;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  SELECT * INTO v_ride FROM rides WHERE id = v_booking.ride_id;
  IF v_ride.driver_id <> auth.uid() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  IF p_new_fare <= 0 THEN
    RAISE EXCEPTION 'INVALID_FARE';
  END IF;

  -- Update booking with new fare and mark completed
  UPDATE bookings
  SET total_fare = p_new_fare,
      status = 'completed',
      completed_at = NOW(),
      updated_at = NOW()
  WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  -- Restore the seats for this passenger
  UPDATE rides
  SET available_seats = available_seats + v_booking.seats_booked,
      updated_at = NOW()
  WHERE id = v_booking.ride_id;

  -- Log lifecycle event
  INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
  VALUES (v_booking.ride_id, p_booking_id, 'early_exit_accepted', auth.uid(),
          jsonb_build_object('new_fare', p_new_fare));

  -- Notify passenger
  SELECT name INTO v_driver_name FROM profiles WHERE id = auth.uid();
  INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    v_booking.passenger_id,
    auth.uid(),
    'Early Exit Accepted',
    COALESCE(v_driver_name, 'The driver') || ' accepted your early exit. Updated fare: ₹' || p_new_fare || '.',
    'early_exit_accepted',
    'ride',
    jsonb_build_object('ride_id', v_booking.ride_id, 'booking_id', p_booking_id,
                       'new_fare', p_new_fare),
    '/trip-details'
  );

  RETURN row_to_json(v_booking);
END $$;

-- Reject early exit — ride continues as normal
CREATE OR REPLACE FUNCTION reject_early_exit(p_booking_id UUID)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_ride rides%ROWTYPE;
  v_driver_name TEXT;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  SELECT * INTO v_ride FROM rides WHERE id = v_booking.ride_id;
  IF v_ride.driver_id <> auth.uid() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  -- Log lifecycle event
  INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
  VALUES (v_booking.ride_id, p_booking_id, 'early_exit_rejected', auth.uid(), NULL);

  -- Notify passenger
  SELECT name INTO v_driver_name FROM profiles WHERE id = auth.uid();
  INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    v_booking.passenger_id,
    auth.uid(),
    'Early Exit Rejected',
    COALESCE(v_driver_name, 'The driver') || ' wants to continue the original ride.',
    'early_exit_rejected',
    'ride',
    jsonb_build_object('ride_id', v_booking.ride_id, 'booking_id', p_booking_id),
    '/trip-details'
  );

  RETURN row_to_json(v_booking);
END $$;

-- ============================================================
-- 12. LIFECYCLE LOGGING TRIGGERS
-- ============================================================

-- Log lifecycle when booking status changes
CREATE OR REPLACE FUNCTION log_booking_lifecycle()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
    VALUES (
      NEW.ride_id,
      NEW.id,
      'booking_status_' || NEW.status,
      auth.uid(),
      jsonb_build_object('old_status', OLD.status, 'new_status', NEW.status)
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_log_booking_lifecycle ON bookings;
CREATE TRIGGER trg_log_booking_lifecycle
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW EXECUTE FUNCTION log_booking_lifecycle();

-- Log lifecycle when ride status changes
CREATE OR REPLACE FUNCTION log_ride_lifecycle()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO trip_lifecycle (ride_id, event, actor_id, metadata)
    VALUES (
      NEW.id,
      'ride_status_' || NEW.status,
      auth.uid(),
      jsonb_build_object('old_status', OLD.status, 'new_status', NEW.status)
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_log_ride_lifecycle ON rides;
CREATE TRIGGER trg_log_ride_lifecycle
  AFTER UPDATE OF status ON rides
  FOR EACH ROW EXECUTE FUNCTION log_ride_lifecycle();

-- ============================================================
-- 13. UPDATED NOTIFICATION TRIGGER FOR BOOKING STATUS
-- ============================================================
-- Enhanced: also notify on pending→accepted, pending→rejected
CREATE OR REPLACE FUNCTION notify_on_booking_status_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_driver_id UUID;
  v_ride rides%ROWTYPE;
  v_actor_name TEXT;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    SELECT * INTO v_ride FROM rides WHERE id = NEW.ride_id;
    v_driver_id := v_ride.driver_id;

    -- Notify passenger when ride starts or completes for their booking
    IF NEW.status = 'in_progress' THEN
      SELECT name INTO v_actor_name FROM profiles WHERE id = v_driver_id;
      INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
      VALUES (
        NEW.passenger_id, v_driver_id,
        'Ride Started 🚗',
        'Your ride to ' || v_ride.destination_address || ' has started!',
        'ride_started', 'ride',
        jsonb_build_object('ride_id', NEW.ride_id, 'booking_id', NEW.id),
        '/live-tracking'
      );
    ELSIF NEW.status = 'completed' AND OLD.status = 'in_progress' THEN
      INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
      VALUES (
        NEW.passenger_id, v_driver_id,
        'Ride Completed ✅',
        'Your ride is complete. Please complete your payment.',
        'ride_completed', 'payment',
        jsonb_build_object('ride_id', NEW.ride_id, 'booking_id', NEW.id,
                           'total_fare', NEW.total_fare),
        '/payment-method'
      );
    ELSIF NEW.status = 'payment_completed' THEN
      -- Notify driver that payment was received
      SELECT name INTO v_actor_name FROM profiles WHERE id = NEW.passenger_id;
      INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
      VALUES (
        v_driver_id, NEW.passenger_id,
        'Payment Received 💰',
        COALESCE(v_actor_name, 'A passenger') || ' completed payment of ₹' || NEW.total_fare || '.',
        'payment_completed', 'payment',
        jsonb_build_object('ride_id', NEW.ride_id, 'booking_id', NEW.id,
                           'amount', NEW.total_fare),
        '/my-trips'
      );
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notify_booking_status ON bookings;
CREATE TRIGGER trg_notify_booking_status
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW EXECUTE FUNCTION notify_on_booking_status_change();

-- ============================================================
-- 14. SEARCH RECURRING RIDES RPC
-- ============================================================
CREATE OR REPLACE FUNCTION search_recurring_rides(
  p_pickup_lat DOUBLE PRECISION,
  p_pickup_lng DOUBLE PRECISION,
  p_dest_lat DOUBLE PRECISION,
  p_dest_lng DOUBLE PRECISION,
  p_days TEXT,            -- comma-separated: 'Mon,Wed,Fri'
  p_seats INT DEFAULT 1,
  p_radius_km NUMERIC DEFAULT 5
)
RETURNS SETOF JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_requested_days TEXT[];
  v_ride RECORD;
  v_ride_days TEXT[];
  v_match_count INT;
BEGIN
  v_requested_days := string_to_array(p_days, ',');

  FOR v_ride IN
    SELECT r.*, p.name AS driver_name, p.avatar_url AS driver_avatar,
           p.phone AS driver_phone, v.id AS vid, v.model AS vehicle_model,
           v.registration_number AS vehicle_registration
    FROM rides r
    JOIN profiles p ON p.id = r.driver_id
    JOIN vehicles v ON v.id = r.vehicle_id
    WHERE r.status = 'published'
      AND NOT r.is_deleted
      AND r.driver_id <> auth.uid()
      AND r.available_seats >= p_seats
      AND r.is_recurring = TRUE
      AND r.recurring_days IS NOT NULL
      -- Bounding box filter
      AND r.pickup_lat BETWEEN LEAST(p_pickup_lat, p_dest_lat) - (p_radius_km / 111.0)
                           AND GREATEST(p_pickup_lat, p_dest_lat) + (p_radius_km / 111.0)
  LOOP
    v_ride_days := string_to_array(v_ride.recurring_days, ',');
    v_match_count := 0;
    FOR i IN 1..array_length(v_requested_days, 1) LOOP
      IF v_requested_days[i] = ANY(v_ride_days) THEN
        v_match_count := v_match_count + 1;
      END IF;
    END LOOP;

    IF v_match_count > 0 THEN
      RETURN NEXT json_build_object(
        'id', v_ride.id,
        'driver_id', v_ride.driver_id,
        'driver_name', v_ride.driver_name,
        'driver_avatar', v_ride.driver_avatar,
        'driver_phone', v_ride.driver_phone,
        'vehicle_id', v_ride.vid,
        'vehicle_model', v_ride.vehicle_model,
        'vehicle_registration', v_ride.vehicle_registration,
        'pickup_address', v_ride.pickup_address,
        'pickup_lat', v_ride.pickup_lat,
        'pickup_lng', v_ride.pickup_lng,
        'destination_address', v_ride.destination_address,
        'destination_lat', v_ride.destination_lat,
        'destination_lng', v_ride.destination_lng,
        'route_polyline', v_ride.route_polyline,
        'distance_km', v_ride.distance_km,
        'duration_minutes', v_ride.duration_minutes,
        'departure_time', v_ride.departure_time,
        'total_seats', v_ride.total_seats,
        'available_seats', v_ride.available_seats,
        'fare_per_seat', v_ride.fare_per_seat,
        'is_recurring', v_ride.is_recurring,
        'recurring_days', v_ride.recurring_days,
        'status', v_ride.status,
        'match_count', v_match_count,
        'total_requested', array_length(v_requested_days, 1),
        'is_exact_match', v_match_count = array_length(v_requested_days, 1)
          AND array_length(v_ride_days, 1) = array_length(v_requested_days, 1)
      );
    END IF;
  END LOOP;
END $$;

-- ============================================================
-- 15. GRANT EXECUTE ON ALL NEW RPCs
-- ============================================================
GRANT EXECUTE ON FUNCTION request_booking TO authenticated;
GRANT EXECUTE ON FUNCTION accept_booking TO authenticated;
GRANT EXECUTE ON FUNCTION reject_booking TO authenticated;
GRANT EXECUTE ON FUNCTION submit_feedback TO authenticated;
GRANT EXECUTE ON FUNCTION request_early_exit TO authenticated;
GRANT EXECUTE ON FUNCTION accept_early_exit TO authenticated;
GRANT EXECUTE ON FUNCTION reject_early_exit TO authenticated;
GRANT EXECUTE ON FUNCTION search_recurring_rides TO authenticated;

-- ============================================================
-- 16. ENABLE REALTIME FOR NEW TABLES
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
      AND tablename = 'trip_lifecycle'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE trip_lifecycle;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
      AND tablename = 'feedback'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE feedback;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
      AND tablename = 'device_tokens'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE device_tokens;
  END IF;
END $$;

-- ============================================================
-- Update the existing bookings insert policy to allow pending
-- ============================================================
DROP POLICY IF EXISTS "bookings insert" ON bookings;
CREATE POLICY "bookings insert" ON bookings
  FOR INSERT TO authenticated
  WITH CHECK (passenger_id = auth.uid());
