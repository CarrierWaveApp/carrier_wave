# Web UI Phase 3: Activation Detail Overlay — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Click an activation card to open a detail overlay with audio playback, full transcript with semantic highlighting, spot context, and per-SDR source recording quality indicators.

**Architecture:** A modal overlay slides up from the bottom when an activation card is clicked. It fetches the recording detail (segments) on open and composes several sub-components: AudioPlayer (HTML5 `<audio>` with WAV segment streaming), TranscriptView (full text with callsign/prosign highlighting), SpotContext (POTA/RBN attribution), and SourceRecordingList (per-SDR correlation quality). A spectrogram placeholder reserves space for future Canvas-rendered visualization. No backend changes — all data comes from existing API endpoints.

**Tech Stack:** React 18, TypeScript, existing design tokens and inline style pattern, HTML5 Audio API, existing `/api/v1/recordings/{id}` and `/api/v1/recordings/{id}/segments/{num}/audio` endpoints.

**Design Reference:** `docs/plans/2026-02-21-web-ui-design.md` — Phase 3 component specs (DetailOverlay, ActivationDetail, AudioPlayer, TranscriptView, SpotContext, SourceRecordingList, Spectrogram, SectionTitle, QualityBadge).

**Existing code patterns:** Phases 1-2 established inline styles using `tokens`, function components with typed props, Zustand stores with `create<T>()`, and polling via `useEffect` + `setInterval`. Follow the same patterns.

---

## Task 1: SectionTitle and QualityBadge primitives

**Files:**
- Create: `web/src/components/SectionTitle.tsx`
- Create: `web/src/components/QualityBadge.tsx`

These are small reusable primitives used by the detail sub-components.

**Step 1: Create `web/src/components/SectionTitle.tsx`**

A 12px uppercase section label for grouping content in the detail view.

```tsx
import { tokens } from '../styles/tokens';

interface SectionTitleProps {
  children: React.ReactNode;
}

export function SectionTitle({ children }: SectionTitleProps) {
  return (
    <div
      style={{
        fontSize: '0.6875rem',
        fontWeight: 600,
        textTransform: 'uppercase',
        letterSpacing: '0.06em',
        color: tokens.color.textTertiary,
        padding: '0.5rem 0 0.25rem',
      }}
    >
      {children}
    </div>
  );
}
```

**Step 2: Create `web/src/components/QualityBadge.tsx`**

A correlation quality pill: green (r >= 0.6), yellow (0.3-0.6), red (< 0.3 or excluded).

```tsx
interface QualityBadgeProps {
  quality: 'good' | 'fair' | 'excluded';
  label?: string;
}

const QUALITY_COLORS: Record<string, { bg: string; text: string }> = {
  good: { bg: 'rgba(61,220,151,0.15)', text: '#3ddc97' },
  fair: { bg: 'rgba(251,191,36,0.15)', text: '#fbbf24' },
  excluded: { bg: 'rgba(248,113,113,0.15)', text: '#f87171' },
};

export function QualityBadge({ quality, label }: QualityBadgeProps) {
  const colors = QUALITY_COLORS[quality] ?? QUALITY_COLORS.excluded;

  return (
    <span
      style={{
        display: 'inline-block',
        padding: '0.125rem 0.5rem',
        borderRadius: '9999px',
        fontSize: '0.6875rem',
        fontWeight: 600,
        color: colors.text,
        background: colors.bg,
        lineHeight: 1.4,
      }}
    >
      {label ?? quality}
    </span>
  );
}
```

**Step 3: Verify TypeScript compiles**

```bash
cd /Users/jsvana/projects/cw-swl/web && npx tsc --noEmit
```

**Step 4: Commit**

```bash
git add web/src/components/SectionTitle.tsx web/src/components/QualityBadge.tsx
git commit -m "feat(web): add SectionTitle and QualityBadge primitives"
```

---

## Task 2: DetailOverlay modal component

**Files:**
- Create: `web/src/components/DetailOverlay.tsx`
- Modify: `web/src/styles/global.css` (add overlay animations)

The overlay is a modal backdrop with a slide-up panel. Clicking outside or pressing ESC closes it. Body scroll is locked while open.

**Step 1: Create `web/src/components/DetailOverlay.tsx`**

