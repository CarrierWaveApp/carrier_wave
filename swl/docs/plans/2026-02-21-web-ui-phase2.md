# Web UI Phase 2: Activation Cards + Spot Integration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Populate the "On the Air" tab with activation cards built from recordings, transcriptions, and POTA/RBN spot data, with band filtering and localStorage favorites.

**Architecture:** Client-side activation aggregation — the backend has no "Activation" model. The UI fetches recordings + transcriptions from our API, fetches POTA/RBN spots directly from public APIs, groups recordings by frequency/time proximity, extracts callsigns from transcripts, and matches against spots for park enrichment. Zustand stores manage data + polling. Band filtering and favorites are purely client-side.

**Tech Stack:** React 18, TypeScript, Zustand, existing API client pattern from Phase 1.

**Design Reference:** `docs/plans/2026-02-21-web-ui-design.md` — component specs, activation aggregation logic, polling strategy, and state management.

**Existing code patterns:** Phase 1 established inline styles using `tokens`, function components with typed props, Zustand stores with `create<T>()`, and polling via `useEffect` + `setInterval`. Follow the same patterns.

---

## Task 1: Recording + Transcription API types

**Files:**
- Modify: `web/src/api/types.ts`
- Modify: `web/src/api/client.ts`

**Step 1: Add types to `web/src/api/types.ts`**

Append these interfaces (matching the Rust `RecordingRow`, `TranscriptionResponse`, and `SegmentRow` shapes):

```ts
export interface RecordingRow {
  id: string;
  capture_id: string | null;
  sdr_id: string;
  frequency: number;
  bandwidth: number;
  mode: string;
  status: string;           // "recording" | "stopped" | "combined"
  started_at: string;
  stopped_at: string | null;
  retention_days: number;
  created_at: string;
}

export interface TranscriptionResponse {
  id: string;
  recording_id: string;
  text: string;
  status: string;           // "completed" | "failed"
  wpm_estimate: number | null;
  char_count: number;
  error_message: string | null;
}

export interface SegmentRow {
  id: string;
  recording_id: string;
  segment_number: number;
  file_path: string;
  duration_secs: number;
  file_size_bytes: number;
  sample_rate: number;
  started_at: string;
  ended_at: string;
  created_at: string;
}

export interface RecordingResponse {
  id: string;
  capture_id: string | null;
  sdr_id: string;
  frequency: number;
  bandwidth: number;
  mode: string;
  status: string;
  started_at: string;
  stopped_at: string | null;
  retention_days: number;
  created_at: string;
  segments: SegmentRow[];
}
```

**Step 2: Add API methods to `web/src/api/client.ts`**

```ts
import type {
  SdrListResponse,
  HealthResponse,
  RecordingRow,
  RecordingResponse,
  TranscriptionResponse,
} from './types';

// ... existing get<T> function unchanged ...

export const api = {
  health: () => get<HealthResponse>('/health'),
  sdrs: () => get<SdrListResponse>('/sdrs'),
  recordings: () => get<RecordingRow[]>('/recordings'),
  recording: (id: string) => get<RecordingResponse>(`/recordings/${id}`),
  transcriptions: () => get<TranscriptionResponse[]>('/transcriptions'),
};
```

**Step 3: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 4: Commit**

```bash
git add web/src/api/
git commit -m "feat(web): add recording and transcription API types and client methods"
```

---

## Task 2: POTA + RBN spot types and fetchers

**Files:**
- Modify: `web/src/api/types.ts`
- Create: `web/src/api/spots.ts`

**Step 1: Add spot types to `web/src/api/types.ts`**

```ts
export interface PotaSpot {
  activator: string;          // callsign, e.g., "WA9AGG"
  frequency: string;          // e.g., "7030.0"
  mode: string;               // e.g., "CW"
  reference: string;          // park ref, e.g., "K-1234"
  parkName: string;           // e.g., "Yellowstone NP"
  spotTime: string;           // ISO timestamp
  spotter: string;
  comments: string;
}

export interface RbnSpot {
  callsign: string;
  frequency: number;          // kHz
  snr: number;
  wpm: number;
  mode: string;
  spotter_callsign: string;
  timestamp: string;
}
```

**Step 2: Create `web/src/api/spots.ts`**

Direct fetch to external public APIs. Catches errors gracefully (these are optional enrichment, not critical data).

