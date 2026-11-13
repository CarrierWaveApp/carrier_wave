// Wire types for the Spots page: active spots from the activities server
// (GET /v1/spots — logbook-web is served same-origin by that server) and
// KiwiSDR receivers from the shared WASM directory parser.

/** One active spot (server `SpotResponse`, camelCase). */
export interface Spot {
  id: string;
  callsign: string;
  programSlug?: string;
  source: string;
  frequencyKhz: number;
  mode: string;
  reference?: string;
  referenceName?: string;
  spotter?: string;
  spotterGrid?: string;
  locationDesc?: string;
  countryCode?: string;
  stateAbbr?: string;
  comments?: string;
  snr?: number;
  wpm?: number;
  /** Reference (park/summit) coordinates when the server's catalog knows them. */
  latitude?: number;
  longitude?: number;
  spottedAt: string;
  expiresAt: string;
}

export interface SpotsListResponse {
  data: {
    spots: Spot[];
    pagination: { hasMore: boolean; nextCursor: string | null };
  };
}

/** One KiwiSDR receiver (WASM `ReceiverDto`, camelCase). */
export interface KiwiReceiver {
  id: string;
  name: string;
  host: string;
  port: number;
  latitude: number;
  longitude: number;
  bands: string;
  users: number;
  maxUsers: number;
  location: string;
  antenna: string;
  distanceKm?: number;
  snrAll?: number;
  snrHf?: number;
  antConnected?: boolean;
  grid?: string;
  isAvailable: boolean;
}
