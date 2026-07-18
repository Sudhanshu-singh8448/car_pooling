import { useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';

export interface AdminProfile {
  id: string;
  email: string;
  name: string;
  role: 'employee' | 'admin';
  org_id: string | null;
}

interface AuthState {
  loading: boolean;
  session: Session | null;
  profile: AdminProfile | null;
  isAdmin: boolean;
  error: string | null;
}

export function useAuth(): AuthState & { refresh: () => Promise<void> } {
  const [state, setState] = useState<AuthState>({
    loading: true,
    session: null,
    profile: null,
    isAdmin: false,
    error: null,
  });

  async function loadProfile(session: Session | null) {
    if (!session) {
      setState({ loading: false, session: null, profile: null, isAdmin: false, error: null });
      return;
    }
    const { data, error } = await supabase
      .from('profiles')
      .select('id, email, name, role, org_id')
      .eq('id', session.user.id)
      .maybeSingle();

    if (error) {
      setState({
        loading: false,
        session,
        profile: null,
        isAdmin: false,
        error: error.message,
      });
      return;
    }

    const profile = data as AdminProfile | null;
    setState({
      loading: false,
      session,
      profile,
      isAdmin: profile?.role === 'admin',
      error: null,
    });
  }

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      void loadProfile(data.session);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_ev, session) => {
      void loadProfile(session);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  return {
    ...state,
    refresh: async () => {
      const { data } = await supabase.auth.getSession();
      await loadProfile(data.session);
    },
  };
}
