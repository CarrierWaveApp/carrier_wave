# Web UI Phase 4: Map View + Polish — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Leaflet map view for activations and SDRs with band-colored pins, a list/map view toggle, mobile responsive polish, loading skeletons, and stub tabs for Spots and Search.

**Architecture:** The "On the Air" tab gains a ViewToggle (list/map) that switches between the existing card grid and a new Leaflet map. Activations with coordinates (from matched POTA spots or SDR locations) appear as band-colored circle markers. SDRs with lat/lon from KiwiStatus appear as gray diamond markers. A frosted-glass MapLegend shows band colors. Mobile polish adds responsive padding, skeleton loading states, and better touch targets. Spots and Search tabs are stub placeholders for future phases. One optional backend endpoint (CORS proxy for external spot APIs) is included if needed.

**Tech Stack:** react-leaflet v4 (React 18 compatible), leaflet, existing design tokens and inline style patterns.

**Design Reference:** `docs/plans/2026-02-21-web-ui-design.md` — Phase 4 components (ActivationMap, MapLegend, ViewToggle), polish items.

**Existing code patterns:** Phases 1-3 established inline styles using `tokens`, function components with typed props, Zustand stores, and polling hooks. Follow the same patterns.

---

## Task 1: Install Leaflet dependencies

**Files:**
- Modify: `web/package.json`

**Step 1: Install react-leaflet v4 and leaflet**

react-leaflet v4 is the latest version compatible with React 18 (v5 requires React 19).

```bash
cd /Users/jsvana/projects/cw-swl/web && npm install react-leaflet@^4 leaflet@^1.9 && npm install -D @types/leaflet
```

**Step 2: Verify build still works**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit && npm run build
```

**Step 3: Commit**

```bash
git add web/package.json web/package-lock.json
git commit -m "chore(web): add react-leaflet and leaflet dependencies for map view"
```

---

## Task 2: ViewToggle component

**Files:**
- Create: `web/src/components/ViewToggle.tsx`

A segmented control that switches between "List" and "Map" views. Two buttons side-by-side with rounded corners on the outer edges.

**Step 1: Create `web/src/components/ViewToggle.tsx`**

```tsx
import { tokens } from '../styles/tokens';

interface ViewToggleProps {
  value: 'list' | 'map';
  onChange: (value: 'list' | 'map') => void;
}

export function ViewToggle({ value, onChange }: ViewToggleProps) {
  return (
    <div
      style={{
        display: 'inline-flex',
        background: tokens.color.surface,
        borderRadius: tokens.radius.sm,
        padding: '2px',
      }}
    >
      {(['list', 'map'] as const).map((option) => (
        <button
          key={option}
          onClick={() => onChange(option)}
          style={{
            background: value === option ? tokens.color.accentLight : 'transparent',
            color: value === option ? tokens.color.accent : tokens.color.textTertiary,
            border: 'none',
            borderRadius: '6px',
            padding: '0.25rem 0.625rem',
            fontSize: '0.75rem',
            fontWeight: 500,
            fontFamily: 'inherit',
            cursor: 'pointer',
            transition: 'background 0.15s, color 0.15s',
          }}
        >
          {option === 'list' ? 'List' : 'Map'}
        </button>
      ))}
    </div>
  );
}
```

**Step 2: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 3: Commit**

```bash
git add web/src/components/ViewToggle.tsx
git commit -m "feat(web): add ViewToggle component for list/map switching"
```

---

## Task 3: MapLegend component

**Files:**
- Create: `web/src/components/MapLegend.tsx`

A frosted-glass overlay legend that shows band colors. Positioned in the bottom-right of the map container.

**Step 1: Create `web/src/components/MapLegend.tsx`**

```tsx
import { tokens } from '../styles/tokens';

const BANDS = ['160m', '80m', '40m', '30m', '20m', '17m', '15m', '12m', '10m'];

