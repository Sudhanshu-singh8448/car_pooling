import { useEffect, useState } from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
} from 'recharts';
import StatCard from '../components/StatCard';
import { supabase } from '../lib/supabase';

interface Stats {
  total_employees: number;
  active_employees: number;
  total_vehicles: number;
  total_rides: number;
  completed_rides: number;
  active_rides_today: number;
  total_bookings: number;
  total_distance_km: number;
  total_revenue: number;
  co2_saved_kg: number;
  rides_this_month: number;
  rides_last_7_days: { day: string; ride_count: number }[];
}

function formatNumber(n: number, digits = 0) {
  return n.toLocaleString(undefined, {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}

export default function DashboardPage() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const { data, error: rpcError } = await supabase.rpc('admin_dashboard_stats');
      if (rpcError) {
        setError(rpcError.message);
        setLoading(false);
        return;
      }
      setStats(data as Stats);
      setLoading(false);
    })();
  }, []);

  if (loading) return <div className="page"><h1>Dashboard</h1><p>Loading…</p></div>;
  if (error) {
    const isMissingRpc = /admin_dashboard_stats|does not exist|not found/i.test(error);
    return (
      <div className="page">
        <h1>Dashboard</h1>
        <div className="error">Could not load dashboard data: {error}</div>
        {isMissingRpc && (
          <div className="panel" style={{ marginTop: 16 }}>
            <h2>Database not ready</h2>
            <p className="muted">
              The <code>admin_dashboard_stats</code> function is missing from your
              Supabase database. Open the Supabase SQL editor and run{' '}
              <code>supabase/schema_updates.sql</code> once, then refresh this page.
            </p>
          </div>
        )}
      </div>
    );
  }
  if (!stats) return null;

  return (
    <div className="page">
      <header className="page-header">
        <div>
          <h1>Dashboard</h1>
          <p className="muted">Live overview of your organization's carpooling program.</p>
        </div>
      </header>

      <div className="stat-grid">
        <StatCard
          label="Total employees"
          value={formatNumber(stats.total_employees)}
          hint={`${formatNumber(stats.active_employees)} with active access`}
          accent="primary"
        />
        <StatCard
          label="Active rides today"
          value={formatNumber(stats.active_rides_today)}
          hint={`${formatNumber(stats.rides_this_month)} this month`}
          accent="info"
        />
        <StatCard
          label="Trips completed"
          value={formatNumber(stats.completed_rides)}
          hint={`out of ${formatNumber(stats.total_rides)} published`}
          accent="success"
        />
        <StatCard
          label="Vehicles registered"
          value={formatNumber(stats.total_vehicles)}
          hint="in the fleet"
          accent="primary"
        />
        <StatCard
          label="Total distance"
          value={`${formatNumber(stats.total_distance_km, 1)} km`}
          hint="on completed trips"
          accent="info"
        />
        <StatCard
          label="Est. CO₂ saved"
          value={`${formatNumber(stats.co2_saved_kg, 1)} kg`}
          hint="vs everyone driving alone"
          accent="success"
        />
        <StatCard
          label="Bookings"
          value={formatNumber(stats.total_bookings)}
          hint="all-time seats booked"
          accent="warning"
        />
        <StatCard
          label="Revenue processed"
          value={`₹ ${formatNumber(stats.total_revenue, 2)}`}
          hint="successful payments"
          accent="primary"
        />
      </div>

      <section className="panel">
        <h2>Rides last 7 days</h2>
        <div style={{ width: '100%', height: 300 }}>
          <ResponsiveContainer>
            <LineChart data={stats.rides_last_7_days}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
              <XAxis dataKey="day" />
              <YAxis allowDecimals={false} />
              <Tooltip />
              <Line type="monotone" dataKey="ride_count" stroke="#2563eb" strokeWidth={2} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </section>
    </div>
  );
}
