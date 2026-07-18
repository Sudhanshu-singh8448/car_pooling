# Admin Website — What Was Built

This document summarises the admin dashboard that was added on top of the existing
Flutter carpooling app.

## Why a separate website

The Flutter app in `app/` is for **employees** — they book rides, publish rides,
chat with drivers, pay, rate trips, and so on.

Company **administrators** don't need a phone in their pocket to do their job.
They need a big screen with tables, charts, filters, and one-click controls.
Trying to squeeze that into the mobile app would be the wrong shape for the job,
so it lives in its own project: **`admin-web/`** — a React + Vite + TypeScript
single-page app that talks to the **same Supabase backend** as the mobile app.

- No new backend was written.
- No data is duplicated.
- Access is gated by `profiles.role = 'admin'` and enforced by Postgres RLS.

## What an admin can do (from the requirements PDF)

| Requirement                                        | Where it lives                          |
| -------------------------------------------------- | --------------------------------------- |
| Manage employee records                            | Employees page                          |
| Grant / revoke platform access                     | Employees page (one-click toggle)       |
| Manage registered vehicles and driver information  | Vehicles page                           |
| Configure organization-specific carpooling settings| Organization page                       |
| Maintain fuel cost                                 | Pricing page (`fuel_cost_per_liter`)    |
| Maintain per-km operating cost                     | Pricing page (`cost_per_km`)            |
| Maintain minimum travel cost                       | Pricing page (`travel_cost_per_km`)     |
| Monitor employee participation                     | Dashboard KPIs + Rides page             |
| Easy dashboard access to all data                  | Dashboard is the landing page           |

## Pages built

1. **Login** — email + password Supabase auth. Non-admins are shown an
   "Access denied" screen and asked to sign out.
2. **Dashboard** *(landing page)* — 8 KPI cards + a 7-day rides line chart
   powered by one SQL RPC:
    - Total employees / with active access
    - Active rides today / rides this month
    - Trips completed vs published
    - Vehicles registered
    - Total distance covered
    - Estimated CO₂ saved
    - Total bookings
    - Revenue processed
3. **Employees** — searchable table of every registered user with
   grant/revoke buttons for `platform_access`.
4. **Vehicles** — fleet inventory joined with the owner profile.
5. **Rides** — every ride, filterable by status
   (`published` / `in_progress` / `completed` / `cancelled`).
6. **Pricing** — form editing the org's `fuel_cost_per_liter`, `cost_per_km`,
   and `travel_cost_per_km`. Drivers see the updated suggested fare immediately.
7. **Organization** — company profile (name, industry, address, admin contact).
   If no org exists it lets the first admin create one and links it to their profile.

## Backend changes (SQL)

All changes are in `supabase/schema_updates.sql`, safe to re-run.

1. **Bug fix.** The `ALTER PUBLICATION supabase_realtime ADD TABLE notifications;`
   statement was not idempotent and failed with `42710` on re-run. It's now wrapped
   in a `DO $$ ... $$` block that checks `pg_publication_tables` first.
2. **Admin RLS policies.** Added read policies so admins can `SELECT` across
   `profiles`, `vehicles`, `rides`, `bookings`, `payments` and `organizations`.
3. **Update policy.** Added `org update by admin` so admins can edit pricing and
   organization details.
4. **Analytics RPC.** New `admin_dashboard_stats(p_org_id UUID DEFAULT NULL)`
   `SECURITY DEFINER` function that returns every KPI on the dashboard in one JSON
   payload. It raises `not authorized` for non-admins.

No new tables were needed — `organizations` already had the pricing columns and
`profiles.role` already supported the `'admin'` value.

## File layout of the new admin site

```
admin-web/
├── package.json
├── vite.config.ts
├── tsconfig.json
├── index.html
├── .env.example
├── .gitignore
├── README.md
└── src/
    ├── main.tsx
    ├── App.tsx                    (routes)
    ├── styles.css                 (single stylesheet, ~250 lines)
    ├── vite-env.d.ts
    ├── lib/
    │   └── supabase.ts            (browser Supabase client)
    ├── hooks/
    │   └── useAuth.ts             (session + role check)
    ├── components/
    │   ├── Layout.tsx             (sidebar + main area)
    │   ├── ProtectedRoute.tsx     (admin gate)
    │   └── StatCard.tsx
    └── pages/
        ├── LoginPage.tsx
        ├── DashboardPage.tsx
        ├── EmployeesPage.tsx
        ├── VehiclesPage.tsx
        ├── RidesPage.tsx
        ├── PricingPage.tsx
        └── OrganizationPage.tsx
```

## How to run it

```bash
cd admin-web
cp .env.example .env
# edit .env and set:
#   VITE_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
#   VITE_SUPABASE_ANON_KEY=YOUR-PUBLISHABLE-KEY
npm install
npm run dev
```

Open http://localhost:5173.

**First-time admin promotion** (do this once in the Supabase SQL editor):

```sql
UPDATE profiles SET role = 'admin' WHERE email = 'your-admin@email.com';
```

**Production build:**

```bash
npm run build
```

Outputs a static `dist/` folder ready to deploy to any static host
(Vercel, Netlify, Cloudflare Pages, S3+CloudFront, Supabase static hosting, etc.).

## Verified

- `npm install` — 117 packages, no install errors
- `tsc --noEmit` — passes with `strict`, `noUnusedLocals`, `noUnusedParameters`
- `npm run build` — 1.63s, produces `dist/index.html` + JS + CSS bundles
- SQL update block for `supabase_realtime` publication is now safe to re-run.

## What is *not* in the admin site

- No employee-facing features (booking, chat, payments). Those stay in the Flutter
  app because the admin should never impersonate an employee.
- No live map. The Flutter app owns Google Maps because that key has a mobile
  restriction and it's not needed for admin analytics.
- No hard-coded credentials. Both the Supabase URL and publishable key are read
  from `.env` at build time; the file is git-ignored.