export function MapLegend() {
  return (
    <div
      style={{
        position: 'absolute',
        bottom: '1rem',
        right: '1rem',
        zIndex: 1000,
        background: 'rgba(37,37,45,0.85)',
        backdropFilter: 'blur(12px) saturate(180%)',
        WebkitBackdropFilter: 'blur(12px) saturate(180%)',
        borderRadius: tokens.radius.sm,
        padding: '0.5rem 0.75rem',
        display: 'flex',
        flexDirection: 'column',
        gap: '0.25rem',
        border: `1px solid ${tokens.color.border}`,
      }}
    >
      <div
        style={{
          fontSize: '0.625rem',
          fontWeight: 600,
          textTransform: 'uppercase',
          letterSpacing: '0.06em',
          color: tokens.color.textTertiary,
          marginBottom: '0.125rem',
        }}
      >
        Bands
      </div>
      {BANDS.map((band) => {
        const color = tokens.band[band] ?? tokens.color.textTertiary;
        return (
          <div
            key={band}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.375rem',
              fontSize: '0.6875rem',
              color: tokens.color.textSecondary,
            }}
          >
            <span
              style={{
                width: 8,
                height: 8,
                borderRadius: '50%',
                background: color,
                flexShrink: 0,
              }}
            />
            {band}
          </div>
        );
      })}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '0.375rem',
          fontSize: '0.6875rem',
          color: tokens.color.textSecondary,
          marginTop: '0.125rem',
          borderTop: `1px solid ${tokens.color.border}`,
          paddingTop: '0.25rem',
        }}
      >
        <span
          style={{
            width: 8,
            height: 8,
            borderRadius: '2px',
            background: tokens.color.textTertiary,
            flexShrink: 0,
            transform: 'rotate(45deg)',
          }}
        />
        SDR
      </div>
    </div>
  );
}
```

**Step 2: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 3: Commit**

```bash
git add web/src/components/MapLegend.tsx
git commit -m "feat(web): add MapLegend component with frosted glass band color legend"
```

---

## Task 4: ActivationMap component

**Files:**
- Create: `web/src/components/ActivationMap.tsx`
- Modify: `web/src/styles/global.css` (add Leaflet CSS import)

The map component uses react-leaflet with OpenStreetMap tiles. Activations with coordinates appear as band-colored circle markers. SDRs with lat/lon appear as gray diamond-shaped markers. Clicking an activation marker opens the detail overlay.

Coordinate sources:
- **Activations:** Matched POTA spots have no coordinates in the API, but SDRs do. Activations inherit coordinates from the first SDR that recorded them (matched via `recordings[].sdr_id` → `sdrs[].kiwi_status.lat/lon`). This is approximate (SDR location, not activator location) but useful for visualization.
- **SDRs:** `sdr.kiwi_status.lat` and `sdr.kiwi_status.lon` directly.

**Step 1: Add Leaflet CSS to `web/src/styles/global.css`**

Append at the top of the file (before the CSS reset):

```css
@import 'leaflet/dist/leaflet.css';
```

**Step 2: Create `web/src/components/ActivationMap.tsx`**

```tsx
import { useMemo } from 'react';
import { MapContainer, TileLayer, CircleMarker, Popup } from 'react-leaflet';
import { tokens } from '../styles/tokens';
import { BandBadge } from './BandBadge';
import { MapLegend } from './MapLegend';
import type { Activation } from '../hooks/useActivations';
import type { SdrInfo } from '../api/types';

interface ActivationMapProps {
  activations: Activation[];
  sdrs: SdrInfo[];
  onActivationClick: (id: string) => void;
}

interface MapActivation {
  activation: Activation;
  lat: number;
  lon: number;
}

interface MapSdr {
  sdr: SdrInfo;
  lat: number;
  lon: number;
}

function formatFrequency(hz: number): string {
  return (hz / 1000).toFixed(1);
}