```tsx
import { useEffect, useCallback, type ReactNode } from 'react';
import { tokens } from '../styles/tokens';

interface DetailOverlayProps {
  isOpen: boolean;
  onClose: () => void;
  children: ReactNode;
}

export function DetailOverlay({ isOpen, onClose, children }: DetailOverlayProps) {
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    },
    [onClose],
  );

  useEffect(() => {
    if (isOpen) {
      document.addEventListener('keydown', handleKeyDown);
      document.body.style.overflow = 'hidden';
    }
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
      document.body.style.overflow = '';
    };
  }, [isOpen, handleKeyDown]);

  if (!isOpen) return null;

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 200,
        display: 'flex',
        alignItems: 'flex-end',
        justifyContent: 'center',
      }}
    >
      {/* Backdrop */}
      <div
        onClick={onClose}
        style={{
          position: 'absolute',
          inset: 0,
          background: 'rgba(0,0,0,0.6)',
          backdropFilter: 'blur(4px)',
          WebkitBackdropFilter: 'blur(4px)',
          animation: 'overlayFadeIn 0.2s ease-out',
        }}
      />

      {/* Panel */}
      <div
        style={{
          position: 'relative',
          width: '100%',
          maxWidth: '720px',
          maxHeight: '85vh',
          overflowY: 'auto',
          background: tokens.color.bg,
          borderRadius: `${tokens.radius.lg} ${tokens.radius.lg} 0 0`,
          boxShadow: '0 -4px 32px rgba(0,0,0,0.4)',
          animation: 'overlaySlideUp 0.25s ease-out',
          padding: '1.5rem',
        }}
      >
        {/* Close button */}
        <button
          onClick={onClose}
          style={{
            position: 'absolute',
            top: '1rem',
            right: '1rem',
            background: tokens.color.surface,
            border: 'none',
            borderRadius: '50%',
            width: 32,
            height: 32,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            cursor: 'pointer',
            color: tokens.color.textSecondary,
            fontSize: '1.125rem',
            lineHeight: 1,
          }}
          title="Close"
        >
          ✕
        </button>

        {children}
      </div>
    </div>
  );
}
```

**Step 2: Add overlay animations to `web/src/styles/global.css`**

Append these keyframes after the existing `cardIn` animation:

```css
@keyframes overlayFadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}

@keyframes overlaySlideUp {
  from {
    opacity: 0;
    transform: translateY(24px);
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
git add web/src/components/DetailOverlay.tsx web/src/styles/global.css
git commit -m "feat(web): add DetailOverlay modal with slide-up animation and ESC/click-outside close"
```

---

## Task 3: AudioPlayer component

**Files:**
- Create: `web/src/components/AudioPlayer.tsx`

Plays WAV segments from the API. Uses HTML5 `<audio>` element with play/pause toggle, seek bar, and time display. Loads the first segment's audio URL on mount. For multi-segment recordings, concatenates segment URLs (one at a time — gapless playback is a future enhancement).

The audio URL pattern is: `/api/v1/recordings/{recordingId}/segments/{segmentNumber}/audio`

**Step 1: Create `web/src/components/AudioPlayer.tsx`**

