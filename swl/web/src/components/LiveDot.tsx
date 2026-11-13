import { tokens } from '../styles/tokens';

export function LiveDot() {
  return (
    <span
      style={{
        display: 'inline-block',
        width: 7,
        height: 7,
        borderRadius: '50%',
        background: tokens.color.liveGreen,
        boxShadow: `0 0 6px ${tokens.color.liveGreen}`,
        animation: 'pulse 2s ease-in-out infinite',
      }}
    />
  );
}
