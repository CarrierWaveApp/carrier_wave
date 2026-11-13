import { useMemo } from 'react';
import { useActivationStore } from './useActivations';
import { frequencyToBand } from '../utils/bands';
import type { PotaSpot, RbnSpot } from '../api/types';

export interface UnifiedSpot {
  id: string;
  source: 'pota' | 'rbn';
  callsign: string;
  frequencyKhz: number;
  band: string;
  mode: string;
  snr?: number;
  wpm?: number;
  parkRef?: string;
  parkName?: string;
  spotter: string;
  timestamp: string;
}

function potaToUnified(spot: PotaSpot): UnifiedSpot {
  const freqKhz = parseFloat(spot.frequency);
  return {
    id: `pota-${spot.activator}-${spot.frequency}-${spot.spotTime}`,
    source: 'pota',
    callsign: spot.activator,
    frequencyKhz: freqKhz,
    band: frequencyToBand(freqKhz * 1000),
    mode: spot.mode,
    parkRef: spot.reference,
    parkName: spot.parkName ?? undefined,
    spotter: spot.spotter,
    timestamp: spot.spotTime,
  };
}

function rbnToUnified(spot: RbnSpot): UnifiedSpot {
  return {
    id: `rbn-${spot.callsign}-${spot.frequency}-${spot.timestamp}`,
    source: 'rbn',
    callsign: spot.callsign,
    frequencyKhz: spot.frequency,
    band: frequencyToBand(spot.frequency * 1000),
    mode: spot.mode,
    snr: spot.snr,
    wpm: spot.wpm,
    spotter: spot.spotter_callsign,
    timestamp: spot.timestamp,
  };
}

export function useSpots() {
  const { potaSpots, rbnSpots, bandFilters } = useActivationStore();

  const allSpots = useMemo(() => {
    const pota = potaSpots.map(potaToUnified);
    const rbn = rbnSpots.map(rbnToUnified);
    return [...pota, ...rbn];
  }, [potaSpots, rbnSpots]);

  const filteredSpots = useMemo(() => {
    if (bandFilters.length === 0) return allSpots;
    return allSpots.filter((s) => bandFilters.includes(s.band));
  }, [allSpots, bandFilters]);

  const availableBands = useMemo(
    () => [...new Set(allSpots.map((s) => s.band))],
    [allSpots],
  );

  return { spots: filteredSpots, allSpots, availableBands };
}
