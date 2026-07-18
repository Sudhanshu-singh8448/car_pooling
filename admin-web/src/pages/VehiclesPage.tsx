import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

interface Vehicle {
  id: string;
  model: string;
  registration_number: string;
  seating_capacity: number;
  status: string;
  created_at: string;
  owner: { id: string; name: string | null; email: string } | null;
}

export default function VehiclesPage() {
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      const { data, error: err } = await supabase
        .from('vehicles')
        .select(
          'id, model, registration_number, seating_capacity, status, created_at, ' +
            'owner:profiles!vehicles_owner_id_fkey(id, name, email)',
        )
        .eq('is_deleted', false)
        .order('created_at', { ascending: false });
      if (err) setError(err.message);
      else setVehicles((data ?? []) as unknown as Vehicle[]);
      setLoading(false);
    })();
  }, []);

  return (
    <div className="page">
      <header className="page-header">
        <div>
          <h1>Vehicles</h1>
          <p className="muted">Every vehicle registered by employees in your organization.</p>
        </div>
      </header>

      {loading && <p>Loading…</p>}
      {error && <div className="error">{error}</div>}

      {!loading && !error && (
        <div className="panel table-panel">
          <table>
            <thead>
              <tr>
                <th>Model</th>
                <th>Registration</th>
                <th>Seats</th>
                <th>Owner</th>
                <th>Status</th>
                <th>Added</th>
              </tr>
            </thead>
            <tbody>
              {vehicles.map((v) => (
                <tr key={v.id}>
                  <td>{v.model}</td>
                  <td className="mono">{v.registration_number}</td>
                  <td>{v.seating_capacity}</td>
                  <td>
                    {v.owner?.name || v.owner?.email || <span className="muted">—</span>}
                  </td>
                  <td>
                    <span className={`chip chip-${v.status === 'active' ? 'success' : 'muted'}`}>
                      {v.status}
                    </span>
                  </td>
                  <td>{new Date(v.created_at).toLocaleDateString()}</td>
                </tr>
              ))}
              {vehicles.length === 0 && (
                <tr>
                  <td colSpan={6} className="muted center">
                    No vehicles registered yet.
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
