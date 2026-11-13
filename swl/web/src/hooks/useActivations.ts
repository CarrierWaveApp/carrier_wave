import { useEffect, useMemo } from 'react';
import { create } from 'zustand';
import { api } from '../api/client';
import { fetchPotaSpots, fetchRbnSpots } from '../api/spots';
import type {
  RecordingRow,
  TranscriptionResponse,
  PotaSpot,
  RbnSpot,
} from '../api/types';
import { frequencyToBand } from '../utils/bands';

// ---------------------------------------------------------------------------
// Activation model (client-side only, does not exist in backend)
// ---------------------------------------------------------------------------

export interface Activation {
  id: string;
  callsign: string;
  frequency: number;
  band: string;
  mode: string;
  parkRef?: string;
  parkName?: string;
  isLive: boolean;
  recordings: RecordingRow[];
  combinedRecordingId?: string;
  transcription?: TranscriptionResponse;
  spot?: PotaSpot;
  sdrCount: number;
  wpm?: number;
  startedAt: string;
  lastActivity: string;
}

// ---------------------------------------------------------------------------
// Callsign extraction from transcript text
// ---------------------------------------------------------------------------

const CALLSIGN_RE = /\b([A-Z]{1,2}\d[A-Z0-9]*[A-Z])\b/;

function extractCallsign(text: string): string | undefined {
  const m = text.match(CALLSIGN_RE);
  return m?.[1];
}

// ---------------------------------------------------------------------------
// Aggregation: recordings → activations
// ---------------------------------------------------------------------------

function groupRecordingsIntoActivations(
  recordings: RecordingRow[],
  transcriptions: TranscriptionResponse[],
  potaSpots: PotaSpot[],
): Activation[] {
  // Index transcriptions by recording_id
  const txMap = new Map<string, TranscriptionResponse>();
  for (const tx of transcriptions) {
    if (tx.status === 'completed' && tx.text.length > 0) {
      txMap.set(tx.recording_id, tx);
    }
  }

  // Sort recordings by frequency then start time
  const sorted = [...recordings]
    .filter((r) => r.mode.toLowerCase() === 'cw')
    .sort((a, b) => a.frequency - b.frequency || a.started_at.localeCompare(b.started_at));

  // Group by (frequency ±500Hz, overlapping time within 5 min)
  const groups: RecordingRow[][] = [];
  for (const rec of sorted) {
    let placed = false;
    for (const group of groups) {
      const ref = group[0]!;
      const freqClose = Math.abs(rec.frequency - ref.frequency) <= 500;
      const timeClose = group.some((g) => {
        const gEnd = g.stopped_at ?? g.started_at;
        const recStart = rec.started_at;
        const diffMs =
          Math.abs(new Date(recStart).getTime() - new Date(gEnd).getTime());
        return diffMs <= 5 * 60 * 1000;
      });
      if (freqClose && timeClose) {
        group.push(rec);
        placed = true;
        break;
      }
    }
    if (!placed) {
      groups.push([rec]);
    }
  }

  // Build activations from groups
  return groups.map((recs) => {
    const first = recs[0]!;
    const isLive = recs.some((r) => r.status === 'recording');
    const combined = recs.find((r) => r.status === 'combined');

    // Find transcription (prefer combined recording's, fall back to any)
    const tx =
      (combined ? txMap.get(combined.id) : undefined) ??
      recs.map((r) => txMap.get(r.id)).find(Boolean);

    // Extract callsign from transcript
    const callsign = tx ? extractCallsign(tx.text) : undefined;

    // Match POTA spot by callsign + frequency (±1 kHz)
    const spot = callsign
      ? potaSpots.find(
          (s) =>
            s.activator === callsign &&
            Math.abs(parseFloat(s.frequency) * 1000 - first.frequency) <= 1000,
        )
      : undefined;

    // Unique SDR count
    const sdrIds = new Set(recs.map((r) => r.sdr_id));

    // Time range
    const starts = recs.map((r) => r.started_at);
    const ends = recs.map((r) => r.stopped_at ?? r.started_at);
    const startedAt = starts.sort()[0]!;
    const lastActivity = ends.sort().reverse()[0]!;

    return {
      id: first.id,
      callsign: callsign ?? spot?.activator ?? 'Unknown',
      frequency: first.frequency,
      band: frequencyToBand(first.frequency),
      mode: first.mode.toUpperCase(),
      parkRef: spot?.reference,
      parkName: spot?.parkName ?? undefined,
      isLive,
      recordings: recs,
      combinedRecordingId: combined?.id,
      transcription: tx,
      spot,
      sdrCount: sdrIds.size,
      wpm: tx?.wpm_estimate ?? undefined,
      startedAt,
      lastActivity,
    };
  });
}

