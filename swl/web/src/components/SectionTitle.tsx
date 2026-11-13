import { tokens } from '../styles/tokens';

interface SectionTitleProps {
  children: React.ReactNode;
}

export function SectionTitle({ children }: SectionTitleProps) {
  return (
    <div
      style={{
        fontSize: '0.75rem',
        fontWeight: 600,
        textTransform: 'uppercase',
        letterSpacing: '0.06em',
        color: tokens.color.textTertiary,
        padding: '0.5rem 0 0.25rem',
      }}
    >
      {children}
    </div>
  );
}
