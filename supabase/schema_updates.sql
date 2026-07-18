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
BEGIN
  INSERT INTO public.profiles AS p (id, email, name, phone, role, platform_access)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'phone', ''),
    'employee',
    'granted'
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = COALESCE(NULLIF(EXCLUDED.name, ''), p.name),
    phone = COALESCE(NULLIF(EXCLUDED.phone, ''), p.phone);
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
  USING (EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));

-- Admins can create the organization row if none exists
DROP POLICY IF EXISTS "org insert by admin" ON organizations;
CREATE POLICY "org insert by admin" ON organizations
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));

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

-- Enable realtime for notifications
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- ---------- MAKE A USER ADMIN (edit the email, then run) ----------
-- UPDATE profiles SET role = 'admin' WHERE email = 'your-admin@email.com';
