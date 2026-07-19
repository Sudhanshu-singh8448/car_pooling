-- ============================================================
-- Feature Fixes — Run AFTER schema.sql, schema_updates.sql,
-- and feature_migration.sql have already been applied.
-- These patches fix:
--   1. Driver wallet is not credited when passenger pays cash/card/UPI.
--   2. Partial (half) ride charges full fare — now proportional.
--   3. Deep links in notifications used routes that require a TripEntity
--      extra, causing the app to crash on tap.
-- ============================================================

-- ============================================================
-- 1. AUTO-CREDIT DRIVER WALLET ON SUCCESSFUL PAYMENT
-- ============================================================
-- Whenever a payments row is inserted with status='completed', we
-- credit the *driver's* wallet with the amount (minus a small platform
-- fee if you want to introduce one — currently 0%). Cash payments are
-- excluded because the money is exchanged physically off-platform.

CREATE OR REPLACE FUNCTION credit_driver_wallet_on_payment()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_driver_id UUID;
  v_wallet wallets%ROWTYPE;
BEGIN
  IF NEW.status <> 'completed' THEN
    RETURN NEW;
  END IF;

  -- Skip cash — the passenger hands cash to the driver directly.
  IF NEW.method = 'cash' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = NEW.booking_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT driver_id INTO v_driver_id FROM rides WHERE id = v_booking.ride_id;
  IF v_driver_id IS NULL THEN RETURN NEW; END IF;

  -- Ensure the driver has a wallet row.
  SELECT * INTO v_wallet FROM wallets WHERE user_id = v_driver_id FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO wallets (user_id) VALUES (v_driver_id) RETURNING * INTO v_wallet;
  END IF;

  UPDATE wallets
     SET balance = balance + NEW.amount,
         updated_at = NOW()
   WHERE id = v_wallet.id
   RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions
    (wallet_id, type, amount, balance_after, description, reference_id, reference_type)
  VALUES
    (v_wallet.id, 'credit', NEW.amount, v_wallet.balance,
     'Ride payment received (' || NEW.method || ')',
     NEW.booking_id, 'ride_payment');

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_credit_driver_wallet ON payments;
CREATE TRIGGER trg_credit_driver_wallet
  AFTER INSERT ON payments
  FOR EACH ROW EXECUTE FUNCTION credit_driver_wallet_on_payment();

-- ============================================================
-- 2. HALF-RIDE: PROPORTIONAL PARTIAL FARE
-- ============================================================
-- Passenger-driven: the passenger says "I'm getting off now, I've
-- travelled roughly X km of the Y km trip". The RPC recalculates the
-- fare proportionally, marks the booking `completed`, restores the seat,
-- and notifies the driver. No driver approval needed — the passenger is
-- always allowed to leave early; only the money changes.

