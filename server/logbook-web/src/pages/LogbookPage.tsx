import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { loadAllQsos, type LoadProgress, type SkippedEntry } from '../sync/syncClient';
import { downloadAdif } from '../sync/adif';
import { useAppState } from '../state/AppState';
import { createLogbookIndex, type LogbookIndex } from '../wasm';
import { WaveMark, Wordmark } from '../components/Brand';
import AccountPane from '../components/AccountPane';
import DedupePane from '../components/DedupePane';
import { QsoRow } from '../logbook/QsoRow';
import { QUICK_FILTERS, bandColor } from '../logbook/bandColors';
import type { SyncQso } from '../sync/types';

type SortKey = 'timestamp' | 'callsign' | 'band' | 'mode' | 'frequency';
type SortDir = 'asc' | 'desc';

const PAGE_SIZE = 100;

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

export default function LogbookPage() {
  const nav = useNavigate();
  const { dataKey, qsos, setQsos, logout } = useAppState();

  const [progress, setProgress] = useState<LoadProgress | null>(null);
  const [error, setError] = useState('');
  // Journal entries whose blob was missing on the server. Their QSOs are
  // absent from `qsos`, so the user must be told the log is incomplete.
  const [skipped, setSkipped] = useState<SkippedEntry[]>([]);
  const [query, setQuery] = useState('');
  const [sortKey, setSortKey] = useState<SortKey>('timestamp');
  const [sortDir, setSortDir] = useState<SortDir>('desc');
  const [index, setIndex] = useState<LogbookIndex | null>(null);
  const [accountOpen, setAccountOpen] = useState(false);
  const [dedupeOpen, setDedupeOpen] = useState(false);
  const [page, setPage] = useState(0);

  // Load + decrypt.
  useEffect(() => {
    if (qsos !== null || !dataKey) return;
    let cancelled = false;
    (async () => {
      try {
        setError('');
        const loaded = await loadAllQsos(dataKey, (p) => !cancelled && setProgress(p));
        if (!cancelled) {
          setSkipped(loaded.skipped);
          setQsos(loaded.qsos);
        }
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : 'Failed to load logs');
      } finally {
        if (!cancelled) setProgress(null);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [dataKey, qsos, setQsos]);

  // Build the shared-engine query index once the QSOs are decrypted.
  useEffect(() => {
    if (!qsos) return;
    let disposed = false;
    let built: LogbookIndex | null = null;
    createLogbookIndex(JSON.stringify(qsos)).then((idx) => {
      if (disposed) {
        idx.free();
      } else {
        built = idx;
        setIndex(idx);
      }
    });
    return () => {
      disposed = true;
      built?.free();
      setIndex(null);
    };
  }, [qsos]);

  // Filter via the WASM `.cwquery` engine → indices into `qsos`. A parse error
  // surfaces inline and leaves everything shown.
  const { rows, queryError } = useMemo<{ rows: SyncQso[]; queryError: string | null }>(() => {
    const all = qsos ?? [];
    const trimmed = query.trim();
    if (!index || !trimmed) return { rows: all, queryError: null };
    const err = index.validate(trimmed);
    if (err) return { rows: all, queryError: err };
    const matched: SyncQso[] = [];
    for (const idx of index.filter(trimmed)) matched.push(all[idx]);
    return { rows: matched, queryError: null };
  }, [index, query, qsos]);

  const sorted = useMemo(() => {
    const dir = sortDir === 'asc' ? 1 : -1;
    return [...rows].sort((a, b) => {
      const av = a[sortKey];
      const bv = b[sortKey];
      if (av === undefined) return 1;
      if (bv === undefined) return -1;
      if (av < bv) return -1 * dir;
      if (av > bv) return 1 * dir;
      return 0;
    });
  }, [rows, sortKey, sortDir]);

  const pageCount = Math.max(1, Math.ceil(sorted.length / PAGE_SIZE));

  // Keep the page in range as the filtered set shrinks/grows.
  useEffect(() => {
    if (page > pageCount - 1) setPage(pageCount - 1);
  }, [page, pageCount]);

  // Jump back to the first page whenever the query or sort changes.
  useEffect(() => {
    setPage(0);
  }, [query, sortKey, sortDir]);

  const pageStart = page * PAGE_SIZE;
  const pageRows = useMemo(
    () => sorted.slice(pageStart, pageStart + PAGE_SIZE),
    [sorted, pageStart],
  );

  const toggleSort = (key: SortKey) => {
    if (key === sortKey) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(key);
      setSortDir(key === 'timestamp' ? 'desc' : 'asc');
    }
  };

  if (qsos === null) {
    return (
      <div className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center px-6 text-center">
        <WaveMark className="h-10 w-10" />
        <h1 className="mt-4 text-lg font-medium text-cw-white">
          {error ? 'Could not load your logbook' : 'Decrypting your logbook…'}
        </h1>
        {error ? (
          <>
            <p className="mt-3 rounded-lg border border-cw-red/40 bg-cw-red/10 p-3 text-sm text-cw-red">
              {error}
            </p>
            <button
              onClick={() => setQsos(null)}
              className="mt-4 rounded-lg bg-cw-blue px-4 py-2 text-sm font-medium text-cw-bg hover:bg-cw-blue2"
            >
              Retry
            </button>
          </>
        ) : (
          <>
            <p className="cw-eyebrow mt-3 text-[0.62rem]">
              {progress ? `${progress.done} / ${progress.total} entries` : 'Starting…'}
            </p>
            {progress && progress.total > 0 && (
              <div className="mt-3 h-1 w-56 overflow-hidden rounded-full bg-cw-surface2">
                <div
                  className="h-full rounded-full bg-cw-blue transition-all"
                  style={{ width: `${(progress.done / progress.total) * 100}%` }}
                />
              </div>
            )}
          </>
        )}
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-7xl px-4 py-6">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-4">
          <Wordmark />
          <span className="hidden text-sm text-cw-dim sm:inline">
            <span className="font-mono text-cw-text">{sorted.length.toLocaleString()}</span>
            {' of '}
            <span className="font-mono text-cw-text">{qsos.length.toLocaleString()}</span> QSOs
          </span>
        </div>
        <div className="flex gap-2">
          <Link
            to="/spots"
            className="rounded-lg border border-cw-border2 bg-cw-surface px-4 py-2 text-sm font-medium text-cw-text transition-colors hover:border-cw-dim"
          >
            Spots
          </Link>
          <button
            onClick={() => downloadAdif(sorted)}
            disabled={sorted.length === 0}
            className="rounded-lg bg-cw-blue px-4 py-2 text-sm font-medium text-cw-bg transition-colors hover:bg-cw-blue2 disabled:opacity-40"
          >
            Export ADIF
          </button>
          {dataKey && (
            <button
              onClick={() => setDedupeOpen(true)}
              disabled={qsos.length === 0}
              className="rounded-lg border border-cw-border2 bg-cw-surface px-4 py-2 text-sm font-medium text-cw-text transition-colors hover:border-cw-dim disabled:opacity-40"
            >
              Find duplicates
            </button>
          )}
          <button
            onClick={() => setAccountOpen(true)}
            className="rounded-lg border border-cw-border2 bg-cw-surface px-4 py-2 text-sm font-medium text-cw-text transition-colors hover:border-cw-dim"
          >
            Account
          </button>
          <button
            onClick={() => {
              logout();
              nav('/login', { replace: true });
            }}
            className="rounded-lg border border-cw-border2 bg-cw-surface px-4 py-2 text-sm font-medium text-cw-text transition-colors hover:border-cw-dim"
          >
            Sign out
          </button>
        </div>
      </header>

      {skipped.length > 0 && (
        <div
          role="alert"
          className="mt-4 rounded-lg border border-cw-amber/50 bg-cw-amber/10 px-4 py-3 text-sm text-cw-text"
        >
          <span className="font-medium text-cw-amber">Incomplete logbook.</span>{' '}
          <span className="font-mono">{skipped.length.toLocaleString()}</span>{' '}
          {skipped.length === 1 ? 'journal entry' : 'journal entries'} could not be downloaded
          because the encrypted data is missing on the server (seq{' '}
          <span className="font-mono">
            {skipped
              .slice(0, 8)
              .map((s) => s.seq)
              .join(', ')}
            {skipped.length > 8 ? ', …' : ''}
          </span>
          ). QSOs recorded in those entries are not shown, exported, or checked for duplicates.
        </div>
      )}

      {accountOpen && <AccountPane onClose={() => setAccountOpen(false)} />}

      {dedupeOpen && dataKey && (
        <DedupePane
          qsos={qsos}
          dataKey={dataKey}
          onDeleted={(ids) => {
            const gone = new Set(ids);
            setQsos(qsos.filter((q) => !gone.has(q.id)));
          }}
          onClose={() => setDedupeOpen(false)}
        />
      )}

      {/* .cwquery search bar — the same query language as the iOS logbook. */}
      <div className="mt-5">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search callsign, or use band:20m, mode:CW, after:30d…"
          spellCheck={false}
          autoCapitalize="none"
          className={`w-full rounded-lg border bg-cw-surface px-3.5 py-2.5 font-mono text-sm text-cw-white placeholder:font-sans placeholder:text-cw-xdim focus:outline-none focus:ring-1 ${
            queryError
              ? 'border-cw-red/60 focus:border-cw-red focus:ring-cw-red'
              : 'border-cw-border2 focus:border-cw-blue focus:ring-cw-blue'
          }`}
        />
        {queryError && <p className="mt-1.5 text-xs text-cw-red">{queryError}</p>}
        <div className="mt-2 flex flex-wrap gap-2">
          {QUICK_FILTERS.map((f) => {
            const active = query.trim() === f.query;
            return (
              <button
                key={f.query}
                onClick={() => setQuery(active ? '' : f.query)}
                className="rounded-full border px-3 py-1 text-xs font-medium transition-colors"
                style={
                  active
                    ? { backgroundColor: `${f.tint}26`, borderColor: f.tint, color: f.tint }
                    : { borderColor: '#2a2f38', color: '#c9cdd6' }
                }
              >
                {f.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* Mobile: iOS-style list. Desktop: dense table. */}
      <div className="mt-4 divide-y divide-cw-border/60 overflow-hidden rounded-xl border border-cw-border md:hidden">
        {pageRows.map((qso) => (
          <QsoRow key={qso.id} qso={qso} />
        ))}
        {sorted.length === 0 && (
          <div className="px-4 py-12 text-center text-cw-dim">No QSOs match this query.</div>
        )}
      </div>

      <div className="mt-4 hidden overflow-x-auto rounded-xl border border-cw-border md:block">
        <table className="min-w-full text-sm">
          <thead>
            <tr className="border-b border-cw-border bg-cw-surface">
              <Th label="Date (UTC)" onClick={() => toggleSort('timestamp')} active={sortKey === 'timestamp'} dir={sortDir} />
              <Th label="Call" onClick={() => toggleSort('callsign')} active={sortKey === 'callsign'} dir={sortDir} />
              <Th label="Band" onClick={() => toggleSort('band')} active={sortKey === 'band'} dir={sortDir} />
              <Th label="Mode" onClick={() => toggleSort('mode')} active={sortKey === 'mode'} dir={sortDir} />
              <Th label="Freq (MHz)" onClick={() => toggleSort('frequency')} active={sortKey === 'frequency'} dir={sortDir} />
              <PlainTh>RST S/R</PlainTh>
              <PlainTh>Grid</PlainTh>
              <PlainTh>Park</PlainTh>
              <PlainTh>Conf.</PlainTh>
            </tr>
          </thead>
          <tbody>
            {pageRows.map((q) => (
              <tr key={q.id} className="border-b border-cw-border/60 last:border-0 hover:bg-cw-surface/60">
                <td className="whitespace-nowrap px-3 py-2 font-mono text-cw-dim">{fmtUtc(q.timestamp)}</td>
                <td className="whitespace-nowrap px-3 py-2 font-mono font-medium text-cw-white">{q.callsign}</td>
                <td className="whitespace-nowrap px-3 py-2">
                  <span
                    className="rounded-full px-2 py-0.5 font-mono text-xs"
                    style={{ backgroundColor: `${bandColor(q.band)}26`, color: bandColor(q.band) }}
                  >
                    {q.band}
                  </span>
                </td>
                <td className="whitespace-nowrap px-3 py-2">
                  <span className="rounded-full bg-cw-surface2 px-2 py-0.5 font-mono text-xs text-cw-dim">
                    {q.mode}
                  </span>
                </td>
                <td className="whitespace-nowrap px-3 py-2 font-mono tabular-nums text-cw-text">{fmtFreq(q.frequency)}</td>
                <td className="whitespace-nowrap px-3 py-2 font-mono text-cw-dim">
                  {[q.rstSent, q.rstReceived].filter(Boolean).join(' / ')}
                </td>
                <td className="whitespace-nowrap px-3 py-2 font-mono text-cw-dim">{q.theirGrid ?? ''}</td>
                <td className="whitespace-nowrap px-3 py-2 font-mono text-cw-dim">
                  {q.parkReference ?? q.theirParkReference ?? ''}
                </td>
                <td className="whitespace-nowrap px-3 py-2">
                  {q.lotwConfirmed && <Badge>LoTW</Badge>}
                  {q.qrzConfirmed && <Badge>QRZ</Badge>}
                </td>
              </tr>
            ))}
            {sorted.length === 0 && (
              <tr>
                <td colSpan={9} className="px-3 py-12 text-center text-cw-dim">
                  No QSOs match this query.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {sorted.length > PAGE_SIZE && (
        <Pagination
          page={page}
          pageCount={pageCount}
          pageStart={pageStart}
          shown={pageRows.length}
          total={sorted.length}
          onPage={setPage}
        />
      )}
    </div>
  );
}

function Pagination({
  page,
  pageCount,
  pageStart,
  shown,
  total,
  onPage,
}: {
  page: number;
  pageCount: number;
  pageStart: number;
  shown: number;
  total: number;
  onPage: (p: number) => void;
}) {
  // A compact window of page numbers around the current page.
  const windowSize = 5;
  let first = Math.max(0, page - Math.floor(windowSize / 2));
  const last = Math.min(pageCount - 1, first + windowSize - 1);
  first = Math.max(0, last - windowSize + 1);
  const nums: number[] = [];
  for (let i = first; i <= last; i++) nums.push(i);

  return (
    <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
      <span className="text-sm text-cw-dim">
        Showing{' '}
        <span className="font-mono text-cw-text">
          {(pageStart + 1).toLocaleString()}–{(pageStart + shown).toLocaleString()}
        </span>{' '}
        of <span className="font-mono text-cw-text">{total.toLocaleString()}</span>
      </span>
      <div className="flex items-center gap-1">
        <PageButton disabled={page === 0} onClick={() => onPage(page - 1)}>
          Prev
        </PageButton>
        {first > 0 && (
          <>
            <PageButton active={false} onClick={() => onPage(0)}>
              1
            </PageButton>
            {first > 1 && <span className="px-1 text-cw-dim">…</span>}
          </>
        )}
        {nums.map((n) => (
          <PageButton key={n} active={n === page} onClick={() => onPage(n)}>
            {n + 1}
          </PageButton>
        ))}
        {last < pageCount - 1 && (
          <>
            {last < pageCount - 2 && <span className="px-1 text-cw-dim">…</span>}
            <PageButton active={false} onClick={() => onPage(pageCount - 1)}>
              {pageCount}
            </PageButton>
          </>
        )}
        <PageButton disabled={page === pageCount - 1} onClick={() => onPage(page + 1)}>
          Next
        </PageButton>
      </div>
    </div>
  );
}

function PageButton({
  children,
  onClick,
  active,
  disabled,
}: {
  children: React.ReactNode;
  onClick: () => void;
  active?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`min-w-[2rem] rounded-lg border px-2.5 py-1.5 text-sm font-medium transition-colors disabled:opacity-40 ${
        active
          ? 'border-cw-blue bg-cw-blue/15 text-cw-blue'
          : 'border-cw-border2 bg-cw-surface text-cw-text hover:border-cw-dim'
      }`}
    >
      {children}
    </button>
  );
}

function Th({
  label,
  onClick,
  active,
  dir,
}: {
  label: string;
  onClick: () => void;
  active: boolean;
  dir: SortDir;
}) {
  return (
    <th className="px-3 py-2.5 text-left">
      <button
        onClick={onClick}
        className={`cw-eyebrow inline-flex items-center gap-1 text-[0.6rem] transition-colors hover:text-cw-text ${
          active ? 'text-cw-blue' : ''
        }`}
      >
        {label}
        <span>{active ? (dir === 'asc' ? '▲' : '▼') : ''}</span>
      </button>
    </th>
  );
}

function PlainTh({ children }: { children: React.ReactNode }) {
  return <th className="cw-eyebrow px-3 py-2.5 text-left text-[0.6rem]">{children}</th>;
}

function Badge({ children }: { children: React.ReactNode }) {
  return (
    <span className="mr-1 inline-block rounded bg-cw-green/15 px-1.5 py-0.5 text-xs font-medium text-cw-green">
      {children}
    </span>
  );
}
