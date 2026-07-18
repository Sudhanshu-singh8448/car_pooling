import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

interface Ride {
  id: string;
  pickup_address: string;
  destination_address: string;
  departure_time: string;
  status: string;
  total_seats: number;
  available_seats: number;
  fare_per_seat: number;
  distance_km: number | null;
  driver: { name: string | null; email: string } | null;
  vehicle: { model: string; registration_number: string } | null;
}

const STATUSES = ['all', 'published', 'in_progress', 'completed', 'cancelled'];

export default function RidesPage() {
  const [rides, setRides] = useState<Ride[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string>('all');

  useEffect(() => {
    (async () => {
      setLoading(true);
      let query = supabase
        .from('rides')
        .select(
          'id, pickup_address, destination_address, departure_time, status, total_seats, ' +
            'available_seats, fare_per_seat, distance_km, ' +
            'driver:profiles!rides_driver_id_fkey(name, email), ' +
            'vehicle:vehicles!rides_vehicle_id_fkey(model, registration_number)',
        )
        .eq('is_deleted', false)
        .order('departure_time', { ascending: false })
        .limit(200);
      if (status !== 'all') query = query.eq('status', status);
      const { data, error: err } = await query;
      if (err) setError(err.message);
      else {
        setRides((data ?? []) as unknown as Ride[]);
        setError(null);
      }
      setLoading(false);
    })();
  }, [status]);

  return (
    <div className="page">
      <header className="page-header">
        <div>
          <h1>Rides</h1>
          <p className="muted">Every published ride, filtered by status.</p>
        </div>
        <select
          className="search-input"
          value={status}
          onChange={(e) => setStatus(e.target.value)}
        >
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {s === 'all' ? 'All statuses' : s.replace('_', ' ')}
            </option>
          ))}
        </select>
      </header>

      {loading && <p>Loading…</p>}
      {error && <div className="error">{error}</div>}

      {!loading && !error && (
        <div className="panel table-panel">
          <table>
            <thead>
              <tr>
                <th>Departure</th>
                <th>Route</th>
                <th>Driver</th>
                <th>Vehicle</th>
                <th>Seats</th>
                <th>Fare / seat</th>
                <th>Distance</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {rides.map((r) => (
                <tr key={r.id}>
                  <td>{new Date(r.departure_time).toLocaleString()}</td>
                  <td className="route-cell">
                    <div>{r.pickup_address}</div>
                    <div className="muted">→ {r.destination_address}</div>
                  </td>
                  <td>{r.driver?.name || r.driver?.email || '—'}</td>
                  <td>
                    {r.vehicle ? (
                      <>
                        {r.vehicle.model}
                        <div className="muted mono small">{r.vehicle.registration_number}</div>
                      </>
                    ) : (
                      '—'
                    )}
                  </td>
                  <td>
                    {r.total_seats - r.available_seats} / {r.total_seats}
                  </td>
                  <td>₹ {Number(r.fare_per_seat).toFixed(2)}</td>
                  <td>{r.distance_km ? `${Number(r.distance_km).toFixed(1)} km` : '—'}</td>
                  <td>
                    <span className={`chip chip-status-${r.status}`}>
                      {r.status.replace('_', ' ')}
                    </span>
                  </td>
                </tr>
              ))}
              {rides.length === 0 && (
                <tr>
                  <td colSpan={8} className="muted center">
                    No rides in this filter.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
