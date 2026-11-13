import { tokens } from '../styles/tokens';
import { StatusDot } from './StatusDot';
import type { SdrInfo } from '../api/types';

interface SDRCardProps {
  sdr: SdrInfo;
  onClick?: () => void;
}

function getSdrStatus(sdr: SdrInfo): 'online' | 'active' | 'offline' {
  const ks = sdr.kiwi_status;
  if (!ks || ks.offline) return 'offline';
  if (ks.users && ks.users > 0) return 'active';
  return 'online';
}

export function SDRCard({ sdr, onClick }: SDRCardProps) {
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
      onClick={onClick}
      onMouseEnter={(e) => {
        if (!dimmed) e.currentTarget.style.boxShadow = tokens.shadow.cardHover;
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.boxShadow = tokens.shadow.card;
      }}
    >
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
