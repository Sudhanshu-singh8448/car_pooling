import { NavLink, Outlet } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import { supabase } from '../lib/supabase';

const NAV = [
  { to: '/dashboard', label: 'Dashboard' },
  { to: '/employees', label: 'Employees' },
  { to: '/vehicles', label: 'Vehicles' },
  { to: '/rides', label: 'Rides' },
  { to: '/pricing', label: 'Pricing' },
  { to: '/organization', label: 'Organization' },
];

export default function Layout() {
  const { profile } = useAuth();
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-logo">CP</div>
          <div>
            <div className="brand-title">Carpool Admin</div>
            <div className="brand-subtitle">Enterprise Platform</div>
          </div>
        </div>
        <nav>
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) => (isActive ? 'nav-item active' : 'nav-item')}
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-footer">
          <div className="user-name">{profile?.name || profile?.email}</div>
          <div className="user-role">Administrator</div>
          <button
            className="btn white"
            style={{ opacity: 100 }}
            onClick={() => {
              void supabase.auth.signOut();
            }}
          >
            Sign out
          </button>
        </div>
      </aside>
      <main className="main">
        <Outlet />
      </main>
    </div>
  );
}