```tsx
import { useRef, useState, useEffect, useCallback } from 'react';
import { tokens } from '../styles/tokens';
import type { SegmentRow } from '../api/types';

interface AudioPlayerProps {
  recordingId: string;
  segments: SegmentRow[];
}

function formatTime(secs: number): string {
  const m = Math.floor(secs / 60);
  const s = Math.floor(secs % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export function AudioPlayer({ recordingId, segments }: AudioPlayerProps) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [playing, setPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [segmentIndex, setSegmentIndex] = useState(0);

  const sorted = [...segments].sort((a, b) => a.segment_number - b.segment_number);
  const currentSegment = sorted[segmentIndex];

  const audioUrl = currentSegment
    ? `/api/v1/recordings/${recordingId}/segments/${currentSegment.segment_number}/audio`
    : undefined;

  // Total duration across all segments
  const totalDuration = sorted.reduce((sum, s) => sum + s.duration_secs, 0);

  // Cumulative offset for current segment
  const segmentOffset = sorted
    .slice(0, segmentIndex)
    .reduce((sum, s) => sum + s.duration_secs, 0);

  const togglePlay = useCallback(() => {
    const audio = audioRef.current;
    if (!audio) return;
    if (playing) {
      audio.pause();
    } else {
      audio.play().catch(() => {});
    }
  }, [playing]);

  const handleTimeUpdate = useCallback(() => {
    const audio = audioRef.current;
    if (audio) {
      setCurrentTime(segmentOffset + audio.currentTime);
    }
  }, [segmentOffset]);

  const handleEnded = useCallback(() => {
    if (segmentIndex < sorted.length - 1) {
      setSegmentIndex((i) => i + 1);
    } else {
      setPlaying(false);
      setCurrentTime(0);
      setSegmentIndex(0);
    }
  }, [segmentIndex, sorted.length]);

  // Auto-play next segment
  useEffect(() => {
    const audio = audioRef.current;
    if (audio && playing && audioUrl) {
      audio.load();
      audio.play().catch(() => {});
    }
  }, [segmentIndex]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleSeek = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const seekTime = parseFloat(e.target.value);
      // Find which segment this falls into
      let cumulative = 0;
      for (let i = 0; i < sorted.length; i++) {
        if (seekTime < cumulative + sorted[i]!.duration_secs) {
          setSegmentIndex(i);
          const audio = audioRef.current;
          if (audio) {
            audio.currentTime = seekTime - cumulative;
          }
          setCurrentTime(seekTime);
          return;
        }
        cumulative += sorted[i]!.duration_secs;
      }
    },
    [sorted],
  );

  if (sorted.length === 0) {
    return (
      <div style={{ fontSize: '0.8125rem', color: tokens.color.textTertiary }}>
        No audio segments available.
      </div>
    );
  }

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: '0.5rem',
        background: tokens.color.surface,
        borderRadius: tokens.radius.sm,
        padding: '0.75rem 1rem',
      }}
    >
      <audio
        ref={audioRef}
        src={audioUrl}
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
        onTimeUpdate={handleTimeUpdate}
        onLoadedMetadata={() => {
          if (audioRef.current) setDuration(audioRef.current.duration);
        }}
        onEnded={handleEnded}
      />

      <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
        {/* Play/Pause button */}
        <button
          onClick={togglePlay}
          style={{
            background: tokens.color.accent,
            border: 'none',
            borderRadius: '50%',
            width: 36,
            height: 36,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            cursor: 'pointer',
            color: '#fff',
            fontSize: '1rem',
            flexShrink: 0,
          }}
          title={playing ? 'Pause' : 'Play'}
        >
          {playing ? '⏸' : '▶'}
        </button>

        {/* Time + seek */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: '0.25rem' }}>
          <input
            type="range"
            min={0}
            max={totalDuration}
            step={0.1}
            value={currentTime}
            onChange={handleSeek}
            style={{
              width: '100%',
              accentColor: tokens.color.accent,
              cursor: 'pointer',
            }}
          />
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              fontSize: '0.6875rem',
              fontFamily: tokens.font.mono,
              color: tokens.color.textTertiary,
            }}
          >
            <span>{formatTime(currentTime)}</span>
            <span>{formatTime(totalDuration)}</span>
          </div>
        </div>
      </div>

      {sorted.length > 1 && (
        <div
          style={{
            fontSize: '0.6875rem',
            color: tokens.color.textTertiary,
          }}
        >
          Segment {segmentIndex + 1} of {sorted.length}
        </div>
      )}
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
git add web/src/components/AudioPlayer.tsx
git commit -m "feat(web): add AudioPlayer component with multi-segment WAV playback"
```

---

## Task 4: TranscriptView component

**Files:**
- Create: `web/src/components/TranscriptView.tsx`

Displays the full CW transcript with semantic highlighting. Callsigns are accent blue, prosigns (BT, SK, AR, KN, etc.) are gold. Words are inline spans for future click-to-highlight.

**Step 1: Create `web/src/components/TranscriptView.tsx`**

