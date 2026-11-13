// Duplicate-finder pane: scans the whole logbook for duplicate QSOs (same
// call/band/mode within a time window), lets the user review each group, and
// soft-deletes the selected duplicates by pushing `Delete` ops to the sync
// journal. The keeper of each group is auto-chosen (see dedupe.ts) and left
// unchecked; the other members are pre-checked for deletion. A group must keep
// at least one QSO — the last remaining keeper can't be checked.
//
// Delete durability (CAR-319): the push commits journal rows before the blobs
// upload, so an interrupted delete leaves seqs every device 404s on. While a
// delete is in flight the tab warns before unloading; a partial upload shows
// an explicit "retry upload" state instead of a generic error; and if an
// earlier session left uploads parked (see writeClient.ts) the pane offers to
// resume them on mount.

import { useCallback, useEffect, useMemo, useState } from 'react';
import { findDuplicateGroups } from '../logbook/dedupe';
import {
  discardPendingUploads,
  looksLikeCorsFailure,
  pendingUploadsFor,
  pushDeletes,
  resumePendingUploads,
  type DeleteProgress,
  type PendingSummary,
  type PushResult,
} from '../sync/writeClient';
import { bandColor } from '../logbook/bandColors';
import type { SyncQso } from '../sync/types';

const DEFAULT_WINDOW_MIN = 15;

/** The R2 bucket must allow cross-origin PUT for the viewer's origin — a CORS
 *  refusal shows up as an opaque network failure, so name the fix explicitly. */
const CORS_HINT =
  'This looks like a CORS refusal: the R2 bucket needs a CORS policy allowing PUT ' +
  'from this origin before the browser can upload sync blobs.';

