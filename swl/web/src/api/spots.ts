import type { PotaSpot, RbnSpot } from './types';

const POTA_URL = 'https://api.pota.app/spot/activator';
const RBN_URL = 'https://rbn.telegraphy.de/skimmer/spots/current';

export async function fetchPotaSpots(): Promise<PotaSpot[]> {
  try {
    const res = await fetch(POTA_URL);
    if (!res.ok) return [];
    const data: PotaSpot[] = await res.json();
    // Filter to CW only. The rebuilt POTA API (2026-10) leaves parkName null
    // and carries the park name in `name`, so normalize it here.
    return data
      .filter((s) => s.mode?.toUpperCase() === 'CW')
      .map((s) => ({ ...s, parkName: s.parkName ?? s.name ?? null }));
  } catch {
    return [];
  }
}

export async function fetchRbnSpots(): Promise<RbnSpot[]> {
  try {
    const res = await fetch(RBN_URL);
    if (!res.ok) return [];
    return (await res.json()) as RbnSpot[];
  } catch {
    return [];
  }
}
