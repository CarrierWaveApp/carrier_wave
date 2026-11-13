// Wire types mirroring the Rust sync journal (cw-sync). Field names are the
// exact JSON keys: SyncQso uses camelCase (serde rename_all) with two explicit
// overrides (`rawADIF`, `isActivityLogQSO`); JournalOperation is internally
// tagged on `op` with PascalCase variant names.

export interface SyncQso {
  id: string;
  callsign: string;
  band: string;
  mode: string;
  frequency?: number;
  timestamp: number; // Unix seconds
  rstSent?: string;
  rstReceived?: string;
  myCallsign: string;
  myGrid?: string;
  theirGrid?: string;
  parkReference?: string;
  theirParkReference?: string;
  notes?: string;
  importSource: string;
  importedAt?: number;
  modifiedAt?: number;
  rawADIF?: string;
  name?: string;
  qth?: string;
  state?: string;
  country?: string;
  power?: number;
  myRig?: string;
  stationProfileName?: string;
  sotaRef?: string;
  wwffRef?: string;
  qrzLogId?: string;
  qrzConfirmed: boolean;
  lotwConfirmedDate?: number;
  lotwConfirmed: boolean;
  dxcc?: number;
  theirLicenseClass?: string;
  isHidden: boolean;
  isActivityLogQSO: boolean;
  loggingSessionId?: string;
  stationCallsign?: string;
  spotCommentsData?: string; // base64
  notesUserAuthored: boolean;
  /** ADIF SAT_NAME — satellite short name (e.g. "AO-91"). */
  satName?: string;
  /** ADIF PROP_MODE — "SAT" for satellite QSOs. */
  propMode?: string;
}

// Internally-tagged: an upsert is `{ op: "UpsertQso", ...SyncQso }`; a delete is
// `{ op: "Delete", entity_type, id }` (the Delete variant's fields are NOT
// camelCased — no rename_all on the enum).
export type JournalOperation =
  | ({ op: 'UpsertQso' } & SyncQso)
  | { op: 'Delete'; entity_type: string; id: string };

export interface JournalPayload {
  id: string;
  deviceId: string;
  timestamp: number;
  sequenceNumber: number;
  operations: JournalOperation[];
}

// --- server sync API responses (raw, no {data} envelope) ---

export interface KeyBlob {
  wrappedKey: string; // base64
  kdfParams: unknown; // { salt:[..16..], m_cost, t_cost, p_cost }
}

export interface ChangeItem {
  seq: number;
  entityType: string;
  op: string;
  blobKey: string;
  byteSize: number;
  contentHash: string;
  downloadUrl: string;
}

export interface BootstrapResponse {
  snapshotUrl: string | null;
  snapshotSeq: number | null;
  /**
   * Only the FIRST page after the snapshot (server default 500 entries) — not
   * the whole journal. Compare the last seq against `highWater` and pull the
   * rest with `GET /v1/sync/changes?since=`.
   */
  entries: ChangeItem[];
  /** Highest seq the tenant has reserved; the load is complete at this seq. */
  highWater: number;
}

export interface ChangesResponse {
  /** Entries with `seq > since`, ascending, at most `limit` (clamped to 1..1000). */
  entries: ChangeItem[];
  snapshotSeq: number | null;
  snapshotUrl: string | null;
  highWater: number;
}
