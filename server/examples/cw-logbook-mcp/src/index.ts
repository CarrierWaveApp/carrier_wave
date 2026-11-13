#!/usr/bin/env node
// MCP server exposing a Carrier Wave logbook over the third-party OAuth API.
//
// This is a real third-party client — it holds no privileged position. It goes
// through the same authorization-server flow, carries the same `cid`-stamped
// token, and is subject to the same default-deny scope gate as anyone else's
// application. That makes it a working exercise of the whole API surface as
// well as a useful tool.
//
// # The two secrets, and why they are separate
//
// - The OAuth tokens (written by `cw-oauth-log-client login`) authorize ACCESS.
// - The sync passphrase authorizes DECRYPTION, locally.
//
// The server never sees the passphrase. Neither does the MCP host: it is read
// from the environment at startup, used to derive the data key, and the
// passphrase string itself is dropped immediately afterward.
//
// # Configuration
//
//   CW_CLIENT_ID          required — a registered OAuth client_id
//   CW_BASE_URL           default https://activities.carrierwave.app
//   CW_TOKEN_FILE         default ~/.cw-tokens.json
//   CW_SYNC_PASSPHRASE    required for anything that reads QSOs
//   CW_CACHE_TTL_SECONDS  default 300

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  addQsos,
  api,
  configFromEnv,
  fetchKeyBlob,
  filterQsos,
  loadQsos,
  newQso,
  unlockDataKey,
  validateQuery,
  QUERY_FIELDS,
  type Config,
  type SyncQso,
} from 'cw-oauth-log-client';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';

const CACHE_TTL_MS = Number.parseInt(process.env.CW_CACHE_TTL_SECONDS ?? '300', 10) * 1000;

const config: Config = configFromEnv();

// --- log cache --------------------------------------------------------------

interface CachedLog {
  qsos: SyncQso[];
  loadedAt: number;
}

let cache: CachedLog | undefined;
let dataKey: Uint8Array | undefined;
let inFlight: Promise<CachedLog> | undefined;

/**
 * The data key, derived once per process.
 *
 * Argon2id is deliberately expensive (that is the point), so deriving it on
 * every tool call would add seconds to each one.
 */
async function key(): Promise<Uint8Array> {
  if (dataKey) return dataKey;

  const passphrase = process.env.CW_SYNC_PASSPHRASE;
  if (!passphrase) {
    throw new Error(
      'CW_SYNC_PASSPHRASE is not set. This log is end-to-end encrypted — the server ' +
        'cannot decrypt it, so the passphrase must be provided to this process.',
    );
  }

  const keyBlob = await fetchKeyBlob(config);
  dataKey = await unlockDataKey(passphrase, keyBlob);

  // The derived key is what is needed from here on; keep the passphrase out of
  // this process's environment so it cannot leak into a crash dump or a child.
  delete process.env.CW_SYNC_PASSPHRASE;

  return dataKey;
}

/**
 * The current log, from cache when fresh.
 *
 * Concurrent calls share one load: MCP hosts happily fire several tools at
 * once, and re-downloading and re-decrypting the whole journal per call would
 * be both slow and rude to the server.
 */
async function log(forceRefresh = false): Promise<CachedLog> {
  if (!forceRefresh && cache && Date.now() - cache.loadedAt < CACHE_TTL_MS) return cache;
  if (inFlight) return inFlight;

  inFlight = (async () => {
    const qsos = await loadQsos(config, await key());
    cache = { qsos, loadedAt: Date.now() };
    return cache;
  })();

  try {
    return await inFlight;
  } finally {
    inFlight = undefined;
  }
}

// --- formatting -------------------------------------------------------------

