import { useEffect } from 'react';
import { create } from 'zustand';
import { api } from '../api/client';
import type { SdrInfo } from '../api/types';

interface SdrState {
  sdrs: SdrInfo[];
  loading: boolean;
  error: string | null;
  fetch: () => Promise<void>;
}

export const useSdrStore = create<SdrState>((set) => ({
  sdrs: [],
  loading: false,
  error: null,
  fetch: async () => {
    set({ loading: true, error: null });
    try {
      const data = await api.sdrs();
      set({ sdrs: data.sdrs, loading: false });
    } catch (e) {
      set({ error: (e as Error).message, loading: false });
    }
  },
}));

const POLL_INTERVAL = 60_000;

export function useSdrs() {
  const store = useSdrStore();

  useEffect(() => {
    store.fetch();
    const id = setInterval(() => store.fetch(), POLL_INTERVAL);
    return () => clearInterval(id);
    // Only run on mount/unmount
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return store;
}