export function ActivationMap({ activations, sdrs, onActivationClick }: ActivationMapProps) {
  // Build SDR coordinate index
  const sdrCoords = useMemo(() => {
    const map = new Map<string, { lat: number; lon: number }>();
    for (const sdr of sdrs) {
      const ks = sdr.kiwi_status;
      if (ks?.lat != null && ks?.lon != null) {
        map.set(sdr.id, { lat: ks.lat, lon: ks.lon });
      }
    }
    return map;
  }, [sdrs]);

  // Activations with coordinates (from their recording's SDR)
  const mapActivations: MapActivation[] = useMemo(() => {
    const result: MapActivation[] = [];
    for (const act of activations) {
      // Find first recording whose SDR has coordinates
      for (const rec of act.recordings) {
        const coords = sdrCoords.get(rec.sdr_id);
        if (coords) {
          result.push({ activation: act, ...coords });
          break;
        }
      }
    }
    return result;
  }, [activations, sdrCoords]);

  // SDRs with coordinates
  const mapSdrs: MapSdr[] = useMemo(() => {
    const result: MapSdr[] = [];
    for (const sdr of sdrs) {
      const coords = sdrCoords.get(sdr.id);
      if (coords) {
        result.push({ sdr, ...coords });
      }
    }
    return result;
  }, [sdrs, sdrCoords]);

  // Default center: US center, or first activation/SDR with coords
  const defaultCenter: [number, number] = useMemo(() => {
    if (mapActivations.length > 0) {
      return [mapActivations[0]!.lat, mapActivations[0]!.lon];
    }
    if (mapSdrs.length > 0) {
      return [mapSdrs[0]!.lat, mapSdrs[0]!.lon];
    }
    return [39.8, -98.5]; // Geographic center of US
  }, [mapActivations, mapSdrs]);

  return (
    <div style={{ position: 'relative', height: '500px', margin: '0 1.5rem', borderRadius: tokens.radius.md, overflow: 'hidden' }}>
      <MapContainer
        center={defaultCenter}
        zoom={4}
        style={{ height: '100%', width: '100%', background: tokens.color.surface }}
        scrollWheelZoom={true}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
        />

        {/* SDR markers (gray diamonds — rendered first so activations appear on top) */}
        {mapSdrs.map((ms) => (
          <CircleMarker
            key={`sdr-${ms.sdr.id}`}
            center={[ms.lat, ms.lon]}
            radius={5}
            pathOptions={{
              color: tokens.color.textTertiary,
              fillColor: tokens.color.textTertiary,
              fillOpacity: 0.6,
              weight: 1,
            }}
          >
            <Popup>
              <div style={{ fontFamily: tokens.font.sans, fontSize: '0.8125rem' }}>
                <strong>{ms.sdr.label || ms.sdr.id}</strong>
                <br />
                {ms.sdr.kiwi_status?.location ?? ms.sdr.driver}
              </div>
            </Popup>
          </CircleMarker>
        ))}

        {/* Activation markers (band-colored circles) */}
        {mapActivations.map((ma) => {
          const color = tokens.band[ma.activation.band] ?? tokens.color.accent;
          return (
            <CircleMarker
              key={`act-${ma.activation.id}`}
              center={[ma.lat, ma.lon]}
              radius={ma.activation.isLive ? 8 : 6}
              pathOptions={{
                color,
                fillColor: color,
                fillOpacity: 0.7,
                weight: ma.activation.isLive ? 2 : 1,
              }}
              eventHandlers={{
                click: () => onActivationClick(ma.activation.id),
              }}
            >
              <Popup>
                <div style={{ fontFamily: tokens.font.sans, fontSize: '0.8125rem' }}>
                  <strong>{ma.activation.callsign}</strong>{' '}
                  <span style={{ fontFamily: tokens.font.mono }}>
                    {formatFrequency(ma.activation.frequency)} kHz
                  </span>
                  <br />
                  {ma.activation.band}
                  {ma.activation.parkRef && ` — ${ma.activation.parkRef}`}
                </div>
              </Popup>
            </CircleMarker>
          );
        })}
      </MapContainer>

      <MapLegend />
    </div>
  );
}
```

**Step 3: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 4: Verify build succeeds**

```bash
cd /Users/jsvana/projects/cw-swl/web && npm run build
```

**Step 5: Commit**

```bash
git add web/src/components/ActivationMap.tsx web/src/styles/global.css
git commit -m "feat(web): add ActivationMap component with Leaflet dark tiles and band-colored markers"
```

---

## Task 5: Wire map view into On the Air tab

**Files:**
- Modify: `web/src/App.tsx`
- Modify: `web/src/components/FilterBar.tsx` (add ViewToggle integration)

Add `activeView` state and the ViewToggle to the FilterBar. When view is "map", show ActivationMap instead of CardGrid. The FilterBar needs to accept and render the ViewToggle.

**Step 1: Add ViewToggle to FilterBar**

Modify `web/src/components/FilterBar.tsx` to accept an optional `children` prop for the ViewToggle, rendered before the filter pills:

```tsx
import { tokens } from '../styles/tokens';
import { FilterPill } from './FilterPill';

interface FilterBarProps {
  availableBands: string[];
  activeBands: string[];
  onBandToggle: (band: string) => void;
  children?: React.ReactNode;
}

const BAND_ORDER = ['160m', '80m', '40m', '30m', '20m', '17m', '15m', '12m', '10m'];

