-- ============================================================
-- Demo Seed Data
-- PREREQUISITE: Sign up at least 2 users through the app first
-- (e.g. driver@demo.com and rider@demo.com), then run this.
-- It attaches an organization, vehicles, rides and wallet money
-- to the first two profiles found.
-- ============================================================

DO $$
DECLARE
  v_org UUID;
  v_driver UUID;
  v_rider UUID;
  v_vehicle1 UUID;
  v_vehicle2 UUID;
BEGIN
  -- Organization
  INSERT INTO organizations (name, industry, address, admin_contact,
                             fuel_cost_per_liter, cost_per_km, travel_cost_per_km)
  VALUES ('TechCorp Solutions', 'Information Technology',
          'Infocity, Gandhinagar, Gujarat', '+91 98765 43210', 102.5, 12, 15)
  RETURNING id INTO v_org;

  -- Pick first two users (oldest signups first)
  SELECT id INTO v_driver FROM profiles ORDER BY created_at ASC LIMIT 1;
  SELECT id INTO v_rider  FROM profiles ORDER BY created_at ASC OFFSET 1 LIMIT 1;

  IF v_driver IS NULL THEN
    RAISE EXCEPTION 'No profiles found — sign up users in the app first.';
  END IF;

  -- Attach users to org
  UPDATE profiles SET org_id = v_org, department = 'Engineering',
                      manager = 'Priya Sharma', location = 'Gandhinagar'
  WHERE id IN (v_driver, v_rider);

  -- Vehicles for the driver
  INSERT INTO vehicles (owner_id, org_id, model, registration_number, seating_capacity)
  VALUES (v_driver, v_org, 'Maruti Suzuki Swift', 'GJ-01-AB-1234', 4)
  RETURNING id INTO v_vehicle1;

  INSERT INTO vehicles (owner_id, org_id, model, registration_number, seating_capacity)
  VALUES (v_driver, v_org, 'Hyundai Creta', 'GJ-01-CD-5678', 6)
  RETURNING id INTO v_vehicle2;

  -- Published rides (ISKCON ↔ Infocity, Ahmedabad/Gandhinagar area)
  INSERT INTO rides (driver_id, vehicle_id, org_id,
                     pickup_address, pickup_lat, pickup_lng,
                     destination_address, destination_lat, destination_lng,
                     distance_km, duration_minutes, departure_time,
                     total_seats, available_seats, fare_per_seat)
  VALUES
    (v_driver, v_vehicle1, v_org,
     'ISKCON Temple, Ahmedabad', 23.0225, 72.5077,
     'Infocity, Gandhinagar', 23.1890, 72.6367,
     28.5, 45, NOW() + INTERVAL '4 hours', 3, 3, 120),
    (v_driver, v_vehicle1, v_org,
     'ISKCON Temple, Ahmedabad', 23.0225, 72.5077,
     'Infocity, Gandhinagar', 23.1890, 72.6367,
     28.5, 45, NOW() + INTERVAL '1 day 2 hours', 3, 3, 120),
    (v_driver, v_vehicle2, v_org,
     'Infocity, Gandhinagar', 23.1890, 72.6367,
     'ISKCON Temple, Ahmedabad', 23.0225, 72.5077,
     28.5, 50, NOW() + INTERVAL '1 day 10 hours', 5, 5, 100);

  -- Wallet money for both users
  UPDATE wallets SET balance = 500 WHERE user_id IN (v_driver, v_rider);
  INSERT INTO wallet_transactions (wallet_id, type, amount, balance_after, description, reference_type)
  SELECT w.id, 'credit', 500, 500, 'Demo seed recharge', 'recharge'
  FROM wallets w WHERE w.user_id IN (v_driver, v_rider);

  RAISE NOTICE 'Seed complete. Org: %, Driver: %, Rider: %', v_org, v_driver, v_rider;
END $$;
