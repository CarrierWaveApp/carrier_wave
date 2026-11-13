import { tokens } from '../styles/tokens';

interface SortHeaderProps {
  label: string;
  sortKey: string;
  activeSortKey: string;
  ascending: boolean;
  onSort: (key: string) => void;
}

export function SortHeader({
  label,
  sortKey,
  activeSortKey,
  ascending,
  onSort,
}: SortHeaderProps) {
  const isActive = sortKey === activeSortKey;

  return (
    <th
      onClick={() => onSort(sortKey)}
      style={{
        cursor: 'pointer',
        userSelect: 'none',
        padding: '0.5rem 0.75rem',
        textAlign: 'left',
        fontSize: '0.6875rem',
        fontWeight: 600,
        textTransform: 'uppercase',
        letterSpacing: '0.04em',
        color: isActive ? tokens.color.accent : tokens.color.textTertiary,
        borderBottom: `1px solid ${tokens.color.border}`,
        whiteSpace: 'nowrap',
      }}
    >
      {label}
      {isActive && (
        <span style={{ marginLeft: '0.25rem' }}>
          {ascending ? '\u25B2' : '\u25BC'}
        </span>
      )}
    </th>
  );
}
