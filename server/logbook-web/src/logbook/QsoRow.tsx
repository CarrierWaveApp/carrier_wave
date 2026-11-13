// iOS-app-style QSO list row (mirrors the iOS Logbook `QSORow` portrait layout):
// a band-color bar, callsign + name + time on the first line, then
// freq / band pill / mode pill / park on the second. Used on narrow screens.
import type { SyncQso } from '../sync/types';
import { bandColor } from './bandColors';

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

export function QsoRow({ qso }: { qso: SyncQso }) {
  const color = bandColor(qso.band);
  const park = qso.parkReference ?? qso.theirParkReference;
  return (
    <div className="flex gap-3 px-4 py-3">
      <div className="w-1 shrink-0 rounded-full" style={{ backgroundColor: color }} />
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2">
          <span className="font-mono font-semibold text-cw-white">{qso.callsign}</span>
          {qso.name && <span className="truncate text-sm text-cw-dim">{qso.name}</span>}
          <span className="ml-auto shrink-0 font-mono text-xs text-cw-dim">
            {fmtUtc(qso.timestamp)}
          </span>
        </div>
        <div className="mt-1.5 flex flex-wrap items-center gap-1.5 text-xs">
          {qso.frequency !== undefined && (
            <span className="font-mono tabular-nums text-cw-text">{fmtFreq(qso.frequency)}</span>
          )}
          <span
            className="rounded-full px-2 py-0.5 font-mono font-medium"
            style={{ backgroundColor: `${color}26`, color }}
          >
            {qso.band}
          </span>
          <span className="rounded-full bg-cw-surface2 px-2 py-0.5 font-mono text-cw-dim">
            {qso.mode}
          </span>
          {qso.theirGrid && <span className="font-mono text-cw-dim">{qso.theirGrid}</span>}
          {park && <span className="font-mono text-cw-green">🌲 {park}</span>}
          <span className="ml-auto flex gap-1">
            {qso.lotwConfirmed && (
              <span className="rounded bg-cw-green/15 px-1.5 py-0.5 font-medium text-cw-green">
                LoTW
              </span>
            )}
            {qso.qrzConfirmed && (
              <span className="rounded bg-cw-green/15 px-1.5 py-0.5 font-medium text-cw-green">
                QRZ
              </span>
            )}
          </span>
        </div>
      </div>
    </div>
  );
}
