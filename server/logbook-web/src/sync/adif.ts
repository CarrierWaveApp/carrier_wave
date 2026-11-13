// Build an ADIF 3.1.4 document from decrypted QSOs, client-side. Frequencies in
// SyncQso are already MHz (e.g. 14.074 for 20m FT8) — the wire projects the
// store's kHz down to MHz — and ADIF FREQ is MHz, so no conversion is needed.

import type { SyncQso } from './types';

const utf8 = new TextEncoder();

/**
 * One `<NAME:LENGTH>value ` field. ADIF LENGTH is the value's UTF-8 BYTE count
 * — not `String.length`, which counts UTF-16 code units and undercounts any
 * non-ASCII character (`José` is 4 units but 5 bytes; an emoji is 2 units but
 * 4 bytes). A short length makes strict importers truncate the value and
 * then misparse everything that follows. Mirrors `cw-domain`'s
 * `adif_writer::format_field` (`value.len()` on a Rust `&str`).
 */
export function field(name: string, value: string | undefined | null): string {
  if (value === undefined || value === null || value === '') return '';
  return `<${name}:${utf8.encode(value).length}>${value} `;
}

function utcParts(unixSeconds: number): { date: string; time: string } {
  const d = new Date(unixSeconds * 1000);
  const p = (n: number, w = 2) => String(n).padStart(w, '0');
  return {
    date: `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}`,
    time: `${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}`,
  };
}

function record(q: SyncQso): string {
  const { date, time } = utcParts(q.timestamp);
  const freqMhz =
    q.frequency !== undefined ? q.frequency.toFixed(6).replace(/0+$/, '').replace(/\.$/, '') : undefined;

  return (
    field('CALL', q.callsign) +
    field('QSO_DATE', date) +
    field('TIME_ON', time) +
    field('BAND', q.band) +
    field('MODE', q.mode) +
    field('FREQ', freqMhz) +
    field('RST_SENT', q.rstSent) +
    field('RST_RCVD', q.rstReceived) +
    field('STATION_CALLSIGN', q.stationCallsign ?? q.myCallsign) +
    field('OPERATOR', q.myCallsign) +
    field('MY_GRIDSQUARE', q.myGrid) +
    field('GRIDSQUARE', q.theirGrid) +
    field('NAME', q.name) +
    field('QTH', q.qth) +
    field('STATE', q.state) +
    field('COUNTRY', q.country) +
    field('DXCC', q.dxcc !== undefined ? String(q.dxcc) : undefined) +
    field('TX_PWR', q.power !== undefined ? String(q.power) : undefined) +
    field('SOTA_REF', q.sotaRef) +
    // POTA / WWFF park references (my activation vs. worked park).
    field('MY_SIG', q.parkReference ? 'POTA' : undefined) +
    field('MY_SIG_INFO', q.parkReference) +
    field('SIG', q.theirParkReference ? 'POTA' : undefined) +
    field('SIG_INFO', q.theirParkReference) +
    field('WWFF_REF', q.wwffRef) +
    field('SAT_NAME', q.satName) +
    field('PROP_MODE', q.propMode) +
    field('QSL_RCVD', q.lotwConfirmed ? 'Y' : undefined) +
    field('LOTW_QSL_RCVD', q.lotwConfirmed ? 'Y' : undefined) +
    field('COMMENT', q.notes) +
    '<EOR>'
  );
}

export function toAdif(qsos: SyncQso[]): string {
  const header =
    'Carrier Wave logbook export\n' +
    '<ADIF_VER:5>3.1.4 ' +
    '<PROGRAMID:12>Carrier Wave ' +
    '<EOH>\n';
  // Oldest-first, the conventional log order.
  const body = [...qsos]
    .sort((a, b) => a.timestamp - b.timestamp)
    .map((q) => record(q))
    .join('\n');
  return header + body + '\n';
}

/** Trigger a browser download of the ADIF text. */
export function downloadAdif(qsos: SyncQso[], filename = 'carrierwave-log.adi'): void {
  const blob = new Blob([toAdif(qsos)], { type: 'text/plain' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