function formatQso(qso: SyncQso): string {
  const when = new Date(qso.timestamp * 1000).toISOString().replace('T', ' ').slice(0, 16);
  const parts = [
    when,
    qso.callsign,
    qso.mode,
    // MHz on the wire; ADIF FREQ is also MHz, so this is printed as-is.
    qso.frequency ? `${qso.frequency.toFixed(3)} MHz` : qso.band,
  ];
  if (qso.parkReference) parts.push(`park ${qso.parkReference}`);
  if (qso.theirParkReference) parts.push(`their park ${qso.theirParkReference}`);
  if (qso.sotaRef) parts.push(`SOTA ${qso.sotaRef}`);
  if (qso.name) parts.push(qso.name);
  if (qso.state) parts.push(qso.state);
  else if (qso.country) parts.push(qso.country);
  if (qso.rstSent || qso.rstReceived) {
    parts.push(`${qso.rstSent ?? '—'}/${qso.rstReceived ?? '—'}`);
  }
  return parts.join('  ');
}

function text(body: string) {
  return { content: [{ type: 'text' as const, text: body }] };
}

/** Turn a thrown value into a tool error the model can act on. */
function failure(err: unknown) {
  return {
    content: [{ type: 'text' as const, text: err instanceof Error ? err.message : String(err) }],
    isError: true,
  };
}

