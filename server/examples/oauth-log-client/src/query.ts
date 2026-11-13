// The Carrier Wave query language, over a decrypted set of QSOs.
//
// This is not a reimplementation — `LogbookIndex` is compiled from
// `rust/cw-core/cw-domain/src/query/` (lexer → parser → evaluator), the same
// code the iOS and Android apps run. A query that works in the app works here,
// and stays working when the grammar grows.

import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

import type { SyncQso } from './types.js';

const require = createRequire(import.meta.url);

interface LogbookIndexCtor {
  new (qsosJson: string): {
    filter(query: string): Uint32Array;
    validate(query: string): string | undefined;
    readonly len: number;
    free(): void;
  };
}

interface CwCryptoQuery {
  initSync(module: { module: BufferSource }): unknown;
  LogbookIndex: LogbookIndexCtor;
}

let wasm: CwCryptoQuery | undefined;

async function load(): Promise<CwCryptoQuery> {
  if (wasm) return wasm;
  const entry = require.resolve('cw-web-crypto');
  const module = (await import(entry)) as unknown as CwCryptoQuery;
  module.initSync({ module: readFileSync(join(dirname(entry), 'cw_web_crypto_bg.wasm')) });
  wasm = module;
  return module;
}

/** Field names the grammar accepts, for help text and error messages. */
export const QUERY_FIELDS = [
  'call',
  'callsign',
  'band',
  'mode',
  'freq',
  'frequency',
  'park',
  'pota',
  'sota',
  'grid',
  'state',
  'country',
  'dxcc',
  'name',
  'op',
  'qth',
  'notes',
  'mycall',
  'mygrid',
  'date',
  'on',
  'after',
  'since',
  'from',
  'before',
  'until',
  'to',
  'power',
  'confirmed',
  'synced',
  'pending',
  'source',
] as const;

/**
 * Syntax check without running the query. Returns the parser's message, or
 * `undefined` when the query is valid.
 */
export async function validateQuery(query: string): Promise<string | undefined> {
  const { LogbookIndex } = await load();
  const index = new LogbookIndex('[]');
  try {
    return index.validate(query);
  } finally {
    index.free();
  }
}

/**
 * Rows matching `query`, in the order given. An empty query matches everything.
 *
 * Throws with the parser's own message on a syntax error, so the caller can show
 * something more useful than "invalid query".
 */
export async function filterQsos(qsos: SyncQso[], query: string): Promise<SyncQso[]> {
  if (!query.trim()) return qsos;

  const { LogbookIndex } = await load();
  const index = new LogbookIndex(JSON.stringify(qsos));
  try {
    const problem = index.validate(query);
    if (problem) throw new Error(problem);
    return Array.from(index.filter(query), (row) => qsos[row]).filter(
      (qso): qso is SyncQso => qso !== undefined,
    );
  } finally {
    // WASM memory is not garbage-collected for us; a long-lived process that
    // skips this leaks the whole indexed log on every search.
    index.free();
  }
}
