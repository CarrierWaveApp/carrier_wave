import { tokens } from '../styles/tokens';

interface PageHeaderProps {
  title: string;
  subtitle?: string;
}

export function PageHeader({ title, subtitle }: PageHeaderProps) {
  return (
    <div style={{ padding: '1.5rem 1.5rem 1rem' }}>
      <h1
        style={{
          fontSize: '1.5rem',
          fontWeight: 700,
          color: tokens.color.textPrimary,
          letterSpacing: '-0.02em',
        }}
      >
        {title}
      </h1>
      {subtitle && (
        <p
          style={{
            fontSize: '0.875rem',
            color: tokens.color.textSecondary,
            marginTop: '0.25rem',
          }}
        >
          {subtitle}
        </p>
      )}
    </div>
  );
}
