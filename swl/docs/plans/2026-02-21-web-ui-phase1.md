# Web UI Phase 1: Static Shell + SDR List — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Serve a React + TypeScript SPA from the axum binary that renders real SDR data from the existing API.

**Architecture:** Vite + React + TypeScript project in `web/`. The axum server serves `web/dist/` as static files with an SPA fallback (all non-API, non-asset routes return `index.html`). During development, Vite runs on `:5173` and proxies `/api` to the axum server. CORS middleware on axum allows the dev origin.

**Tech Stack:** React 18, TypeScript, Vite, Zustand (state), DM Sans + JetBrains Mono (fonts via Google Fonts CDN)

**Design Reference:** `docs/plans/2026-02-21-web-ui-design.md` — design tokens, component specs, and data flow are defined there.

---

## Task 1: Scaffold Vite + React + TypeScript project

**Files:**
- Create: `web/package.json`
- Create: `web/tsconfig.json`
- Create: `web/tsconfig.node.json`
- Create: `web/vite.config.ts`
- Create: `web/index.html`
- Create: `web/src/main.tsx`
- Create: `web/src/App.tsx`
- Create: `web/src/vite-env.d.ts`
- Create: `web/.gitignore`

**Step 1: Create `web/` directory and init project**

```bash
cd /Users/jsvana/projects/cw-swl
mkdir -p web/src
```

**Step 2: Create `web/package.json`**

```json
{
  "name": "cw-swl-web",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "lint": "tsc --noEmit"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "zustand": "^5.0.3"
  },
  "devDependencies": {
    "@types/react": "^18.3.18",
    "@types/react-dom": "^18.3.5",
    "@vitejs/plugin-react": "^4.3.4",
    "typescript": "~5.7.0",
    "vite": "^6.1.0"
  }
}
```

**Step 3: Create `web/vite.config.ts`**

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
});
```

**Step 4: Create `web/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true
  },
  "include": ["src"]
}
```

**Step 5: Create `web/tsconfig.node.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["vite.config.ts"]
}
```

**Step 6: Create `web/index.html`**

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>CW-SWL</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap"
      rel="stylesheet"
    />
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

**Step 7: Create `web/src/vite-env.d.ts`**

```ts
/// <reference types="vite/client" />
```

**Step 8: Create `web/src/main.tsx`**

```tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';
import './styles/global.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
```

**Step 9: Create `web/src/App.tsx`**

```tsx
export function App() {
  return (
    <div style={{ color: '#ededea', padding: '2rem' }}>
      <h1>CW-SWL</h1>
      <p>Loading...</p>
    </div>
  );
}
```

**Step 10: Create `web/.gitignore`**

```
node_modules/
dist/
```

**Step 11: Install dependencies**

```bash
cd /Users/jsvana/projects/cw-swl/web && npm install
```

**Step 12: Verify dev server starts**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx vite --host 127.0.0.1 &
sleep 3
curl -s http://127.0.0.1:5173 | head -20
kill %1 2>/dev/null
```

Expected: HTML with `<div id="root">`.

**Step 13: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

Expected: No errors.

**Step 14: Commit**

```bash
git add web/
git commit -m "feat(web): scaffold Vite + React + TypeScript project"
```

---

## Task 2: Design tokens + global CSS

**Files:**
- Create: `web/src/styles/tokens.ts`
- Create: `web/src/styles/global.css`

**Step 1: Create `web/src/styles/tokens.ts`**

