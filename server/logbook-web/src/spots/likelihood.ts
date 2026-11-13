// How likely a KiwiSDR receiver is to hear a spot, for map marker styling.
// Purely visual: the shared WASM distance ranking still decides list order
// and which receiver auto-connects.

import type { KiwiReceiver } from './types';

export type LikelihoodBucket = 'good' | 'fair' | 'weak' | 'unusable';

/** Ranking radius used by receiversForSpot — a receiver at this distance scores 0. */
const MAX_DISTANCE_KM = 2000;

/**
 * 0–1 composite of proximity to the spot (60 %) and the receiver's own
 * measured HF SNR (40 %, normalized over 10–30 dB).
 */
export function likelihoodScore(receiver: KiwiReceiver): number {
  const distanceFactor =
    receiver.distanceKm !== undefined
      ? Math.max(0, 1 - receiver.distanceKm / MAX_DISTANCE_KM)
      : 0;
  const snr = receiver.snrHf ?? receiver.snrAll;
  const snrFactor = snr !== undefined ? Math.max(0, Math.min(1, (snr - 10) / 20)) : 0;
  return 0.6 * distanceFactor + 0.4 * snrFactor;
}

/**
 * Bucket for marker color. Full or antenna-disconnected receivers are
 * `unusable` regardless of score — you can still click them, but they're
 * unlikely to produce audio right now.
 */
export function likelihoodBucket(receiver: KiwiReceiver): LikelihoodBucket {
  if (!receiver.isAvailable || receiver.antConnected === false) return 'unusable';
  const score = likelihoodScore(receiver);
  if (score >= 0.6) return 'good';
  if (score >= 0.3) return 'fair';
  return 'weak';
}

/** Marker/legend color per bucket (CW theme tokens). */
export const BUCKET_COLORS: Record<LikelihoodBucket, string> = {
  good: '#34d399', // cw-green
  fair: '#e0a458', // cw-amber
  weak: '#666c7a', // cw-dim
  unusable: '#f26d6d', // cw-red
};

export const BUCKET_LABELS: Record<LikelihoodBucket, string> = {
  good: 'likely to hear',
  fair: 'maybe',
  weak: 'unlikely',
  unusable: 'full / no antenna',
};
