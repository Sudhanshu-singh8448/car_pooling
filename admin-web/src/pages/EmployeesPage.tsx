import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../lib/supabase';

interface Employee {
  id: string;
  email: string;
  name: string | null;
  phone: string | null;
  role: 'employee' | 'admin';
  platform_access: 'granted' | 'revoked';
  created_at: string;
}

export default function EmployeesPage() {
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [savingId, setSavingId] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    const { data, error: err } = await supabase
      .from('profiles')
      .select('id, email, name, phone, role, platform_access, created_at')
      .order('created_at', { ascending: false });
    if (err) setError(err.message);
    else setEmployees((data ?? []) as Employee[]);
    setLoading(false);
  }

  useEffect(() => {
    void load();
  }, []);

  async function toggleAccess(emp: Employee) {
    setSavingId(emp.id);
    const next = emp.platform_access === 'granted' ? 'revoked' : 'granted';
    const { error: err } = await supabase
      .from('profiles')
      .update({ platform_access: next })
      .eq('id', emp.id);
    setSavingId(null);
    if (err) {
      alert(`Failed: ${err.message}`);
      return;
    }
    setEmployees((prev) =>
      prev.map((e) => (e.id === emp.id ? { ...e, platform_access: next } : e)),
    );
  }

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return employees;
    return employees.filter(
      (e) =>
        (e.name || '').toLowerCase().includes(q) ||
        (e.email || '').toLowerCase().includes(q) ||
        (e.phone || '').toLowerCase().includes(q),
    );
  }, [employees, query]);

  return (
    <div className="page">
      <header className="page-header">
        <div>
          <h1>Employees</h1>
          <p className="muted">
            Grant or revoke platform access. Revoked employees will be signed out of the
            mobile app on their next request.
          </p>
        </div>
        <input
          type="search"
          placeholder="Search by name, email or phone…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="search-input"
        />
      </header>

      {loading && <p>Loading…</p>}
      {error && <div className="error">{error}</div>}

      {!loading && !error && (
        <div className="panel table-panel">
          <table>
            <thead>
              <tr>
                <th>Name</th>
                <th>Email</th>
                <th>Phone</th>
                <th>Role</th>
                <th>Access</th>
                <th>Joined</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {filtered.map((e) => (
                <tr key={e.id}>
                  <td>{e.name || <span className="muted">—</span>}</td>
                  <td>{e.email}</td>
                  <td>{e.phone || <span className="muted">—</span>}</td>
                  <td>
                    <span className={`chip chip-${e.role}`}>{e.role}</span>
                  </td>
                  <td>
                    <span
                      className={`chip ${
                        e.platform_access === 'granted' ? 'chip-success' : 'chip-danger'
                      }`}
                    >
                      {e.platform_access}
                    </span>
                  </td>
                  <td>{new Date(e.created_at).toLocaleDateString()}</td>
                  <td>
                    {e.role !== 'admin' && (
                      <button
                        className="btn btn-ghost"
                        disabled={savingId === e.id}
                        onClick={() => toggleAccess(e)}
                      >
                        {savingId === e.id
                          ? 'Saving…'
                          : e.platform_access === 'granted'
                            ? 'Revoke access'
                            : 'Grant access'}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={7} className="muted center">
                    No employees found.
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
