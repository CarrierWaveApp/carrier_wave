import { tokens } from '../styles/tokens';

interface FilterPillProps {
  label: string;
  active: boolean;
  color?: string;
  onClick: () => void;
}

export function FilterPill({ label, active, color, onClick }: FilterPillProps) {
  const pillColor = color ?? tokens.color.accent;

  return (
    <button
      onClick={onClick}
      style={{
        display: 'inline-block',
        padding: '0.25rem 0.625rem',
        borderRadius: '9999px',
        fontSize: '0.75rem',
        fontWeight: 500,
        fontFamily: tokens.font.mono,
        cursor: 'pointer',
        border: 'none',
        transition: 'background 0.15s, color 0.15s',
        color: active ? pillColor : tokens.color.textTertiary,
        background: active ? `${pillColor}1a` : 'transparent',
      }}
    >
      {label}
    </button>
  );
}