```ts
import type { PotaSpot, RbnSpot } from './types';

const POTA_URL = 'https://api.pota.app/spot/activator';
const RBN_URL = 'https://rbn.telegraphy.de/skimmer/spots/current';

export async function fetchPotaSpots(): Promise<PotaSpot[]> {
  try {
    const res = await fetch(POTA_URL);
    if (!res.ok) return [];
    const data: PotaSpot[] = await res.json();
    // Filter to CW only
    return data.filter((s) => s.mode?.toUpperCase() === 'CW');
  } catch {
    return [];
  }
}

export async function fetchRbnSpots(): Promise<RbnSpot[]> {
  try {
    const res = await fetch(RBN_URL);
    if (!res.ok) return [];
    return (await res.json()) as RbnSpot[];
  } catch {
    return [];
  }
}
```

**Step 3: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 4: Commit**

```bash
git add web/src/api/
git commit -m "feat(web): add POTA and RBN spot types and fetchers"
```

---

## Task 3: Activation aggregation logic

**Files:**
- Create: `web/src/hooks/useActivations.ts`

This is the core logic of Phase 2. It groups recordings into activations, matches transcriptions, extracts callsigns, and matches POTA spots.

**Step 1: Create `web/src/hooks/useActivations.ts`**

```ts
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
// Band derivation from frequency (Hz)
// ---------------------------------------------------------------------------

const BAND_EDGES: [number, number, string][] = [
  [1_800_000, 2_000_000, '160m'],
  [3_500_000, 4_000_000, '80m'],
  [7_000_000, 7_300_000, '40m'],
  [10_100_000, 10_150_000, '30m'],
  [14_000_000, 14_350_000, '20m'],
  [18_068_000, 18_168_000, '17m'],
  [21_000_000, 21_450_000, '15m'],
  [24_890_000, 24_990_000, '12m'],
  [28_000_000, 29_700_000, '10m'],
];

function frequencyToBand(freqHz: number): string {
  for (const [lo, hi, band] of BAND_EDGES) {
    if (freqHz >= lo && freqHz <= hi) return band;
  }
  return 'unknown';
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
      parkName: spot?.parkName,
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
```

**Step 2: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 3: Commit**

```bash
git add web/src/hooks/useActivations.ts
git commit -m "feat(web): add activation aggregation logic with spot matching and favorites"
```

---

## Task 4: BandBadge, LiveDot, and FavoriteButton primitives

**Files:**
- Create: `web/src/components/BandBadge.tsx`
- Create: `web/src/components/LiveDot.tsx`
- Create: `web/src/components/FavoriteButton.tsx`

**Step 1: Create `web/src/components/BandBadge.tsx`**

```tsx
import { tokens } from '../styles/tokens';

interface BandBadgeProps {
  band: string;
  size?: 'sm' | 'md';
}

export function BandBadge({ band, size = 'sm' }: BandBadgeProps) {
  const color = tokens.band[band] ?? tokens.color.textTertiary;
  const isSm = size === 'sm';

  return (
    <span
      style={{
        display: 'inline-block',
        padding: isSm ? '0.125rem 0.5rem' : '0.1875rem 0.625rem',
        borderRadius: '9999px',
        fontSize: isSm ? '0.6875rem' : '0.75rem',
        fontWeight: 600,
        fontFamily: tokens.font.mono,
        color,
        background: `${color}1a`,
        lineHeight: 1.4,
      }}
    >
      {band}
    </span>
  );
}
```

**Step 2: Create `web/src/components/LiveDot.tsx`**

```tsx
import { tokens } from '../styles/tokens';

export function LiveDot() {
  return (
    <span
      style={{
        display: 'inline-block',
        width: 7,
        height: 7,
        borderRadius: '50%',
        background: tokens.color.liveGreen,
        boxShadow: `0 0 6px ${tokens.color.liveGreen}`,
        animation: 'pulse 2s ease-in-out infinite',
      }}
    />
  );
}
```

**Step 3: Create `web/src/components/FavoriteButton.tsx`**

```tsx
import { tokens } from '../styles/tokens';

interface FavoriteButtonProps {
  isFavorited: boolean;
  onClick: (e: React.MouseEvent) => void;
}

export function FavoriteButton({ isFavorited, onClick }: FavoriteButtonProps) {
  return (
    <button
      onClick={onClick}
      style={{
        background: 'none',
        border: 'none',
        cursor: 'pointer',
        padding: '0.25rem',
        fontSize: '1rem',
        lineHeight: 1,
        color: isFavorited ? '#fbbf24' : tokens.color.textTertiary,
        transition: 'color 0.15s',
      }}
      title={isFavorited ? 'Remove from favorites' : 'Add to favorites'}
    >
      {isFavorited ? '\u2605' : '\u2606'}
    </button>
  );
}
```

