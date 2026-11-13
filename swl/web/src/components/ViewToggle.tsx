import { tokens } from '../styles/tokens';

interface ViewToggleProps {
  value: 'list' | 'map';
  onChange: (value: 'list' | 'map') => void;
}

export function ViewToggle({ value, onChange }: ViewToggleProps) {
  return (
    <div
      style={{
        display: 'inline-flex',
        background: tokens.color.surface,
        borderRadius: tokens.radius.sm,
        padding: '2px',
      }}
    >
      {(['list', 'map'] as const).map((option) => (
        <button
          key={option}
          onClick={() => onChange(option)}
          style={{
            background: value === option ? tokens.color.accentLight : 'transparent',
            color: value === option ? tokens.color.accent : tokens.color.textTertiary,
            border: 'none',
            borderRadius: '6px',
            padding: '0.25rem 0.625rem',
            fontSize: '0.75rem',
            fontWeight: 500,
            fontFamily: 'inherit',
            cursor: 'pointer',
            transition: 'background 0.15s, color 0.15s',
          }}
        >
          {option === 'list' ? 'List' : 'Map'}
        </button>
      ))}
    </div>
  );
}
