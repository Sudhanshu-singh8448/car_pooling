import { FormEvent, useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../hooks/useAuth';

export default function LoginPage() {
  const nav = useNavigate();
  const { session, isAdmin, loading, profile } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hint, setHint] = useState<string | null>(null);

  useEffect(() => {
    if (loading || !session) return;
    if (isAdmin && profile?.org_id) {
      nav('/dashboard', { replace: true });
    } else if (session && !isAdmin) {
      // Signed in but not admin — send them to /register so they can either
      // finish org setup, or (for a real non-admin employee) sign out.
      nav('/register', { replace: true });
    }
  }, [loading, session, isAdmin, profile?.org_id, nav]);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    setHint(null);
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password,
    });
    setSubmitting(false);
    if (signInError) {
      setError(signInError.message);
      const msg = signInError.message.toLowerCase();
      if (msg.includes('email not confirmed') || msg.includes('not confirmed')) {
        setHint(
          'Your email is not confirmed yet. Either click the link in the verification ' +
            'email, or disable "Confirm email" in Supabase Dashboard → Authentication ' +
            '→ Providers → Email, then try again.',
        );
      } else if (msg.includes('invalid login') || msg.includes('invalid credentials')) {
        setHint(
          "Double-check the email and password. If you just registered, make sure you're " +
            'using the same email — and if email confirmation is enabled, confirm first.',
        );
      }
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-shell">
        <aside className="auth-hero">
          <div>
            <div className="hero-badge">CP</div>
            <h1 className="hero-title">Welcome back</h1>
            <p className="hero-lead">
              Sign in to manage your organization's carpooling program.
            </p>
            <ul className="hero-points">
              <li>Track trips, distance and savings in real time</li>
              <li>Grant or revoke employee access instantly</li>
              <li>Adjust fuel and per-km pricing anytime</li>
            </ul>
          </div>
          <p className="hero-fine">Admin only · employees use the mobile app</p>
        </aside>

        <main className="auth-card">
          <header className="auth-card-header">
            <h1>Sign in</h1>
            <p className="muted">Use your administrator credentials.</p>
          </header>

          <form onSubmit={onSubmit} className="auth-form">
            <label>
              Email
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
              />
            </label>
            <label>
              Password
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="current-password"
              />
            </label>

            {error && <div className="error">{error}</div>}
            {hint && <div className="tip">{hint}</div>}

            <button
              className="btn btn-primary btn-lg"
              type="submit"
              disabled={submitting}
            >
              {submitting ? 'Signing in…' : 'Sign in'}
            </button>
          </form>

          <p className="muted small auth-footer">
            New here? <Link to="/register">Register your organization</Link>
          </p>
        </main>
      </div>
    </div>
  );
}