function fmtUtc(unix: number): string {
  const d = new Date(unix * 1000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())} ${p(
    d.getUTCHours(),
  )}:${p(d.getUTCMinutes())}Z`;
}

function fmtFreq(mhz?: number): string {
  // SyncQso.frequency is already MHz (the wire projects the store's kHz to MHz).
  return mhz === undefined ? '' : mhz.toFixed(3);
}

function plural(n: number, word: string): string {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}

export default function DedupePane({
  qsos,
  dataKey,
  onDeleted,
  onClose,
}: {
  qsos: SyncQso[];
  dataKey: Uint8Array;
  onDeleted: (ids: string[]) => void;
  onClose: () => void;
}) {
  const [windowMin, setWindowMin] = useState(DEFAULT_WINDOW_MIN);
  const [toDelete, setToDelete] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<DeleteProgress | null>(null);
  const [error, setError] = useState('');
  /** Set after a push whose blob uploads didn't all land — the "retry upload" state. */
  const [partial, setPartial] = useState<PushResult | null>(null);
  /** Uploads parked by an earlier session, found on mount. */
  const [parked, setParked] = useState<PendingSummary | null>(null);
  const [resumedNote, setResumedNote] = useState('');

  const groups = useMemo(
    () => findDuplicateGroups(qsos, windowMin),
    [qsos, windowMin],
  );

  // Whenever the groups change (window edit / initial scan), pre-select every
  // duplicate for deletion and leave the keepers alone.
  useEffect(() => {
    const next = new Set<string>();
    for (const g of groups) for (const d of g.duplicates) next.add(d.id);
    setToDelete(next);
  }, [groups]);

  // Close on Escape (unless mid-delete).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && !busy && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose, busy]);

  // Warn before the tab unloads while uploads are in flight. Closing mid-loop
  // is exactly what strands committed journal rows without blobs.
  useEffect(() => {
    if (!busy) return;
    const onBeforeUnload = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      // Legacy browsers need returnValue set to show the prompt.
      e.returnValue = '';
    };
    window.addEventListener('beforeunload', onBeforeUnload);
    return () => window.removeEventListener('beforeunload', onBeforeUnload);
  }, [busy]);

  // On mount, look for uploads an earlier (interrupted) delete left parked.
  useEffect(() => {
    let cancelled = false;
    pendingUploadsFor(dataKey)
      .then((summary) => {
        if (!cancelled) setParked(summary);
      })
      .catch(() => {
        // Storage unreadable — nothing to offer.
      });
    return () => {
      cancelled = true;
    };
  }, [dataKey]);

  const totalDupes = useMemo(
    () => groups.reduce((n, g) => n + g.duplicates.length, 0),
    [groups],
  );
  const selectedCount = toDelete.size;

  const toggle = (group: { keeper: SyncQso; duplicates: SyncQso[] }, id: string) => {
    setToDelete((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
        return next;
      }
      // Refuse to select the last un-selected member — every group keeps ≥1.
      const members = [group.keeper, ...group.duplicates];
      const remaining = members.filter((m) => !next.has(m.id) && m.id !== id);
      if (remaining.length === 0) return prev;
      next.add(id);
      return next;
    });
  };

  /**
   * Apply a push result: hide whatever is now durable, then either finish
   * (close when this was a delete, or clear the banner when it was a resume)
   * or drop into the retry state.
   */
  const settle = useCallback(
    (result: PushResult, closeOnSuccess: boolean) => {
      if (result.deletedIds.length > 0) onDeleted(result.deletedIds);
      if (result.failed.length === 0) {
        setPartial(null);
        setParked(null);
        setProgress(null);
        setBusy(false);
        if (closeOnSuccess) {
          onClose();
        } else {
          setResumedNote(
            `Finished uploading ${plural(result.uploaded, 'entry')} from the earlier delete.`,
          );
        }
        return;
      }
      setPartial(result);
      setParked(null);
      setProgress(null);
      setBusy(false);
    },
    [onDeleted, onClose],
  );

  const runDelete = async () => {
    setError('');
    setResumedNote('');
    setBusy(true);
    const ids = [...toDelete];
    try {
      const result = await pushDeletes(dataKey, ids, setProgress);
      settle(result, true);
    } catch (e) {
      // Only the push request itself throws — nothing was committed, so a
      // plain error (not the retry-upload state) is right here.
      setError(e instanceof Error ? e.message : 'Delete failed');
      setBusy(false);
      setProgress(null);
    }
  };

  const retryUpload = async (closeOnSuccess: boolean) => {
    setError('');
    setResumedNote('');
    setBusy(true);
    try {
      const result = await resumePendingUploads(dataKey, setProgress);
      settle(result, closeOnSuccess);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Upload retry failed');
      setBusy(false);
      setProgress(null);
    }
  };

  const discardParked = () => {
    discardPendingUploads();
    setParked(null);
    setPartial(null);
  };

  const partialCors = partial ? looksLikeCorsFailure(partial.failed) : false;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Find duplicates"
      onClick={() => !busy && onClose()}
    >
      <div
        className="flex max-h-[85vh] w-full max-w-2xl flex-col rounded-2xl border border-cw-border bg-cw-bg shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-cw-border p-5">
          <h2 className="text-lg font-semibold text-cw-white">Find duplicates</h2>
          <button
            onClick={() => !busy && onClose()}
            aria-label="Close"
            className="rounded-lg px-2 py-1 text-cw-dim transition-colors hover:text-cw-text"
          >
            ✕
          </button>
        </div>

        {parked && !partial && (
          <div
            role="status"
            className="flex flex-wrap items-center gap-3 border-b border-cw-amber/40 bg-cw-amber/10 px-5 py-3 text-sm text-cw-text"
          >
            <span>
              {parked.matchesKey ? (
                <>
                  An earlier delete left{' '}
                  <span className="font-mono text-cw-white">{plural(parked.entries, 'entry')}</span>{' '}
                  ({plural(parked.qsos, 'QSO')}) not fully uploaded. Other devices can’t sync
                  past them until the upload finishes.
                </>
              ) : (
                <>
                  Unfinished uploads from another account’s sync key are parked on this
                  browser. They can only be finished from that account.
                </>
              )}
            </span>
            <div className="ml-auto flex gap-2">
              {parked.matchesKey && (
                <button
                  onClick={() => retryUpload(false)}
                  disabled={busy}
                  className="rounded-lg bg-cw-amber px-3 py-1.5 text-sm font-medium text-cw-bg transition-colors hover:bg-cw-amber/80 disabled:opacity-40"
                >
                  {busy ? 'Uploading…' : 'Resume upload'}
                </button>
              )}
              <button
                onClick={discardParked}
                disabled={busy}
                className="rounded-lg border border-cw-border2 bg-cw-surface px-3 py-1.5 text-sm font-medium text-cw-text transition-colors hover:border-cw-dim disabled:opacity-40"
              >
                Discard
              </button>
            </div>
          </div>
        )}

        <div className="flex flex-wrap items-center gap-3 border-b border-cw-border px-5 py-3">
          <label className="flex items-center gap-2 text-sm text-cw-dim">
            Same call/band/mode within
            <input
              type="number"
              min={0}
              max={1440}
              value={windowMin}
              disabled={busy}
              onChange={(e) => setWindowMin(Math.max(0, Number(e.target.value) || 0))}
              className="w-16 rounded-lg border border-cw-border2 bg-cw-surface px-2 py-1 text-center font-mono text-cw-white focus:border-cw-blue focus:outline-none"
            />
            min
          </label>
          <span className="ml-auto text-sm text-cw-dim">
            <span className="font-mono text-cw-text">{groups.length}</span> groups ·{' '}
            <span className="font-mono text-cw-text">{totalDupes}</span> duplicates
          </span>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
          {groups.length === 0 ? (
            <p className="py-12 text-center text-cw-dim">No duplicate QSOs found.</p>
          ) : (
            <ul className="space-y-4">
              {groups.map((g) => {
                const members = [g.keeper, ...g.duplicates].sort(
                  (a, b) => a.timestamp - b.timestamp,
                );
                return (
                  <li
                    key={g.keeper.id}
                    className="overflow-hidden rounded-xl border border-cw-border"
                  >
                    <div className="flex items-center gap-2 bg-cw-surface px-3 py-2">
                      <span className="font-mono font-semibold text-cw-white">
                        {g.keeper.callsign}
                      </span>
                      <span
                        className="rounded-full px-2 py-0.5 font-mono text-xs"
                        style={{
                          backgroundColor: `${bandColor(g.keeper.band)}26`,
                          color: bandColor(g.keeper.band),
                        }}
                      >
                        {g.keeper.band}
                      </span>
                      <span className="rounded-full bg-cw-surface2 px-2 py-0.5 font-mono text-xs text-cw-dim">
                        {g.keeper.mode}
                      </span>
                      <span className="ml-auto text-xs text-cw-dim">
                        {members.length} contacts
                      </span>
                    </div>
                    <ul className="divide-y divide-cw-border/60">
                      {members.map((m) => {
                        const isKeeper = m.id === g.keeper.id;
                        const checked = toDelete.has(m.id);
                        return (
                          <li
                            key={m.id}
                            className={`flex items-center gap-3 px-3 py-2 ${
                              checked ? 'bg-cw-red/5' : ''
                            }`}
                          >
                            <input
                              type="checkbox"
                              checked={checked}
                              disabled={busy}
                              onChange={() => toggle(g, m.id)}
                              aria-label={`Delete ${m.callsign} at ${fmtUtc(m.timestamp)}`}
                              className="h-4 w-4 accent-cw-red"
                            />
                            <span className="font-mono text-sm text-cw-dim">
                              {fmtUtc(m.timestamp)}
                            </span>
                            {m.frequency !== undefined && (
                              <span className="font-mono text-xs tabular-nums text-cw-text">
                                {fmtFreq(m.frequency)}
                              </span>
                            )}
                            {(m.lotwConfirmed || m.qrzConfirmed) && (
                              <span className="rounded bg-cw-green/15 px-1.5 py-0.5 text-xs font-medium text-cw-green">
                                {m.lotwConfirmed ? 'LoTW' : 'QRZ'}
                              </span>
                            )}
                            {isKeeper && !checked && (
                              <span className="ml-auto text-xs font-medium text-cw-green">
                                keep
                              </span>
                            )}
                          </li>
                        );
                      })}
                    </ul>
                  </li>
                );
              })}
            </ul>
          )}
        </div>

        <div className="border-t border-cw-border p-5">
          {error && (
            <p className="mb-3 rounded-lg border border-cw-red/40 bg-cw-red/10 p-3 text-sm text-cw-red">
              {error}
            </p>
          )}
          {resumedNote && !error && (
            <p className="mb-3 rounded-lg border border-cw-green/40 bg-cw-green/10 p-3 text-sm text-cw-green">
              {resumedNote}
            </p>
          )}
          {partial && (
            <div
              role="alert"
              className="mb-3 rounded-lg border border-cw-amber/40 bg-cw-amber/10 p-3 text-sm text-cw-text"
            >
              <p>
                <span className="font-mono text-cw-white">{plural(partial.failed.length, 'entry')}</span>{' '}
                ({plural(partial.pendingIds.length, 'QSO')}) did not finish uploading
                {partial.uploaded > 0 && (
                  <>
                    ; <span className="font-mono text-cw-white">{partial.uploaded}</span> did
                  </>
                )}
                . The deletes are recorded on the server, but no device can sync past them
                until the upload completes. Your data is kept locally so you can retry.
              </p>
              {partialCors && <p className="mt-2 text-cw-amber">{CORS_HINT}</p>}
              <ul className="mt-2 space-y-0.5 font-mono text-xs text-cw-dim">
                {partial.failed.slice(0, 3).map((f) => (
                  <li key={f.clientEntryId}>
                    {f.clientEntryId.slice(0, 8)}… — {f.error}
                  </li>
                ))}
                {partial.failed.length > 3 && <li>…and {partial.failed.length - 3} more</li>}
              </ul>
            </div>
          )}
          {busy && progress && (
            <p className="mb-3 text-sm text-cw-dim">
              Uploading… {progress.done} / {progress.total}
            </p>
          )}
          <div className="flex items-center gap-3">
            <p className="text-sm text-cw-dim">
              {partial ? (
                <>
                  <span className="font-mono text-cw-text">{partial.pendingIds.length}</span>{' '}
                  waiting to upload
                </>
              ) : (
                <>
                  <span className="font-mono text-cw-text">{selectedCount}</span> selected for
                  deletion
                </>
              )}
            </p>
            <div className="ml-auto flex gap-2">
              <button
                onClick={() => !busy && onClose()}
                disabled={busy}
                className="rounded-lg border border-cw-border2 bg-cw-surface px-4 py-2 text-sm font-medium text-cw-text transition-colors hover:border-cw-dim disabled:opacity-40"
              >
                {partial ? 'Close' : 'Cancel'}
              </button>
              {partial ? (
                <button
                  onClick={() => retryUpload(true)}
                  disabled={busy}
                  className="rounded-lg bg-cw-amber px-4 py-2 text-sm font-medium text-cw-bg transition-colors hover:bg-cw-amber/80 disabled:opacity-40"
                >
                  {busy ? 'Uploading…' : 'Retry upload'}
                </button>
              ) : (
                <button
                  onClick={runDelete}
                  disabled={busy || selectedCount === 0}
                  className="rounded-lg bg-cw-red px-4 py-2 text-sm font-medium text-cw-white transition-colors hover:bg-cw-red/80 disabled:opacity-40"
                >
                  {busy
                    ? 'Deleting…'
                    : `Delete ${selectedCount} duplicate${selectedCount === 1 ? '' : 's'}`}
                </button>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