function tally(values: (string | undefined)[]): [string, number][] {
  const counts = new Map<string, number>();
  for (const value of values) {
    if (!value) continue;
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
}

// --- server -----------------------------------------------------------------

const server = new McpServer({ name: 'cw-logbook', version: '0.1.0' });

server.registerTool(
  'whoami',
  {
    title: 'Who am I',
    description:
      'The Carrier Wave account this server is authorized for, and the scopes it was granted. ' +
      'Needs no sync passphrase, so it is the quickest check that OAuth is working.',
    inputSchema: {},
    annotations: { readOnlyHint: true },
  },
  async () => {
    try {
      const resp = await api(config, '/v1/oauth/userinfo');
      if (!resp.ok) {
        return failure(new Error(`userinfo failed (${resp.status}). Try logging in again.`));
      }
      const info = (await resp.json()) as { sub: string; callsign: string; email?: string };
      return text(
        [
          `Callsign:  ${info.callsign}`,
          `Account:   ${info.sub}`,
          info.email ? `Email:     ${info.email}` : undefined,
          `Server:    ${config.baseUrl}`,
          `Client:    ${config.clientId}`,
        ]
          .filter(Boolean)
          .join('\n'),
      );
    } catch (err) {
      return failure(err);
    }
  },
);

server.registerTool(
  'search_qsos',
  {
    title: 'Search QSOs',
    description:
      "Search the operator's logged contacts using the Carrier Wave query language — the same " +
      'grammar the mobile apps use.\n\n' +
      'Terms are `field:value`, combined with AND by default; `OR` and `-` (negation) are ' +
      'supported, and bare words match the callsign.\n\n' +
      `Fields: ${QUERY_FIELDS.join(', ')}.\n\n` +
      'Examples: `band:20m mode:ft8`, `park:US-1044 after:2026-01-01`, ' +
      '`state:CA -confirmed`, `W1AW OR K1ABC`.\n\n' +
      'An empty query returns the most recent contacts.',
    inputSchema: {
      query: z.string().describe('Query expression. Empty matches everything.'),
      limit: z.number().int().min(1).max(500).default(50).describe('Max contacts to return.'),
      refresh: z
        .boolean()
        .default(false)
        .describe('Re-download the log instead of using the cached copy.'),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ query, limit, refresh }) => {
    try {
      const problem = await validateQuery(query);
      if (problem) return failure(new Error(`Invalid query: ${problem}`));

      const { qsos, loadedAt } = await log(refresh);
      const matched = (await filterQsos(qsos, query)).sort((a, b) => b.timestamp - a.timestamp);
      const shown = matched.slice(0, limit);

      if (matched.length === 0) {
        return text(`No contacts matched \`${query}\` (searched ${qsos.length} QSOs).`);
      }

      const age = Math.round((Date.now() - loadedAt) / 1000);
      const header =
        `${matched.length} of ${qsos.length} contacts matched` +
        (shown.length < matched.length ? `, showing ${shown.length}` : '') +
        ` (log loaded ${age}s ago)`;

      return text([header, '', ...shown.map(formatQso)].join('\n'));
    } catch (err) {
      return failure(err);
    }
  },
);

server.registerTool(
  'log_summary',
  {
    title: 'Log summary',
    description:
      'Totals for the whole log: contacts by band, mode, year, and most-worked callsigns. ' +
      'Use this before search_qsos to understand what is actually in the log.',
    inputSchema: {
      refresh: z
        .boolean()
        .default(false)
        .describe('Re-download the log instead of using the cached copy.'),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ refresh }) => {
    try {
      const { qsos } = await log(refresh);
      if (qsos.length === 0) return text('The log is empty.');

      const sorted = [...qsos].sort((a, b) => a.timestamp - b.timestamp);
      const first = new Date(sorted[0]!.timestamp * 1000).toISOString().slice(0, 10);
      const last = new Date(sorted[sorted.length - 1]!.timestamp * 1000)
        .toISOString()
        .slice(0, 10);

      const line = (entries: [string, number][], max = 12) =>
        entries
          .slice(0, max)
          .map(([k, n]) => `${k} (${n})`)
          .join(', ');

      const years = tally(
        qsos.map((q) => new Date(q.timestamp * 1000).getUTCFullYear().toString()),
      ).sort((a, b) => a[0].localeCompare(b[0]));

      const parks = tally(qsos.map((q) => q.parkReference ?? q.theirParkReference));
      const uniqueCalls = new Set(qsos.map((q) => q.callsign)).size;

      return text(
        [
          `${qsos.length} contacts, ${uniqueCalls} unique callsigns, ${first} → ${last}`,
          '',
          `Bands:  ${line(tally(qsos.map((q) => q.band)))}`,
          `Modes:  ${line(tally(qsos.map((q) => q.mode)))}`,
          `Years:  ${line(years, 20)}`,
          parks.length > 0 ? `Parks:  ${line(parks, 10)}` : undefined,
          '',
          `Most worked: ${line(tally(qsos.map((q) => q.callsign)), 10)}`,
        ]
          .filter((l) => l !== undefined)
          .join('\n'),
      );
    } catch (err) {
      return failure(err);
    }
  },
);

server.registerTool(
  'add_qso',
  {
    title: 'Log a contact',
    description:
      "Append a contact to the operator's log. This writes to their real logbook and syncs to " +
      'every device they own, so confirm the details with them before calling it. ' +
      'Requires the sync:write scope.',
    inputSchema: {
      callsign: z.string().describe('Station worked, e.g. W1AW.'),
      band: z.string().describe('Band, e.g. 20m.'),
      mode: z.string().describe('Mode, e.g. FT8, CW, SSB.'),
      frequencyMhz: z.number().optional().describe('Frequency in MEGAHERTZ, e.g. 14.074.'),
      timestamp: z
        .number()
        .int()
        .optional()
        .describe('Unix seconds (UTC). Defaults to now.'),
      rstSent: z.string().optional().describe('Report sent.'),
      rstReceived: z.string().optional().describe('Report received.'),
      notes: z.string().optional().describe('Free-text note.'),
    },
    annotations: { readOnlyHint: false, destructiveHint: false },
  },
  async (args) => {
    try {
      const resp = await api(config, '/v1/oauth/userinfo');
      if (!resp.ok) return failure(new Error(`userinfo failed (${resp.status})`));
      const { callsign: myCallsign } = (await resp.json()) as { callsign: string };

      const qso = newQso({ ...args, myCallsign });
      const written = await addQsos(config, await key(), [qso], `mcp-${randomUUID()}`);

      // The new entry is not in the cached fold; drop it so the next read sees it.
      cache = undefined;

      return text(
        written > 0
          ? `Logged ${qso.callsign} — ${qso.band} ${qso.mode}` +
              (qso.frequency ? ` @ ${qso.frequency.toFixed(3)} MHz` : '') +
              `, ${new Date(qso.timestamp * 1000).toISOString().replace('T', ' ').slice(0, 16)} UTC.`
          : 'That contact was already logged (idempotent retry).',
      );
    } catch (err) {
      return failure(err);
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
