import { tokens } from '../styles/tokens';

type Tab = 'air' | 'sdrs' | 'spots' | 'search';

const TAB_LABELS: Record<Tab, string> = {
  air: 'On the Air',
  sdrs: 'SDRs',
  spots: 'Spots',
  search: 'Search',
};

interface TopNavProps {
  activeTab: Tab;
  onTabChange: (tab: Tab) => void;
  hasLive: boolean;
}

export function TopNav({ activeTab, onTabChange, hasLive }: TopNavProps) {
  return (
    <nav
      style={{
        position: 'sticky',
        top: 0,
        zIndex: 100,
        display: 'flex',
        alignItems: 'center',
        gap: '1.5rem',
        padding: '0 1.5rem',
        height: '56px',
        background: 'rgba(37,37,45,0.8)',
        backdropFilter: 'blur(20px) saturate(180%)',
        WebkitBackdropFilter: 'blur(20px) saturate(180%)',
        borderBottom: `1px solid ${tokens.color.border}`,
      }}
    >
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '0.5rem',
          fontWeight: 700,
          fontSize: '1rem',
          letterSpacing: '-0.01em',
        }}
      >
        <span
          style={{
            width: 7,
            height: 7,
            borderRadius: '50%',
            background: hasLive ? tokens.color.liveGreen : tokens.color.textTertiary,
            boxShadow: hasLive
              ? `0 0 6px ${tokens.color.liveGreen}`
              : 'none',
            animation: hasLive ? 'pulse 2s ease-in-out infinite' : 'none',
          }}
        />
        CW-SWL
      </div>

      <div style={{ display: 'flex', gap: '0.25rem' }}>
        {(['air', 'sdrs', 'spots', 'search'] as const).map((tab) => (
          <button
            key={tab}
            onClick={() => onTabChange(tab)}
            style={{
              background:
                activeTab === tab ? tokens.color.accentLight : 'transparent',
              color:
                activeTab === tab
                  ? tokens.color.accent
                  : tokens.color.textSecondary,
              border: 'none',
              borderRadius: tokens.radius.sm,
              padding: '0.375rem 0.75rem',
              fontSize: '0.8125rem',
              fontWeight: 500,
              cursor: 'pointer',
              fontFamily: 'inherit',
              transition: 'background 0.15s, color 0.15s',
            }}
          >
            {TAB_LABELS[tab]}
          </button>
        ))}
      </div>
    </nav>
  );
}