```tsx
import { tokens } from '../styles/tokens';

interface TranscriptViewProps {
  text: string;
  wpm?: number;
}

const CALLSIGN_RE = /\b([A-Z]{1,2}\d[A-Z0-9]*[A-Z])\b/g;
const PROSIGNS = new Set(['BT', 'SK', 'AR', 'KN', 'BK', 'CL', 'SN', 'HH']);

interface Token {
  text: string;
  type: 'callsign' | 'prosign' | 'text';
}

function tokenize(text: string): Token[] {
  const tokens: Token[] = [];
  const words = text.split(/(\s+)/);

  for (const word of words) {
    if (/^\s+$/.test(word)) {
      tokens.push({ text: word, type: 'text' });
      continue;
    }

    if (PROSIGNS.has(word)) {
      tokens.push({ text: word, type: 'prosign' });
    } else if (CALLSIGN_RE.test(word)) {
      CALLSIGN_RE.lastIndex = 0; // reset global regex
      tokens.push({ text: word, type: 'callsign' });
    } else {
      tokens.push({ text: word, type: 'text' });
    }
  }

  return tokens;
}

const TOKEN_STYLES: Record<string, React.CSSProperties> = {
  callsign: { color: '#6fb1f7', fontWeight: 600 },
  prosign: { color: '#fbbf24', fontWeight: 600 },
  text: {},
};

export function TranscriptView({ text, wpm }: TranscriptViewProps) {
  const toks = tokenize(text);

  return (
    <div
      style={{
        background: tokens.color.surface,
        borderRadius: tokens.radius.sm,
        padding: '0.75rem 1rem',
      }}
    >
      {wpm && (
        <div
          style={{
            fontSize: '0.6875rem',
            color: tokens.color.textTertiary,
            marginBottom: '0.5rem',
          }}
        >
          {wpm.toFixed(0)} WPM
        </div>
      )}

      <div
        style={{
          fontFamily: tokens.font.mono,
          fontSize: '0.875rem',
          lineHeight: 1.7,
          color: tokens.color.textPrimary,
          wordBreak: 'break-word',
        }}
      >
        {toks.map((tok, i) => (
          <span key={i} style={TOKEN_STYLES[tok.type]}>
            {tok.text}
          </span>
        ))}
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
git add web/src/components/TranscriptView.tsx
git commit -m "feat(web): add TranscriptView with callsign and prosign highlighting"
```

---

## Task 5: SpotContext component

**Files:**
- Create: `web/src/components/SpotContext.tsx`

Shows POTA/RBN spot attribution — the source of the spot match, park reference, spotter callsign, and timing.

**Step 1: Create `web/src/components/SpotContext.tsx`**

```tsx
import { tokens } from '../styles/tokens';
import type { PotaSpot, RbnSpot } from '../api/types';

interface SpotContextProps {
  potaSpot?: PotaSpot;
  rbnSpots?: RbnSpot[];
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

export function SpotContext({ potaSpot, rbnSpots }: SpotContextProps) {
  if (!potaSpot && (!rbnSpots || rbnSpots.length === 0)) return null;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
      {potaSpot && (
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '0.5rem',
            background: tokens.color.surface,
            borderRadius: tokens.radius.sm,
            padding: '0.5rem 0.75rem',
            fontSize: '0.8125rem',
          }}
        >
          <span
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: 22,
              height: 22,
              borderRadius: '50%',
              background: 'rgba(61,220,151,0.15)',
              color: '#3ddc97',
              fontSize: '0.6875rem',
              fontWeight: 700,
              flexShrink: 0,
            }}
          >
            P
          </span>
          <div style={{ flex: 1 }}>
            <span style={{ color: tokens.color.accent, fontWeight: 600 }}>
              {potaSpot.reference}
            </span>
            {potaSpot.parkName && (
              <span style={{ color: tokens.color.textSecondary }}>
                {' '}{potaSpot.parkName}
              </span>
            )}
          </div>
          <span style={{ fontSize: '0.6875rem', color: tokens.color.textTertiary }}>
            spotted by {potaSpot.spotter} {timeAgo(potaSpot.spotTime)}
          </span>
        </div>
      )}

      {rbnSpots && rbnSpots.length > 0 && (
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: '0.25rem',
            background: tokens.color.surface,
            borderRadius: tokens.radius.sm,
            padding: '0.5rem 0.75rem',
            fontSize: '0.8125rem',
          }}
        >
          {rbnSpots.slice(0, 3).map((spot, i) => (
            <div
              key={i}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '0.5rem',
              }}
            >
              <span
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  width: 22,
                  height: 22,
                  borderRadius: '50%',
                  background: 'rgba(111,177,247,0.15)',
                  color: '#6fb1f7',
                  fontSize: '0.6875rem',
                  fontWeight: 700,
                  flexShrink: 0,
                }}
              >
                R
              </span>
              <span style={{ color: tokens.color.textSecondary, flex: 1 }}>
                {spot.spotter_callsign}
              </span>
              <span
                style={{
                  fontFamily: "'JetBrains Mono', monospace",
                  color: tokens.color.textTertiary,
                  fontSize: '0.6875rem',
                }}
              >
                {spot.snr} dB &middot; {spot.wpm} WPM
              </span>
            </div>
          ))}
        </div>
      )}
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
git add web/src/components/SpotContext.tsx
git commit -m "feat(web): add SpotContext component for POTA and RBN spot attribution"
```

