# Requirements → Implementation Mapping

This document maps every section of `car_pooling_requirements.pdf`
(Odoo Carpooling Hackathon spec) to the concrete file(s) and
feature(s) that satisfy it in this repository.

Legend: ✅ complete · 🟡 partial / stubbed · ⚪️ documented but not
enabled by default.

---

## 5. Core Feature Areas

### 5.1 Authentication ✅
- **Spec**: Sign-up, login, session management, profile.
- **Implementation**:
  - Supabase Auth (email + password) — `app/lib/features/auth/data/datasources/auth_remote_datasource.dart`
  - Repository & providers — `app/lib/features/auth/`
  - Profile row auto-created on sign-up via `handle_new_user()` trigger in `supabase/schema.sql`
  - Session persisted by `supabase_flutter` on-device; auto-refresh handled by `AuthNotifier`

### 5.2 Ride Discovery ✅
- **Spec**: Search for rides by pickup, destination, date/time, seats.
- **Implementation**:
  - Google Places autocomplete — `core/services/maps_service.dart`
  - `search_rides` RPC in `supabase/schema.sql`
  - Screen — `features/ride/presentation/screens/dashboard_home_screen.dart` (Find tab)
  - Results — `features/ride/presentation/screens/available_rides_screen.dart`

### 5.3 Ride Publishing ✅
- **Spec**: Driver publishes ride with route, seats, fare, vehicle.
- **Implementation**:
  - Form state — `features/ride/presentation/providers/ride_provider.dart` (`RideFormNotifier`)
  - Publish RPC — `publish_ride` in `supabase/schema.sql`
  - Recurring rides — `is_recurring` + `recurring_days` columns; toggle on Offer tab

### 5.4 Route Confirmation ✅
- **Spec**: Show map with route polyline before confirming.
- **Implementation**:
  - Google Directions API — `core/services/maps_service.dart`
  - Screen — `features/ride/presentation/screens/route_confirmation_screen.dart`

### 5.5 Ride Booking ✅
- **Spec**: Passenger requests booking; driver approves.
- **Implementation**:
  - `request_booking`, `accept_booking`, `reject_booking` RPCs — `supabase/feature_fixes.sql`
  - Passenger flow — `features/ride/presentation/screens/available_rides_screen.dart`
  - Driver flow — Notification Center (Accept / Reject buttons)
  - Optimistic UI so buttons feel instant — `handledBookingIdsProvider`

### 5.6 Trip Management ✅
- **Spec**: Cancel booking / cancel ride with reasons, view active + past.
- **Implementation**:
  - `features/trip/data/datasources/trip_remote_datasource.dart` (`cancelBooking`, `cancelRide`)
  - Reason prompts — `features/trip/presentation/screens/trip_details_screen.dart` (`_promptCancellationAndRun`)
  - My Trips list — `features/trip/presentation/screens/my_trips_screen.dart`

### 5.7 Live Trip Tracking ✅
- **Spec**: Realtime driver location while trip is in progress.
- **Implementation**:
  - `ride_locations` table (Supabase Realtime enabled) — `supabase/schema.sql`
  - Broadcast — `features/trip/data/datasources/location_broadcast_service.dart`
  - Consumer screen — `features/trip/presentation/screens/live_tracking_screen.dart`
  - Half-ride early exit — `end_ride_early_auto` RPC in `supabase/feature_fixes.sql`

### 5.8 Vehicle Management ✅
- **Spec**: Add / edit / delete vehicles.
- **Implementation**:
  - Table `vehicles` — `supabase/schema.sql`
  - Feature — `features/vehicle/`

