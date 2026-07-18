-- ============================================================
-- Schema Updates — Phases 3-6 (Admin, Notifications)
-- Run AFTER schema.sql in the Supabase SQL Editor.
-- ============================================================

-- Apply this block independently when schema.sql was already run before the
-- auth profile trigger was added.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
BEGIN
  -- If the client supplied an org_id in user_metadata, validate it exists.
  BEGIN
    v_org_id := NULLIF(NEW.raw_user_meta_data ->> 'org_id', '')::uuid;
  EXCEPTION WHEN others THEN
    v_org_id := NULL;
  END;

  IF v_org_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.organizations o WHERE o.id = v_org_id AND NOT o.is_deleted
  ) THEN
    v_org_id := NULL;
  END IF;

  INSERT INTO public.profiles AS p (id, email, name, phone, role, platform_access, org_id)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'phone', ''),
    'employee',
    'granted',
    v_org_id
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = COALESCE(NULLIF(EXCLUDED.name, ''), p.name),
    phone = COALESCE(NULLIF(EXCLUDED.phone, ''), p.phone),
    org_id = COALESCE(p.org_id, EXCLUDED.org_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Repair users created before this trigger existed.
INSERT INTO public.profiles (id, email, name, phone, role, platform_access)
SELECT
  u.id,
  u.email,
  COALESCE(u.raw_user_meta_data ->> 'name', ''),
  COALESCE(u.raw_user_meta_data ->> 'phone', ''),
  'employee',
  'granted'
FROM auth.users u
WHERE NOT EXISTS (
  SELECT 1 FROM public.profiles p WHERE p.id = u.id
);

-- Admins can update any profile in their org (grant/revoke access)
DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;
CREATE POLICY "Users can insert own profile" ON profiles
  FOR INSERT TO authenticated WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE TO authenticated USING (id = auth.uid());

DROP POLICY IF EXISTS "profiles update by admin" ON profiles;
CREATE POLICY "profiles update by admin" ON profiles
  FOR UPDATE TO authenticated
  USING (public.is_admin());

-- Admins can create the organization row if none exists
DROP POLICY IF EXISTS "org insert by admin" ON organizations;
CREATE POLICY "org insert by admin" ON organizations
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

-- ---------- NOTIFICATION TRIGGERS ----------

-- Notify the driver when a passenger books their ride
CREATE OR REPLACE FUNCTION notify_driver_on_booking()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_driver UUID;
  v_passenger_name TEXT;
BEGIN
  SELECT driver_id INTO v_driver FROM rides WHERE id = NEW.ride_id;
  SELECT name INTO v_passenger_name FROM profiles WHERE id = NEW.passenger_id;
  INSERT INTO notifications (user_id, title, body, type, data)
  VALUES (v_driver, 'New Booking',
          COALESCE(v_passenger_name, 'A passenger') || ' booked ' ||
          NEW.seats_booked || ' seat(s) on your ride.',
          'booking', jsonb_build_object('ride_id', NEW.ride_id, 'booking_id', NEW.id));
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notify_booking ON bookings;
CREATE TRIGGER trg_notify_booking
  AFTER INSERT ON bookings
  FOR EACH ROW EXECUTE FUNCTION notify_driver_on_booking();

-- Notify passengers when the ride status changes
CREATE OR REPLACE FUNCTION notify_passengers_on_ride_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('in_progress', 'completed', 'cancelled') THEN
    INSERT INTO notifications (user_id, title, body, type, data)
    SELECT b.passenger_id,
           CASE NEW.status
             WHEN 'in_progress' THEN 'Trip Started'
             WHEN 'completed' THEN 'Trip Completed'
             ELSE 'Ride Cancelled'
           END,
           CASE NEW.status
             WHEN 'in_progress' THEN 'Your ride to ' || NEW.destination_address || ' has started.'
             WHEN 'completed' THEN 'Your trip is complete. Please proceed to payment.'
             ELSE 'Your ride to ' || NEW.destination_address || ' was cancelled by the driver.'
           END,
           'trip_status',
           jsonb_build_object('ride_id', NEW.id, 'status', NEW.status)
    FROM bookings b
    WHERE b.ride_id = NEW.id AND b.status NOT IN ('cancelled');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notify_ride_status ON rides;
CREATE TRIGGER trg_notify_ride_status
  AFTER UPDATE ON rides
  FOR EACH ROW EXECUTE FUNCTION notify_passengers_on_ride_status();

-- Enable realtime for notifications (idempotent — safe to re-run)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  END IF;
END $$;

-- ============================================================
-- SEARCH RIDES V2 — time-window + route-corridor matching
-- ============================================================
-- Fixes two problems with the original search_rides:
--   1. `departure_time::date = p_date` compared dates in UTC, so rides
--      after ~18:30 IST fell on the "next day" and never matched.
--      V2 takes an explicit [p_start, p_end] timestamptz window computed
--      by the client in the user's local timezone.
--   2. Both endpoints had to be within the radius of the ride's own
--      endpoints, so passengers wanting to join MIDWAY along the route
--      never saw the ride. V2 does a cheap bounding-box corridor
--      prefilter here; the app then decodes the route polyline and does
--      precise "is my pickup on the way?" matching client-side.
CREATE OR REPLACE FUNCTION search_rides_v2(
  p_pickup_lat DOUBLE PRECISION,
  p_pickup_lng DOUBLE PRECISION,
  p_dest_lat DOUBLE PRECISION,
  p_dest_lng DOUBLE PRECISION,
  p_start TIMESTAMPTZ,
  p_end TIMESTAMPTZ,
  p_seats INT DEFAULT 1,
  p_radius_km NUMERIC DEFAULT 5
)
RETURNS SETOF JSON
LANGUAGE sql SECURITY DEFINER
SET search_path = public
AS $$
  WITH candidates AS (
    SELECT r.*,
           -- degrees of latitude per km ≈ 1/111; widen lng by cos(lat)
           (p_radius_km / 111.0) AS lat_pad,
           (p_radius_km / (111.0 * GREATEST(0.2, cos(radians((r.pickup_lat + r.destination_lat) / 2))))) AS lng_pad
    FROM rides r
    WHERE r.status = 'published'
      AND NOT r.is_deleted
      AND r.driver_id <> auth.uid()
      AND r.available_seats >= p_seats
      AND r.departure_time >= p_start
      AND r.departure_time < p_end
      AND r.departure_time > NOW()
  )
  SELECT json_build_object(
    'id', c.id,
    'driver_id', c.driver_id,
    'driver_name', p.name,
    'driver_avatar', p.avatar_url,
    'driver_phone', p.phone,
    'vehicle_id', v.id,
    'vehicle_model', v.model,
    'vehicle_registration', v.registration_number,
    'pickup_address', c.pickup_address,
    'pickup_lat', c.pickup_lat,
    'pickup_lng', c.pickup_lng,
    'destination_address', c.destination_address,
    'destination_lat', c.destination_lat,
    'destination_lng', c.destination_lng,
    'route_polyline', c.route_polyline,
    'distance_km', c.distance_km,
    'duration_minutes', c.duration_minutes,
    'departure_time', c.departure_time,
    'total_seats', c.total_seats,
    'available_seats', c.available_seats,
    'fare_per_seat', c.fare_per_seat,
    'is_recurring', c.is_recurring,
    'recurring_days', c.recurring_days,
    'status', c.status
  )
  FROM candidates c
  JOIN profiles p ON p.id = c.driver_id
  JOIN vehicles v ON v.id = c.vehicle_id
  WHERE
    -- passenger pickup inside the ride's route bounding box (padded)
    p_pickup_lat BETWEEN LEAST(c.pickup_lat, c.destination_lat) - c.lat_pad
                     AND GREATEST(c.pickup_lat, c.destination_lat) + c.lat_pad
    AND p_pickup_lng BETWEEN LEAST(c.pickup_lng, c.destination_lng) - c.lng_pad
                         AND GREATEST(c.pickup_lng, c.destination_lng) + c.lng_pad
    -- passenger destination inside the same padded corridor box
    AND p_dest_lat BETWEEN LEAST(c.pickup_lat, c.destination_lat) - c.lat_pad
                       AND GREATEST(c.pickup_lat, c.destination_lat) + c.lat_pad
    AND p_dest_lng BETWEEN LEAST(c.pickup_lng, c.destination_lng) - c.lng_pad
                       AND GREATEST(c.pickup_lng, c.destination_lng) + c.lng_pad
  ORDER BY c.departure_time ASC;
$$;

GRANT EXECUTE ON FUNCTION search_rides_v2 TO authenticated;

-- ============================================================
-- ADMIN DASHBOARD SUPPORT (used by the admin-web React app)
-- ============================================================

-- SECURITY DEFINER helper that bypasses RLS when checking whether the
-- current user is an admin. Using EXISTS(SELECT ... FROM profiles) inside
-- a policy ON profiles causes infinite recursion, so we go through this.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_admin TO authenticated;

-- Allow admins to SELECT every row in the operational tables so the
-- admin dashboard can list employees, vehicles, rides, bookings and
-- payments across the whole organization.
DROP POLICY IF EXISTS "admin read all profiles" ON profiles;
CREATE POLICY "admin read all profiles" ON profiles
  FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "admin read all vehicles" ON vehicles;
CREATE POLICY "admin read all vehicles" ON vehicles
  FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "admin read all rides" ON rides;
CREATE POLICY "admin read all rides" ON rides
  FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "admin read all bookings" ON bookings;
CREATE POLICY "admin read all bookings" ON bookings
  FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "admin read all payments" ON payments;
CREATE POLICY "admin read all payments" ON payments
  FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "admin read all orgs" ON organizations;
CREATE POLICY "admin read all orgs" ON organizations
  FOR SELECT TO authenticated
  USING (public.is_admin());

-- Admins can update pricing / org details
DROP POLICY IF EXISTS "org update by admin" ON organizations;
CREATE POLICY "org update by admin" ON organizations
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ============================================================
-- ADMIN ANALYTICS RPC — one call returns every KPI for the dashboard
-- ============================================================
CREATE OR REPLACE FUNCTION admin_dashboard_stats(p_org_id UUID DEFAULT NULL)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin BOOLEAN;
  v_total_employees INT;
  v_active_employees INT;
  v_total_vehicles INT;
  v_total_rides INT;
  v_completed_rides INT;
  v_active_rides_today INT;
  v_total_bookings INT;
  v_total_distance NUMERIC;
  v_total_revenue NUMERIC;
  v_co2_saved_kg NUMERIC;
  v_rides_this_month INT;
  v_rides_last_7_days JSON;
BEGIN
  SELECT (role = 'admin') INTO v_is_admin
  FROM profiles WHERE id = auth.uid();

  IF NOT COALESCE(v_is_admin, FALSE) THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT COUNT(*) INTO v_total_employees
    FROM profiles WHERE role = 'employee' AND (p_org_id IS NULL OR org_id = p_org_id);

  SELECT COUNT(*) INTO v_active_employees
    FROM profiles WHERE role = 'employee' AND platform_access = 'granted'
      AND (p_org_id IS NULL OR org_id = p_org_id);

  SELECT COUNT(*) INTO v_total_vehicles
    FROM vehicles WHERE NOT is_deleted
      AND (p_org_id IS NULL OR org_id = p_org_id);

  SELECT COUNT(*) INTO v_total_rides
    FROM rides WHERE NOT is_deleted
      AND (p_org_id IS NULL OR org_id = p_org_id);

  SELECT COUNT(*) INTO v_completed_rides
    FROM rides WHERE status = 'completed' AND NOT is_deleted
      AND (p_org_id IS NULL OR org_id = p_org_id);

  SELECT COUNT(*) INTO v_active_rides_today
    FROM rides
    WHERE status IN ('published', 'in_progress')
      AND departure_time::date = CURRENT_DATE
      AND NOT is_deleted
      AND (p_org_id IS NULL OR org_id = p_org_id);

  SELECT COUNT(*) INTO v_total_bookings FROM bookings b
    JOIN rides r ON r.id = b.ride_id
    WHERE (p_org_id IS NULL OR r.org_id = p_org_id);

  SELECT COALESCE(SUM(distance_km), 0) INTO v_total_distance
    FROM rides WHERE status = 'completed' AND NOT is_deleted
      AND (p_org_id IS NULL OR org_id = p_org_id);

  SELECT COALESCE(SUM(amount), 0) INTO v_total_revenue
    FROM payments WHERE status = 'success';

  SELECT COUNT(*) INTO v_rides_this_month
    FROM rides
    WHERE departure_time >= date_trunc('month', NOW())
      AND NOT is_deleted
      AND (p_org_id IS NULL OR org_id = p_org_id);

  -- Rough CO2 saved: ~0.192 kg per km per shared seat (avg petrol car)
  SELECT COALESCE(SUM(r.distance_km * GREATEST(0, r.total_seats - r.available_seats) * 0.192), 0)
    INTO v_co2_saved_kg
  FROM rides r
  WHERE r.status = 'completed' AND NOT r.is_deleted
    AND (p_org_id IS NULL OR r.org_id = p_org_id);

  -- Rides per day for the last 7 days
  SELECT json_agg(row_to_json(t)) INTO v_rides_last_7_days
  FROM (
    SELECT to_char(d::date, 'YYYY-MM-DD') AS day,
           COALESCE((
             SELECT COUNT(*) FROM rides r
             WHERE r.departure_time::date = d::date
               AND NOT r.is_deleted
               AND (p_org_id IS NULL OR r.org_id = p_org_id)
           ), 0) AS ride_count
    FROM generate_series(CURRENT_DATE - INTERVAL '6 days', CURRENT_DATE, INTERVAL '1 day') d
  ) t;

  RETURN json_build_object(
    'total_employees', v_total_employees,
    'active_employees', v_active_employees,
    'total_vehicles', v_total_vehicles,
    'total_rides', v_total_rides,
    'completed_rides', v_completed_rides,
    'active_rides_today', v_active_rides_today,
    'total_bookings', v_total_bookings,
    'total_distance_km', v_total_distance,
    'total_revenue', v_total_revenue,
    'co2_saved_kg', v_co2_saved_kg,
    'rides_this_month', v_rides_this_month,
    'rides_last_7_days', COALESCE(v_rides_last_7_days, '[]'::json)
  );
END $$;

GRANT EXECUTE ON FUNCTION admin_dashboard_stats TO authenticated;

-- ============================================================
-- ORGANIZATION SELF-REGISTRATION + EMPLOYEE ORG PICKER
-- ============================================================

-- Publicly readable list of orgs (id + name only) so the mobile app can
-- populate the "Choose your organization" dropdown on the signup screen.
CREATE OR REPLACE FUNCTION list_organizations()
RETURNS TABLE(id UUID, name TEXT)
LANGUAGE sql SECURITY DEFINER
SET search_path = public
AS $$
  SELECT o.id, o.name
  FROM organizations o
  WHERE NOT o.is_deleted
  ORDER BY o.name;
$$;

GRANT EXECUTE ON FUNCTION list_organizations TO anon, authenticated;

-- Called from the admin website's "Register your organization" flow.
-- After the user signs up via Supabase Auth we call this to atomically
-- (a) create the organization row and (b) promote the calling user to
-- admin of that new org. Defensively upserts the profile in case the
-- handle_new_user trigger never ran (e.g. schema.sql not fully applied).
CREATE OR REPLACE FUNCTION register_organization(
  p_name TEXT,
  p_industry TEXT,
  p_address TEXT,
  p_admin_contact TEXT
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_email TEXT;
  v_org_id UUID;
  v_existing_org UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
    RAISE EXCEPTION 'organization name is required';
  END IF;

  SELECT org_id INTO v_existing_org FROM profiles WHERE id = v_uid;
  IF v_existing_org IS NOT NULL THEN
    RAISE EXCEPTION 'this account is already linked to an organization';
  END IF;

  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;

  INSERT INTO organizations (name, industry, address, admin_contact)
  VALUES (trim(p_name), NULLIF(trim(p_industry), ''),
          NULLIF(trim(p_address), ''), NULLIF(trim(p_admin_contact), ''))
  RETURNING id INTO v_org_id;

  -- Upsert the profile so this works even if the handle_new_user trigger
  -- didn't fire when the auth user was created.
  INSERT INTO profiles (id, email, name, phone, role, platform_access, org_id)
  VALUES (v_uid, COALESCE(v_email, ''), '', '', 'admin', 'granted', v_org_id)
  ON CONFLICT (id) DO UPDATE
    SET role = 'admin',
        org_id = COALESCE(profiles.org_id, EXCLUDED.org_id);

  RETURN v_org_id;
END $$;

GRANT EXECUTE ON FUNCTION register_organization TO authenticated;

-- Make org_id immutable once set: employees pick their organization ONCE
-- at signup and cannot switch afterwards. Only blocks regular end users —
-- superusers, service_role, and SQL editor sessions (where auth.uid() is
-- NULL) can still update org_id for repair / admin actions.
CREATE OR REPLACE FUNCTION prevent_org_id_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND OLD.org_id IS NOT NULL
     AND NEW.org_id IS DISTINCT FROM OLD.org_id THEN
    RAISE EXCEPTION 'org_id cannot be changed once assigned';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_lock_org_id ON profiles;
CREATE TRIGGER trg_lock_org_id
  BEFORE UPDATE OF org_id ON profiles
  FOR EACH ROW EXECUTE FUNCTION prevent_org_id_change();

-- ---------- MAKE A USER ADMIN (edit the email, then run) ----------
-- UPDATE profiles SET role = 'admin' WHERE email = 'your-admin@email.com';
