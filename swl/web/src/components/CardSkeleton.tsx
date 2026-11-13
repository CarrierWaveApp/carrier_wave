import { tokens } from '../styles/tokens';

interface CardSkeletonProps {
  lines?: number;
}

function SkeletonLine({ width }: { width: string }) {
  return (
    <div
      style={{
        height: '0.75rem',
        width,
        borderRadius: '4px',
        background: `linear-gradient(90deg, ${tokens.color.surface} 25%, ${tokens.color.surfaceHover} 50%, ${tokens.color.surface} 75%)`,
        backgroundSize: '200% 100%',
        animation: 'shimmer 1.5s ease-in-out infinite',
      }}
    />
  );
}

export function CardSkeleton({ lines = 3 }: CardSkeletonProps) {
  const widths = ['60%', '80%', '45%', '70%'];

  return (
    <div
      style={{
        background: tokens.color.surface,
        borderRadius: tokens.radius.md,
        padding: '1rem 1.125rem',
        boxShadow: tokens.shadow.card,
        display: 'flex',
        flexDirection: 'column',
        gap: '0.625rem',
      }}
    >
      {Array.from({ length: lines }, (_, i) => (
        <SkeletonLine key={i} width={widths[i % widths.length]!} />
      ))}
    </div>
  );
}
