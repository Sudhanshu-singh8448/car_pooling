import { FormEvent, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../hooks/useAuth';

interface OrgPricing {
  id: string;
  name: string;
  fuel_cost_per_liter: number;
  cost_per_km: number;
  travel_cost_per_km: number;
}

export default function PricingPage() {
  const { profile } = useAuth();
  const [org, setOrg] = useState<OrgPricing | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    const query = supabase
      .from('organizations')
      .select('id, name, fuel_cost_per_liter, cost_per_km, travel_cost_per_km')
      .eq('is_deleted', false)
      .limit(1);
    if (profile?.org_id) query.eq('id', profile.org_id);
    const { data, error: err } = await query.maybeSingle();
    if (err) setError(err.message);
    else setOrg(data as OrgPricing | null);
    setLoading(false);
  }

  useEffect(() => {
    void load();
  }, [profile?.org_id]);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (!org) return;
    setSaving(true);
    setError(null);
    setSuccess(null);
    const { error: err } = await supabase
      .from('organizations')
      .update({
        fuel_cost_per_liter: org.fuel_cost_per_liter,
        cost_per_km: org.cost_per_km,
        travel_cost_per_km: org.travel_cost_per_km,
      })
      .eq('id', org.id);
    setSaving(false);
    if (err) setError(err.message);
    else setSuccess('Pricing updated. Drivers will see the new suggested fares.');
  }

  if (loading) return <div className="page"><h1>Pricing</h1><p>Loading…</p></div>;
  if (!org)
    return (
      <div className="page">
        <h1>Pricing</h1>
        <div className="error">
          No organization is linked to your account. Create one first from the
          Organization page.
        </div>
      </div>
    );

  return (
    <div className="page">
      <header className="page-header">
        <div>
          <h1>Pricing</h1>
          <p className="muted">
            These values are used by the mobile app to suggest a per-seat fare when a
            driver publishes a ride. Employees see the minimum travel cost as a fare
            floor.
          </p>
        </div>
      </header>

      <form onSubmit={onSubmit} className="panel form-panel">
        <label>
          Fuel cost per litre (₹)
          <input
            type="number"
            step="0.01"
            min="0"
            required
            value={org.fuel_cost_per_liter}
            onChange={(e) =>
              setOrg({ ...org, fuel_cost_per_liter: parseFloat(e.target.value) })
            }
          />
          <span className="muted small">Current market fuel rate for suggested fare calc.</span>
        </label>

        <label>
          Operating cost per km (₹)
          <input
            type="number"
            step="0.01"
            min="0"
            required
            value={org.cost_per_km}
            onChange={(e) => setOrg({ ...org, cost_per_km: parseFloat(e.target.value) })}
          />
          <span className="muted small">
            Rough all-in cost (fuel + maintenance + depreciation) per kilometre.
          </span>
        </label>

        <label>
          Minimum travel cost per km (₹)
          <input
            type="number"
            step="0.01"
            min="0"
            required
            value={org.travel_cost_per_km}
            onChange={(e) =>
              setOrg({ ...org, travel_cost_per_km: parseFloat(e.target.value) })
            }
          />
          <span className="muted small">
            Fare floor — drivers cannot charge less than this per km.
          </span>
        </label>

        {error && <div className="error">{error}</div>}
        {success && <div className="success">{success}</div>}

        <button className="btn btn-primary" disabled={saving} type="submit">
          {saving ? 'Saving…' : 'Save pricing'}
        </button>
      </form>
    </div>
  );
}
