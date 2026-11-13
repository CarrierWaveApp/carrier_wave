import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { listSessions, logoutAllSessions, type Session } from '../auth/account';
import { useAppState } from '../state/AppState';

// Account pane: a modal over the logbook that lists the account's active
// sessions and lets the user revoke every one of them ("sign out everywhere").
// Revoking bumps the server-side kill epoch, so this tab's tokens die too — we
// clear local state and bounce to login on success.
export default function AccountPane({ onClose }: { onClose: () => void }) {
  const nav = useNavigate();
  const { logout } = useAppState();

  const [sessions, setSessions] = useState<Session[] | null>(null);
  const [loadError, setLoadError] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState('');

  // Load the session list once when the pane opens.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const list = await listSessions();
        if (!cancelled) setSessions(list);
      } catch (e) {
        if (!cancelled) setLoadError(e instanceof Error ? e.message : 'Could not load sessions');
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Close on Escape for keyboard users.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const signOutEverywhere = async () => {
    setActionError('');
    setBusy(true);
    try {
      await logoutAllSessions();
      logout(); // drop this tab's tokens + in-memory key
      nav('/login', { replace: true });
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Sign out everywhere failed');
      setBusy(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Account"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md rounded-2xl border border-cw-border bg-cw-bg p-6 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold text-cw-white">Account</h2>
          <button
            onClick={onClose}
            aria-label="Close"
            className="rounded-lg px-2 py-1 text-cw-dim transition-colors hover:text-cw-text"
          >
            ✕
          </button>
        </div>

        <div className="mt-5">
          <h3 className="cw-eyebrow text-[0.6rem]">Active sessions</h3>
          {loadError ? (
            <p className="mt-2 rounded-lg border border-cw-red/40 bg-cw-red/10 p-3 text-sm text-cw-red">
              {loadError}
            </p>
          ) : sessions === null ? (
            <p className="mt-2 text-sm text-cw-dim">Loading sessions…</p>
          ) : sessions.length === 0 ? (
            <p className="mt-2 text-sm text-cw-dim">No active sessions.</p>
          ) : (
            <ul className="mt-2 divide-y divide-cw-border/60 overflow-hidden rounded-xl border border-cw-border">
              {sessions.map((s) => (
                <li key={s.id} className="flex items-center justify-between gap-3 px-3 py-2.5">
                  <div className="min-w-0">
                    <div className="truncate text-sm font-medium text-cw-white">
                      {s.deviceName ?? 'Unknown device'}
                    </div>
                    <div className="text-xs text-cw-dim">
                      {s.platform ? `${s.platform} · ` : ''}last active {fmtRelative(s.lastSeenAt)}
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="mt-6 border-t border-cw-border pt-5">
          <p className="text-sm text-cw-dim">
            Sign out of every device and browser signed in to this account,
            including this one. You&apos;ll need to sign in again everywhere.
          </p>

          {actionError && (
            <p className="mt-3 rounded-lg border border-cw-red/40 bg-cw-red/10 p-3 text-sm text-cw-red">
              {actionError}
            </p>
          )}

          {confirming ? (
            <div className="mt-4 flex gap-2">
              <button
                onClick={signOutEverywhere}
                disabled={busy}
                className="flex-1 rounded-lg bg-cw-red px-4 py-2.5 text-sm font-medium text-cw-white transition-colors hover:bg-cw-red/80 disabled:opacity-40"
              >
                {busy ? 'Signing out…' : 'Yes, sign out everywhere'}
              </button>
              <button
                onClick={() => setConfirming(false)}
                disabled={busy}
                className="rounded-lg border border-cw-border2 bg-cw-surface px-4 py-2.5 text-sm font-medium text-cw-text transition-colors hover:border-cw-dim disabled:opacity-40"
              >
                Cancel
              </button>
            </div>
          ) : (
            <button
              onClick={() => setConfirming(true)}
              className="mt-4 w-full rounded-lg border border-cw-red/50 bg-cw-red/10 px-4 py-2.5 text-sm font-medium text-cw-red transition-colors hover:bg-cw-red/20"
            >
              Sign out everywhere
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// Compact "3h ago" / "2d ago" relative time from an ISO timestamp.
function fmtRelative(iso: string): string {
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return 'unknown';
  const secs = Math.max(0, Math.floor((Date.now() - then) / 1000));
  if (secs < 60) return 'just now';
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}