Copy the design tokens from `docs/plans/2026-02-21-web-ui-design.md` exactly:

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
    '160m': '#a78bfa',
    '80m': '#818cf8',
    '40m': '#fbbf24',
    '30m': '#a3e635',
    '20m': '#38bdf8',
    '17m': '#22d3ee',
    '15m': '#34d399',
    '12m': '#fb923c',
    '10m': '#f87171',
  } as Record<string, string>,
  radius: { sm: '8px', md: '14px', lg: '20px' },
  shadow: {
    card: '0 1px 4px rgba(0,0,0,0.2), 0 0 0 1px rgba(255,255,255,0.05)',
    cardHover:
      '0 6px 24px rgba(0,0,0,0.35), 0 0 0 1px rgba(255,255,255,0.08)',
  },
  font: {
    sans: "'DM Sans', -apple-system, BlinkMacSystemFont, sans-serif",
    mono: "'JetBrains Mono', 'SF Mono', monospace",
  },
} as const;
```

**Step 2: Create `web/src/styles/global.css`**

```css
*,
*::before,
*::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

html {
  font-size: 16px;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

body {
  font-family: 'DM Sans', -apple-system, BlinkMacSystemFont, sans-serif;
  background: #25252d;
  color: #ededea;
  min-height: 100vh;
}

code, pre, .mono {
  font-family: 'JetBrains Mono', 'SF Mono', monospace;
}

a {
  color: #6fb1f7;
  text-decoration: none;
}
a:hover {
  text-decoration: underline;
}
```

**Step 3: Verify build**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 4: Commit**

```bash
git add web/src/styles/
git commit -m "feat(web): add design tokens and global CSS"
```

---

## Task 3: API types + SDR data hook

**Files:**
- Create: `web/src/api/types.ts`
- Create: `web/src/api/client.ts`
- Create: `web/src/hooks/useSdrs.ts`

**Step 1: Create `web/src/api/types.ts`**

Types matching the existing Rust API responses (`SdrInfo`, `KiwiStatus`, `SdrCapabilities`, `HealthResponse`):

```ts
export interface SdrCapabilities {
  sample_rates: number[];
  freq_range: [number, number];
  max_bandwidth: number;
  antennas: string[];
  has_agc: boolean;
}

export interface KiwiStatus {
  users?: number;
  users_max?: number;
  grid?: string;
  snr?: string;
  antenna?: string;
  location?: string;
  lat?: number;
  lon?: number;
  offline?: boolean;
}

export interface SdrInfo {
  id: string;
  driver: string;
  label?: string;
  serial?: string;
  capabilities: SdrCapabilities;
  kiwi_status?: KiwiStatus;
}

export interface SdrListResponse {
  sdrs: SdrInfo[];
}

export interface HealthResponse {
  status: string;
  version: string;
}
```

**Step 2: Create `web/src/api/client.ts`**

```ts
import type { SdrListResponse, HealthResponse } from './types';

const BASE = '/api/v1';

async function get<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) {
    throw new Error(`API ${res.status}: ${path}`);
  }
  return res.json() as Promise<T>;
}

export const api = {
  health: () => get<HealthResponse>('/health'),
  sdrs: () => get<SdrListResponse>('/sdrs'),
};
```

**Step 3: Create `web/src/hooks/useSdrs.ts`**

Simple polling hook using Zustand:

```ts
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
```

**Step 4: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 5: Commit**

```bash
git add web/src/api/ web/src/hooks/
git commit -m "feat(web): add API types, client, and SDR polling hook"
```

---

## Task 4: TopNav component

**Files:**
- Create: `web/src/components/TopNav.tsx`

**Step 1: Create `web/src/components/TopNav.tsx`**

Frosted glass nav bar. Tabs: "On the Air", "SDRs". Brand dot (green when any SDR is active). "On the Air" tab is a placeholder for Phase 2.

```tsx
import { tokens } from '../styles/tokens';

interface TopNavProps {
  activeTab: 'air' | 'sdrs';
  onTabChange: (tab: 'air' | 'sdrs') => void;
  hasLive: boolean;
}

