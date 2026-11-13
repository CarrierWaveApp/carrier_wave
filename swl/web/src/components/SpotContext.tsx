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
                  fontFamily: tokens.font.mono,
                  color: tokens.color.textTertiary,
                  fontSize: '0.6875rem',
                }}
              >
                {spot.snr} dB · {spot.wpm} WPM
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
