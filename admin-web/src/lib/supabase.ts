import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

if (!url || !key) {
  // Fail loudly in the browser console — this is the #1 setup mistake.
  // eslint-disable-next-line no-console
  console.error(
    'Missing Supabase env vars. Copy admin-web/.env.example to admin-web/.env ' +
      'and set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.',
  );
}

export const supabase = createClient(url ?? '', key ?? '', {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
});
