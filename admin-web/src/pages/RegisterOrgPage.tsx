import { FormEvent, useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../hooks/useAuth';

interface Form {
  orgName: string;
  industry: string;
  address: string;
  adminContact: string;
  name: string;
  email: string;
  phone: string;
  password: string;
  confirm: string;
}

const EMPTY: Form = {
  orgName: '',
  industry: '',
  address: '',
  adminContact: '',
  name: '',
  email: '',
  phone: '',
  password: '',
  confirm: '',
};

export default function RegisterOrgPage() {
  const nav = useNavigate();
  const { loading: authLoading, session, isAdmin, profile, refresh } = useAuth();
  const [form, setForm] = useState<Form>(EMPTY);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  // If already an admin with an org, kick them straight to the dashboard.
  useEffect(() => {
    if (!authLoading && session && isAdmin && profile?.org_id) {
      nav('/dashboard', { replace: true });
    }
  }, [authLoading, session, isAdmin, profile?.org_id, nav]);

  // Prefill from the current session if the user already signed up and is now
  // finishing the org step.
  useEffect(() => {
    if (session && !form.email) {
      setForm((prev) => ({
        ...prev,
        email: session.user.email ?? '',
        name: (session.user.user_metadata?.name as string) ?? prev.name,
        phone: (session.user.user_metadata?.phone as string) ?? prev.phone,
      }));
    }
  }, [session, form.email]);

  function set<K extends keyof Form>(key: K, value: Form[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  const alreadySignedIn = !!session;

  async function callRegisterOrgRpc(): Promise<string | null> {
    if (!session) return 'You are not signed in. Refresh and try again.';

    const { error: rpcError } = await supabase.rpc('register_organization', {
      p_name: form.orgName.trim(),
      p_industry: form.industry.trim(),
      p_address: form.address.trim(),
      p_admin_contact: form.adminContact.trim() || form.email.trim(),
    });

    // Special case: user already had an org linked. Their profile is already
    // admin — refresh and continue as if this call succeeded.
    if (rpcError && !/already linked/i.test(rpcError.message)) {
      return rpcError.message;
    }

    // Verify the promotion actually stuck. Reads the profile directly instead
    // of relying on state that hasn't propagated yet.
    const { data: verify, error: verifyErr } = await supabase
      .from('profiles')
      .select('role, org_id')
      .eq('id', session.user.id)
      .maybeSingle();

    if (verifyErr) {
      return `Organization was created but reading the profile failed: ${verifyErr.message}`;
    }
    if (!verify) {
      return (
        'Organization was created but no profile row exists for your account. ' +
        'Run supabase/schema.sql once in the Supabase SQL editor and refresh.'
      );
    }
    if (verify.role !== 'admin' || !verify.org_id) {
      return (
        `Organization was created but the promotion did not stick ` +
        `(role=${verify.role}, org_id=${verify.org_id ?? 'null'}). ` +
        'Make sure you ran the LATEST supabase/schema_updates.sql, then reload.'
      );
    }

    await refresh();
    return null;
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setInfo(null);
    setSubmitting(true);

    // Path A — user is already signed in and just needs to create the org.
    if (alreadySignedIn) {
      const err = await callRegisterOrgRpc();
      setSubmitting(false);
      if (err) {
        setError(
          err.includes('does not exist')
            ? `${err}. Run supabase/schema_updates.sql once in the Supabase SQL editor.`
            : err,
        );
        return;
      }
      nav('/dashboard', { replace: true });
      return;
    }

    // Path B — brand new user: sign up first, then create org.
    if (form.password !== form.confirm) {
      setSubmitting(false);
      setError('Passwords do not match.');
      return;
    }
    if (form.password.length < 8) {
      setSubmitting(false);
      setError('Password must be at least 8 characters.');
      return;
    }

    const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
      email: form.email.trim().toLowerCase(),
      password: form.password,
      options: {
        data: { name: form.name.trim(), phone: form.phone.trim() },
      },
    });
    if (signUpError) {
      setSubmitting(false);
      setError(signUpError.message);
      return;
    }

    // If email confirmation is ON in Supabase, no session yet.
    if (!signUpData.session) {
      setSubmitting(false);
      setInfo(
        'Account created. Please confirm your email, then sign in — you will ' +
          'come back here automatically to finish organization setup.',
      );
      return;
    }

    // Session is live → create the org and promote to admin.
    const err = await callRegisterOrgRpc();
    setSubmitting(false);
    if (err) {
      setError(
        err.includes('does not exist')
          ? `${err}. Run supabase/schema_updates.sql once in the Supabase SQL editor.`
          : `Signed up, but organization setup failed: ${err}`,
      );
      return;
    }
    nav('/dashboard', { replace: true });
  }

  if (authLoading) {
    return <div className="fullscreen-center">Loading…</div>;
  }

  return (
    <div className="auth-page">
      <div className="auth-shell">
        <aside className="auth-hero">
          <div>
            <div className="hero-badge">CP</div>
            <h1 className="hero-title">Carpool for your company</h1>
            <p className="hero-lead">
              Cut commute cost, reduce your CO₂ footprint, and give employees a
              friendlier way to get to work.
            </p>
            <ul className="hero-points">
              <li>Set fuel and per-km rates once</li>
              <li>Employees register and pick your org in seconds</li>
              <li>Live dashboard of trips, savings and participation</li>
            </ul>
          </div>
          <p className="hero-fine">Employees use the mobile app · admins use this dashboard</p>
        </aside>

        <main className="auth-card auth-card-wide">
          <header className="auth-card-header">
            <h1>
              {alreadySignedIn ? 'Finish organization setup' : 'Register your organization'}
            </h1>
            <p className="muted">
              {alreadySignedIn
                ? 'Almost done — tell us about your company and you become the first administrator.'
                : "Create your company's carpooling program. Employees can then sign up in the mobile app and choose your organization."}
            </p>
          </header>

          {!alreadySignedIn && (
            <div className="tip">
              <strong>Tip</strong> — to skip email verification during setup, turn OFF
              <em> Confirm email </em>in Supabase&nbsp;Dashboard → Authentication →
              Providers → Email.
            </div>
          )}

          <form onSubmit={onSubmit} className="auth-form">
            <section>
              <h2>Organization</h2>

              <label>
                Organization name
                <input
                  type="text"
                  required
                  value={form.orgName}
                  onChange={(e) => set('orgName', e.target.value)}
                />
              </label>

              <div className="row-2">
                <label>
                  Industry
                  <input
                    type="text"
                    value={form.industry}
                    onChange={(e) => set('industry', e.target.value)}
                    placeholder="e.g. Software"
                  />
                </label>
                <label>
                  Administrator contact
                  <input
                    type="text"
                    value={form.adminContact}
                    onChange={(e) => set('adminContact', e.target.value)}
                    placeholder="Phone or alt email"
                  />
                </label>
              </div>

              <label>
                Address
                <textarea
                  rows={2}
                  value={form.address}
                  onChange={(e) => set('address', e.target.value)}
                />
              </label>
            </section>

            {!alreadySignedIn && (
              <section>
                <h2>Administrator account</h2>

                <div className="row-2">
                  <label>
                    Your name
                    <input
                      type="text"
                      required
                      value={form.name}
                      onChange={(e) => set('name', e.target.value)}
                      autoComplete="name"
                    />
                  </label>
                  <label>
                    Phone
                    <input
                      type="tel"
                      value={form.phone}
                      onChange={(e) => set('phone', e.target.value)}
                      autoComplete="tel"
                    />
                  </label>
                </div>

                <label>
                  Email
                  <input
                    type="email"
                    required
                    value={form.email}
                    onChange={(e) => set('email', e.target.value)}
                    autoComplete="email"
                  />
                </label>

                <div className="row-2">
                  <label>
                    Password
                    <input
                      type="password"
                      required
                      minLength={8}
                      value={form.password}
                      onChange={(e) => set('password', e.target.value)}
                      autoComplete="new-password"
                    />
                  </label>
                  <label>
                    Confirm password
                    <input
                      type="password"
                      required
                      minLength={8}
                      value={form.confirm}
                      onChange={(e) => set('confirm', e.target.value)}
                      autoComplete="new-password"
                    />
                  </label>
                </div>
              </section>
            )}

            {error && <div className="error">{error}</div>}
            {info && <div className="success">{info}</div>}

            <div className="form-actions">
              <button className="btn btn-primary btn-lg" type="submit" disabled={submitting}>
                {submitting
                  ? 'Working…'
                  : alreadySignedIn
                    ? 'Create organization'
                    : 'Register organization'}
              </button>
              {alreadySignedIn && (
                <button
                  type="button"
                  className="btn btn-ghost"
                  onClick={() => {
                    void supabase.auth.signOut();
                  }}
                >
                  Sign out
                </button>
              )}
            </div>
          </form>

          <p className="muted small auth-footer">
            {alreadySignedIn ? (
              <>Signed in as <strong>{session?.user.email}</strong></>
            ) : (
              <>Already have an admin account? <Link to="/login">Sign in</Link></>
            )}
          </p>
        </main>
      </div>
    </div>
  );
}
