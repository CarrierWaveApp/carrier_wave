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
