// Carrier Wave brand mark: a modulated sine "carrier" glyph + wordmark.
// Inline SVG so it scales crisply and carries no binary asset.

export function WaveMark({ className = 'h-7 w-7' }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" className={className} role="img" aria-label="Carrier Wave">
      <rect width="32" height="32" rx="7" className="fill-cw-surface2" />
      <path
        // A carrier wave whose amplitude swells toward the centre — the app's namesake.
        d="M3 16 Q6.5 16 8 16 T11 9 T14 23 T17 6 T20 26 T23 12 T26 16 Q27.5 16 29 16"
        fill="none"
        className="stroke-cw-blue"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function Wordmark({ size = 'text-base' }: { size?: string }) {
  return (
    <div className="flex items-center gap-2.5">
      <WaveMark />
      <div className="leading-none">
        <div className={`font-semibold tracking-tight text-cw-white ${size}`}>Carrier Wave</div>
        <div className="cw-eyebrow mt-1 text-[0.62rem]">Logbook</div>
      </div>
    </div>
  );
}
