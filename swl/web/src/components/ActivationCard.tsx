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
