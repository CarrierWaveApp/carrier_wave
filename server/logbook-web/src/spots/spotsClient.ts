// Spots + WebSDR API client. Everything is same-origin: logbook-web is served
// by the activities server, which owns /v1/spots and the /v1/websdr proxies —
// so no separate API base is needed (mirrors syncClient's relative fetches).

import { parseKiwiDirectoryJson, rankKiwiReceivers } from '../wasm';
import type { KiwiReceiver, Spot, SpotsListResponse } from './types';

/** Fetch active spots (no auth required). */
export async function fetchSpots(): Promise<Spot[]> {
  const resp = await fetch('/v1/spots?limit=250&maxAgeMinutes=30');
  if (!resp.ok) throw new Error(`GET /v1/spots failed (${resp.status})`);
  const body = (await resp.json()) as SpotsListResponse;
  return body.data.spots;
}

// The directory JS is ~1 MB; the server caches it for an hour and we keep the
// parsed receivers for the life of the tab.
let directoryCache: Promise<string> | null = null;

async function loadDirectoryJson(): Promise<string> {
  if (!directoryCache) {
    directoryCache = (async () => {
      const resp = await fetch('/v1/websdr/directory');
      if (!resp.ok) throw new Error(`GET /v1/websdr/directory failed (${resp.status})`);
      const jsText = await resp.text();
      const json = await parseKiwiDirectoryJson(jsText);
      const count = (JSON.parse(json) as unknown[]).length;
      if (count === 0) throw new Error('KiwiSDR directory is empty or unparseable');
      return json;
    })();
    // Let a failed load be retried instead of caching the rejection.
    directoryCache.catch(() => {
      directoryCache = null;
    });
  }
  return directoryCache;
}

/**
 * Receivers ranked for a spot: nearest to the spot's coordinates when we have
 * them (via the spotter's Maidenhead grid), otherwise the first `limit`
 * receivers unranked. Ranking runs in the shared WASM `find_nearby`.
 */
export async function receiversForSpot(spot: Spot, limit = 10): Promise<KiwiReceiver[]> {
  const json = await loadDirectoryJson();
  const coords = spotCoords(spot);
  if (coords) {
    const ranked = await rankKiwiReceivers(json, coords[0], coords[1], 2000, limit);
    const receivers = JSON.parse(ranked) as KiwiReceiver[];
    if (receivers.length > 0) return receivers;
  }
  const capped = await rankKiwiReceivers(json, null, null, 0, limit);
  return JSON.parse(capped) as KiwiReceiver[];
}

/**
 * Best coordinates for a spot: the server-resolved reference (park/summit)
 * position when present, otherwise the spotter's grid square center.
 */
export function spotCoords(spot: Spot): [number, number] | null {
  if (spot.latitude !== undefined && spot.longitude !== undefined) {
    return [spot.latitude, spot.longitude];
  }
  return spot.spotterGrid ? gridToLatLon(spot.spotterGrid) : null;
}

/**
 * Maidenhead grid (4 or 6 chars) → approximate center [lat, lon].
 * Returns null for malformed grids.
 */
export function gridToLatLon(grid: string): [number, number] | null {
  const g = grid.trim().toUpperCase();
  if (!/^[A-R]{2}[0-9]{2}([A-X]{2})?$/.test(g)) return null;
  let lon = (g.charCodeAt(0) - 65) * 20 - 180;
  let lat = (g.charCodeAt(1) - 65) * 10 - 90;
  lon += (g.charCodeAt(2) - 48) * 2;
  lat += g.charCodeAt(3) - 48;
  if (g.length === 6) {
    lon += ((g.charCodeAt(4) - 65) * 5) / 60 + 2.5 / 60;
    lat += ((g.charCodeAt(5) - 65) * 2.5) / 60 + 1.25 / 60;
  } else {
    lon += 1;
    lat += 0.5;
  }
  return [lat, lon];
}

/** kHz → band label, for the band chip (matches the app's band edges). */
export function bandFromKhz(khz: number): string | undefined {
  const bands: Array<[number, number, string]> = [
    [1800, 2000, '160m'],
    [3500, 4000, '80m'],
    [5330, 5410, '60m'],
    [7000, 7300, '40m'],
    [10100, 10150, '30m'],
    [14000, 14350, '20m'],
    [18068, 18168, '17m'],
    [21000, 21450, '15m'],
    [24890, 24990, '12m'],
    [28000, 29700, '10m'],
    [50000, 54000, '6m'],
    [144000, 148000, '2m'],
    [420000, 450000, '70cm'],
  ];
  const hit = bands.find(([lo, hi]) => khz >= lo && khz <= hi);
  return hit?.[2];
}

/** Short human age like "3m" / "1h 12m" from an ISO timestamp. */
export function spotAge(spottedAt: string): string {
  const ms = Date.now() - new Date(spottedAt).getTime();
  const mins = Math.max(0, Math.floor(ms / 60_000));
  if (mins < 60) return `${mins}m`;
  return `${Math.floor(mins / 60)}h ${mins % 60}m`;
}
