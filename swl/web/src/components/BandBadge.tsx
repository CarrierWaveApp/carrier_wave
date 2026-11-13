import { tokens } from '../styles/tokens';

interface BandBadgeProps {
  band: string;
  size?: 'sm' | 'md';
}

export function BandBadge({ band, size = 'sm' }: BandBadgeProps) {
  const color = tokens.band[band] ?? tokens.color.textTertiary;
  const isSm = size === 'sm';

  return (
    <span
      style={{
        display: 'inline-block',
        padding: isSm ? '0.125rem 0.5rem' : '0.1875rem 0.625rem',
        borderRadius: '9999px',
        fontSize: isSm ? '0.6875rem' : '0.75rem',
        fontWeight: 600,
        fontFamily: tokens.font.mono,
        color,
        background: `${color}1a`,
        lineHeight: 1.4,
      }}
    >
      {band}
    </span>
  );
}
