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