CREATE OR REPLACE FUNCTION end_ride_early_auto(
  p_booking_id UUID,
  p_completed_km NUMERIC
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking  bookings%ROWTYPE;
  v_ride     rides%ROWTYPE;
  v_full_km  NUMERIC;
  v_new_fare NUMERIC;
  v_pct      NUMERIC;
  v_driver_name TEXT;
  v_passenger_name TEXT;
BEGIN
  IF p_completed_km IS NULL OR p_completed_km <= 0 THEN
    RAISE EXCEPTION 'INVALID_DISTANCE';
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR v_booking.passenger_id <> auth.uid() THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;
  IF v_booking.status <> 'in_progress' THEN
    RAISE EXCEPTION 'RIDE_NOT_IN_PROGRESS';
  END IF;

  SELECT * INTO v_ride FROM rides WHERE id = v_booking.ride_id FOR UPDATE;
  v_full_km := COALESCE(v_ride.distance_km, 0);
  IF v_full_km <= 0 THEN
    -- Fallback: no distance recorded, keep full fare.
    v_new_fare := v_booking.total_fare;
    v_pct := 1;
  ELSE
    v_pct := LEAST(1, GREATEST(0.1, p_completed_km / v_full_km));
    v_new_fare := ROUND(v_booking.total_fare * v_pct, 2);
  END IF;

  UPDATE bookings
     SET total_fare   = v_new_fare,
         status       = 'completed',
         completed_at = NOW(),
         updated_at   = NOW()
   WHERE id = p_booking_id
   RETURNING * INTO v_booking;

  -- Return the seat back to the pool so other passengers can book.
  UPDATE rides
     SET available_seats = available_seats + v_booking.seats_booked,
         updated_at = NOW()
   WHERE id = v_booking.ride_id;

  INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
  VALUES (v_booking.ride_id, p_booking_id, 'early_exit_completed', auth.uid(),
          jsonb_build_object('completed_km', p_completed_km,
                             'full_km', v_full_km,
                             'new_fare', v_new_fare,
                             'percent', v_pct));

  -- Notify the driver so they know the passenger left early.
  SELECT name INTO v_passenger_name FROM profiles WHERE id = auth.uid();
  SELECT name INTO v_driver_name    FROM profiles WHERE id = v_ride.driver_id;
  INSERT INTO notifications
    (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    v_ride.driver_id, auth.uid(),
    'Passenger ended ride early',
    COALESCE(v_passenger_name, 'A passenger') ||
      ' got off after ' || ROUND(p_completed_km, 1) ||
      ' km. Adjusted fare: ₹' || v_new_fare || '.',
    'early_exit_completed', 'ride',
    jsonb_build_object('ride_id', v_booking.ride_id,
                       'booking_id', p_booking_id,
                       'completed_km', p_completed_km,
                       'new_fare', v_new_fare),
    '/my-trips'
  );

  -- Also notify the passenger with the pay-now nudge.
  INSERT INTO notifications
    (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    v_booking.passenger_id, v_ride.driver_id,
    'Ride ended — please pay',
    'Partial fare: ₹' || v_new_fare || ' for ' ||
      ROUND(p_completed_km, 1) || ' km of ' || ROUND(v_full_km, 1) || ' km.',
    'ride_completed', 'payment',
    jsonb_build_object('ride_id', v_booking.ride_id,
                       'booking_id', p_booking_id,
                       'total_fare', v_new_fare),
    '/my-trips'
  );

  RETURN row_to_json(v_booking);
END $$;

GRANT EXECUTE ON FUNCTION end_ride_early_auto TO authenticated;

-- ============================================================
-- 3. SAFE DEEP LINKS ON NOTIFICATIONS
-- ============================================================
-- The original triggers used '/trip-details' and '/payment-method' as
-- deep links, but those routes expect a TripEntity object via `extra`.
-- Tapping such a notification therefore crashed the app. We route all
-- booking / ride / payment notifications to `/my-trips` — a safe screen
-- that always renders and lets the user pick the trip.

-- Rewrite the booking-request notification to open My Trips.
UPDATE notifications SET deep_link = '/my-trips'
 WHERE deep_link IN ('/trip-details', '/payment-method', '/live-tracking');

-- Rebuild the RPCs and triggers that set the deep link so future rows
-- are correct too.

CREATE OR REPLACE FUNCTION request_booking(p_ride_id UUID, p_seats INT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride rides%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_passenger_name TEXT;
BEGIN
  SELECT * INTO v_ride FROM rides WHERE id = p_ride_id AND NOT is_deleted FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RIDE_NOT_FOUND'; END IF;
  IF v_ride.driver_id = auth.uid() THEN RAISE EXCEPTION 'CANNOT_BOOK_OWN_RIDE'; END IF;
  IF v_ride.status <> 'published' THEN RAISE EXCEPTION 'RIDE_NOT_AVAILABLE'; END IF;
  IF v_ride.available_seats < p_seats THEN RAISE EXCEPTION 'INSUFFICIENT_SEATS'; END IF;
  IF EXISTS (SELECT 1 FROM bookings WHERE ride_id = p_ride_id AND passenger_id = auth.uid()
             AND status NOT IN ('cancelled', 'rejected')) THEN
    RAISE EXCEPTION 'ALREADY_BOOKED';
  END IF;

  INSERT INTO bookings (ride_id, passenger_id, seats_booked, total_fare, status)
  VALUES (p_ride_id, auth.uid(), p_seats, p_seats * v_ride.fare_per_seat, 'pending')
  RETURNING * INTO v_booking;

  INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
  VALUES (p_ride_id, v_booking.id, 'booking_requested', auth.uid(),
          jsonb_build_object('seats', p_seats));

  SELECT name INTO v_passenger_name FROM profiles WHERE id = auth.uid();
  INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    v_ride.driver_id, auth.uid(),
    'New Booking Request',
    COALESCE(v_passenger_name, 'A passenger') || ' wants to book ' ||
      p_seats || ' seat(s) on your ride.',
    'booking_request', 'booking',
    jsonb_build_object('ride_id', p_ride_id, 'booking_id', v_booking.id,
                       'passenger_name', v_passenger_name, 'seats', p_seats),
    '/my-trips'
  );
  RETURN row_to_json(v_booking);
END $$;

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
  IF NOT FOUND THEN RAISE EXCEPTION 'BOOKING_NOT_FOUND'; END IF;

  SELECT * INTO v_ride FROM rides WHERE id = v_booking.ride_id FOR UPDATE;
  IF v_ride.driver_id <> auth.uid() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF v_booking.status <> 'pending' THEN RAISE EXCEPTION 'BOOKING_NOT_PENDING'; END IF;
  IF v_ride.available_seats < v_booking.seats_booked THEN RAISE EXCEPTION 'INSUFFICIENT_SEATS'; END IF;

  UPDATE bookings SET status = 'accepted', updated_at = NOW()
   WHERE id = p_booking_id RETURNING * INTO v_booking;

  UPDATE rides SET available_seats = available_seats - v_booking.seats_booked,
                   updated_at = NOW()
   WHERE id = v_booking.ride_id;

  INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
  VALUES (v_booking.ride_id, p_booking_id, 'booking_accepted', auth.uid(),
          jsonb_build_object('seats', v_booking.seats_booked));

  SELECT name INTO v_driver_name FROM profiles WHERE id = auth.uid();
  INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    v_booking.passenger_id, auth.uid(),
    'Booking Accepted',
    COALESCE(v_driver_name, 'The driver') || ' accepted your booking request.',
    'booking_accepted', 'booking',
    jsonb_build_object('ride_id', v_booking.ride_id, 'booking_id', p_booking_id,
                       'driver_name', v_driver_name,
                       'pickup_address', v_ride.pickup_address,
                       'destination_address', v_ride.destination_address,
                       'fare', v_booking.total_fare),
    '/my-trips'
  );
  RETURN row_to_json(v_booking);