### 5.9 Payments & Wallet ✅
- **Spec**: In-app wallet, top-up, per-ride payment, driver earnings.
- **Implementation**:
  - Tables — `wallets`, `wallet_transactions`, `payments` (`supabase/schema.sql`)
  - RPCs — `recharge_wallet`, `pay_with_wallet` (`supabase/schema.sql`)
  - Payment methods (Razorpay UPI/card, wallet, cash) — `features/payment/`
  - **Auto driver credit** — `credit_driver_wallet_on_payment` trigger in `supabase/feature_fixes.sql`
  - **Proportional fare on early exit** — `end_ride_early_auto` RPC

### 5.10 Ride History ✅
- **Spec**: Chronological list of all past + upcoming trips.
- **Implementation**:
  - `features/trip/presentation/screens/ride_history_screen.dart`
  - Provider — `activeTripsProvider`, `pastTripsProvider`

### 5.11 Reports & Analytics ✅
- **Spec**: Admin dashboard with usage / revenue metrics.
- **Implementation**:
  - Admin site — `admin-web/`
  - Dashboard page — `admin-web/src/pages/DashboardPage.tsx`
  - Backing views/RPCs — `admin_*` functions in `supabase/schema.sql`

---

## 6. Functional Requirements

| Requirement | Where |
|-------------|-------|
| Google Maps integration | `core/services/maps_service.dart` |
| Real-time updates | Supabase Realtime channels — `ride_locations`, `bookings`, `notifications` |
| Role-based access (passenger, driver, admin) | RLS policies in `supabase/schema.sql`; admin bit checked in `admin-web` |
| Secure secrets | Supabase anon key only shipped in-app; service-role key never leaves server |
| Offline resilience | Riverpod AsyncValue error states + pull-to-refresh on every list |

---

## 7. Non-Functional Requirements

- **Performance**: DB indexes on `rides(status, departure_time)`,
  `bookings(passenger_id)`, `notifications(user_id, is_read)`.
- **Security**: OWASP-aligned — RLS on every table; parameterised SQL;
  no dynamic string queries.
- **Scalability**: Stateless client; Supabase handles horizontal scale.

---

## 8. Mandatory & Bonus Features

### Mandatory
- User Registration & Auth ✅
- Ride Publishing ✅
- Ride Discovery ✅
- Booking ✅
- Route Confirmation ✅
- Live Trip Tracking ✅
- Payment ✅
- Ride History ✅

### Bonus (implemented)
- Notifications (in-app centre + realtime) ✅
- Recurring Rides (search + publish) ✅
- Cancellation with reason logging ✅
- Intelligent matching — Haversine + polyline overlap in `search_rides` ✅
- Route optimisation via Google Directions ✅
- Enhanced analytics (admin dashboard) ✅
- Wallet-based earnings for drivers ✅
- Feedback / Reviews ✅

### Bonus (documented, not enabled by default)
- Push Notifications (FCM) ⚪️ — see `PUSH_NOTIFICATIONS_SETUP.md`

---

## 9. File-Map Quick Reference

```
supabase/
  schema.sql                    # tables, RLS, wallet, chat, admin RPCs
  schema_updates.sql            # incremental patches
  feature_migration.sql         # notifications, feedback, recurring, lifecycle
  feature_fixes.sql             # wallet credit trigger, partial fare, safe links

app/lib/
  core/
    router/app_router.dart      # GoRouter table
    services/maps_service.dart  # Google Maps + Places + Directions
    theme/                      # Colours, spacing, typography tokens
  features/
    auth/                       # Supabase auth
    ride/                       # search, publish, book, route confirm
    trip/                       # active trips, live tracking, cancel, half-ride
    notification/               # in-app centre, realtime, actions
    payment/                    # Razorpay + wallet
    feedback/                   # star + comment
    vehicle/                    # driver's vehicles CRUD
    dashboard/                  # bottom-nav host

admin-web/
  src/pages/                    # login, users, rides, dashboard, analytics
```

---

Every checklist item above corresponds to code that runs today — the
only exception is the FCM layer, which is fully specified in
`PUSH_NOTIFICATIONS_SETUP.md` and requires a Firebase project to
switch on.
