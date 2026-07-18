# Carpool Admin Dashboard (React + Vite)

Admin-only web dashboard for the Enterprise Carpooling Platform.
Employees use the **Flutter** app in `../app`; company administrators use **this website**.

It talks to the **same Supabase backend** — no separate server, no data duplication.
Access is gated by `profiles.role = 'admin'` and enforced by Postgres RLS policies.

## Features

Everything an admin needs to run the carpooling program:

- **Dashboard** — KPI cards (total employees, active rides today, total trips this month,
  distance covered, revenue, estimated CO₂ saved) and a 7-day rides line chart.
- **Employees** — see every registered employee, search by name/email, and grant / revoke
  platform access with one click.
- **Vehicles** — inventory of every vehicle registered in the organization with owner,
  registration number, seats and status.
- **Rides** — every ride ever published, filterable by status (published / in progress /
  completed / cancelled) with route, seats, fare and departure time.
- **Pricing** — edit the fuel cost per litre, per-km cost and minimum travel cost that
  the mobile app uses when suggesting fares to drivers.
- **Organization** — edit organization profile (name, industry, address, admin contact).

## Getting started

```bash
cd admin-web
cp .env.example .env
# then edit .env and set VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY
npm install
npm run dev
```

Open http://localhost:5173 and sign in with an admin account.

## Making a user an admin

The first admin has to be promoted manually. Run this once in the Supabase SQL editor:

```sql
UPDATE profiles SET role = 'admin' WHERE email = 'your-admin@email.com';
```

After that you can grant / revoke access to any employee from the dashboard.

## Build for production

```bash
npm run build
```

Static files are emitted to `dist/`. Serve them from any static host
(Netlify, Vercel, Cloudflare Pages, Supabase static hosting, S3+CloudFront, etc.).
