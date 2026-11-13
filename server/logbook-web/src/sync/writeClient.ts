// Writes soft-delete operations back to the E2E-blind sync journal.
//
// This is the one place the viewer is not read-only. A delete is a journal
// `Delete` op which every client applies as a *soft* delete (`isHidden = true`),
// so nothing is ever hard-removed. The wire path mirrors the Rust client
// (`cw-sync/src/http_transport.rs::push`):
//
//   1. Build a JournalPayload of `Delete` ops (≤100 ops per entry).
//   2. seal(dataKey, gzip(json(payload)))  → ciphertext blob (WASM `sealBlob`).
//   3. POST /v1/sync/push { entries:[{ clientEntryId, entityType, op,
//      byteSize, contentHash }] } → reserved seq + presigned R2 upload URL.
//   4. PUT the ciphertext to each presigned URL (no auth header; the URL is
//      self-signed). NOTE: the R2 bucket CORS policy must allow PUT for this
//      origin, or the upload fails in the browser.
//
// Durability (CAR-322): step 3 commits `sync_entry` rows *immediately*, so a
// step-4 PUT that never lands leaves a seq every device will 404 on forever.
// Each PUT is therefore retried with backoff, one failure never abandons the
// others, and the sealed ciphertexts are parked in localStorage until every
// blob is confirmed. `resumePendingUploads()` re-pushes the leftovers: the
// server dedups on `client_entry_id`, so a re-push hands back the *same*
// seq/blobKey with a fresh presigned URL and the blob lands where the journal
// already points. Only ciphertext is persisted (never the data key), so
// surviving a tab close costs nothing security-wise.

import { authFetch, syncFailure } from '../auth/session';
import { sealBlob } from '../wasm';
import { putWithRetry, type UploadOutcome } from './retry';

// The on-the-wire JournalPayload shape. NOTE: unlike SyncQso (camelCase), the
// Rust `JournalPayload` struct has NO `rename_all`, so its fields serialize as
// snake_case (`device_id`, `sequence_number`). The Delete op is the tagged-enum
// variant `{ op:"Delete", entity_type, id }` (also snake_case — the enum has no
// rename_all either). Getting these keys wrong makes iOS/Android `serde_json`
// fail to deserialize the pulled blob, so they must match exactly.
interface WireDeleteOp {
  op: 'Delete';
  entity_type: string;
  id: string;
}

interface WireJournalPayload {
  id: string;
  device_id: string;
  timestamp: number;
  sequence_number: number;
  operations: WireDeleteOp[];
}

const DEVICE_ID_KEY = 'cw_logbook_device_id';
const SEQUENCE_KEY = 'cw_logbook_seq';
const PENDING_KEY = 'cw_logbook_pending_uploads';

/** Max operations per journal entry — matches `JournalPayload::MAX_OPERATIONS_PER_ENTRY`. */
const MAX_OPS_PER_ENTRY = 100;

interface PushEntryReq {
  clientEntryId: string;
  entityType: string;
  op: string;
  byteSize: number;
  contentHash: string;
}

interface PushedEntry {
  clientEntryId: string;
  seq: number;
  blobKey: string;
  uploadUrl: string;
}

interface PushResponse {
  entries: PushedEntry[];
  highWater: number;
}

/** Stable per-browser device id, minted and persisted on first delete. */
function deviceId(): string {
  let id = localStorage.getItem(DEVICE_ID_KEY);
  if (!id) {
    id = `web-${crypto.randomUUID()}`;
    localStorage.setItem(DEVICE_ID_KEY, id);
  }
  return id;
}

/** Next monotonic outbound sequence number for this browser. */
function nextSequence(): number {
  const current = Number.parseInt(localStorage.getItem(SEQUENCE_KEY) ?? '0', 10) || 0;
  const next = current + 1;
  localStorage.setItem(SEQUENCE_KEY, String(next));
  return next;
}

function bytesToBase64(bytes: Uint8Array): string {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** base64(SHA-256(bytes)) — the `contentHash` format the server records. */
async function contentHash(bytes: Uint8Array): Promise<string> {
  // Copy into a fresh ArrayBuffer-backed view so the type is `Uint8Array<ArrayBuffer>`,
  // which subtle.digest accepts (WASM returns an ArrayBufferLike-backed view).
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new Uint8Array(bytes)));
  return bytesToBase64(digest);
}

const UUID_NAMESPACE_OID = '6ba7b812-9dad-11d1-80b4-00c04fd430c8';

/** Deterministic UUIDv5 so an unchanged batch re-pushes to the same entry id
 *  (the server dedups on `client_entry_id`), making retries idempotent. */
