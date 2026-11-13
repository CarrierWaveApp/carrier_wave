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
  const [segmentIndex, setSegmentIndex] = useState(0);

  const sorted = [...segments].sort((a, b) => a.segment_number - b.segment_number);
  const currentSegment = sorted[segmentIndex];

  const audioUrl = currentSegment
    ? `/api/v1/recordings/${recordingId}/segments/${currentSegment.segment_number}/audio`
    : undefined;

  const totalDuration = sorted.reduce((sum, s) => sum + s.duration_secs, 0);

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
        onEnded={handleEnded}
      />

      <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
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
          {playing ? '\u23F8' : '\u25B6'}
        </button>

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
        <div style={{ fontSize: '0.6875rem', color: tokens.color.textTertiary }}>
          Segment {segmentIndex + 1} of {sorted.length}
        </div>
      )}
    </div>
  );
}
