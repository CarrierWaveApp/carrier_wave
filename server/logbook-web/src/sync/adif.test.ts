import { describe, expect, it } from 'vitest';
import { field, toAdif } from './adif';
import type { SyncQso } from './types';

function qso(overrides: Partial<SyncQso> = {}): SyncQso {
  return {
    id: '00000000-0000-0000-0000-000000000001',
    callsign: 'W1AW',
    band: '20m',
    mode: 'CW',
    frequency: 14.03,
    timestamp: 1_700_000_000, // 2023-11-14 22:13:20Z
    myCallsign: 'N0CALL',
    importSource: 'test',
    qrzConfirmed: false,
    lotwConfirmed: false,
    isHidden: false,
    isActivityLogQSO: false,
    notesUserAuthored: false,
    ...overrides,
  };
}

describe('field', () => {
  it('uses the UTF-8 byte count, not UTF-16 units, as the ADIF length', () => {
    // Pinned against cw-domain/src/adif_writer.rs::format_field: "José" is
    // 4 code units / 4 chars but 5 bytes (é = 0xC3 0xA9).
    expect('José'.length).toBe(4);
    expect(field('NAME', 'José')).toBe('<NAME:5>José ');
  });

  it('counts a 4-byte emoji as 4, not the 2 UTF-16 surrogates', () => {
    const grin = '\u{1F600}';
    expect(grin.length).toBe(2);
    expect(field('COMMENT', `73 ${grin}`)).toBe(`<COMMENT:7>73 ${grin} `);
  });

  it('is unchanged for plain ASCII', () => {
    expect(field('CALL', 'W1AW')).toBe('<CALL:4>W1AW ');
  });

  it('omits empty and absent values', () => {
    expect(field('QTH', '')).toBe('');
    expect(field('QTH', undefined)).toBe('');
    expect(field('QTH', null)).toBe('');
  });
});

describe('toAdif', () => {
  it('emits byte-accurate lengths for non-ASCII fields in a record', () => {
    const out = toAdif([qso({ name: 'José', qth: 'Zürich', notes: 'gl \u{1F600}' })]);
    expect(out).toContain('<NAME:5>José ');
    expect(out).toContain('<QTH:7>Zürich ');
    expect(out).toContain('<COMMENT:7>gl \u{1F600} ');
    expect(out).toContain('<CALL:4>W1AW ');
    expect(out).toContain('<QSO_DATE:8>20231114 ');
    expect(out).toContain('<TIME_ON:6>221320 ');
    expect(out.trimEnd().endsWith('<EOR>')).toBe(true);
  });
});