**Step 4: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 5: Commit**

```bash
git add web/src/components/
git commit -m "feat(web): add BandBadge, LiveDot, and FavoriteButton primitives"
```

---

## Task 5: FilterBar (ViewToggle + FilterPill)

**Files:**
- Create: `web/src/components/FilterPill.tsx`
- Create: `web/src/components/FilterBar.tsx`

**Step 1: Create `web/src/components/FilterPill.tsx`**

```tsx
import { tokens } from '../styles/tokens';

interface FilterPillProps {
  label: string;
  active: boolean;
  color?: string;
  onClick: () => void;
}

export function FilterPill({ label, active, color, onClick }: FilterPillProps) {
  const pillColor = color ?? tokens.color.accent;

  return (
    <button
      onClick={onClick}
      style={{
        display: 'inline-block',
        padding: '0.25rem 0.625rem',
        borderRadius: '9999px',
        fontSize: '0.75rem',
        fontWeight: 500,
        fontFamily: tokens.font.mono,
        cursor: 'pointer',
        border: 'none',
        transition: 'background 0.15s, color 0.15s',
        color: active ? pillColor : tokens.color.textTertiary,
        background: active ? `${pillColor}1a` : 'transparent',
      }}
    >
      {label}
    </button>
  );
}
```

**Step 2: Create `web/src/components/FilterBar.tsx`**

Composes band filter pills. Shows only bands that exist in the current activations.

```tsx
import { tokens } from '../styles/tokens';
import { FilterPill } from './FilterPill';

interface FilterBarProps {
  availableBands: string[];
  activeBands: string[];
  onBandToggle: (band: string) => void;
}

const BAND_ORDER = ['160m', '80m', '40m', '30m', '20m', '17m', '15m', '12m', '10m'];

export function FilterBar({
  availableBands,
  activeBands,
  onBandToggle,
}: FilterBarProps) {
  const ordered = BAND_ORDER.filter((b) => availableBands.includes(b));

  if (ordered.length === 0) return null;

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '0.375rem',
        padding: '0 1.5rem 0.75rem',
        flexWrap: 'wrap',
      }}
    >
      {ordered.map((band) => (
        <FilterPill
          key={band}
          label={band}
          active={activeBands.includes(band)}
          color={tokens.band[band]}
          onClick={() => onBandToggle(band)}
        />
      ))}
    </div>
  );
}
```

**Step 3: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 4: Commit**

```bash
git add web/src/components/
git commit -m "feat(web): add FilterPill and FilterBar for band filtering"
```

---

## Task 6: ActivationCard component

**Files:**
- Create: `web/src/components/ActivationCard.tsx`

**Step 1: Create `web/src/components/ActivationCard.tsx`**

The primary content card. Shows callsign, frequency, band, park, transcript snippet, live status, and favorite toggle. Live cards get a green left border. Staggered fade-in animation.

