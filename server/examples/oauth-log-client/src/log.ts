// Reading and writing the encrypted journal.
//
// The log is not a table you query — it is an append-only journal of encrypted
// blobs. You reconstruct the current set of QSOs by replaying every operation in
// server-sequence order. An edit is a later upsert with the same id; a delete is
// a tombstone. Last write wins by `seq`.

import { createHash, randomUUID } from 'node:crypto';

import { decryptBlob, sealBlob } from './crypto.js';
import { api, type Config } from './oauth.js';
import {
  MAX_OPS_PER_ENTRY,
  type BootstrapResponse,
  type ChangeItem,
  type ChangesResponse,
  type JournalPayload,
  type KeyBlob,
  type PushResponse,
  type SyncQso,
} from './types.js';

/**
 * Page size for `/v1/sync/changes`. The server clamps `limit` to [1, 1000];
 * asking for the max halves the round trips versus its default of 500.
 */
const CHANGES_PAGE_LIMIT = 1000;

/** `GET /v1/sync/key` — the passphrase-wrapped envelope (`sync:read`). */
export async function fetchKeyBlob(config: Config): Promise<KeyBlob> {
  const resp = await api(config, '/v1/sync/key');
  if (resp.status === 404) {
    throw new Error('This account has not set up log sync yet — there is nothing to read.');
  }
  if (!resp.ok) throw new Error(await failure(resp, 'GET /v1/sync/key'));
  return (await resp.json()) as KeyBlob;
}

const SNAPSHOT_UNSUPPORTED = 'This log has a server snapshot, which this example cannot read.';

/**
 * Download and replay the whole journal.
 *
 * `/v1/sync/bootstrap` hands back only the FIRST page of entries (500 by
 * server default) plus `highWater`, the newest seq. A client that folds that
 * page and stops has the oldest 500 entries and none of the recent QSOs — and
 * nothing tells it so. This keeps pulling `/v1/sync/changes?since=<lastSeq>`
 * until the highest applied seq reaches `highWater`.
 *
 * Still naive on purpose: a real client persists `highWater` and pulls only
 * `/v1/sync/changes?since=` on subsequent runs instead of re-reading everything.
 */
export async function loadQsos(config: Config, dataKey: Uint8Array): Promise<SyncQso[]> {
  const resp = await api(config, '/v1/sync/bootstrap');
  if (!resp.ok) throw new Error(await failure(resp, 'GET /v1/sync/bootstrap'));
  const boot = (await resp.json()) as BootstrapResponse;

  // Snapshots compact the journal. Reading the entries alone once a snapshot
  // exists would silently skip everything folded into it, so refuse rather than
  // return a partial log that looks complete.
  if (boot.snapshotUrl) throw new Error(SNAPSHOT_UNSUPPORTED);

  const byId = new Map<string, SyncQso>();
  let highWater = boot.highWater;
  let lastSeq = boot.snapshotSeq ?? 0;

  lastSeq = await applyEntries(dataKey, byId, boot.entries, lastSeq);

  while (lastSeq < highWater) {
    const page = await changesSince(config, lastSeq);
    if (page.snapshotUrl) throw new Error(SNAPSHOT_UNSUPPORTED);

    const pageMax = page.entries.reduce((m, e) => Math.max(m, e.seq), lastSeq);
    if (page.entries.length === 0 || pageMax <= lastSeq) {
      // The server says more exists but returns nothing past our cursor.
      // Returning here would present a truncated log as complete.
      throw new Error(
        `sync paging stalled: applied through seq ${lastSeq}, server reports highWater ` +
          `${highWater}, but GET /v1/sync/changes?since=${lastSeq} returned no newer entries`,
      );
    }

    // Another device may push while we load; follow the moving high-water mark
    // rather than stopping at the bootstrap-time value.
    highWater = Math.max(highWater, page.highWater);
    lastSeq = await applyEntries(dataKey, byId, page.entries, lastSeq);
  }

  // `isHidden` is the app's soft delete. The rows stay in the journal.
  return [...byId.values()].filter((qso) => !qso.isHidden);
}

/** One page of `GET /v1/sync/changes` — entries with `seq > since`. */
async function changesSince(config: Config, since: number): Promise<ChangesResponse> {
  const path = `/v1/sync/changes?since=${since}&limit=${CHANGES_PAGE_LIMIT}`;
  const resp = await api(config, path);
  if (!resp.ok) throw new Error(await failure(resp, `GET ${path}`));
  return (await resp.json()) as ChangesResponse;
}

/**
 * Download, decrypt and fold one page of entries into `byId`. Returns the
 * highest seq applied so far (the cursor for the next `/changes` call).
 */