async function uuidv5(name: string): Promise<string> {
  const ns = new Uint8Array(16);
  const hex = UUID_NAMESPACE_OID.replace(/-/g, '');
  for (let i = 0; i < 16; i++) ns[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  const nameBytes = new TextEncoder().encode(name);
  const input = new Uint8Array(ns.length + nameBytes.length);
  input.set(ns, 0);
  input.set(nameBytes, ns.length);
  const hash = new Uint8Array(await crypto.subtle.digest('SHA-1', input));
  const b = hash.slice(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50; // version 5
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

/**
 * Short, domain-separated digest of the data key. Stored alongside pending
 * uploads so a later session with a *different* key (another account on the
 * same browser) refuses to re-push ciphertext its tenant can't decrypt.
 * Reveals nothing useful about a 32-byte random key.
 */
async function keyFingerprint(dataKey: Uint8Array): Promise<string> {
  const prefix = new TextEncoder().encode('cw-logbook-pending-v1:');
  const input = new Uint8Array(prefix.length + dataKey.length);
  input.set(prefix, 0);
  input.set(dataKey, prefix.length);
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', input));
  return Array.from(digest.slice(0, 12), (x) => x.toString(16).padStart(2, '0')).join('');
}

/** Split ids into chunks of at most `MAX_OPS_PER_ENTRY`. */
function chunk(ids: string[]): string[][] {
  const out: string[][] = [];
  for (let i = 0; i < ids.length; i += MAX_OPS_PER_ENTRY) {
    out.push(ids.slice(i, i + MAX_OPS_PER_ENTRY));
  }
  return out;
}

// ---- Pending-upload store ---------------------------------------------------

/** One sealed journal entry that is (or may be) committed server-side without its blob. */
interface PendingEntry {
  clientEntryId: string;
  ciphertextB64: string;
  /** QSO ids whose Delete ops this entry carries — for the UI's local hide. */
  qsoIds: string[];
}

interface PendingUploads {
  version: 1;
  keyFingerprint: string;
  createdAt: number;
  entries: PendingEntry[];
}

function loadPending(): PendingUploads | null {
  const raw = localStorage.getItem(PENDING_KEY);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<PendingUploads>;
    if (parsed.version !== 1 || !Array.isArray(parsed.entries) || !parsed.keyFingerprint) {
      localStorage.removeItem(PENDING_KEY);
      return null;
    }
    if (parsed.entries.length === 0) {
      localStorage.removeItem(PENDING_KEY);
      return null;
    }
    return parsed as PendingUploads;
  } catch {
    localStorage.removeItem(PENDING_KEY);
    return null;
  }
}

function savePending(p: PendingUploads): void {
  if (p.entries.length === 0) {
    localStorage.removeItem(PENDING_KEY);
    return;
  }
  localStorage.setItem(PENDING_KEY, JSON.stringify(p));
}

/** Forget any parked uploads (e.g. they belong to another account's key). */
export function discardPendingUploads(): void {
  localStorage.removeItem(PENDING_KEY);
}

export interface PendingSummary {
  /** Journal entries still missing their blob. */
  entries: number;
  /** QSO deletes those entries carry. */
  qsos: number;
  /** False when the parked ciphertext was sealed under a different data key. */
  matchesKey: boolean;
  createdAt: number;
}

/**
 * What, if anything, is parked from an earlier interrupted delete. `null`
 * when nothing is pending. The UI should offer "resume" when `matchesKey` and
 * "discard" otherwise.
 */
export async function pendingUploadsFor(dataKey: Uint8Array): Promise<PendingSummary | null> {
  const pending = loadPending();
  if (!pending) return null;
  return {
    entries: pending.entries.length,
    qsos: pending.entries.reduce((n, e) => n + e.qsoIds.length, 0),
    matchesKey: pending.keyFingerprint === (await keyFingerprint(dataKey)),
    createdAt: pending.createdAt,
  };
}

// ---- Push ---------------------------------------------------------------------

export interface DeleteProgress {
  done: number;
  total: number;
}

export interface UploadFailure {
  clientEntryId: string;
  /** Human-readable reason; already includes the HTTP status where there was one. */
  error: string;
  /** `http` = the PUT got a terminal/exhausted status; `network` = fetch rejected (offline or CORS). */
  kind: 'http' | 'network';
  status?: number;
  /** QSO ids whose delete is committed server-side but not yet visible to other devices. */
  qsoIds: string[];
}

export interface PushResult {
  /** Entries whose blob is confirmed in object storage. */
  uploaded: number;
  /** Entries still missing their blob; these stay parked for `resumePendingUploads`. */
  failed: UploadFailure[];
  /** QSO ids whose Delete op is now fully durable — safe to hide locally. */
  deletedIds: string[];
  /** QSO ids carried by the failed entries. */
  pendingIds: string[];
}

/**
 * Heuristic for the error copy: the browser refuses cross-origin PUTs the R2
 * bucket's CORS policy doesn't allow with an opaque network error (no status),
 * which is indistinguishable from being offline — so "network failure while
 * online" is our best CORS signal.
 */
export function looksLikeCorsFailure(failed: UploadFailure[]): boolean {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return false;
  return failed.length > 0 && failed.every((f) => f.kind === 'network');
}

/**
 * Push every parked entry: re-POST to (re)reserve seqs and get fresh presigned
 * URLs, then PUT each ciphertext with retry. Attempts *all* entries even when
 * one fails; leftovers are written back to storage. Throws only if the push
 * request itself fails (nothing was consumed; the parked set is untouched).
 */
async function uploadPending(
  pending: PendingUploads,
  onProgress?: (p: DeleteProgress) => void,
): Promise<PushResult> {
  const ciphertexts = new Map<string, Uint8Array>();
  const byId = new Map<string, PendingEntry>();
  const entries: PushEntryReq[] = [];
  for (const e of pending.entries) {
    const ciphertext = base64ToBytes(e.ciphertextB64);
    ciphertexts.set(e.clientEntryId, ciphertext);
    byId.set(e.clientEntryId, e);
    entries.push({
      clientEntryId: e.clientEntryId,
      entityType: 'qso',
      op: 'upsert',
      byteSize: ciphertext.length,
      contentHash: await contentHash(ciphertext),
    });
  }

  const resp = await authFetch('/v1/sync/push', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ entries }),
  });
  if (!resp.ok) throw await syncFailure(resp, 'POST /v1/sync/push');
  const pushed = (await resp.json()) as PushResponse;

  const total = pushed.entries.length;
  let done = 0;
  onProgress?.({ done, total });

  const result: PushResult = { uploaded: 0, failed: [], deletedIds: [], pendingIds: [] };
  const remaining: PendingEntry[] = [];
  for (const entry of pushed.entries) {
    const ciphertext = ciphertexts.get(entry.clientEntryId);
    const parked = byId.get(entry.clientEntryId);
    if (!ciphertext || !parked) continue;
    const outcome: UploadOutcome = await putWithRetry(
      entry.uploadUrl,
      new Blob([new Uint8Array(ciphertext)]),
    );
    done += 1;
    if (outcome.ok) {
      result.uploaded += 1;
      result.deletedIds.push(...parked.qsoIds);
    } else {
      remaining.push(parked);
      result.pendingIds.push(...parked.qsoIds);
      result.failed.push({
        clientEntryId: entry.clientEntryId,
        error: outcome.error,
        kind: outcome.kind,
        status: outcome.kind === 'http' ? outcome.status : undefined,
        qsoIds: parked.qsoIds,
      });
    }
    onProgress?.({ done, total });
  }

  savePending({ ...pending, entries: remaining });
  return result;
}

