import { tokens } from '../styles/tokens';

interface TranscriptViewProps {
  text: string;
  wpm?: number;
}

const CALLSIGN_RE = /\b([A-Z]{1,2}\d[A-Z0-9]*[A-Z])\b/;
const PROSIGNS = new Set(['BT', 'SK', 'AR', 'KN', 'BK', 'CL', 'SN', 'HH']);

interface Token {
  text: string;
  type: 'callsign' | 'prosign' | 'text';
}

function tokenize(text: string): Token[] {
  const toks: Token[] = [];
  const words = text.split(/(\s+)/);

  for (const word of words) {
    if (/^\s+$/.test(word)) {
      toks.push({ text: word, type: 'text' });
      continue;
    }

    if (PROSIGNS.has(word)) {
      toks.push({ text: word, type: 'prosign' });
    } else if (CALLSIGN_RE.test(word)) {
      toks.push({ text: word, type: 'callsign' });
    } else {
      toks.push({ text: word, type: 'text' });
    }
  }

  return toks;
}

const TOKEN_STYLES: Record<string, React.CSSProperties> = {
  callsign: { color: '#6fb1f7', fontWeight: 600 },
  prosign: { color: '#fbbf24', fontWeight: 600 },
  text: {},
};

export function TranscriptView({ text, wpm }: TranscriptViewProps) {
  const toks = tokenize(text);

  return (
    <div
      style={{
        background: tokens.color.surface,
        borderRadius: tokens.radius.sm,
        padding: '0.75rem 1rem',
      }}
    >
      {wpm && (
        <div
          style={{
            fontSize: '0.6875rem',
            color: tokens.color.textTertiary,
            marginBottom: '0.5rem',
          }}
        >
          {wpm.toFixed(0)} WPM
        </div>
      )}

      <div
        style={{
          fontFamily: tokens.font.mono,
          fontSize: '0.875rem',
          lineHeight: 1.7,
          color: tokens.color.textPrimary,
          wordBreak: 'break-word',
        }}
      >
        {toks.map((tok, i) => (
          <span key={i} style={TOKEN_STYLES[tok.type]}>
            {tok.text}
          </span>
        ))}
      </div>
    </div>
  );
}
