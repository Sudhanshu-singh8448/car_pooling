-- ============================================================
-- Recurring rides v2
-- Run after schema.sql, schema_updates.sql, and feature_migration.sql.
-- Existing rides.is_recurring / rides.recurring_days are retained for
-- compatibility; recurring_rides is the canonical configuration table.
-- ============================================================

CREATE OR REPLACE FUNCTION public.normalize_weekday(p_day TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(trim(p_day))
    WHEN 'mon' THEN 'Monday'
    WHEN 'monday' THEN 'Monday'
    WHEN 'tue' THEN 'Tuesday'
    WHEN 'tues' THEN 'Tuesday'
    WHEN 'tuesday' THEN 'Tuesday'
    WHEN 'wed' THEN 'Wednesday'
    WHEN 'wednesday' THEN 'Wednesday'
    WHEN 'thu' THEN 'Thursday'
    WHEN 'thur' THEN 'Thursday'
    WHEN 'thurs' THEN 'Thursday'
    WHEN 'thursday' THEN 'Thursday'
    WHEN 'fri' THEN 'Friday'
    WHEN 'friday' THEN 'Friday'
    WHEN 'sat' THEN 'Saturday'
    WHEN 'saturday' THEN 'Saturday'
    WHEN 'sun' THEN 'Sunday'
    WHEN 'sunday' THEN 'Sunday'
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.normalize_weekdays(p_days TEXT[])
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    ARRAY(
      SELECT normalized_day
      FROM (
        SELECT public.normalize_weekday(input_day) AS normalized_day
        FROM unnest(COALESCE(p_days, ARRAY[]::TEXT[])) AS input_day
      ) normalized
      WHERE normalized_day IS NOT NULL
      GROUP BY normalized_day
      ORDER BY array_position(
        ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']::TEXT[],
        normalized_day
      )
    ),
    ARRAY[]::TEXT[]
  );
$$;

CREATE TABLE IF NOT EXISTS public.recurring_rides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL UNIQUE REFERENCES public.rides(id) ON DELETE CASCADE,
  offerer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_recurring BOOLEAN NOT NULL DEFAULT TRUE,
  recurrence_type TEXT NOT NULL DEFAULT 'weekly'
    CHECK (recurrence_type IN ('weekly')),
  recurrence_days TEXT[] NOT NULL,
  trips_per_week INT NOT NULL DEFAULT 1
    CHECK (trips_per_week BETWEEN 1 AND 7),
  start_date DATE NOT NULL DEFAULT CURRENT_DATE,
  end_date DATE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT recurring_rides_days_check CHECK (
    cardinality(recurrence_days) BETWEEN 1 AND 7
  ),
  CONSTRAINT recurring_rides_trip_count_check CHECK (
    trips_per_week <= cardinality(recurrence_days)
  ),
  CONSTRAINT recurring_rides_date_check CHECK (
    end_date IS NULL OR end_date >= start_date
  )
);