/**
 * Soft-delete the given QSO ids by pushing `Delete` journal entries. Resolves
 * with a per-entry report once every upload has been attempted. Throws only
 * when the initial `POST /v1/sync/push` fails; a failed blob PUT is reported
 * in `failed` and its ciphertext stays parked for `resumePendingUploads()`.
 */
export async function pushDeletes(
  dataKey: Uint8Array,
  ids: string[],
  onProgress?: (p: DeleteProgress) => void,
): Promise<PushResult> {
  const batches = chunk(ids);
  const fingerprint = await keyFingerprint(dataKey);

  // Anything already parked under this key rides along, so a fresh delete
  // also drains an older backlog. Leftovers from another key are dropped —
  // this session could never upload them anyway.
  const previous = loadPending();
  const carried =
    previous && previous.keyFingerprint === fingerprint ? previous.entries : [];
  const seen = new Set(carried.map((e) => e.clientEntryId));

  if (batches.length === 0 && carried.length === 0) {
    return { uploaded: 0, failed: [], deletedIds: [], pendingIds: [] };
  }

  const device = deviceId();
  const now = Math.floor(Date.now() / 1000);

  const fresh: PendingEntry[] = [];
  for (const batch of batches) {
    const operations: WireDeleteOp[] = batch.map((id) => ({
      op: 'Delete',
      entity_type: 'qso',
      id,
    }));
    const entryId = await uuidv5(JSON.stringify(operations));
    if (seen.has(entryId)) continue;
    seen.add(entryId);
    const payload: WireJournalPayload = {
      id: entryId,
      device_id: device,
      timestamp: now,
      sequence_number: nextSequence(),
      operations,
    };
    const ciphertext = await sealBlob(dataKey, JSON.stringify(payload));
    fresh.push({ clientEntryId: entryId, ciphertextB64: bytesToBase64(ciphertext), qsoIds: batch });
  }

  // Park *before* the push: if the tab dies between the POST committing rows
  // and the PUTs landing, the next visit can still finish the job.
  const pending: PendingUploads = {
    version: 1,
    keyFingerprint: fingerprint,
    createdAt: previous?.createdAt ?? Date.now(),
    entries: [...carried, ...fresh],
  };
  savePending(pending);

  return uploadPending(pending, onProgress);
}

/**
 * Finish an interrupted delete: re-push only the parked entries and PUT their
 * blobs. Throws if nothing is parked, if the parked ciphertext belongs to a
 * different data key, or if the push request fails.
 */
export async function resumePendingUploads(
  dataKey: Uint8Array,
  onProgress?: (p: DeleteProgress) => void,
): Promise<PushResult> {
  const pending = loadPending();
  if (!pending) return { uploaded: 0, failed: [], deletedIds: [], pendingIds: [] };
  if (pending.keyFingerprint !== (await keyFingerprint(dataKey))) {
    throw new Error(
      'The unfinished uploads were sealed with a different sync key (another ' +
        'account on this browser). Discard them, or sign in to that account to finish.',
    );
  }
  return uploadPending(pending, onProgress);
}
