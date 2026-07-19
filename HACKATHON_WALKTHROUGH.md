# Carpooling App — Hackathon Judge Walkthrough

Welcome! This document is a **10-minute end-to-end tour** of the
carpooling app so you can validate every feature on the rubric without
having to hunt through the code.

- **Team**: Sudhanshu Kumar
- **Track**: Odoo Carpooling Hackathon
- **Live back-end**: Supabase (Postgres + Auth + Realtime + RLS)
- **Mobile client**: Flutter 3 (Riverpod + GoRouter + Google Maps + Razorpay)
- **Admin console**: React 18 + Vite + TypeScript in `admin-web/`

---

## 1. Quick-Start — running the app

### Mobile app (Android / iOS / macOS / Chrome)

```bash
cd app
flutter pub get
flutter run                       # pick your device from the list
```

Supabase URL and publishable key are already baked into
`lib/core/constants/app_constants.dart`, so no `.env` is required.

### Admin console

```bash
cd admin-web
npm install
npm run dev                       # opens http://localhost:5173
```

Login with an admin account (an admin user exists at
`sudhanshusingh8448@gmail.com`; ask us for the password during the
demo).

### Supabase schema

Everything the app talks to lives in three ordered SQL files. If you're
running a fresh Supabase project, execute them in this order in the SQL
editor:

1. `supabase/schema.sql`            – base tables, RLS, wallet, chat
2. `supabase/schema_updates.sql`    – incremental additions
3. `supabase/feature_migration.sql` – notifications, lifecycle, feedback,
   recurring rides, early-exit
4. `supabase/feature_fixes.sql`     – wallet-credit trigger, proportional
   partial-fare RPC, safe deep links

---

## 2. Suggested Demo Path

The order below mirrors the flow in the requirements PDF. Each step
maps to a screenshot / feature that a judge can tick off.

| # | Screen | What to demo | Requirement covered |
|---|--------|--------------|---------------------|
| 1 | Sign-up / Sign-in | Email + password, Supabase Auth | 5.1 Authentication |
| 2 | Dashboard **Find** tab | Enter pickup + destination via Google Places, choose date/time | 5.2 Ride Discovery |
| 3 | Available Rides | Ride cards with driver, vehicle, ETA, fare; tap **Book** | 5.5 Ride Booking |
| 4 | Dashboard **Offer** tab | Fill route, seats, fare per seat, optional **Recurring** toggle + weekdays | 5.3 Ride Publishing |
| 5 | Route Confirmation | Preview polyline on the map, distance + duration from Google Directions | 5.4 Route Confirmation |
| 6 | Notification Center (driver) | Accept / Reject the passenger's booking request — button reacts instantly | Bonus: notifications |
| 7 | Trip Details → Start Trip → Live Tracking | Realtime driver location on map (Supabase Realtime channel) | 5.7 Live Trip Tracking |
| 8 | End Ride Early | Passenger enters "I travelled 4 km of 10 km" → fare drops proportionally | Half-ride pricing |
| 9 | Payment Method | Razorpay UPI / card / cash / wallet | 5.9 Payments & Wallet |
| 10 | Wallet screen | Driver's balance is credited automatically after payment | 5.9 Payments & Wallet |
| 11 | Feedback | Passenger rates driver 1–5 with comment | Trip completion loop |
| 12 | Ride History | Past & upcoming trips, tap for details | 5.10 Ride History |
| 13 | Admin console | User list, ride list, block/unblock, analytics dashboard | 5.11 Reports & Analytics |

---

## 3. Key files to open during code review

| Concern | Path |
|---------|------|
| App entrypoint & DI | `app/lib/main.dart`, `app/lib/core/router/app_router.dart` |
| Auth state | `app/lib/features/auth/presentation/providers/auth_provider.dart` |
| Ride publish / search / book | `app/lib/features/ride/` |
| Trip lifecycle & live tracking | `app/lib/features/trip/` |
| Notifications & realtime bell | `app/lib/features/notification/` |
| Payments (Razorpay + wallet) | `app/lib/features/payment/` |
| Feedback | `app/lib/features/feedback/` |
| SQL schema & RPCs | `supabase/*.sql` |
| Admin analytics | `admin-web/src/pages/DashboardPage.tsx` |

---

## 4. Bonus / recently-shipped items

- **Optimistic notifications** — Accept / Reject buttons hide
  immediately, no wait for the server round-trip.
- **Deep-link safety** — every notification now routes to a screen
  that can't crash if the payload is missing (`/my-trips`, `/wallet`).
- **Recurring ride search** — the "Recurring" toggle on the Find form
  fans out to a bespoke RPC (`search_recurring_rides`) and groups
  results into *Exact Matches* and *Other Suggested Matches*.
- **Auto driver-wallet credit** — a `payments` INSERT trigger
  (`credit_driver_wallet_on_payment`) writes the money into the
  driver's `wallets` row without any client-side ceremony.
- **Proportional partial fare** — passengers who exit mid-trip pay for
  the km actually travelled (`end_ride_early_auto` RPC).

---

## 5. Not-yet-integrated (documented alternatives)

- **FCM push** — the `device_tokens` table already collects tokens on
  login. See [`PUSH_NOTIFICATIONS_SETUP.md`](PUSH_NOTIFICATIONS_SETUP.md)
  for a complete step-by-step Firebase + Supabase Edge Function
  integration; enabling it is a config-only exercise, no code refactor
  is required.

---

Thanks for taking the time to review the project — enjoy the ride!