---

## Task 6: SourceRecordingList component

**Files:**
- Create: `web/src/components/SourceRecordingList.tsx`

Shows per-SDR source recordings with status and quality indicators. Each source recording shows the SDR ID, status, duration, and a quality badge. Quality is not yet computed by the backend (no correlation data in the API response), so we show status-based badges for now: "combined" recordings get green "included", stopped ones get yellow "source", and active ones get green "live".

**Step 1: Create `web/src/components/SourceRecordingList.tsx`**

```tsx
import { tokens } from '../styles/tokens';
import { QualityBadge } from './QualityBadge';
import type { RecordingRow } from '../api/types';

interface SourceRecordingListProps {
  recordings: RecordingRow[];
}

function formatDuration(startedAt: string, stoppedAt: string | null): string {
  const start = new Date(startedAt).getTime();
  const end = stoppedAt ? new Date(stoppedAt).getTime() : Date.now();
  const secs = Math.floor((end - start) / 1000);
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function statusToQuality(status: string): 'good' | 'fair' | 'excluded' {
  if (status === 'recording') return 'good';
  if (status === 'combined') return 'good';
  if (status === 'stopped') return 'fair';
  return 'excluded';
}

function statusLabel(status: string): string {
  if (status === 'recording') return 'live';
  if (status === 'combined') return 'combined';
  return status;
}

export function SourceRecordingList({ recordings }: SourceRecordingListProps) {
  // Filter out the combined recording itself — show only individual sources
  const sources = recordings.filter((r) => r.status !== 'combined');

  if (sources.length === 0) return null;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '0.375rem' }}>
      {sources.map((rec) => (
        <div
          key={rec.id}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '0.5rem',
            background: tokens.color.surface,
            borderRadius: tokens.radius.sm,
            padding: '0.5rem 0.75rem',
            fontSize: '0.8125rem',
          }}
        >
          <span
            style={{
              fontFamily: tokens.font.mono,
              color: tokens.color.textSecondary,
              flex: 1,
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}
          >
            {rec.sdr_id}
          </span>
          <span
            style={{
              fontFamily: tokens.font.mono,
              fontSize: '0.6875rem',
              color: tokens.color.textTertiary,
            }}
          >
            {formatDuration(rec.started_at, rec.stopped_at)}
          </span>
          <QualityBadge
            quality={statusToQuality(rec.status)}
            label={statusLabel(rec.status)}
          />
        </div>
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
git add web/src/components/SourceRecordingList.tsx
git commit -m "feat(web): add SourceRecordingList component with per-SDR status badges"
```

---

## Task 7: ActivationDetail composed view + useActivationDetail hook

**Files:**
- Create: `web/src/hooks/useActivationDetail.ts`
- Create: `web/src/components/ActivationDetail.tsx`

ActivationDetail composes all the detail sub-components into a single view. The `useActivationDetail` hook fetches the recording detail (segments) when an activation is selected, and finds matching RBN spots.

**Step 1: Create `web/src/hooks/useActivationDetail.ts`**

```tsx
import { useEffect, useState } from 'react';
import { api } from '../api/client';
import type { RecordingResponse, RbnSpot } from '../api/types';
import type { Activation } from './useActivations';

interface ActivationDetailData {
  recordingDetail: RecordingResponse | null;
  matchingRbnSpots: RbnSpot[];
  loading: boolean;
  error: string | null;
}

export function useActivationDetail(
  activation: Activation | null,
  rbnSpots: RbnSpot[],
): ActivationDetailData {
  const [recordingDetail, setRecordingDetail] = useState<RecordingResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Fetch recording detail (segments) for the best recording
  // Prefer combined recording, fall back to first recording
  const recordingId = activation?.combinedRecordingId ?? activation?.recordings[0]?.id;

  useEffect(() => {
    if (!recordingId) {
      setRecordingDetail(null);
      return;
    }

    setLoading(true);
    setError(null);
    api
      .recording(recordingId)
      .then((data) => {
        setRecordingDetail(data);
        setLoading(false);
      })
      .catch((e) => {
        setError((e as Error).message);
        setLoading(false);
      });
  }, [recordingId]);

  // Find matching RBN spots by callsign + frequency (±1 kHz)
  const matchingRbnSpots = activation
    ? rbnSpots.filter(
        (s) =>
          s.callsign === activation.callsign &&
          Math.abs(s.frequency * 1000 - activation.frequency) <= 1000,
      )
    : [];

  return { recordingDetail, matchingRbnSpots, loading, error };
}
```

