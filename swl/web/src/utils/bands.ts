export const BAND_EDGES: [number, number, string][] = [
  [1_800_000, 2_000_000, '160m'],
  [3_500_000, 4_000_000, '80m'],
  [7_000_000, 7_300_000, '40m'],
  [10_100_000, 10_150_000, '30m'],
  [14_000_000, 14_350_000, '20m'],
  [18_068_000, 18_168_000, '17m'],
  [21_000_000, 21_450_000, '15m'],
  [24_890_000, 24_990_000, '12m'],
  [28_000_000, 29_700_000, '10m'],
];

export function frequencyToBand(freqHz: number): string {
  for (const [lo, hi, band] of BAND_EDGES) {
    if (freqHz >= lo && freqHz <= hi) return band;
  }
  return 'unknown';
}
