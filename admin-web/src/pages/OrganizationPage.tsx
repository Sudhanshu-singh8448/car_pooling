import { FormEvent, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../hooks/useAuth';

interface Organization {
  id: string;
  name: string;
  industry: string | null;
  address: string | null;
  admin_contact: string | null;
}

const EMPTY: Organization = {
  id: '',
  name: '',
  industry: '',
  address: '',
  admin_contact: '',
};

export default function OrganizationPage() {
  const { profile, refresh } = useAuth();
  const [org, setOrg] = useState<Organization>(EMPTY);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    const query = supabase
      .from('organizations')
      .select('id, name, industry, address, admin_contact')
      .eq('is_deleted', false)
      .limit(1);
    if (profile?.org_id) query.eq('id', profile.org_id);
    const { data, error: err } = await query.maybeSingle();
    if (err) setError(err.message);
    else if (data) setOrg(data as Organization);
    else setOrg(EMPTY);
    setLoading(false);
  }

  useEffect(() => {
    void load();
  }, [profile?.org_id]);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    setError(null);
    setSuccess(null);

    if (org.id) {
      // update existing
      const { error: err } = await supabase
        .from('organizations')
        .update({
          name: org.name,
          industry: org.industry,
          address: org.address,
          admin_contact: org.admin_contact,
        })
        .eq('id', org.id);
      setSaving(false);
      if (err) setError(err.message);
      else setSuccess('Organization updated.');
    } else {
      // insert new
      const { data, error: err } = await supabase
        .from('organizations')
        .insert({
          name: org.name,
          industry: org.industry,
          address: org.address,
          admin_contact: org.admin_contact,
        })
        .select('id')
        .single();
      if (err || !data) {
        setSaving(false);
        setError(err?.message ?? 'Failed to create organization.');
        return;
      }
      // link current admin profile to the new org
      if (profile) {
        await supabase.from('profiles').update({ org_id: data.id }).eq('id', profile.id);
      }
      await refresh();
      setSaving(false);
      setSuccess('Organization created and linked to your profile.');
    }
  }

  if (loading) return <div className="page"><h1>Organization</h1><p>Loading…</p></div>;

  return (
    <div className="page">
      <header className="page-header">
        <div>
          <h1>Organization</h1>
          <p className="muted">
            Company profile. This information is used across the mobile app and the admin
            dashboard.
          </p>
        </div>
      </header>

      <form onSubmit={onSubmit} className="panel form-panel">
        <label>
          Name
          <input
            type="text"
            required
            value={org.name}
            onChange={(e) => setOrg({ ...org, name: e.target.value })}
          />
        </label>
        <label>
          Industry
          <input
            type="text"
            value={org.industry ?? ''}
            onChange={(e) => setOrg({ ...org, industry: e.target.value })}
          />
        </label>
        <label>
          Address
          <textarea
            rows={3}
            value={org.address ?? ''}
            onChange={(e) => setOrg({ ...org, address: e.target.value })}
          />
        </label>
        <label>
          Administrator contact
          <input
            type="text"
            placeholder="Email or phone"
            value={org.admin_contact ?? ''}
            onChange={(e) => setOrg({ ...org, admin_contact: e.target.value })}
          />
        </label>

        {error && <div className="error">{error}</div>}
        {success && <div className="success">{success}</div>}

        <button className="btn btn-primary" disabled={saving} type="submit">
          {saving ? 'Saving…' : org.id ? 'Save changes' : 'Create organization'}
        </button>
      </form>
    </div>
  );
}