```tsx
import { tokens } from '../styles/tokens';
import { BandBadge } from './BandBadge';
import { LiveDot } from './LiveDot';
import { FavoriteButton } from './FavoriteButton';
import type { Activation } from '../hooks/useActivations';

interface ActivationCardProps {
  activation: Activation;
  isFavorited: boolean;
  onFavoriteToggle: () => void;
  onClick: () => void;
  index: number;
}

function formatFrequency(hz: number): string {
  return (hz / 1000).toFixed(1);
}

function timeAgo(isoStr: string): string {
  const diffMs = Date.now() - new Date(isoStr).getTime();
  const mins = Math.floor(diffMs / 60_000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}

export function ActivationCard({
  activation,
  isFavorited,
  onFavoriteToggle,
  onClick,
  index,
}: ActivationCardProps) {
  const { callsign, frequency, band, parkRef, parkName, transcription, wpm, sdrCount, isLive, lastActivity } = activation;

  const snippet = transcription?.text
    ? transcription.text.length > 80
      ? transcription.text.slice(0, 80) + '...'
      : transcription.text
    : undefined;

  return (
    <div
      onClick={onClick}
      style={{
        background: tokens.color.surface,
        borderRadius: tokens.radius.md,
        padding: '1rem 1.125rem',
        boxShadow: tokens.shadow.card,
        borderLeft: isLive ? `3px solid ${tokens.color.liveGreen}` : '3px solid transparent',
        cursor: 'pointer',
        display: 'flex',
        flexDirection: 'column',
        gap: '0.5rem',
        transition: 'box-shadow 0.2s, transform 0.2s',
        animation: `cardIn 0.3s ease-out ${index * 0.03}s both`,
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.boxShadow = tokens.shadow.cardHover;
        e.currentTarget.style.transform = 'translateY(-1px)';
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.boxShadow = tokens.shadow.card;
        e.currentTarget.style.transform = 'none';
      }}
    >
      {/* Row 1: Callsign + badge + favorite */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          {isLive && <LiveDot />}
          <span style={{ fontWeight: 700, fontSize: '1.0625rem', color: tokens.color.textPrimary }}>
            {callsign}
          </span>
          <BandBadge band={band} />
        </div>
        <FavoriteButton isFavorited={isFavorited} onClick={(e) => { e.stopPropagation(); onFavoriteToggle(); }} />
      </div>

      {/* Row 2: Frequency + park */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.8125rem' }}>
        <span style={{ fontFamily: tokens.font.mono, color: tokens.color.textSecondary }}>
          {formatFrequency(frequency)} kHz
        </span>
        {parkRef && (
          <span style={{ color: tokens.color.accent }}>
            {parkRef}{parkName ? ` ${parkName}` : ''}
          </span>
        )}
      </div>

      {/* Row 3: Transcript snippet */}
      {snippet && (
        <div
          style={{
            fontSize: '0.8125rem',
            color: tokens.color.textTertiary,
            fontFamily: tokens.font.mono,
            lineHeight: 1.5,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
          }}
        >
          {snippet}
        </div>
      )}

      {/* Row 4: Meta */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          fontSize: '0.6875rem',
          color: tokens.color.textTertiary,
        }}
      >
        <div style={{ display: 'flex', gap: '0.75rem' }}>
          {wpm && <span>{wpm.toFixed(0)} WPM</span>}
          <span>{sdrCount} SDR{sdrCount !== 1 ? 's' : ''}</span>
        </div>
        <span>{timeAgo(lastActivity)}</span>
      </div>
    </div>
  );
}
```

**Step 2: Add `cardIn` animation to `web/src/styles/global.css`**

Append:

```css
@keyframes cardIn {
  from {
    opacity: 0;
    transform: translateY(8px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
```

**Step 3: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 4: Commit**

```bash
git add web/src/components/ActivationCard.tsx web/src/styles/global.css
git commit -m "feat(web): add ActivationCard component with live indicators and staggered animation"
```

---

## Task 7: Wire "On the Air" tab into App

**Files:**
- Modify: `web/src/App.tsx`

**Step 1: Rewrite `web/src/App.tsx`**

Replace the Phase 2 placeholder with the real activation grid. The "On the Air" tab now uses `useActivations()` and shows activation cards with band filtering and favorites.