async function applyEntries(
  dataKey: Uint8Array,
  byId: Map<string, SyncQso>,
  entries: ChangeItem[],
  lastSeq: number,
): Promise<number> {
  // Sequence order is what makes the replay deterministic. Do not skip this
  // sort: the server does not promise `entries` arrives ordered.
  for (const entry of [...entries].sort((a, b) => a.seq - b.seq)) {
    // Presigned URL — deliberately no Authorization header.
    const blobResp = await fetch(entry.downloadUrl);
    if (!blobResp.ok) {
      throw new Error(`blob download failed for seq ${entry.seq} (${blobResp.status})`);
    }

    const ciphertext = new Uint8Array(await blobResp.arrayBuffer());
    const payload = JSON.parse(await decryptBlob(dataKey, ciphertext)) as JournalPayload;

    for (const op of payload.operations) {
      switch (op.op) {
        case 'UpsertQso': {
          const { op: _tag, ...qso } = op as { op: string } & SyncQso;
          byId.set(qso.id, qso as SyncQso);
          break;
        }
        case 'Delete':
          byId.delete((op as { id: string }).id);
          break;
        default:
          // An operation type minted by a newer client. Skipping it is REQUIRED
          // forward-compatibility: throwing here would discard the QSOs in the
          // same batch and break this client the day a new op ships.
          break;
      }
    }

    lastSeq = Math.max(lastSeq, entry.seq);
  }
  return lastSeq;
}

/**
 * Append QSOs to the journal (`sync:write`).
 *
 * Two steps, because the server never handles blob bytes: `push` reserves
 * sequence numbers and hands back presigned upload URLs, then the ciphertext
 * goes straight to object storage.
 */
export async function addQsos(
  config: Config,
  dataKey: Uint8Array,
  qsos: SyncQso[],
  deviceId: string,
): Promise<number> {
  if (qsos.length === 0) return 0;
  if (qsos.length > MAX_OPS_PER_ENTRY) {
    throw new Error(`at most ${MAX_OPS_PER_ENTRY} operations per journal entry`);
  }

  const payload: JournalPayload = {
    id: randomUUID(),
    device_id: deviceId,
    timestamp: Math.floor(Date.now() / 1000),
    sequence_number: Date.now(),
    operations: qsos.map((qso) => ({ op: 'UpsertQso' as const, ...qso })),
  };

  const ciphertext = await sealBlob(dataKey, JSON.stringify(payload));

  // Deriving the entry id from the CONTENT makes a retry idempotent: the server
  // dedups on `clientEntryId`, so a push that timed out after the server
  // committed does not produce a duplicate entry on the second attempt.
  const contentHash = createHash('sha256').update(ciphertext).digest('base64');
  const clientEntryId = uuidV5FromHash(contentHash);

  const pushResp = await api(config, '/v1/sync/push', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      entries: [
        {
          clientEntryId,
          entityType: 'QSO',
          op: 'Upsert',
          byteSize: ciphertext.length,
          contentHash,
        },
      ],
    }),
  });
  if (!pushResp.ok) throw new Error(await failure(pushResp, 'POST /v1/sync/push'));
  const push = (await pushResp.json()) as PushResponse;

  const target = push.entries.find((e) => e.clientEntryId === clientEntryId);
  if (!target) {
    // Already stored from an earlier attempt; nothing left to upload.
    return 0;
  }

  const upload = await fetch(target.uploadUrl, {
    method: 'PUT',
    body: ciphertext as unknown as BodyInit,
  });
  if (!upload.ok) {
    throw new Error(`blob upload failed (${upload.status}) for seq ${target.seq}`);
  }

  return qsos.length;
}

/** Build a QSO with the fields the apps expect to always be present. */
export function newQso(fields: {
  callsign: string;
  band: string;
  mode: string;
  myCallsign: string;
  frequencyMhz?: number;
  timestamp?: number;
  rstSent?: string;
  rstReceived?: string;
  notes?: string;
}): SyncQso {
  return {
    id: randomUUID(),
    callsign: fields.callsign.toUpperCase(),
    band: fields.band,
    mode: fields.mode.toUpperCase(),
    // MHz. See the note in types.ts.
    frequency: fields.frequencyMhz,
    timestamp: fields.timestamp ?? Math.floor(Date.now() / 1000),
    rstSent: fields.rstSent,
    rstReceived: fields.rstReceived,
    myCallsign: fields.myCallsign.toUpperCase(),
    notes: fields.notes,
    // Identify yourself here — it is how a user tells where a QSO came from.
    importSource: 'oauth-example',
    modifiedAt: Math.floor(Date.now() / 1000),
    qrzConfirmed: false,
    lotwConfirmed: false,
    isHidden: false,
    isActivityLogQSO: false,
    notesUserAuthored: fields.notes !== undefined,
  };
}

/** UUIDv5-shaped id derived from a content hash (stable across retries). */
function uuidV5FromHash(contentHash: string): string {
  const bytes = createHash('sha1').update(contentHash).digest();
  const b = Uint8Array.prototype.slice.call(bytes, 0, 16);
  b[6] = (b[6] & 0x0f) | 0x50; // version 5
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  const hex = Buffer.from(b).toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(
    16,
    20,
  )}-${hex.slice(20)}`;
}

async function failure(resp: Response, what: string): Promise<string> {
  const body = (await resp.json().catch(() => ({}))) as {
    error?: { code?: string; message?: string };
  };
  const code = body.error?.code;
  if (resp.status === 403 && code === 'FORBIDDEN') {
    return `${what}: forbidden. This token is missing the required scope, or the route is not open to third-party clients.`;
  }
  if (resp.status === 403 && code === 'ACCOUNT_REQUIRED') {
    return `${what}: this token has no account tenant.`;
  }
  return `${what} failed (${resp.status}${code ? ` ${code}` : ''})`;
}
