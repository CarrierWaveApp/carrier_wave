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
