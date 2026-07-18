import { Navigate } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import { supabase } from '../lib/supabase';

export default function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { loading, session, isAdmin, profile } = useAuth();

  if (loading) {
    return <div className="fullscreen-center">Loading…</div>;
  }

  if (!session) {
    return <Navigate to="/login" replace />;
  }

  // Signed in but not admin yet AND no org linked — they signed up but never
  // finished registering their organization. Send them to finish it.
  if (!isAdmin && !profile?.org_id) {
    return <Navigate to="/register" replace />;
  }

  if (!isAdmin) {
    return (
      <div className="fullscreen-center forbidden">
        <div>
          <h1>Access denied</h1>
          <p>This dashboard is restricted to organization administrators.</p>
          <button
            className="btn btn-primary"
            onClick={() => {
              void supabase.auth.signOut();
            }}
          >
            Sign out
          </button>
        </div>
      </div>
    );
  }

  return <>{children}</>;
}