export function FilterBar({
  availableBands,
  activeBands,
  onBandToggle,
  children,
}: FilterBarProps) {
  const ordered = BAND_ORDER.filter((b) => availableBands.includes(b));

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
      {children}
      {children && ordered.length > 0 && (
        <div style={{ width: 1, height: 16, background: tokens.color.border, margin: '0 0.25rem' }} />
      )}
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

**Step 2: Update `web/src/App.tsx`**

Add imports for ViewToggle and ActivationMap. Add `activeView` state. Pass ViewToggle as child of FilterBar. Conditionally render CardGrid or ActivationMap based on activeView.

```tsx
import { useState, useMemo } from 'react';
import { TopNav } from './components/TopNav';
import { PageHeader } from './components/PageHeader';
import { CardGrid } from './components/CardGrid';
import { SDRCard } from './components/SDRCard';
import { ActivationCard } from './components/ActivationCard';
import { FilterBar } from './components/FilterBar';
import { ViewToggle } from './components/ViewToggle';
import { ActivationMap } from './components/ActivationMap';
import { DetailOverlay } from './components/DetailOverlay';
import { ActivationDetail } from './components/ActivationDetail';
import { useSdrs } from './hooks/useSdrs';
import { useActivations } from './hooks/useActivations';
import { useActivationDetail } from './hooks/useActivationDetail';
import { tokens } from './styles/tokens';

export function App() {
  const [activeTab, setActiveTab] = useState<'air' | 'sdrs'>('air');
  const [activeView, setActiveView] = useState<'list' | 'map'>('list');
  const [selectedActivationId, setSelectedActivationId] = useState<string | null>(null);
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
    rbnSpots,
  } = useActivations();

  const selectedActivation = useMemo(
    () => allActivations.find((a) => a.id === selectedActivationId) ?? null,
    [allActivations, selectedActivationId],
  );

  const {
    recordingDetail,
    matchingRbnSpots,
    loading: detailLoading,
    error: detailError,
  } = useActivationDetail(selectedActivation, rbnSpots);

  const hasLive =
    activations.some((a) => a.isLive) ||
    sdrs.some(
      (s) =>
        s.kiwi_status &&
        !s.kiwi_status.offline &&
        s.kiwi_status.users !== undefined &&
        s.kiwi_status.users > 0,
    );

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
          >
            <ViewToggle value={activeView} onChange={setActiveView} />
          </FilterBar>
          {activationsError && (
            <div style={{ padding: '0.75rem 1.5rem', color: '#f87171', fontSize: '0.875rem' }}>
              Failed to load activations: {activationsError}
            </div>
          )}

          {activeView === 'list' && (
            <>
              <CardGrid minWidth="340px">
                {activations.map((act, i) => (
                  <ActivationCard
                    key={act.id}
                    activation={act}
                    isFavorited={favoriteCallsigns.includes(act.callsign)}
                    onFavoriteToggle={() => toggleFavorite(act.callsign)}
                    onClick={() => setSelectedActivationId(act.id)}
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

          {activeView === 'map' && (
            <ActivationMap
              activations={activations}
              sdrs={sdrs}
              onActivationClick={setSelectedActivationId}
            />
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

      <DetailOverlay
        isOpen={selectedActivation !== null}
        onClose={() => setSelectedActivationId(null)}
      >
        {selectedActivation && (
          <ActivationDetail
            activation={selectedActivation}
            recordingDetail={recordingDetail}
            matchingRbnSpots={matchingRbnSpots}
            loading={detailLoading}
            error={detailError}
          />
        )}
      </DetailOverlay>
    </div>
  );
}
```

**Step 3: Verify TypeScript compiles and build succeeds**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit && npm run build
```

**Step 4: Commit**

```bash
git add web/src/App.tsx web/src/components/FilterBar.tsx
git commit -m "feat(web): wire map view into On the Air tab with ViewToggle"
```

---

## Task 6: Loading skeletons

**Files:**
- Create: `web/src/components/CardSkeleton.tsx`
- Modify: `web/src/styles/global.css` (add shimmer animation)
- Modify: `web/src/App.tsx` (show skeletons during loading)

Show shimmer skeleton cards while data is loading instead of just "Loading..." text.

**Step 1: Add shimmer keyframe to `web/src/styles/global.css`**

Append after the existing keyframes:

```css
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}
```

**Step 2: Create `web/src/components/CardSkeleton.tsx`**

```tsx
import { tokens } from '../styles/tokens';

interface CardSkeletonProps {
  lines?: number;
}