END $$;

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
  IF NOT FOUND THEN RAISE EXCEPTION 'BOOKING_NOT_FOUND'; END IF;
  SELECT * INTO v_ride FROM rides WHERE id = v_booking.ride_id;
  IF v_ride.driver_id <> auth.uid() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF v_booking.status <> 'pending' THEN RAISE EXCEPTION 'BOOKING_NOT_PENDING'; END IF;

  UPDATE bookings SET status = 'rejected', updated_at = NOW()
   WHERE id = p_booking_id RETURNING * INTO v_booking;

  INSERT INTO trip_lifecycle (ride_id, booking_id, event, actor_id, metadata)
  VALUES (v_booking.ride_id, p_booking_id, 'booking_rejected', auth.uid(), NULL);

  SELECT name INTO v_driver_name FROM profiles WHERE id = auth.uid();
  INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
  VALUES (
    v_booking.passenger_id, auth.uid(),
    'Booking Rejected',
    'Your booking request has been rejected by ' || COALESCE(v_driver_name, 'the driver') || '.',
    'booking_rejected', 'booking',
    jsonb_build_object('ride_id', v_booking.ride_id, 'booking_id', p_booking_id),
    '/my-trips'
  );
  RETURN row_to_json(v_booking);
END $$;

-- Rebuild booking-status notification trigger with safe deep links.
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

    IF NEW.status = 'in_progress' THEN
      INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
      VALUES (
        NEW.passenger_id, v_driver_id,
        'Ride Started',
        'Your ride to ' || v_ride.destination_address || ' has started.',
        'ride_started', 'ride',
        jsonb_build_object('ride_id', NEW.ride_id, 'booking_id', NEW.id),
        '/my-trips'
      );
    ELSIF NEW.status = 'completed' AND OLD.status = 'in_progress' THEN
      INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
      VALUES (
        NEW.passenger_id, v_driver_id,
        'Ride Completed',
        'Your ride is complete. Please complete your payment.',
        'ride_completed', 'payment',
        jsonb_build_object('ride_id', NEW.ride_id, 'booking_id', NEW.id,
                           'total_fare', NEW.total_fare),
        '/my-trips'
      );
    ELSIF NEW.status = 'payment_completed' THEN
      SELECT name INTO v_actor_name FROM profiles WHERE id = NEW.passenger_id;
      INSERT INTO notifications (user_id, sender_id, title, body, type, category, data, deep_link)
      VALUES (
        v_driver_id, NEW.passenger_id,
        'Payment Received',
        COALESCE(v_actor_name, 'A passenger') ||
          ' completed payment of ₹' || NEW.total_fare ||
          '. Wallet credited.',
        'payment_completed', 'payment',
        jsonb_build_object('ride_id', NEW.ride_id, 'booking_id', NEW.id,
                           'amount', NEW.total_fare),
        '/wallet'
      );
    END IF;
  END IF;
  RETURN NEW;
END $$;
