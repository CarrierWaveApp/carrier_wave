# Web UI Design — CW-SWL

**Date:** 2026-02-21
**Status:** Design approved, ready for implementation planning
**Mockup:** [docs/mockups/home.html](../mockups/home.html)

## Overview

A React + TypeScript web UI embedded in the axum server binary. Public-facing with read-only visitors and authenticated operator controls. Activation-centric design — operators and their transmissions are the primary content, SDRs are infrastructure.

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Layout approach | Card Grid (Apple Home/Weather style) | Progressive disclosure, mobile-friendly, scannable |
| Primary content model | Activations (callsign + frequency + time) | Operators matter more than SDRs; recordings group naturally by activation |
| Tech stack | React + TypeScript + Vite | Fast dev iteration, strong typing, small bundle |
| Serving model | Embedded in axum | Single binary deployment, no separate web server |
| Spot data | Client-side direct fetch | No backend coupling to external APIs, browser handles CORS |
| Favorites | localStorage visitor bookmarks | No auth needed, zero backend state |
| State management | Zustand | Lightweight, no boilerplate, good for polling pattern |
| Theme | Mid-tone dark (#25252d bg) | Nighttime radio operation, reduced eye strain |

## Information Architecture

### Navigation

```
/ (On the Air)          ← default, activation-centric
/sdrs                   ← infrastructure view
/spots                  ← raw POTA + RBN spot feed
/search                 ← callsign/park/frequency search
/activation/:id         ← deep link (opens overlay)
```

### Two Mental Models

- **Activation view** (On the Air): "What operators are transmitting right now?" — grouped by callsign + frequency + time window
- **SDR view** (SDRs): "What receivers are available?" — infrastructure status, slot usage

### Progressive Disclosure (3 layers)

1. **Card Grid** — Callsign, frequency, band, park, transcript snippet, live status
2. **Detail Overlay** — Spectrogram, audio player, full transcript, spot context, source recordings
3. **Deep Detail** — Individual SDR recordings, per-source audio, raw segment data

### Public vs Authenticated

| Feature | Public | Auth required |
|---------|--------|---------------|
| View activations, SDRs, spots | Yes | — |
| Play audio, read transcripts | Yes | — |
| Favorite operators/SDRs | Yes (localStorage) | — |
| Start/stop recordings | — | Yes |
| Trigger combine/transcribe | — | Yes |
| Configure SDRs | — | Yes |

## Design Tokens

```ts
export const tokens = {
  color: {
    bg: '#25252d',
    surface: '#2f2f3a',
    surfaceHover: '#383844',
    border: '#3e3e4c',
    borderLight: '#363642',
    textPrimary: '#ededea',
    textSecondary: '#a5a19a',
    textTertiary: '#706c66',
    accent: '#6fb1f7',
    accentLight: 'rgba(111,177,247,0.14)',
    liveGreen: '#3ddc97',
    liveGreenBg: 'rgba(61,220,151,0.1)',
  },
  band: {
    '160m': '#a78bfa', '80m': '#818cf8', '40m': '#fbbf24',
    '30m': '#a3e635', '20m': '#38bdf8', '17m': '#22d3ee',
    '15m': '#34d399', '12m': '#fb923c', '10m': '#f87171',
  },
  radius: { sm: '8px', md: '14px', lg: '20px' },
  shadow: {
    card: '0 1px 4px rgba(0,0,0,0.2), 0 0 0 1px rgba(255,255,255,0.05)',
    cardHover: '0 6px 24px rgba(0,0,0,0.35), 0 0 0 1px rgba(255,255,255,0.08)',
  },
  font: {
    sans: "'DM Sans', -apple-system, BlinkMacSystemFont, sans-serif",
    mono: "'JetBrains Mono', 'SF Mono', monospace",
  },
} as const;
```

## Component Library

### Navigation

**`<TopNav />`** — Sticky frosted-glass nav bar (`backdrop-filter: blur(20px) saturate(180%)`)
- Props: `activeTab`, `onTabChange`, `isAuthenticated`, `onSignIn`
- Brand dot pulses green when any recording is live
- Collapses padding on mobile

### Controls

**`<ViewToggle />`** — List/Map segment switcher
- Props: `value: 'list' | 'map'`, `onChange`

**`<FilterPill />`** — Band/mode filter pill (full-round corners)
- Props: `label`, `active`, `onClick`

**`<FilterBar />`** — Composition of ViewToggle + FilterPills
- Props: `view`, `onViewChange`, `activeBands`, `onBandToggle`

### Cards

**`<ActivationCard />`** — Primary content unit
- Props: `callsign`, `frequency`, `band`, `mode`, `parkRef?`, `parkName?`, `transcript?`, `wpm?`, `timeAgo`, `sdrCount`, `isLive`, `isFavorited`, `onClick`, `onFavoriteToggle`
- Live: green left border (3px). Favorited: gold corner triangle (CSS ::after)
- Staggered card-in animation (0.03s delay increment)

**`<SDRCard />`** — Infrastructure unit
- Props: `name`, `driver`, `location`, `gridSquare`, `status`, `activity`, `slotsUsed`, `slotsTotal`, `onClick`
- Offline/full cards dimmed to opacity 0.55. Slot display: "N / M slots"

**`<BandBadge />`** — Colored band indicator pill
- Props: `band`, `size?: 'sm' | 'md'`

### Detail / Overlay

**`<DetailOverlay />`** — Modal backdrop + slide-up panel
- Props: `isOpen`, `onClose`, `children`
- Click-outside, ESC, body scroll lock

**`<ActivationDetail />`** — Full activation view (composed inside overlay)
- Props: `callsign`, `frequency`, `parkRef?`, `parkName?`, `band`, `wpm?`, `sdrCount`, `audioSegments`, `transcript?`, `spot?`, `sourceRecordings`

**`<Spectrogram />`** — Waterfall visualization
- Phase 1: purple gradient placeholder. Phase 2+: Canvas-rendered from WAV FFT

**`<AudioPlayer />`** — Combined audio playback
- Props: `segments[]`, `duration`, `onTimeUpdate?`
- HTML5 `<audio>`, play/pause, progress seek, mono time display

**`<TranscriptView />`** — Semantic CW transcript
- Props: `data: TranscriptData`, `currentTime?`
- Callsigns: accent blue. Prosigns: gold. Hover highlight on words.

**`<SpotContext />`** — POTA/RBN spot attribution
- Props: `spot: SpotData`
- Icon: "P" for POTA, "R" for RBN

**`<SourceRecordingList />`** — Per-SDR quality display
- Props: `sources: SourceRecording[]`
- Quality badges: green (r >= 0.6), yellow (0.3-0.6), red (excluded)

### Map

**`<ActivationMap />`** — Leaflet map with band-colored pins
- Props: `activations[]`, `sdrs?[]`, `onActivationClick`
- Phase 1: CSS placeholder. Phase 2+: Leaflet/OpenStreetMap

**`<MapLegend />`** — Frosted glass legend overlay

### Layout

**`<PageHeader />`** — Title + subtitle + optional action
**`<CardGrid />`** — Responsive auto-fill grid (340px min for activations, 280px for SDRs)

### Primitives

| Component | Purpose |
|-----------|---------|
| `<LiveDot />` | 7px pulsing green indicator |
| `<StatusDot />` | 8px SDR status (green/pulsing/gray) |
| `<FavoriteButton />` | Star toggle (gold active, tertiary inactive) |
| `<SectionTitle />` | 12px uppercase label |
| `<QualityBadge />` | Correlation pill (green/yellow/red) |

### Component Tree (Home Page)

```
<TopNav />
<PageHeader />
<FilterBar>
  <ViewToggle />
  <FilterPill /> x N
</FilterBar>
<CardGrid>
  <ActivationCard /> x N
</CardGrid>
<ActivationMap />
<DetailOverlay>
  <ActivationDetail>
    <Spectrogram />
    <AudioPlayer />
    <TranscriptView />
    <SpotContext />
    <SourceRecordingList />
  </ActivationDetail>
</DetailOverlay>
```

## Data Flow

### Existing API Endpoints (no changes needed)

| Endpoint | Method | Used by |
|----------|--------|---------|
| `/api/v1/health` | GET | TopNav connection status |
| `/api/v1/sdrs` | GET | SDR card grid, map pins |
| `/api/v1/sdrs/{id}` | GET | SDR detail |
| `/api/v1/sdrs/search?lat=&lon=&count=` | GET | Find nearest SDRs |
| `/api/v1/recordings` | GET | Activation aggregation |
| `/api/v1/recordings/{id}` | GET | Activation detail (segments) |
| `/api/v1/recordings/{id}/segments/{num}/audio` | GET | Audio player |
| `/api/v1/transcriptions` | GET | Transcript previews + detail |
| `/api/v1/transcriptions/{id}` | GET | Full transcript |

### Activation Aggregation (client-side, Phase 1)

The "Activation" concept does not exist in the backend. The UI constructs it:

```ts
interface Activation {
  id: string;                    // first recording UUID
  callsign: string;              // from transcription or POTA spot
  frequency: number;
  band: string;                  // derived from frequency
  mode: string;
  parkRef?: string;              // from matched POTA spot
  parkName?: string;
  isLive: boolean;               // any recording with status="recording"
  recordings: RecordingRow[];
  combinedRecordingId?: string;
  transcription?: TranscriptionResponse;
  spot?: SpotData;
  sdrCount: number;
  wpm?: number;
  startedAt: string;
  lastActivity: string;
}
```

**Aggregation steps:**
1. Fetch recordings + transcriptions from server
2. Group recordings by (frequency ±500Hz, overlapping time within 5 min)
3. Match transcription to group by recording_id
4. Extract callsign from transcript text (first callsign pattern) or POTA spot
5. Match against POTA spots by callsign + frequency (±1 kHz)
6. Derive band from frequency using HF band edges

### External APIs (client-side direct)

**POTA Spots:** `GET https://api.pota.app/spot/activator`
- No auth, public API. Poll every 60s. Filter to CW mode.

**RBN Spots:** `GET https://rbn.telegraphy.de/skimmer/spots/current`
- No auth. Poll every 30s. Provides SNR + WPM enrichment.

**CORS fallback:** If direct fetch fails, add proxy endpoints:
- `GET /api/v1/proxy/pota/spots`
- `GET /api/v1/proxy/rbn/spots`

### Polling Strategy

| Source | Interval | Hook |
|--------|----------|------|
| Recordings + transcriptions | 30s | `useActivations()` |
| SDRs | 60s | `useSdrs()` |
| POTA spots | 60s | `usePotaSpots()` |
| RBN spots | 30s | `useRbnSpots()` |

### State Management (Zustand)

```ts
interface AppStore {
  // Data
  recordings: RecordingRow[];
  transcriptions: TranscriptionResponse[];
  sdrs: SdrInfo[];
  potaSpots: PotaSpot[];
  rbnSpots: RbnSpot[];
  activations: Activation[];       // computed from above

  // UI state
  activeTab: 'air' | 'sdrs' | 'spots' | 'search';
  activeView: 'list' | 'map';
  bandFilters: string[];
  selectedActivation: string | null;

  // Favorites (localStorage)
  favoriteCallsigns: string[];
  favoriteSdrs: string[];

  // Actions
  fetchAll: () => Promise<void>;
  toggleFavorite: (type: 'callsign' | 'sdr', id: string) => void;
}
```

### Serving the SPA

```rust
// axum router addition
Router::new()
    // ... existing API routes ...
    .nest_service("/assets", ServeDir::new("web/dist/assets"))
    .fallback(serve_spa)    // serves index.html for client-side routing
```

- Dev: Vite dev server on :5173, axum proxies or CORS allows
- Production: `web/dist/` built by Vite, served by axum

## Phased Build Plan

### Phase 1: Static Shell + SDR List

**Goal:** React app serving from axum, rendering real SDR data.

**Backend:**
- Add `tower-http` ServeDir to axum for static files
- Fallback handler serves index.html for client-side routing

**Frontend:**
- Vite + React + TypeScript project in `web/`
- Design tokens, global CSS, font loading
- Components: `TopNav`, `PageHeader`, `SDRCard`, `CardGrid`
- Hook: `useSdrs()` → `GET /api/v1/sdrs`, polling 60s

**Deliverable:** `http://localhost:3000` shows real SDRs with live status and slot counts.

### Phase 2: Activation Cards + Spot Integration

**Goal:** "On the Air" tab with activations from recordings + spots.

**Components:** `ActivationCard`, `BandBadge`, `FilterBar`, `ViewToggle`, `FilterPill`, `FavoriteButton`, `LiveDot`

**Hooks:** `useRecordings()`, `useTranscriptions()`, `usePotaSpots()`, `useRbnSpots()`, `useActivations()` (aggregation)

**Deliverable:** Activation cards with real data — POTA parks, live indicators, transcript previews, band filters, localStorage favorites.

### Phase 3: Activation Detail Overlay

**Goal:** Click card → full detail with audio and transcript.

**Components:** `DetailOverlay`, `ActivationDetail`, `AudioPlayer`, `TranscriptView`, `SpotContext`, `SourceRecordingList`, `Spectrogram` (placeholder), `SectionTitle`, `QualityBadge`

**Deliverable:** Full detail flow. Audio plays combined WAV segments. Transcript shows semantic highlighting. Source recordings show per-SDR correlation quality.

### Phase 4: Map View + Polish

**Goal:** Map view, mobile polish, tab stubs.

**Components:** `ActivationMap` (Leaflet), `MapLegend`, map pins

**Polish:** Mobile responsive, loading skeletons, error states, staggered animations, CORS proxy fallback, Spots tab stub, Search tab stub.

**Deliverable:** Complete mockup realized with both list and map views, real data, mobile-friendly.

### Phase Summary

| Phase | Components | New Backend | Data Sources |
|-------|-----------|-------------|-------------|
| 1 | 4 | Static file serving | SDRs |
| 2 | 7 | 0 | + Recordings, transcriptions, POTA, RBN |
| 3 | 9 | 0 | + Segment audio streaming |
| 4 | 3 + polish | 1 (CORS proxy, optional) | + Coordinates for map |

**Total: 22 components, 0-1 new backend endpoints, 0 schema changes.**

## Future Enhancements (beyond Phase 4)

- Server-side activation model with `activations` table
- WebSocket/SSE for live updates (replace polling)
- Canvas-rendered spectrogram from WAV FFT data
- Gapless multi-segment audio with waveform visualization
- Full-text search across callsigns, parks, transcripts
- JWT authentication for operator controls
- Start/stop recording from UI
- Trigger combine + transcribe from activation detail