export function TopNav({ activeTab, onTabChange, hasLive }: TopNavProps) {
  return (
    <nav
      style={{
        position: 'sticky',
        top: 0,
        zIndex: 100,
        display: 'flex',
        alignItems: 'center',
        gap: '1.5rem',
        padding: '0 1.5rem',
        height: '56px',
        background: 'rgba(37,37,45,0.8)',
        backdropFilter: 'blur(20px) saturate(180%)',
        WebkitBackdropFilter: 'blur(20px) saturate(180%)',
        borderBottom: `1px solid ${tokens.color.border}`,
      }}
    >
      {/* Brand */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '0.5rem',
          fontWeight: 700,
          fontSize: '1rem',
          letterSpacing: '-0.01em',
        }}
      >
        <span
          style={{
            width: 7,
            height: 7,
            borderRadius: '50%',
            background: hasLive ? tokens.color.liveGreen : tokens.color.textTertiary,
            boxShadow: hasLive
              ? `0 0 6px ${tokens.color.liveGreen}`
              : 'none',
            animation: hasLive ? 'pulse 2s ease-in-out infinite' : 'none',
          }}
        />
        CW-SWL
      </div>

      {/* Tabs */}
      <div style={{ display: 'flex', gap: '0.25rem' }}>
        {(['air', 'sdrs'] as const).map((tab) => (
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
            {tab === 'air' ? 'On the Air' : 'SDRs'}
          </button>
        ))}
      </div>
    </nav>
  );
}
```

**Step 2: Add pulse keyframe to `global.css`**

Append to `web/src/styles/global.css`:

```css
@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}
```

**Step 3: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 4: Commit**

```bash
git add web/src/components/ web/src/styles/global.css
git commit -m "feat(web): add TopNav component with frosted glass effect"
```

---

## Task 5: SDRCard + CardGrid components

**Files:**
- Create: `web/src/components/SDRCard.tsx`
- Create: `web/src/components/CardGrid.tsx`
- Create: `web/src/components/StatusDot.tsx`

**Step 1: Create `web/src/components/StatusDot.tsx`**

```tsx
import { tokens } from '../styles/tokens';

interface StatusDotProps {
  status: 'online' | 'active' | 'offline';
}

export function StatusDot({ status }: StatusDotProps) {
  const color =
    status === 'offline'
      ? tokens.color.textTertiary
      : status === 'active'
        ? tokens.color.liveGreen
        : tokens.color.accent;

  return (
    <span
      style={{
        display: 'inline-block',
        width: 8,
        height: 8,
        borderRadius: '50%',
        background: color,
        boxShadow: status === 'active' ? `0 0 6px ${color}` : 'none',
        animation: status === 'active' ? 'pulse 2s ease-in-out infinite' : 'none',
      }}
    />
  );
}
```

**Step 2: Create `web/src/components/SDRCard.tsx`**

```tsx
import { tokens } from '../styles/tokens';
import { StatusDot } from './StatusDot';
import type { SdrInfo } from '../api/types';

interface SDRCardProps {
  sdr: SdrInfo;
}

function getSdrStatus(sdr: SdrInfo): 'online' | 'active' | 'offline' {
  const ks = sdr.kiwi_status;
  if (!ks || ks.offline) return 'offline';
  if (ks.users && ks.users > 0) return 'active';
  return 'online';
}

