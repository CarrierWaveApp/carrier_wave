export const tokens = {
  color: {
    bg: '#25252d',
    surface: '#2f2f3a',
    surfaceHover: '#383844',
    border: '#3e3e4c',
    borderLight: '#363642',
    textPrimary: '#ededea',
    textSecondary: '#a5a19a',
    textTertiary: '#706c66',
    accent: '#6fb1f7',
    accentLight: 'rgba(111,177,247,0.14)',
    liveGreen: '#3ddc97',
    liveGreenBg: 'rgba(61,220,151,0.1)',
  },
  band: {
    '160m': '#a78bfa',
    '80m': '#818cf8',
    '40m': '#fbbf24',
    '30m': '#a3e635',
    '20m': '#38bdf8',
    '17m': '#22d3ee',
    '15m': '#34d399',
    '12m': '#fb923c',
    '10m': '#f87171',
  } as Record<string, string>,
  radius: { sm: '8px', md: '14px', lg: '20px' },
  shadow: {
    card: '0 1px 4px rgba(0,0,0,0.2), 0 0 0 1px rgba(255,255,255,0.05)',
    cardHover:
      '0 6px 24px rgba(0,0,0,0.35), 0 0 0 1px rgba(255,255,255,0.08)',
  },
  font: {
    sans: "'DM Sans', -apple-system, BlinkMacSystemFont, sans-serif",
    mono: "'JetBrains Mono', 'SF Mono', monospace",
  },
} as const;
