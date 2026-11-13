// Pulls the E2E-encrypted journal and reconstructs the current logbook.
//
// Flow (all client-side; the server never sees plaintext):
//   1. getKeyBlob()  — GET /v1/sync/key → escrow envelope (wrapped key + KDF).
//   2. <caller unlocks the data key with the passphrase via openEscrow>
//   3. bootstrap()   — GET /v1/sync/bootstrap → presigned R2 download URLs for
//      the FIRST page of the journal (server default: 500 entries) + highWater.
//   4. loadAllQsos() — download each blob (R2, no auth header), decrypt via
//      WASM, JSON.parse the JournalPayload, and fold operations into a QSO map;
//      then keep paging GET /v1/sync/changes?since=<lastSeq> until the highest
//      applied seq reaches highWater.

import { authFetch, syncFailure } from '../auth/session';
import { decryptBlob } from '../wasm';
import type {
  BootstrapResponse,
  ChangeItem,
  ChangesResponse,
  JournalPayload,
  KeyBlob,
  SyncQso,
} from './types';

/**
 * Page size for `/v1/sync/changes`. The server clamps `limit` to [1, 1000], so
 * asking for the max halves the round trips versus its default of 500.
 */
const CHANGES_PAGE_LIMIT = 1000;

export async function getKeyBlob(): Promise<KeyBlob> {
  const resp = await authFetch('/v1/sync/key');
  if (resp.status === 404) {
    throw new Error('No sync key is set up for this account yet.');
  }
  if (!resp.ok) throw await syncFailure(resp, 'GET /v1/sync/key');
  return (await resp.json()) as KeyBlob;
}

async function bootstrap(): Promise<BootstrapResponse> {
  const resp = await authFetch('/v1/sync/bootstrap');
  if (!resp.ok) throw await syncFailure(resp, 'GET /v1/sync/bootstrap');
  return (await resp.json()) as BootstrapResponse;
}

/** `GET /v1/sync/changes?since=&limit=` — entries with `seq > since`, ascending. */
async function changesSince(since: number): Promise<ChangesResponse> {
  const resp = await authFetch(
    `/v1/sync/changes?since=${encodeURIComponent(since)}&limit=${CHANGES_PAGE_LIMIT}`,
  );
  if (!resp.ok) throw await syncFailure(resp, `GET /v1/sync/changes?since=${since}`);
  return (await resp.json()) as ChangesResponse;
}

export interface LoadProgress {
  done: number;
  total: number;
}

/** A journal entry that was listed by the server but could not be loaded. */
export interface SkippedEntry {
  seq: number;
  reason: string;
}

export interface LoadResult {
  /** Current, non-hidden QSOs after replaying every readable entry. */
  qsos: SyncQso[];
  /**
   * Entries whose blob is gone (the presigned GET returned 404). The journal
   * row exists but the ciphertext was never uploaded or has since been deleted,
   * so whatever operations it held are missing from `qsos`. Empty on a clean
   * load; callers should surface a non-empty list to the user.
   */
  skipped: SkippedEntry[];
}

const SNAPSHOT_UNSUPPORTED =
  'This logbook has a server snapshot, which this viewer cannot yet read. ' +
  'Please update the viewer.';

/**
 * Download + decrypt every journal entry and fold it into the current set of
 * QSOs, keyed by id. Entries are applied in server-sequence order, so a later
 * upsert (or delete) for the same id wins — the same replay a fresh client does.
 *
 * Bootstrap only returns the first page of the journal (500 entries by server
 * default), so the tail is pulled with `/v1/sync/changes` until the highest
 * seq we have applied reaches `highWater`. Returning early would drop the most
 * RECENT QSOs while looking like a successful load.
 */
export async function loadAllQsos(
  dataKey: Uint8Array,
  onProgress?: (p: LoadProgress) => void,
): Promise<LoadResult> {
  const boot = await bootstrap();

  // No client writes snapshots yet (the transport has no snapshot support), so
  // bootstrap returns the journal from seq 1 in `entries`. If that ever changes
  // we'd silently miss pre-snapshot state — fail loudly instead.
  if (boot.snapshotUrl) throw new Error(SNAPSHOT_UNSUPPORTED);

  const byId = new Map<string, SyncQso>();
  const skipped: SkippedEntry[] = [];
  let highWater = boot.highWater;
  let lastSeq = boot.snapshotSeq ?? 0;
  let done = 0;

  // Seqs are gap-free per tenant, so with no snapshot `highWater` is the entry
  // count. It can grow if another device pushes mid-load; `total` tracks it.
  const total = () => Math.max(highWater, done);
  onProgress?.({ done, total: total() });

  const applyPage = async (page: ChangeItem[]): Promise<void> => {
    // The server does not promise ordered pages; sequence order is what makes
    // the replay deterministic.
    for (const entry of [...page].sort((a, b) => a.seq - b.seq)) {
      const payload = await downloadAndDecrypt(dataKey, entry);
      if (payload === null) {
        skipped.push({ seq: entry.seq, reason: 'blob missing (404)' });
      } else {
        applyPayload(byId, payload);
      }
      lastSeq = Math.max(lastSeq, entry.seq);
      done += 1;
      onProgress?.({ done, total: total() });
    }
  };

  await applyPage(boot.entries);

  while (lastSeq < highWater) {
    const page = await changesSince(lastSeq);
    if (page.snapshotUrl) throw new Error(SNAPSHOT_UNSUPPORTED);

    const pageMax = page.entries.reduce((m, e) => Math.max(m, e.seq), lastSeq);
    if (page.entries.length === 0 || pageMax <= lastSeq) {
      // The server says more exists (highWater) but hands back nothing past
      // our cursor. Returning here would present a truncated log as complete.
      throw new Error(
        `Sync paging stalled: loaded through seq ${lastSeq} but the server reports ` +
          `highWater ${highWater} and GET /v1/sync/changes?since=${lastSeq} returned no ` +
          'newer entries. Please retry; if this persists, report it.',
      );
    }

    // Track a moving high-water mark so pushes that land during the load are
    // picked up rather than cut off at the bootstrap-time value.
    highWater = Math.max(highWater, page.highWater);
    await applyPage(page.entries);
  }

  // Hidden QSOs are soft-deleted in the app; don't surface them.
  return { qsos: [...byId.values()].filter((q) => !q.isHidden), skipped };
}

/**
 * Fetch and decrypt one entry's blob. Returns `null` when the object is gone
 * (404): the journal row outlived its ciphertext, and one dangling entry must
 * not brick the whole load. Every other failure still throws.
 */
async function downloadAndDecrypt(
  dataKey: Uint8Array,
  entry: ChangeItem,
): Promise<JournalPayload | null> {
  // Presigned R2 URL — no Authorization header (it carries its own signature).
  const resp = await fetch(entry.downloadUrl);
  if (resp.status === 404) return null;
  if (!resp.ok) {
    throw new Error(
      `blob download failed for seq ${entry.seq} (${resp.status}). ` +
        'If this is a CORS error, the R2 bucket needs a CORS policy for this origin.',
    );
  }
  const ciphertext = new Uint8Array(await resp.arrayBuffer());
  const json = await decryptBlob(dataKey, ciphertext);
  return JSON.parse(json) as JournalPayload;
}

function applyPayload(byId: Map<string, SyncQso>, payload: JournalPayload): void {
  for (const op of payload.operations) {
    if (op.op === 'UpsertQso') {
      const { op: _op, ...qso } = op;
      byId.set(qso.id, qso as SyncQso);
    } else if (op.op === 'Delete') {
      byId.delete(op.id);
    }
  }
}
