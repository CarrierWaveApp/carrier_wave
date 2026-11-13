// Band → color, ported from the iOS app's `BandColors` (a spectral gradient:
// low bands warm-ish, high bands cool). Hex tuned to read on the dark theme.
const BAND_COLORS: Record<string, string> = {
  '160m': '#7d7bff', // indigo
  '80m': '#bf5af2', // purple
  '60m': '#5c5cd6',
  '40m': '#4a8cff', // blue
  '30m': '#40c8c8', // teal
  '20m': '#34d399', // green
  '17m': '#5fe3c0', // mint
  '15m': '#ff9f0a', // orange
  '12m': '#ff6fa5', // pink
  '10m': '#ff5a4d', // red
  '6m': '#ffd60a', // yellow
  '2m': '#cc6fcc',
  '70cm': '#b08968', // brown
};

export function bandColor(band: string | undefined): string {
  if (!band) return '#666c7a';
  return BAND_COLORS[band.toLowerCase()] ?? '#666c7a';
}

// Quick-filter chips — mirrors the iOS `QuickFilterChipsView` set + queries.
export interface QuickFilter {
  label: string;
  query: string;
  tint: string;
}

export const QUICK_FILTERS: QuickFilter[] = [
  { label: 'Today', query: 'date:today', tint: '#4a8cff' },
  { label: '7 Days', query: 'after:7d', tint: '#4a8cff' },
  { label: 'FT8', query: 'mode:FT8', tint: '#ff9f0a' },
  { label: 'SSB', query: 'mode:SSB', tint: '#34d399' },
  { label: 'CW', query: 'mode:CW', tint: '#bf5af2' },
  { label: 'POTA', query: 'park:K-*', tint: '#34d399' },
  { label: 'Confirmed', query: 'confirmed:lotw', tint: '#ffd60a' },
];