// ---------------------------------------------------------------------------
// Zustand store
// ---------------------------------------------------------------------------

interface ActivationState {
  recordings: RecordingRow[];
  transcriptions: TranscriptionResponse[];
  potaSpots: PotaSpot[];
  rbnSpots: RbnSpot[];
  loading: boolean;
  error: string | null;

  // Favorites (persisted to localStorage)
  favoriteCallsigns: string[];

  // Band filter
  bandFilters: string[];

  // Actions
  fetchRecordings: () => Promise<void>;
  fetchSpots: () => Promise<void>;
  toggleFavorite: (callsign: string) => void;
  toggleBandFilter: (band: string) => void;
}

function loadFavorites(): string[] {
  try {
    const stored = localStorage.getItem('cw-swl-favorites');
    return stored ? (JSON.parse(stored) as string[]) : [];
  } catch {
    return [];
  }
}

function saveFavorites(favs: string[]) {
  localStorage.setItem('cw-swl-favorites', JSON.stringify(favs));
}

export const useActivationStore = create<ActivationState>((set, get) => ({
  recordings: [],
  transcriptions: [],
  potaSpots: [],
  rbnSpots: [],
  loading: false,
  error: null,
  favoriteCallsigns: loadFavorites(),
  bandFilters: [],

  fetchRecordings: async () => {
    set({ loading: true, error: null });
    try {
      const [recordings, transcriptions] = await Promise.all([
        api.recordings(),
        api.transcriptions(),
      ]);
      set({ recordings, transcriptions, loading: false });
    } catch (e) {
      set({ error: (e as Error).message, loading: false });
    }
  },

  fetchSpots: async () => {
    const [potaSpots, rbnSpots] = await Promise.all([
      fetchPotaSpots(),
      fetchRbnSpots(),
    ]);
    set({ potaSpots, rbnSpots });
  },

  toggleFavorite: (callsign: string) => {
    const current = get().favoriteCallsigns;
    const next = current.includes(callsign)
      ? current.filter((c) => c !== callsign)
      : [...current, callsign];
    saveFavorites(next);
    set({ favoriteCallsigns: next });
  },

  toggleBandFilter: (band: string) => {
    const current = get().bandFilters;
    const next = current.includes(band)
      ? current.filter((b) => b !== band)
      : [...current, band];
    set({ bandFilters: next });
  },
}));

// ---------------------------------------------------------------------------
// Hook with polling + derived activations
// ---------------------------------------------------------------------------

const RECORDING_POLL = 30_000;
const SPOT_POLL = 60_000;

export function useActivations() {
  const store = useActivationStore();

  useEffect(() => {
    store.fetchRecordings();
    store.fetchSpots();
    const recInterval = setInterval(() => store.fetchRecordings(), RECORDING_POLL);
    const spotInterval = setInterval(() => store.fetchSpots(), SPOT_POLL);
    return () => {
      clearInterval(recInterval);
      clearInterval(spotInterval);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const activations = useMemo(
    () =>
      groupRecordingsIntoActivations(
        store.recordings,
        store.transcriptions,
        store.potaSpots,
      ),
    [store.recordings, store.transcriptions, store.potaSpots],
  );

  // Apply band filters
  const filtered = useMemo(() => {
    if (store.bandFilters.length === 0) return activations;
    return activations.filter((a) => store.bandFilters.includes(a.band));
  }, [activations, store.bandFilters]);

  return {
    activations: filtered,
    allActivations: activations,
    loading: store.loading,
    error: store.error,
    favoriteCallsigns: store.favoriteCallsigns,
    toggleFavorite: store.toggleFavorite,
    bandFilters: store.bandFilters,
    toggleBandFilter: store.toggleBandFilter,
    potaSpots: store.potaSpots,
    rbnSpots: store.rbnSpots,
  };
}