export function SDRCard({ sdr }: SDRCardProps) {
  const ks = sdr.kiwi_status;
  const status = getSdrStatus(sdr);
  const slotsUsed = ks?.users ?? 0;
  const slotsTotal = ks?.users_max ?? 0;
  const dimmed = status === 'offline' || slotsUsed >= slotsTotal;

  return (
    <div
      style={{
        background: tokens.color.surface,
        borderRadius: tokens.radius.md,
        padding: '1rem 1.125rem',
        boxShadow: tokens.shadow.card,
        opacity: dimmed ? 0.55 : 1,
        transition: 'box-shadow 0.2s, opacity 0.2s',
        cursor: 'pointer',
        display: 'flex',
        flexDirection: 'column',
        gap: '0.625rem',
      }}
      onMouseEnter={(e) => {
        if (!dimmed) e.currentTarget.style.boxShadow = tokens.shadow.cardHover;
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.boxShadow = tokens.shadow.card;
      }}
    >
      {/* Header row */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <StatusDot status={status} />
          <span
            style={{
              fontWeight: 600,
              fontSize: '0.9375rem',
              color: tokens.color.textPrimary,
            }}
          >
            {sdr.label || sdr.id}
          </span>
        </div>
        <span
          style={{
            fontSize: '0.75rem',
            color: tokens.color.textTertiary,
            fontFamily: tokens.font.mono,
          }}
        >
          {sdr.driver}
        </span>
      </div>

      {/* Location */}
      {ks?.location && (
        <div
          style={{
            fontSize: '0.8125rem',
            color: tokens.color.textSecondary,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
          }}
        >
          {ks.location}
        </div>
      )}

      {/* Footer row */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          fontSize: '0.75rem',
          color: tokens.color.textTertiary,
        }}
      >
        {ks?.grid && (
          <span style={{ fontFamily: tokens.font.mono }}>{ks.grid}</span>
        )}
        {slotsTotal > 0 && (
          <span style={{ fontFamily: tokens.font.mono }}>
            {slotsUsed} / {slotsTotal} slots
          </span>
        )}
      </div>
    </div>
  );
}
```

**Step 3: Create `web/src/components/CardGrid.tsx`**

```tsx
import type { CSSProperties, ReactNode } from 'react';

interface CardGridProps {
  minWidth?: string;
  children: ReactNode;
}

export function CardGrid({ minWidth = '280px', children }: CardGridProps) {
  const style: CSSProperties = {
    display: 'grid',
    gridTemplateColumns: `repeat(auto-fill, minmax(${minWidth}, 1fr))`,
    gap: '0.75rem',
    padding: '0 1.5rem',
  };

  return <div style={style}>{children}</div>;
}
```

**Step 4: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 5: Commit**

```bash
git add web/src/components/
git commit -m "feat(web): add SDRCard, StatusDot, and CardGrid components"
```

---

## Task 6: PageHeader + wire up App

**Files:**
- Create: `web/src/components/PageHeader.tsx`
- Modify: `web/src/App.tsx`

**Step 1: Create `web/src/components/PageHeader.tsx`**

```tsx
import { tokens } from '../styles/tokens';

interface PageHeaderProps {
  title: string;
  subtitle?: string;
}

export function PageHeader({ title, subtitle }: PageHeaderProps) {
  return (
    <div style={{ padding: '1.5rem 1.5rem 1rem' }}>
      <h1
        style={{
          fontSize: '1.5rem',
          fontWeight: 700,
          color: tokens.color.textPrimary,
          letterSpacing: '-0.02em',
        }}
      >
        {title}
      </h1>
      {subtitle && (
        <p
          style={{
            fontSize: '0.875rem',
            color: tokens.color.textSecondary,
            marginTop: '0.25rem',
          }}
        >
          {subtitle}
        </p>
      )}
    </div>
  );
}
```

**Step 2: Rewrite `web/src/App.tsx`**

Wire TopNav, PageHeader, CardGrid, SDRCard, and useSdrs together:

```tsx
import { useState } from 'react';
import { TopNav } from './components/TopNav';
import { PageHeader } from './components/PageHeader';
import { CardGrid } from './components/CardGrid';
import { SDRCard } from './components/SDRCard';
import { useSdrs } from './hooks/useSdrs';
import { tokens } from './styles/tokens';