CREATE INDEX IF NOT EXISTS idx_recurring_rides_active_days
  ON public.recurring_rides (is_active, start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_recurring_rides_offerer
  ON public.recurring_rides (offerer_id, is_active);
CREATE INDEX IF NOT EXISTS idx_recurring_rides_ride
  ON public.recurring_rides (ride_id);
CREATE INDEX IF NOT EXISTS idx_recurring_rides_days
  ON public.recurring_rides USING GIN (recurrence_days);

CREATE OR REPLACE FUNCTION public.set_recurring_rides_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recurring_rides_updated_at ON public.recurring_rides;
CREATE TRIGGER trg_recurring_rides_updated_at
  BEFORE UPDATE ON public.recurring_rides
  FOR EACH ROW EXECUTE FUNCTION public.set_recurring_rides_updated_at();

-- Backfill old recurring configurations. Invalid/empty legacy values are
-- ignored rather than creating unusable rows.
INSERT INTO public.recurring_rides (
  ride_id, offerer_id, is_recurring, recurrence_days, trips_per_week,
  start_date, is_active
)
SELECT
  r.id,
  r.driver_id,
  TRUE,
  public.normalize_weekdays(string_to_array(r.recurring_days, ',')),
  LEAST(
    GREATEST(1, cardinality(public.normalize_weekdays(string_to_array(r.recurring_days, ',')))),
    7
  ),
  r.departure_time::DATE,
  r.status = 'published' AND NOT r.is_deleted
FROM public.rides r
WHERE r.is_recurring
  AND r.recurring_days IS NOT NULL
  AND cardinality(public.normalize_weekdays(string_to_array(r.recurring_days, ','))) BETWEEN 1 AND 7
ON CONFLICT (ride_id) DO UPDATE SET
  offerer_id = EXCLUDED.offerer_id,
  recurrence_days = EXCLUDED.recurrence_days,
  is_active = EXCLUDED.is_active,
  updated_at = NOW();

-- Keep the legacy fields synchronized for clients and older RPCs.
CREATE OR REPLACE FUNCTION public.sync_recurring_ride_to_legacy()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.rides
  SET is_recurring = NEW.is_recurring AND NEW.is_active,
      recurring_days = CASE
        WHEN NEW.is_recurring AND NEW.is_active
        THEN array_to_string(NEW.recurrence_days, ',')
        ELSE NULL
      END,
      updated_at = NOW()
  WHERE id = NEW.ride_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_recurring_ride_to_legacy ON public.recurring_rides;
CREATE TRIGGER trg_sync_recurring_ride_to_legacy
  AFTER INSERT OR UPDATE OF is_recurring, is_active, recurrence_days
  ON public.recurring_rides
  FOR EACH ROW EXECUTE FUNCTION public.sync_recurring_ride_to_legacy();

ALTER TABLE public.recurring_rides ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Recurring rides readable by authenticated users" ON public.recurring_rides;
CREATE POLICY "Recurring rides readable by authenticated users"
  ON public.recurring_rides FOR SELECT TO authenticated
  USING (is_active = TRUE OR offerer_id = auth.uid());
DROP POLICY IF EXISTS "Offerers manage own recurring rides" ON public.recurring_rides;
CREATE POLICY "Offerers manage own recurring rides"
  ON public.recurring_rides FOR ALL TO authenticated
  USING (offerer_id = auth.uid())
  WITH CHECK (offerer_id = auth.uid());

-- Create or replace a recurrence for an existing ride. The ride itself is
-- still created by the existing rides insert flow.
CREATE OR REPLACE FUNCTION public.recurring_ride_as_json(p_ride_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id', rr.id,
    'ride_id', r.id,
    'driver_id', r.driver_id,
    'driver_name', p.name,
    'driver_avatar', p.avatar_url,
    'driver_phone', p.phone,
    'vehicle_id', r.vehicle_id,
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
    'is_recurring', rr.is_recurring,
    'recurring_days', rr.recurrence_days,
    'trips_per_week', rr.trips_per_week,
    'start_date', rr.start_date,
    'end_date', rr.end_date,
    'is_active', rr.is_active,
    'status', r.status
  )
  FROM public.recurring_rides rr
  JOIN public.rides r ON r.id = rr.ride_id
  JOIN public.profiles p ON p.id = r.driver_id
  JOIN public.vehicles v ON v.id = r.vehicle_id
  WHERE rr.ride_id = p_ride_id;
$$;

DROP FUNCTION IF EXISTS public.upsert_recurring_ride(UUID, TEXT[], INT, DATE, DATE, BOOLEAN);
CREATE OR REPLACE FUNCTION public.upsert_recurring_ride(
  p_ride_id UUID,
  p_recurrence_days TEXT[],
  p_trips_per_week INT,
  p_start_date DATE DEFAULT CURRENT_DATE,
  p_end_date DATE DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride public.rides%ROWTYPE;
  v_days TEXT[];
  v_result public.recurring_rides%ROWTYPE;
BEGIN
  SELECT * INTO v_ride
  FROM public.rides
  WHERE id = p_ride_id AND driver_id = auth.uid()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RIDE_NOT_FOUND_OR_NOT_OWNER'; END IF;

  v_days := public.normalize_weekdays(p_recurrence_days);
  IF cardinality(v_days) < 1 THEN RAISE EXCEPTION 'RECURRING_DAYS_REQUIRED'; END IF;
  IF p_trips_per_week < 1 OR p_trips_per_week > cardinality(v_days) THEN
    RAISE EXCEPTION 'INVALID_TRIPS_PER_WEEK';
  END IF;
  IF p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
    RAISE EXCEPTION 'INVALID_RECURRENCE_DATE_RANGE';
  END IF;

  INSERT INTO public.recurring_rides (
    ride_id, offerer_id, is_recurring, recurrence_type, recurrence_days,
    trips_per_week, start_date, end_date, is_active
  ) VALUES (
    p_ride_id, auth.uid(), TRUE, 'weekly', v_days,
    p_trips_per_week, p_start_date, p_end_date, p_is_active
  )
  ON CONFLICT (ride_id) DO UPDATE SET
    offerer_id = EXCLUDED.offerer_id,
    is_recurring = TRUE,
    recurrence_type = 'weekly',
    recurrence_days = EXCLUDED.recurrence_days,
    trips_per_week = EXCLUDED.trips_per_week,
    start_date = EXCLUDED.start_date,
    end_date = EXCLUDED.end_date,
    is_active = EXCLUDED.is_active,
    updated_at = NOW()
  RETURNING * INTO v_result;

  RETURN public.recurring_ride_as_json(p_ride_id);
END;
$$;

DROP FUNCTION IF EXISTS public.set_recurring_ride_active(UUID, BOOLEAN);
CREATE OR REPLACE FUNCTION public.set_recurring_ride_active(
  p_ride_id UUID,
  p_is_active BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result public.recurring_rides%ROWTYPE;
BEGIN
  UPDATE public.recurring_rides
  SET is_active = p_is_active,
      is_recurring = p_is_active
  WHERE ride_id = p_ride_id AND offerer_id = auth.uid()
  RETURNING * INTO v_result;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECURRING_RIDE_NOT_FOUND'; END IF;
  RETURN public.recurring_ride_as_json(p_ride_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_ride_with_recurrence(
  p_vehicle_id UUID,
  p_pickup_address TEXT,
  p_pickup_lat DOUBLE PRECISION,
  p_pickup_lng DOUBLE PRECISION,
  p_destination_address TEXT,
  p_destination_lat DOUBLE PRECISION,
  p_destination_lng DOUBLE PRECISION,
  p_route_polyline TEXT,
  p_distance_km NUMERIC,
  p_duration_minutes INT,
  p_departure_time TIMESTAMPTZ,
  p_total_seats INT,
  p_fare_per_seat NUMERIC,
  p_recurrence_days TEXT[],
  p_trips_per_week INT,
  p_start_date DATE,
  p_end_date DATE DEFAULT NULL
)
RETURNS public.rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days TEXT[];
  v_ride public.rides%ROWTYPE;
BEGIN
  v_days := public.normalize_weekdays(p_recurrence_days);
  IF cardinality(v_days) < 1 THEN RAISE EXCEPTION 'RECURRING_DAYS_REQUIRED'; END IF;
  IF p_trips_per_week < 1 OR p_trips_per_week > cardinality(v_days) THEN
    RAISE EXCEPTION 'INVALID_TRIPS_PER_WEEK';
  END IF;
  IF p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
    RAISE EXCEPTION 'INVALID_RECURRENCE_DATE_RANGE';
  END IF;

  INSERT INTO public.rides (
    driver_id, vehicle_id, pickup_address, pickup_lat, pickup_lng,
    destination_address, destination_lat, destination_lng, route_polyline,
    distance_km, duration_minutes, departure_time, total_seats,
    available_seats, fare_per_seat, status, is_recurring, recurring_days
  ) VALUES (
    auth.uid(), p_vehicle_id, p_pickup_address, p_pickup_lat, p_pickup_lng,
    p_destination_address, p_destination_lat, p_destination_lng, p_route_polyline,
    p_distance_km, p_duration_minutes, p_departure_time, p_total_seats,
    p_total_seats, p_fare_per_seat, 'published', TRUE, array_to_string(v_days, ',')
  )
  RETURNING * INTO v_ride;

  INSERT INTO public.recurring_rides (
    ride_id, offerer_id, is_recurring, recurrence_type, recurrence_days,
    trips_per_week, start_date, end_date, is_active
  ) VALUES (
    v_ride.id, auth.uid(), TRUE, 'weekly', v_days,
    p_trips_per_week, p_start_date, p_end_date, TRUE
  );

  RETURN v_ride;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_recurring_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted_count INT;
BEGIN
  DELETE FROM public.recurring_rides
  WHERE ride_id = p_ride_id AND offerer_id = auth.uid();
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  UPDATE public.rides
  SET is_recurring = FALSE, recurring_days = NULL, updated_at = NOW()
  WHERE id = p_ride_id AND driver_id = auth.uid();
  RETURN v_deleted_count > 0;
END;
$$;

-- Search and score on the backend. Exact means the two weekday sets are
-- equal; suggestions are any non-empty intersection, sorted by score.
CREATE OR REPLACE FUNCTION public.search_recurring_rides_v2(
  p_pickup_lat DOUBLE PRECISION,
  p_pickup_lng DOUBLE PRECISION,
  p_dest_lat DOUBLE PRECISION,
  p_dest_lng DOUBLE PRECISION,
  p_days TEXT[],
  p_date DATE DEFAULT CURRENT_DATE,
  p_seats INT DEFAULT 1,
  p_trips_per_week INT DEFAULT NULL,
  p_radius_km NUMERIC DEFAULT 5,
  p_max_fare NUMERIC DEFAULT NULL,
  p_vehicle_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS SETOF JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH requested AS (
    SELECT public.normalize_weekdays(p_days) AS days
  ), candidates AS (
    SELECT
      r.id,
      r.driver_id,
      p.name AS driver_name,
      p.avatar_url AS driver_avatar,
      p.phone AS driver_phone,
      v.id AS vehicle_id,
      v.model AS vehicle_model,
      v.registration_number AS vehicle_registration,
      r.pickup_address,
      r.pickup_lat,
      r.pickup_lng,
      r.destination_address,
      r.destination_lat,
      r.destination_lng,
      r.route_polyline,
      r.distance_km,
      r.duration_minutes,
      r.departure_time,
      r.total_seats,
      r.available_seats,
      r.fare_per_seat,
      r.status,
      rr.recurrence_days,
      rr.trips_per_week,
      rr.start_date,
      rr.end_date,
      ARRAY(
        SELECT day
        FROM unnest(rr.recurrence_days) AS day
        WHERE day = ANY(requested.days)
        ORDER BY array_position(
          ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']::TEXT[],
          day
        )
      ) AS matching_days,
      requested.days AS requested_days
    FROM public.recurring_rides rr
    JOIN public.rides r ON r.id = rr.ride_id
    JOIN public.profiles p ON p.id = r.driver_id
    JOIN public.vehicles v ON v.id = r.vehicle_id
    CROSS JOIN requested
    WHERE rr.is_recurring
      AND rr.is_active
      AND p.platform_access = 'granted'
      AND r.status = 'published'
      AND NOT r.is_deleted
      AND r.driver_id <> auth.uid()
      AND r.available_seats >= p_seats
      AND (p_trips_per_week IS NULL OR rr.trips_per_week = p_trips_per_week)
      AND (p_vehicle_id IS NULL OR r.vehicle_id = p_vehicle_id)
      AND (p_max_fare IS NULL OR r.fare_per_seat <= p_max_fare)
      AND p_date >= rr.start_date
      AND (rr.end_date IS NULL OR p_date <= rr.end_date)
      AND r.pickup_lat BETWEEN p_pickup_lat - (p_radius_km / 111.0)
                           AND p_pickup_lat + (p_radius_km / 111.0)
      AND r.pickup_lng BETWEEN p_pickup_lng - (p_radius_km / 111.0)
                           AND p_pickup_lng + (p_radius_km / 111.0)
      AND r.destination_lat BETWEEN p_dest_lat - (p_radius_km / 111.0)
                                AND p_dest_lat + (p_radius_km / 111.0)
      AND r.destination_lng BETWEEN p_dest_lng - (p_radius_km / 111.0)
                                AND p_dest_lng + (p_radius_km / 111.0)
  ), scored AS (
    SELECT *,
      cardinality(matching_days) AS match_count,
      cardinality(requested_days) AS total_requested,
      ROUND(
        (cardinality(matching_days)::NUMERIC / NULLIF(cardinality(requested_days), 0)) * 100,
        0
      ) AS match_percentage,
      recurrence_days @> requested_days AND requested_days @> recurrence_days
        AND cardinality(recurrence_days) = cardinality(requested_days) AS is_exact_match
    FROM candidates
  )
  SELECT jsonb_build_object(
    'id', id,
    'ride_id', id,
    'driver_id', driver_id,
    'driver_name', driver_name,
    'driver_avatar', driver_avatar,
    'driver_phone', driver_phone,
    'vehicle_id', vehicle_id,
    'vehicle_model', vehicle_model,
    'vehicle_registration', vehicle_registration,
    'pickup_address', pickup_address,
    'pickup_lat', pickup_lat,
    'pickup_lng', pickup_lng,
    'destination_address', destination_address,
    'destination_lat', destination_lat,
    'destination_lng', destination_lng,
    'route_polyline', route_polyline,
    'distance_km', distance_km,
    'duration_minutes', duration_minutes,
    'departure_time', departure_time,
    'total_seats', total_seats,
    'available_seats', available_seats,
    'fare_per_seat', fare_per_seat,
    'status', status,
    'is_recurring', TRUE,
    'recurring_days', recurrence_days,
    'requested_days', requested_days,
    'trips_per_week', trips_per_week,
    'start_date', start_date,
    'end_date', end_date,
    'matching_days', matching_days,
    'match_count', match_count,
    'total_requested', total_requested,
    'match_percentage', match_percentage,
    'is_exact_match', is_exact_match
  )
  FROM scored
  WHERE match_count > 0
  ORDER BY is_exact_match DESC, match_count DESC,
           match_percentage DESC, departure_time ASC, fare_per_seat ASC
  LIMIT GREATEST(1, LEAST(p_limit, 100))
  OFFSET GREATEST(0, p_offset);
$$;

GRANT EXECUTE ON FUNCTION public.upsert_recurring_ride TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_recurring_ride_active TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_recurring_ride TO authenticated;
GRANT EXECUTE ON FUNCTION public.recurring_ride_as_json TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_ride_with_recurrence TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_recurring_rides_v2 TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'recurring_rides'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.recurring_rides;
  END IF;
END;
$$;