**Step 2: Create `web/src/components/ActivationDetail.tsx`**

```tsx
import { tokens } from '../styles/tokens';
import { BandBadge } from './BandBadge';
import { LiveDot } from './LiveDot';
import { SectionTitle } from './SectionTitle';
import { AudioPlayer } from './AudioPlayer';
import { TranscriptView } from './TranscriptView';
import { SpotContext } from './SpotContext';
import { SourceRecordingList } from './SourceRecordingList';
import type { Activation } from '../hooks/useActivations';
import type { RecordingResponse, RbnSpot } from '../api/types';

interface ActivationDetailProps {
  activation: Activation;
  recordingDetail: RecordingResponse | null;
  matchingRbnSpots: RbnSpot[];
  loading: boolean;
  error: string | null;
}

function formatFrequency(hz: number): string {
  return (hz / 1000).toFixed(1);
}

export function ActivationDetail({
  activation,
  recordingDetail,
  matchingRbnSpots,
  loading,
  error,
}: ActivationDetailProps) {
  const {
    callsign,
    frequency,
    band,
    parkRef,
    parkName,
    isLive,
    transcription,
    wpm,
    sdrCount,
    recordings,
    spot,
  } = activation;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
      {/* Header */}
      <div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.25rem' }}>
          {isLive && <LiveDot />}
          <span style={{ fontWeight: 700, fontSize: '1.5rem', color: tokens.color.textPrimary }}>
            {callsign}
          </span>
          <BandBadge band={band} size="md" />
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', fontSize: '0.875rem' }}>
          <span style={{ fontFamily: tokens.font.mono, color: tokens.color.textSecondary }}>
            {formatFrequency(frequency)} kHz
          </span>
          {parkRef && (
            <span style={{ color: tokens.color.accent }}>
              {parkRef}{parkName ? ` — ${parkName}` : ''}
            </span>
          )}
          <span style={{ color: tokens.color.textTertiary }}>
            {sdrCount} SDR{sdrCount !== 1 ? 's' : ''}
          </span>
        </div>
      </div>

      {/* Spectrogram placeholder */}
      <div
        style={{
          height: '80px',
          borderRadius: tokens.radius.sm,
          background: `linear-gradient(180deg, ${tokens.color.surface} 0%, rgba(111,177,247,0.08) 100%)`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: '0.75rem',
          color: tokens.color.textTertiary,
        }}
      >
        Spectrogram — coming soon
      </div>

      {/* Audio */}
      {loading && (
        <div style={{ fontSize: '0.8125rem', color: tokens.color.textTertiary }}>
          Loading audio...
        </div>
      )}
      {error && (
        <div style={{ fontSize: '0.8125rem', color: '#f87171' }}>
          Failed to load recording: {error}
        </div>
      )}
      {recordingDetail && recordingDetail.segments.length > 0 && (
        <>
          <SectionTitle>Audio</SectionTitle>
          <AudioPlayer
            recordingId={recordingDetail.id}
            segments={recordingDetail.segments}
          />
        </>
      )}

      {/* Transcript */}
      {transcription && (
        <>
          <SectionTitle>Transcript</SectionTitle>
          <TranscriptView text={transcription.text} wpm={wpm ?? undefined} />
        </>
      )}

      {/* Spot context */}
      {(spot || matchingRbnSpots.length > 0) && (
        <>
          <SectionTitle>Spots</SectionTitle>
          <SpotContext potaSpot={spot} rbnSpots={matchingRbnSpots} />
        </>
      )}

      {/* Source recordings */}
      {recordings.length > 1 && (
        <>
          <SectionTitle>Source Recordings</SectionTitle>
          <SourceRecordingList recordings={recordings} />
        </>
      )}
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
git add web/src/hooks/useActivationDetail.ts web/src/components/ActivationDetail.tsx
git commit -m "feat(web): add ActivationDetail composed view with audio, transcript, spots, and sources"
```

