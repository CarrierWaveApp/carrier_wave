// Wire types for the sync journal. These mirror the Rust definitions in
// `rust/cw-core/cw-sync/src/journal.rs` — get a key wrong and the apps will
// silently fail to decode what you wrote.
//
// THE CASING IS NOT UNIFORM. This trips everyone up exactly once:
//
//   JournalPayload    snake_case  (`device_id`, `sequence_number`) — no serde rename_all
//   JournalOperation  tagged on `op`, PascalCase variant names
//   Delete variant    snake_case  (`entity_type`)
//   SyncQso           camelCase   EXCEPT `rawADIF` and `isActivityLogQSO`

/** A logged contact, as it travels inside an encrypted journal blob. */
export interface SyncQso {
  id: string;
  callsign: string;
  band: string;
  mode: string;
  /**
   * MEGAHERTZ, not kilohertz. Same unit as ADIF `FREQ`, so pass it through
   * unchanged. A shipped viewer bug once divided by 1000 a second time and
   * rendered 14.074 MHz as 0.014.
   */
  frequency?: number;
  /** Unix seconds. */
  timestamp: number;
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
  /** Soft delete. Hidden QSOs stay in the journal; don't show them. */
  isHidden: boolean;
  isActivityLogQSO: boolean;
  loggingSessionId?: string;
  stationCallsign?: string;
  spotCommentsData?: string;
  notesUserAuthored: boolean;
  /** ADIF SAT_NAME — satellite short name (e.g. "AO-91"). */
  satName?: string;
  /** ADIF PROP_MODE — "SAT" for satellite QSOs. */
  propMode?: string;
}

/**
 * One journal operation.
 *
 * The union is deliberately open-ended: newer clients mint operation types this
 * code has never heard of (`UpsertSyncedConfig`, `UpsertLoggingSession`, and
 * whatever comes next). The Rust decoder tolerates them via `#[serde(other)]`,
 * and yours MUST too — treating an unrecognized `op` as an error would abort the
 * whole batch and lose the QSOs alongside it.
 */
export type JournalOperation =
  | ({ op: 'UpsertQso' } & SyncQso)
  | { op: 'Delete'; entity_type: string; id: string }
  | { op: string };

/** A batch of operations from one device. NOTE: snake_case keys. */
export interface JournalPayload {
  id: string;
  device_id: string;
  /** Unix seconds. */
  timestamp: number;
  sequence_number: number;
  operations: JournalOperation[];
}

/** Maximum operations per entry — `JournalPayload::MAX_OPERATIONS_PER_ENTRY`. */
export const MAX_OPS_PER_ENTRY = 100;

// --- server responses (raw JSON, no {data} envelope) ---

export interface KeyBlob {
  /** base64 */
  wrappedKey: string;
  /** `{ salt: [..16..], m_cost, t_cost, p_cost }` */
  kdfParams: unknown;
}

export interface ChangeItem {
  seq: number;
  entityType: string;
  op: string;
  blobKey: string;
  byteSize: number;
  contentHash: string;
  /** Presigned; fetch WITHOUT an Authorization header. */
  downloadUrl: string;
}

export interface BootstrapResponse {
  snapshotUrl: string | null;
  snapshotSeq: number | null;
  /**
   * Only the FIRST page after the snapshot — 500 entries by server default,
   * NOT the whole journal. Anyone who folds `entries` and stops has the oldest
   * 500 and none of the recent QSOs. Compare the last seq to `highWater` and
   * pull the rest with `GET /v1/sync/changes?since=`.
   */
  entries: ChangeItem[];
  /** Highest seq the tenant has reserved. You are done when you have applied it. */
  highWater: number;
}

/** `GET /v1/sync/changes?since=&limit=` — entries with `seq > since`, ascending. */
export interface ChangesResponse {
  /** At most `limit` entries; the server clamps `limit` to 1..1000. */
  entries: ChangeItem[];
  snapshotSeq: number | null;
  snapshotUrl: string | null;
  highWater: number;
}

export interface PushedEntry {
  clientEntryId: string;
  seq: number;
  blobKey: string;
  /** Presigned; PUT the ciphertext here, no Authorization header. */
  uploadUrl: string;
}

export interface PushResponse {
  entries: PushedEntry[];
  highWater: number;
}
