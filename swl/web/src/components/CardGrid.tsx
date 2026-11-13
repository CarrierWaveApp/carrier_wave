import type { CSSProperties, ReactNode } from 'react';

interface CardGridProps {
  minWidth?: string;
  children: ReactNode;
}

export function CardGrid({ minWidth = '280px', children }: CardGridProps) {
  const style: CSSProperties = {
    display: 'grid',
    gridTemplateColumns: `repeat(auto-fill, minmax(${minWidth}, 1fr))`,
    gap: '0.75rem',
    padding: '0 1.5rem',
  };

  return <div style={style}>{children}</div>;
}
