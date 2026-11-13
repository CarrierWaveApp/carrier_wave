// Duplicate-QSO detection for the logbook viewer.
//
// Two QSOs are considered duplicates when they share callsign + band + mode and
// their timestamps fall within `windowMinutes` of each other. Within a matched
// cluster one QSO is chosen as the *keeper* and the rest are flagged for
// deletion (a soft-delete pushed back to the E2E sync journal).
//
// Keeper preference, in order: a confirmed QSO (LoTW/QRZ) beats an unconfirmed
// one; then the more-complete record (more populated fields) wins; ties break to
// the earliest timestamp, then the id, so the result is fully deterministic.

import type { SyncQso } from '../sync/types';

export interface DuplicateGroup {
  /** The QSO we keep. */
  keeper: SyncQso;
  /** The duplicates of `keeper`, flagged for deletion by default. */
  duplicates: SyncQso[];
}

/** Normalize the fields that define QSO identity for grouping. */
function bucketKey(q: SyncQso): string {
  return `${q.callsign.trim().toUpperCase()}|${q.band.trim().toLowerCase()}|${q.mode.trim().toUpperCase()}`;
}

/** Rough completeness score — how many optional fields carry data. */
function completeness(q: SyncQso): number {
  const fields: (string | number | undefined)[] = [
    q.frequency,
    q.rstSent,
    q.rstReceived,
    q.theirGrid,
    q.myGrid,
    q.parkReference,
    q.theirParkReference,
    q.name,
    q.qth,
    q.state,
    q.country,
    q.power,
    q.notes,
    q.sotaRef,
    q.wwffRef,
  ];
  let score = fields.reduce<number>((n, f) => n + (f !== undefined && f !== '' ? 1 : 0), 0);
  if (q.lotwConfirmed) score += 100;
  if (q.qrzConfirmed) score += 100;
  return score;
}

/** True when `a` is a better keeper than `b`. */
function prefersFirst(a: SyncQso, b: SyncQso): boolean {
  const ca = completeness(a);
  const cb = completeness(b);
  if (ca !== cb) return ca > cb;
  if (a.timestamp !== b.timestamp) return a.timestamp < b.timestamp;
  return a.id < b.id;
}

/**
 * Find duplicate groups across all QSOs. Only groups with at least one duplicate
 * are returned. Runs in O(n log n): bucket by call/band/mode, sort each bucket
 * by time, then sweep, chaining any two consecutive QSOs within the window into
 * the same cluster.
 */
export function findDuplicateGroups(qsos: SyncQso[], windowMinutes: number): DuplicateGroup[] {
  const windowSecs = Math.max(0, windowMinutes) * 60;
  const buckets = new Map<string, SyncQso[]>();
  for (const q of qsos) {
    const key = bucketKey(q);
    const bucket = buckets.get(key);
    if (bucket) bucket.push(q);
    else buckets.set(key, [q]);
  }

  const groups: DuplicateGroup[] = [];
  for (const bucket of buckets.values()) {
    if (bucket.length < 2) continue;
    bucket.sort((a, b) => a.timestamp - b.timestamp);

    let cluster: SyncQso[] = [bucket[0]];
    const flush = () => {
      if (cluster.length >= 2) groups.push(toGroup(cluster));
      cluster = [];
    };
    for (let i = 1; i < bucket.length; i++) {
      const prev = bucket[i - 1];
      const cur = bucket[i];
      if (cur.timestamp - prev.timestamp <= windowSecs) {
        cluster.push(cur);
      } else {
        flush();
        cluster = [cur];
      }
    }
    flush();
  }

  // Present the most recent duplicates first — that's what a user scanning a
  // freshly-imported log wants to see.
  groups.sort((a, b) => b.keeper.timestamp - a.keeper.timestamp);
  return groups;
}

function toGroup(cluster: SyncQso[]): DuplicateGroup {
  let keeper = cluster[0];
  for (const q of cluster) {
    if (prefersFirst(q, keeper)) keeper = q;
  }
  const duplicates = cluster.filter((q) => q.id !== keeper.id);
  return { keeper, duplicates };
}