function SkeletonLine({ width }: { width: string }) {
  return (
    <div
      style={{
        height: '0.75rem',
        width,
        borderRadius: '4px',
        background: `linear-gradient(90deg, ${tokens.color.surface} 25%, ${tokens.color.surfaceHover} 50%, ${tokens.color.surface} 75%)`,
        backgroundSize: '200% 100%',
        animation: 'shimmer 1.5s ease-in-out infinite',
      }}
    />
  );
}

export function CardSkeleton({ lines = 3 }: CardSkeletonProps) {
  const widths = ['60%', '80%', '45%', '70%'];

  return (
    <div
      style={{
        background: tokens.color.surface,
        borderRadius: tokens.radius.md,
        padding: '1rem 1.125rem',
        boxShadow: tokens.shadow.card,
        display: 'flex',
        flexDirection: 'column',
        gap: '0.625rem',
      }}
    >
      {Array.from({ length: lines }, (_, i) => (
        <SkeletonLine key={i} width={widths[i % widths.length]!} />
      ))}
    </div>
  );
}
```

**Step 3: Update `web/src/App.tsx` to show skeletons**

In the "On the Air" list view, replace the loading subtitle with skeleton cards. In the SDRs tab, do the same.

When `activationsLoading` is true and `activations.length === 0` and `activeView === 'list'`, show 6 skeleton cards instead of an empty grid.

When `sdrsLoading` is true and `sdrs.length === 0`, show 4 skeleton cards.

Add import for `CardSkeleton` and add these blocks right after the error messages, before the real CardGrids:

For the "On the Air" list view, inside the `activeView === 'list'` block, before the existing `<CardGrid>`:

```tsx
{activationsLoading && activations.length === 0 && (
  <CardGrid minWidth="340px">
    {Array.from({ length: 6 }, (_, i) => (
      <CardSkeleton key={i} lines={4} />
    ))}
  </CardGrid>
)}
```

For the SDRs tab, before the existing `<CardGrid>`:

```tsx
{sdrsLoading && sdrs.length === 0 && (
  <CardGrid>
    {Array.from({ length: 4 }, (_, i) => (
      <CardSkeleton key={i} lines={3} />
    ))}
  </CardGrid>
)}
```

**Step 4: Verify TypeScript compiles and build succeeds**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit && npm run build
```

**Step 5: Commit**

```bash
git add web/src/components/CardSkeleton.tsx web/src/styles/global.css web/src/App.tsx
git commit -m "feat(web): add shimmer loading skeletons for card grids"
```

---

## Task 7: Mobile responsive polish

**Files:**
- Modify: `web/src/styles/global.css` (add responsive media queries)
- Modify: `web/src/components/TopNav.tsx` (collapse padding on mobile)

Add CSS media queries for mobile breakpoints. TopNav gets tighter padding. Card grids and filter bars get tighter padding on small screens. The detail overlay goes full-width on mobile.

**Step 1: Add responsive styles to `web/src/styles/global.css`**

Append after the keyframes:

```css
/* Mobile responsive */
@media (max-width: 640px) {
  .map-container {
    margin: 0 0.75rem !important;
    height: 400px !important;
  }
}
```

Note: Most responsiveness comes from the existing CSS Grid `auto-fill` in CardGrid, which naturally reflows. The inline styles with `rem` units also scale well. The main additions are tighter padding at mobile widths.

**Step 2: Update `web/src/components/TopNav.tsx` for mobile**

Reduce gap and padding on small screens by using a CSS class approach. Since we use inline styles, we'll use a simple width-based approach with a media query in global.css instead.

Add to `web/src/styles/global.css`:

```css
@media (max-width: 640px) {
  nav {
    padding-left: 0.75rem !important;
    padding-right: 0.75rem !important;
    gap: 0.75rem !important;
  }
}
```

**Step 3: Verify build succeeds**

```bash
cd /Users/jsvana/projects/cw-swl/web && npm run build
```

**Step 4: Commit**

```bash
git add web/src/styles/global.css
git commit -m "feat(web): add mobile responsive CSS for navigation and map"
```

---

## Task 8: Spots and Search tab stubs

**Files:**
- Modify: `web/src/App.tsx`
- Modify: `web/src/components/TopNav.tsx`

Add "Spots" and "Search" tabs to TopNav. They render simple placeholder content with a "Coming soon" message. This establishes the navigation structure for future phases.

**Step 1: Update TopNav tab type and rendering**