export function App() {
  const [activeTab, setActiveTab] = useState<'air' | 'sdrs'>('sdrs');
  const { sdrs, loading, error } = useSdrs();

  const hasLive = sdrs.some(
    (s) =>
      s.kiwi_status &&
      !s.kiwi_status.offline &&
      s.kiwi_status.users !== undefined &&
      s.kiwi_status.users > 0,
  );

  return (
    <div style={{ minHeight: '100vh', background: tokens.color.bg }}>
      <TopNav
        activeTab={activeTab}
        onTabChange={setActiveTab}
        hasLive={hasLive}
      />

      {activeTab === 'sdrs' && (
        <>
          <PageHeader
            title="SDRs"
            subtitle={
              loading
                ? 'Loading...'
                : `${sdrs.length} receiver${sdrs.length !== 1 ? 's' : ''}`
            }
          />
          {error && (
            <div
              style={{
                padding: '0.75rem 1.5rem',
                color: '#f87171',
                fontSize: '0.875rem',
              }}
            >
              Failed to load SDRs: {error}
            </div>
          )}
          <CardGrid>
            {sdrs.map((sdr) => (
              <SDRCard key={sdr.id} sdr={sdr} />
            ))}
          </CardGrid>
        </>
      )}

      {activeTab === 'air' && (
        <PageHeader
          title="On the Air"
          subtitle="Coming in Phase 2"
        />
      )}
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

Expected: `dist/` directory created with `index.html` and `assets/`.

**Step 5: Commit**

```bash
git add web/src/
git commit -m "feat(web): wire up App with TopNav, PageHeader, SDRCard grid"
```

---

## Task 7: Serve SPA from axum

**Files:**
- Modify: `sdr-server/Cargo.toml` — add `tower-http` with `fs` feature
- Modify: `sdr-core/src/api/mod.rs` — add SPA fallback and static file serving
- Modify: `sdr-server/src/main.rs` — pass web dir path

**Step 1: Add `tower-http` fs feature to `sdr-server/Cargo.toml`**

The workspace already has `tower-http` with `cors` and `trace`. We need to add `fs` for `ServeDir`:

In `Cargo.toml` (workspace root), update the tower-http line:

```toml
tower-http = { version = "0.6", features = ["cors", "trace", "fs"] }
```

**Step 2: Add static serving + SPA fallback to `sdr-core/src/api/mod.rs`**

Add CORS middleware (for Vite dev server) and SPA fallback route after all API routes:

```rust
// New imports at the top:
use axum::response::{Html, IntoResponse};
use tower_http::cors::{Any, CorsLayer};
use tower_http::services::ServeDir;

// Add to AppState:
pub struct AppState {
    pub registry: Arc<SdrRegistry>,
    pub mux: Arc<CaptureMultiplexer>,
    pub recording_engine: Arc<RecordingEngine>,
    pub transcription_engine: Arc<TranscriptionEngine>,
    pub db: Arc<Mutex<Database>>,
    pub web_dir: Option<std::path::PathBuf>,
}
```

Update `router()` to accept web_dir and add static serving:

```rust
pub fn router(state: Arc<AppState>) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let mut app = Router::new()
        // ... all existing API routes unchanged ...
        .with_state(state.clone())
        .layer(cors);

    // Serve SPA static files if web dir exists
    if let Some(ref web_dir) = state.web_dir {
        let dist_dir = web_dir.join("dist");
        if dist_dir.exists() {
            app = app
                .nest_service("/assets", ServeDir::new(dist_dir.join("assets")))
                .fallback(spa_fallback);
        }
    }

    app
}

async fn spa_fallback(
    State(state): State<Arc<AppState>>,
    req: axum::http::Request<axum::body::Body>,
) -> impl IntoResponse {
    // Don't intercept /api requests — return 404 for unknown API paths
    if req.uri().path().starts_with("/api/") {
        return (axum::http::StatusCode::NOT_FOUND, Html(String::new())).into_response();
    }

    if let Some(ref web_dir) = state.web_dir {
        let index = web_dir.join("dist/index.html");
        if let Ok(html) = tokio::fs::read_to_string(&index).await {
            return Html(html).into_response();
        }
    }

    (axum::http::StatusCode::NOT_FOUND, Html("Not found".to_string())).into_response()
}
```

**Step 3: Update `sdr-server/src/main.rs`**

Pass `web_dir` when constructing `AppState`:

```rust
let state = Arc::new(AppState {
    registry: Arc::clone(&registry),
    mux: Arc::clone(&mux),
    recording_engine: Arc::clone(&recording_engine),
    transcription_engine,
    db: Arc::clone(&db),
    web_dir: Some(std::path::PathBuf::from("web")),
});
```

**Step 4: Verify Rust compiles**

```bash
cd /Users/jsvana/projects/cw-swl && cargo build
```

**Step 5: Verify tests pass**

```bash
cd /Users/jsvana/projects/cw-swl && cargo test
```

**Step 6: Commit**

```bash
git add Cargo.toml sdr-server/Cargo.toml sdr-core/src/api/mod.rs sdr-server/src/main.rs
git commit -m "feat(web): serve SPA from axum with static files and CORS"
```

---

## Task 8: Integration smoke test

**Goal:** Verify the full stack works: axum serves the built SPA which fetches real SDR data.

**Step 1: Build the frontend**

```bash
cd /Users/jsvana/projects/cw-swl/web && npm run build
```

**Step 2: Run the full quality gate**

```bash
cd /Users/jsvana/projects/cw-swl && cargo fmt --check && cargo clippy -- -W clippy::all && cargo test
```

**Step 3: Manual verification**

Start the server with an example config and verify in a browser:

```bash
cd /Users/jsvana/projects/cw-swl && cargo run -- examples/config.toml
# In another terminal: curl http://localhost:3000
# Expected: HTML with <div id="root"> and React bundle loaded
# Visit http://localhost:3000 in browser — should show dark UI with SDR cards
```

**Step 4: Update FILE_INDEX.md**

Add the `web/` entries to `docs/FILE_INDEX.md`:

```markdown
## web/ (Frontend SPA)

| File | Description |
|------|-------------|
| `web/package.json` | Frontend dependencies and scripts |
| `web/vite.config.ts` | Vite build config with API proxy for dev |
| `web/index.html` | SPA entry point with font loading |
| `web/src/main.tsx` | React root mount |
| `web/src/App.tsx` | Main app — tab routing, SDR grid |
| `web/src/styles/tokens.ts` | Design tokens (colors, fonts, shadows, radii) |
| `web/src/styles/global.css` | Global CSS reset and base styles |
| `web/src/api/types.ts` | TypeScript types matching Rust API responses |
| `web/src/api/client.ts` | Fetch wrapper for API endpoints |
| `web/src/hooks/useSdrs.ts` | Zustand store + polling hook for SDR data |
| `web/src/components/TopNav.tsx` | Frosted glass navigation bar |
| `web/src/components/PageHeader.tsx` | Page title + subtitle |
| `web/src/components/CardGrid.tsx` | Responsive auto-fill grid layout |
| `web/src/components/SDRCard.tsx` | SDR status card |
| `web/src/components/StatusDot.tsx` | Colored status indicator dot |
```

**Step 5: Commit**

```bash
git add docs/FILE_INDEX.md
git commit -m "docs: add web/ entries to FILE_INDEX.md"
```

---

## Summary

| Task | What | Files | Est. |
|------|------|-------|------|
| 1 | Scaffold Vite project | 9 create | 5 min |
| 2 | Design tokens + global CSS | 2 create | 3 min |
| 3 | API types + SDR hook | 3 create | 3 min |
| 4 | TopNav component | 1 create, 1 modify | 3 min |
| 5 | SDRCard + CardGrid | 3 create | 5 min |
| 6 | PageHeader + wire App | 1 create, 1 modify | 3 min |
| 7 | Serve SPA from axum | 3 modify | 5 min |
| 8 | Integration test + docs | 1 modify | 3 min |

**Total: 15 new files, 4 modified files, 8 commits.**
