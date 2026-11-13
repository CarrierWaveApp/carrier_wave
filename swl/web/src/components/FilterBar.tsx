import type { ReactNode } from 'react';
import { tokens } from '../styles/tokens';
import { FilterPill } from './FilterPill';

interface FilterBarProps {
  availableBands: string[];
  activeBands: string[];
  onBandToggle: (band: string) => void;
  children?: ReactNode;
}

const BAND_ORDER = ['160m', '80m', '40m', '30m', '20m', '17m', '15m', '12m', '10m'];

export function FilterBar({
  availableBands,
  activeBands,
  onBandToggle,
  children,
}: FilterBarProps) {
  const ordered = BAND_ORDER.filter((b) => availableBands.includes(b));

  if (ordered.length === 0 && !children) return null;

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '0.375rem',
        padding: '0 1.5rem 0.75rem',
        flexWrap: 'wrap',
      }}
    >
      {children}
      {children && ordered.length > 0 && (
        <div
          style={{
            width: 1,
            height: 16,
            background: tokens.color.border,
            margin: '0 0.25rem',
          }}
        />
      )}
      {ordered.map((band) => (
        <FilterPill
          key={band}
          label={band}
          active={activeBands.includes(band)}
          color={tokens.band[band]}
          onClick={() => onBandToggle(band)}
        />
      ))}
    </div>
  );
}
