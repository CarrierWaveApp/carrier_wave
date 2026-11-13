// App-wide session state. Holds three things across routes:
//   - whether we have API tokens (login),
//   - the in-memory data key (null until the passphrase unlocks it),
//   - the decrypted QSOs once loaded.
//
// The data key and QSOs live ONLY in memory — never storage — so a tab reload
// requires re-entering the passphrase.

import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';
import { clearTokens, isLoggedIn } from '../auth/session';
import type { SyncQso } from '../sync/types';

interface AppState {
  loggedIn: boolean;
  setLoggedIn: (v: boolean) => void;
  dataKey: Uint8Array | null;
  setDataKey: (k: Uint8Array | null) => void;
  qsos: SyncQso[] | null;
  setQsos: (q: SyncQso[] | null) => void;
  logout: () => void;
}

const Ctx = createContext<AppState | null>(null);

export function AppStateProvider({ children }: { children: ReactNode }) {
  const [loggedIn, setLoggedIn] = useState(isLoggedIn());
  const [dataKey, setDataKey] = useState<Uint8Array | null>(null);
  const [qsos, setQsos] = useState<SyncQso[] | null>(null);

  const value = useMemo<AppState>(
    () => ({
      loggedIn,
      setLoggedIn,
      dataKey,
      setDataKey,
      qsos,
      setQsos,
      logout: () => {
        clearTokens();
        setDataKey(null);
        setQsos(null);
        setLoggedIn(false);
      },
    }),
    [loggedIn, dataKey, qsos],
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useAppState(): AppState {
  const v = useContext(Ctx);
  if (!v) throw new Error('useAppState must be used within AppStateProvider');
  return v;
}