```tsx
import { useState } from 'react';
import { TopNav } from './components/TopNav';
import { PageHeader } from './components/PageHeader';
import { CardGrid } from './components/CardGrid';
import { SDRCard } from './components/SDRCard';
import { ActivationCard } from './components/ActivationCard';
import { FilterBar } from './components/FilterBar';
import { useSdrs } from './hooks/useSdrs';
import { useActivations } from './hooks/useActivations';
import { tokens } from './styles/tokens';

export function App() {
  const [activeTab, setActiveTab] = useState<'air' | 'sdrs'>('air');
  const { sdrs, loading: sdrsLoading, error: sdrsError } = useSdrs();
  const {
    activations,
    allActivations,
    loading: activationsLoading,
    error: activationsError,
    favoriteCallsigns,
    toggleFavorite,
    bandFilters,
    toggleBandFilter,
  } = useActivations();

  const hasLive =
    activations.some((a) => a.isLive) ||
    sdrs.some(
      (s) =>
        s.kiwi_status &&
        !s.kiwi_status.offline &&
        s.kiwi_status.users !== undefined &&
        s.kiwi_status.users > 0,
    );

  // Available bands from all activations (not filtered)
  const availableBands = [...new Set(allActivations.map((a) => a.band))];

  return (
    <div style={{ minHeight: '100vh', background: tokens.color.bg }}>
      <TopNav activeTab={activeTab} onTabChange={setActiveTab} hasLive={hasLive} />

      {activeTab === 'air' && (
        <>
          <PageHeader
            title="On the Air"
            subtitle={
              activationsLoading
                ? 'Loading...'
                : `${activations.length} activation${activations.length !== 1 ? 's' : ''}`
            }
          />
          <FilterBar
            availableBands={availableBands}
            activeBands={bandFilters}
            onBandToggle={toggleBandFilter}
          />
          {activationsError && (
            <div style={{ padding: '0.75rem 1.5rem', color: '#f87171', fontSize: '0.875rem' }}>
              Failed to load activations: {activationsError}
            </div>
          )}
          <CardGrid minWidth="340px">
            {activations.map((act, i) => (
              <ActivationCard
                key={act.id}
                activation={act}
                isFavorited={favoriteCallsigns.includes(act.callsign)}
                onFavoriteToggle={() => toggleFavorite(act.callsign)}
                onClick={() => {/* Phase 3: open detail overlay */}}
                index={i}
              />
            ))}
          </CardGrid>
          {!activationsLoading && activations.length === 0 && (
            <div
              style={{
                textAlign: 'center',
                padding: '3rem 1.5rem',
                color: tokens.color.textTertiary,
                fontSize: '0.875rem',
              }}
            >
              No activations found. Start a recording or wait for spot data.
            </div>
          )}
        </>
      )}

      {activeTab === 'sdrs' && (
        <>
          <PageHeader
            title="SDRs"
            subtitle={
              sdrsLoading
                ? 'Loading...'
                : `${sdrs.length} receiver${sdrs.length !== 1 ? 's' : ''}`
            }
          />
          {sdrsError && (
            <div style={{ padding: '0.75rem 1.5rem', color: '#f87171', fontSize: '0.875rem' }}>
              Failed to load SDRs: {sdrsError}
            </div>
          )}
          <CardGrid>
            {sdrs.map((sdr) => (
              <SDRCard key={sdr.id} sdr={sdr} />
            ))}
          </CardGrid>
        </>
      )}
    </div>
  );
}
```

**Step 2: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 3: Verify build succeeds**

```bash
cd /Users/jsvana/projects/cw-swl/web && npm run build
```

**Step 4: Commit**

```bash
git add web/src/App.tsx
git commit -m "feat(web): wire activation cards into On the Air tab with filtering and favorites"
```

---

## Task 8: Integration test + docs update

**Files:**
- Modify: `docs/FILE_INDEX.md`

**Step 1: Build frontend**

```bash
cd /Users/jsvana/projects/cw-swl/web && npm run build
```

**Step 2: Run Rust quality gate**

```bash
cd /Users/jsvana/projects/cw-swl && cargo fmt --check && cargo clippy -- -W clippy::all && cargo test
```

**Step 3: Update FILE_INDEX.md**

Add the new files to the `web/` section:

```markdown
| `web/src/api/spots.ts` | POTA and RBN spot fetchers |
| `web/src/hooks/useActivations.ts` | Activation aggregation, spot matching, favorites, band filtering |
| `web/src/components/ActivationCard.tsx` | Activation status card with live/favorite indicators |
| `web/src/components/BandBadge.tsx` | Colored band indicator pill |
| `web/src/components/LiveDot.tsx` | Pulsing green live indicator |
| `web/src/components/FavoriteButton.tsx` | Star toggle for favorites |
| `web/src/components/FilterPill.tsx` | Band/mode filter pill |
| `web/src/components/FilterBar.tsx` | Band filter bar composition |
```

**Step 4: Commit**

```bash
git add docs/FILE_INDEX.md
git commit -m "docs: add Phase 2 web files to FILE_INDEX.md"
```

---

## Summary

| Task | What | Files | Key |
|------|------|-------|-----|
| 1 | Recording/transcription API types | 2 modify | Match Rust shapes |
| 2 | POTA/RBN spot types + fetchers | 1 modify, 1 create | Graceful failure |
| 3 | Activation aggregation | 1 create | Core grouping logic |
| 4 | BandBadge, LiveDot, FavoriteButton | 3 create | Primitives |
| 5 | FilterBar | 2 create | Band filtering |
| 6 | ActivationCard | 1 create, 1 modify | Primary content unit |
| 7 | Wire into App | 1 modify | "On the Air" tab |
| 8 | Integration test + docs | 1 modify | Quality gate |

**Total: 8 new files, 5 modified files, 8 commits. 0 backend changes.**
