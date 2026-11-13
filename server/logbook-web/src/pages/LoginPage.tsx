import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { pollOnce, startVerification, type PendingVerification } from '../auth/authClient';
import { useAppState } from '../state/AppState';
import { Wordmark } from '../components/Brand';

// Magic-link login: request a link, then poll until the user clicks it.
export default function LoginPage() {
  const nav = useNavigate();
  const { setLoggedIn } = useAppState();
  const [callsign, setCallsign] = useState('');
  const [email, setEmail] = useState('');
  const [pending, setPending] = useState<PendingVerification | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const pollTimer = useRef<number | null>(null);

  // Poll verify/poll every 3s while a verification is outstanding.
  useEffect(() => {
    if (!pending) return;
    const tick = async () => {
      try {
        const result = await pollOnce(pending);
        if (result === 'authenticated') {
          setLoggedIn(true);
          nav('/unlock', { replace: true });
        }
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Login failed');
        setPending(null);
      }
    };
    pollTimer.current = window.setInterval(tick, 3000);
    return () => {
      if (pollTimer.current) window.clearInterval(pollTimer.current);
    };
  }, [pending, nav, setLoggedIn]);

  const start = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      setPending(await startVerification(callsign, email || undefined));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not start login');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-6">
      <Wordmark size="text-lg" />
      <p className="mt-5 text-sm text-cw-dim">
        Sign in to view your synced logs. Everything is decrypted in your browser —
        the server never sees your QSOs.
      </p>

      {error && (
        <div className="mt-4 rounded-lg border border-cw-red/40 bg-cw-red/10 p-3 text-sm text-cw-red">
          {error}
        </div>
      )}

      {pending ? (
        <div className="mt-6 rounded-xl border border-cw-border2 bg-cw-surface p-5 text-sm text-cw-text">
          <p className="font-semibold text-cw-white">Check your email</p>
          <p className="mt-1.5 text-cw-dim">
            We sent a sign-in link for{' '}
            <span className="font-mono text-cw-text">{callsign.toUpperCase()}</span>. Open it
            on any device — this page will continue automatically.
          </p>
          <div className="mt-4 flex items-center gap-2 text-cw-dim">
            <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-cw-blue" />
            <span className="cw-eyebrow text-[0.62rem]">Waiting for the link</span>
          </div>
        </div>
      ) : (
        <form onSubmit={start} className="mt-6 space-y-4">
          <div>
            <label className="cw-eyebrow text-[0.62rem]">Callsign</label>
            <input
              value={callsign}
              onChange={(e) => setCallsign(e.target.value)}
              required
              autoCapitalize="characters"
              className="mt-1.5 w-full rounded-lg border border-cw-border2 bg-cw-surface px-3 py-2.5 font-mono uppercase tracking-wide text-cw-white placeholder:text-cw-xdim focus:border-cw-blue focus:outline-none focus:ring-1 focus:ring-cw-blue"
              placeholder="W6JY"
            />
          </div>
          <div>
            <label className="cw-eyebrow text-[0.62rem]">
              Email <span className="normal-case tracking-normal text-cw-xdim">· only if not on file</span>
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="mt-1.5 w-full rounded-lg border border-cw-border2 bg-cw-surface px-3 py-2.5 text-cw-white placeholder:text-cw-xdim focus:border-cw-blue focus:outline-none focus:ring-1 focus:ring-cw-blue"
              placeholder="you@example.com"
            />
          </div>
          <button
            type="submit"
            disabled={busy || !callsign}
            className="w-full rounded-lg bg-cw-blue px-4 py-2.5 font-medium text-cw-bg transition-colors hover:bg-cw-blue2 disabled:opacity-40"
          >
            {busy ? 'Sending…' : 'Send sign-in link'}
          </button>
        </form>
      )}
    </div>
  );
}
