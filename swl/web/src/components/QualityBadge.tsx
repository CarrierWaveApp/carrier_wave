interface QualityBadgeProps {
  quality: 'good' | 'fair' | 'excluded';
  label?: string;
}

const QUALITY_COLORS: Record<string, { bg: string; text: string }> = {
  good: { bg: 'rgba(61,220,151,0.15)', text: '#3ddc97' },
  fair: { bg: 'rgba(251,191,36,0.15)', text: '#fbbf24' },
  excluded: { bg: 'rgba(248,113,113,0.15)', text: '#f87171' },
};

export function QualityBadge({ quality, label }: QualityBadgeProps) {
  const fallback = { bg: 'rgba(248,113,113,0.15)', text: '#f87171' };
  const colors = QUALITY_COLORS[quality] ?? fallback;

  return (
    <span
      style={{
        display: 'inline-block',
        padding: '0.125rem 0.5rem',
        borderRadius: '9999px',
        fontSize: '0.6875rem',
        fontWeight: 600,
        color: colors.text,
        background: colors.bg,
        lineHeight: 1.4,
      }}
    >
      {label ?? quality}
    </span>
  );
}
