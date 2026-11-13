import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { getKeyBlob } from '../sync/syncClient';
import { openEscrow } from '../wasm';
import { useAppState } from '../state/AppState';
import { Wordmark } from '../components/Brand';

// Passphrase gate. Fetches the escrow envelope and unwraps the data key in the
// browser (WASM). The passphrase and key never leave this tab's memory.
export default function UnlockPage() {
  const nav = useNavigate();
  const { setDataKey, logout } = useAppState();
  const [passphrase, setPassphrase] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const unlock = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      const blob = await getKeyBlob();
      const key = await openEscrow(
        passphrase,
        JSON.stringify(blob.kdfParams),
        blob.wrappedKey,
      );
      setDataKey(key);
      nav('/', { replace: true });
    } catch (err) {
      // open_escrow throws "wrong passphrase" on a bad KEK; surface verbatim.
      setError(err instanceof Error ? err.message : 'Unlock failed');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-6">
      <Wordmark size="text-lg" />
      <h1 className="mt-6 text-xl font-semibold text-cw-white">Enter sync passphrase</h1>
      <p className="mt-1.5 text-sm text-cw-dim">
        The passphrase you set when enabling sync. It decrypts your logs locally —
        it never leaves this browser.
      </p>

      {error && (
        <div className="mt-4 rounded-lg border border-cw-red/40 bg-cw-red/10 p-3 text-sm text-cw-red">
          {error}
        </div>
      )}

      <form onSubmit={unlock} className="mt-6 space-y-4">
        <input
          type="password"
          value={passphrase}
          onChange={(e) => setPassphrase(e.target.value)}
          required
          autoFocus
          className="w-full rounded-lg border border-cw-border2 bg-cw-surface px-3 py-2.5 text-cw-white placeholder:text-cw-xdim focus:border-cw-blue focus:outline-none focus:ring-1 focus:ring-cw-blue"
          placeholder="Sync passphrase"
        />
        <button
          type="submit"
          disabled={busy || !passphrase}
          className="w-full rounded-lg bg-cw-blue px-4 py-2.5 font-medium text-cw-bg transition-colors hover:bg-cw-blue2 disabled:opacity-40"
        >
          {busy ? 'Unlocking…' : 'Unlock logbook'}
        </button>
        <button
          type="button"
          onClick={() => {
            logout();
            nav('/login', { replace: true });
          }}
          className="w-full text-sm text-cw-dim transition-colors hover:text-cw-text"
        >
          Sign out
        </button>
      </form>
    </div>
  );
}
