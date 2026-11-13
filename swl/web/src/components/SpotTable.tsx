import { useState, useMemo } from 'react';
import { tokens } from '../styles/tokens';
import { SortHeader } from './SortHeader';
import type { UnifiedSpot } from '../hooks/useSpots';

interface SpotTableProps {
  spots: UnifiedSpot[];
}

type SortKey = 'time' | 'callsign' | 'freq' | 'band' | 'snr' | 'wpm' | 'source' | 'spotter';

const MAX_ROWS = 200;

function timeAgo(isoStr: string): string {
  const diffMs = Date.now() - new Date(isoStr).getTime();
  const mins = Math.floor(diffMs / 60_000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}

function compareSpots(a: UnifiedSpot, b: UnifiedSpot, key: SortKey, asc: boolean): number {
  let cmp = 0;
  switch (key) {
    case 'time':
      cmp = new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime();
      break;
    case 'callsign':
      cmp = a.callsign.localeCompare(b.callsign);
      break;
    case 'freq':
      cmp = a.frequencyKhz - b.frequencyKhz;
      break;
    case 'band':
      cmp = a.band.localeCompare(b.band);
      break;
    case 'snr':
      cmp = (a.snr ?? -999) - (b.snr ?? -999);
      break;
    case 'wpm':
      cmp = (a.wpm ?? -999) - (b.wpm ?? -999);
      break;
    case 'source':
      cmp = a.source.localeCompare(b.source);
      break;
    case 'spotter':
      cmp = a.spotter.localeCompare(b.spotter);
      break;
  }
  return asc ? cmp : -cmp;
}

const sourceBadgeStyle = (source: 'pota' | 'rbn'): React.CSSProperties => ({
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  width: 22,
  height: 22,
  borderRadius: '50%',
  fontSize: '0.6875rem',
  fontWeight: 700,
  flexShrink: 0,
  background: source === 'pota' ? 'rgba(61,220,151,0.15)' : 'rgba(111,177,247,0.15)',
  color: source === 'pota' ? '#3ddc97' : '#6fb1f7',
});

export function SpotTable({ spots }: SpotTableProps) {
  const [sortKey, setSortKey] = useState<SortKey>('time');
  const [ascending, setAscending] = useState(false);

  const handleSort = (key: string) => {
    if (key === sortKey) {
      setAscending(!ascending);
    } else {
      setSortKey(key as SortKey);
      setAscending(key === 'callsign' || key === 'spotter');
    }
  };

  const sorted = useMemo(
    () =>
      [...spots]
        .sort((a, b) => compareSpots(a, b, sortKey, ascending))
        .slice(0, MAX_ROWS),
    [spots, sortKey, ascending],
  );

  if (spots.length === 0) {
    return (
      <div
        style={{
          textAlign: 'center',
          padding: '3rem 1.5rem',
          color: tokens.color.textTertiary,
          fontSize: '0.875rem',
        }}
      >
        No spots available. Waiting for spot data...
      </div>
    );
  }

  return (
    <div style={{ padding: '0 1.5rem 1.5rem', overflowX: 'auto' }}>
      <table
        style={{
          width: '100%',
          borderCollapse: 'collapse',
          fontSize: '0.8125rem',
          fontFamily: tokens.font.sans,
        }}
      >
        <thead>
          <tr>
            <SortHeader label="Src" sortKey="source" activeSortKey={sortKey} ascending={ascending} onSort={handleSort} />
            <SortHeader label="Callsign" sortKey="callsign" activeSortKey={sortKey} ascending={ascending} onSort={handleSort} />
            <SortHeader label="Freq (kHz)" sortKey="freq" activeSortKey={sortKey} ascending={ascending} onSort={handleSort} />
            <SortHeader label="Band" sortKey="band" activeSortKey={sortKey} ascending={ascending} onSort={handleSort} />
            <SortHeader label="SNR" sortKey="snr" activeSortKey={sortKey} ascending={ascending} onSort={handleSort} />
            <SortHeader label="WPM" sortKey="wpm" activeSortKey={sortKey} ascending={ascending} onSort={handleSort} />
            <th
              style={{
                padding: '0.5rem 0.75rem',
                textAlign: 'left',
                fontSize: '0.6875rem',
                fontWeight: 600,
                textTransform: 'uppercase',
                letterSpacing: '0.04em',
                color: tokens.color.textTertiary,
                borderBottom: `1px solid ${tokens.color.border}`,
                whiteSpace: 'nowrap',
              }}
            >
              Park
            </th>
            <SortHeader label="Spotter" sortKey="spotter" activeSortKey={sortKey} ascending={ascending} onSort={handleSort} />
            <SortHeader label="Time" sortKey="time" activeSortKey={sortKey} ascending={ascending} onSort={handleSort} />
          </tr>
        </thead>
        <tbody>
          {sorted.map((spot) => (
            <tr
              key={spot.id}
              style={{
                borderBottom: `1px solid ${tokens.color.borderLight}`,
              }}
            >
              <td style={{ padding: '0.5rem 0.75rem' }}>
                <span style={sourceBadgeStyle(spot.source)}>
                  {spot.source === 'pota' ? 'P' : 'R'}
                </span>
              </td>
              <td
                style={{
                  padding: '0.5rem 0.75rem',
                  fontFamily: tokens.font.mono,
                  fontWeight: 600,
                  color: tokens.color.textPrimary,
                }}
              >
                {spot.callsign}
              </td>
              <td
                style={{
                  padding: '0.5rem 0.75rem',
                  fontFamily: tokens.font.mono,
                  color: tokens.color.textSecondary,
                }}
              >
                {spot.frequencyKhz.toFixed(1)}
              </td>
              <td style={{ padding: '0.5rem 0.75rem' }}>
                <span
                  style={{
                    display: 'inline-block',
                    padding: '0.125rem 0.5rem',
                    borderRadius: '9999px',
                    fontSize: '0.6875rem',
                    fontWeight: 600,
                    background: `${tokens.band[spot.band] ?? tokens.color.textTertiary}22`,
                    color: tokens.band[spot.band] ?? tokens.color.textTertiary,
                  }}
                >
                  {spot.band}
                </span>
              </td>
              <td
                style={{
                  padding: '0.5rem 0.75rem',
                  fontFamily: tokens.font.mono,
                  color: tokens.color.textSecondary,
                }}
              >
                {spot.snr != null ? `${spot.snr} dB` : '\u2014'}
              </td>
              <td
                style={{
                  padding: '0.5rem 0.75rem',
                  fontFamily: tokens.font.mono,
                  color: tokens.color.textSecondary,
                }}
              >
                {spot.wpm != null ? spot.wpm : '\u2014'}
              </td>
              <td
                style={{
                  padding: '0.5rem 0.75rem',
                  color: spot.parkRef ? tokens.color.accent : tokens.color.textTertiary,
                  fontSize: '0.8125rem',
                }}
              >
                {spot.parkRef ? (
                  <>
                    <span style={{ fontWeight: 600 }}>{spot.parkRef}</span>
                    {spot.parkName && (
                      <span style={{ color: tokens.color.textSecondary, marginLeft: '0.25rem' }}>
                        {spot.parkName}
                      </span>
                    )}
                  </>
                ) : (
                  '\u2014'
                )}
              </td>
              <td
                style={{
                  padding: '0.5rem 0.75rem',
                  fontFamily: tokens.font.mono,
                  color: tokens.color.textSecondary,
                }}
              >
                {spot.spotter}
              </td>
              <td
                style={{
                  padding: '0.5rem 0.75rem',
                  color: tokens.color.textTertiary,
                  fontSize: '0.75rem',
                  whiteSpace: 'nowrap',
                }}
              >
                {timeAgo(spot.timestamp)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