---

## Task 8: Wire detail overlay into App

**Files:**
- Modify: `web/src/App.tsx`

Connect the ActivationCard click to open the DetailOverlay with ActivationDetail inside. Add state for the selected activation ID. Pass `rbnSpots` from useActivations to the detail hook.

**Step 1: Update `web/src/App.tsx`**

Import the new components and add selection state. The overlay opens when an activation is selected and closes on backdrop click, ESC, or close button.

Replace the current `web/src/App.tsx` with:

```tsx
import { useState, useMemo } from 'react';
import { TopNav } from './components/TopNav';
import { PageHeader } from './components/PageHeader';
import { CardGrid } from './components/CardGrid';
import { SDRCard } from './components/SDRCard';
import { ActivationCard } from './components/ActivationCard';
import { FilterBar } from './components/FilterBar';
import { DetailOverlay } from './components/DetailOverlay';
import { ActivationDetail } from './components/ActivationDetail';
import { useSdrs } from './hooks/useSdrs';
import { useActivations } from './hooks/useActivations';
import { useActivationDetail } from './hooks/useActivationDetail';
import { tokens } from './styles/tokens';

export function App() {
  const [activeTab, setActiveTab] = useState<'air' | 'sdrs'>('air');
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

  // Find the selected activation from the list
  const selectedActivation = useMemo(
    () =>
      selectedActivationId
        ? allActivations.find((a) => a.id === selectedActivationId) ?? null
        : null,
    [selectedActivationId, allActivations],
  );

  const { recordingDetail, matchingRbnSpots, loading: detailLoading, error: detailError } =
    useActivationDetail(selectedActivation, rbnSpots);

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

      {/* Detail overlay */}
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
git commit -m "feat(web): wire activation detail overlay into App with card click to open"
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

Add the new files to the `web/` section and documentation section:

In the `web/ (Frontend SPA)` table, add these rows after the existing entries:

```markdown
| `web/src/hooks/useActivationDetail.ts` | Fetch recording detail + match RBN spots for selected activation |
| `web/src/components/DetailOverlay.tsx` | Modal backdrop with slide-up panel, ESC/click-outside close |
| `web/src/components/ActivationDetail.tsx` | Full activation view composing audio, transcript, spots, sources |
| `web/src/components/AudioPlayer.tsx` | HTML5 audio player with multi-segment WAV playback |
| `web/src/components/TranscriptView.tsx` | CW transcript with callsign/prosign semantic highlighting |
| `web/src/components/SpotContext.tsx` | POTA and RBN spot attribution display |
| `web/src/components/SourceRecordingList.tsx` | Per-SDR source recording list with status badges |
| `web/src/components/SectionTitle.tsx` | 12px uppercase section label |
| `web/src/components/QualityBadge.tsx` | Correlation quality pill (green/yellow/red) |
```

In the `Documentation` table, add:

```markdown
| `docs/plans/2026-02-21-web-ui-phase3.md` | Phase 3 implementation plan (activation detail overlay) |
```

**Step 4: Commit**

```bash
git add docs/FILE_INDEX.md
git commit -m "docs: add Phase 3 web files to FILE_INDEX.md"
```

---

## Summary

| Task | What | Files | Key |
|------|------|-------|-----|
| 1 | SectionTitle + QualityBadge | 2 create | Reusable primitives |
| 2 | DetailOverlay modal | 1 create, 1 modify | Slide-up, ESC/click-outside, scroll lock |
| 3 | AudioPlayer | 1 create | Multi-segment WAV, HTML5 audio |
| 4 | TranscriptView | 1 create | Callsign/prosign highlighting |
| 5 | SpotContext | 1 create | POTA "P" + RBN "R" attribution |
| 6 | SourceRecordingList | 1 create | Per-SDR status badges |
| 7 | ActivationDetail + hook | 2 create | Composed detail view + data fetch |
| 8 | Wire into App | 1 modify | Card click → overlay |
| 9 | Integration test + docs | 1 modify | Quality gate + FILE_INDEX |

**Total: 9 new files, 2 modified files, 9 commits. 0 backend changes.**