Modify `web/src/components/TopNav.tsx`:

Change the interface and tab list:

```tsx
interface TopNavProps {
  activeTab: 'air' | 'sdrs' | 'spots' | 'search';
  onTabChange: (tab: 'air' | 'sdrs' | 'spots' | 'search') => void;
  hasLive: boolean;
}
```

Update the tab labels map:

```tsx
const TAB_LABELS: Record<string, string> = {
  air: 'On the Air',
  sdrs: 'SDRs',
  spots: 'Spots',
  search: 'Search',
};
```

Update the tab rendering to use all four tabs:

```tsx
{(['air', 'sdrs', 'spots', 'search'] as const).map((tab) => (
  <button
    key={tab}
    onClick={() => onTabChange(tab)}
    style={{
      background:
        activeTab === tab ? tokens.color.accentLight : 'transparent',
      color:
        activeTab === tab
          ? tokens.color.accent
          : tokens.color.textSecondary,
      border: 'none',
      borderRadius: tokens.radius.sm,
      padding: '0.375rem 0.75rem',
      fontSize: '0.8125rem',
      fontWeight: 500,
      cursor: 'pointer',
      fontFamily: 'inherit',
      transition: 'background 0.15s, color 0.15s',
    }}
  >
    {TAB_LABELS[tab]}
  </button>
))}
```

**Step 2: Update App.tsx**

Update the `activeTab` state type to include the new tabs:

```tsx
const [activeTab, setActiveTab] = useState<'air' | 'sdrs' | 'spots' | 'search'>('air');
```

Add stub content for Spots and Search tabs after the SDRs tab block:

```tsx
{activeTab === 'spots' && (
  <>
    <PageHeader title="Spots" subtitle="Live POTA + RBN spots" />
    <div
      style={{
        textAlign: 'center',
        padding: '3rem 1.5rem',
        color: tokens.color.textTertiary,
        fontSize: '0.875rem',
      }}
    >
      Raw spot feed coming soon. For now, spot data enriches activation cards on the On the Air tab.
    </div>
  </>
)}

{activeTab === 'search' && (
  <>
    <PageHeader title="Search" subtitle="Find callsigns, parks, and frequencies" />
    <div
      style={{
        textAlign: 'center',
        padding: '3rem 1.5rem',
        color: tokens.color.textTertiary,
        fontSize: '0.875rem',
      }}
    >
      Search coming soon.
    </div>
  </>
)}
```

**Step 3: Verify TypeScript compiles and build succeeds**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit && npm run build
```

**Step 4: Commit**

```bash
git add web/src/App.tsx web/src/components/TopNav.tsx
git commit -m "feat(web): add Spots and Search tab stubs to navigation"
```

---

## Task 9: Integration test + docs update

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
| `web/src/components/ViewToggle.tsx` | List/Map view segmented control |
| `web/src/components/ActivationMap.tsx` | Leaflet map with band-colored activation markers |
| `web/src/components/MapLegend.tsx` | Frosted glass band color legend for map |
| `web/src/components/CardSkeleton.tsx` | Shimmer loading skeleton for card grids |
```

Add the Phase 4 plan to the Documentation section:

```markdown
| `docs/plans/2026-02-21-web-ui-phase4.md` | Phase 4 implementation plan (map view + polish) |
```

**Step 4: Commit**

```bash
git add docs/FILE_INDEX.md
git commit -m "docs: add Phase 4 web files to FILE_INDEX.md"
```

---

## Summary

| Task | What | Files | Key |
|------|------|-------|-----|
| 1 | Install Leaflet deps | 1 modify | react-leaflet v4, leaflet, @types/leaflet |
| 2 | ViewToggle | 1 create | List/Map segmented control |
| 3 | MapLegend | 1 create | Frosted glass band legend |
| 4 | ActivationMap | 1 create, 1 modify | Leaflet dark tiles, band markers, SDR markers |
| 5 | Wire map into App | 2 modify | ViewToggle in FilterBar, map/list switch |
| 6 | Loading skeletons | 1 create, 2 modify | Shimmer cards during loading |
| 7 | Mobile responsive | 1 modify | Nav + map media queries |
| 8 | Tab stubs | 2 modify | Spots + Search placeholders |
| 9 | Integration test + docs | 1 modify | Quality gate + FILE_INDEX |

**Total: 4 new files, 6 modified files, 9 commits. 0 backend changes. 1 new npm dependency (react-leaflet + leaflet).**
