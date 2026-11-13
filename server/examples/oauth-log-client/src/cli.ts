// Reference CLI: login, list, add.
//
// Usage:
//   node dist/cli.js login
//   node dist/cli.js list
//   node dist/cli.js add W1ABC 20m FT8 --freq 14.074 --rst-sent -12

import { randomUUID } from 'node:crypto';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';

import { unlockDataKey } from './crypto.js';
import { addQsos, fetchKeyBlob, loadQsos, newQso } from './log.js';
import { api, configFromEnv, login, tokenFilePath, type Config } from './oauth.js';

const SCOPES = 'openid profile sync:read sync:write';

async function main(): Promise<void> {
  const [command, ...args] = process.argv.slice(2);
  const config = configFromEnv();

  switch (command) {
    case 'login':
      await login(config, SCOPES);
      console.log(`Authorized. Tokens saved to ${tokenFilePath()}`);
      break;
    case 'list':
      await list(config);
      break;
    case 'add':
      await add(config, args);
      break;
    default:
      console.error('Usage: cli.js <login|list|add>');
      process.exitCode = 2;
  }
}

/** Who the token belongs to, via the OIDC UserInfo endpoint (`openid`). */
async function whoami(config: Config): Promise<string> {
  const resp = await api(config, '/v1/oauth/userinfo');
  if (!resp.ok) throw new Error(`userinfo failed (${resp.status})`);
  return ((await resp.json()) as { callsign: string }).callsign;
}

async function list(config: Config): Promise<void> {
  const callsign = await whoami(config);
  const dataKey = await unlock(config);
  const qsos = await loadQsos(config, dataKey);

  console.log(`\n${qsos.length} QSOs in ${callsign}'s log\n`);
  for (const qso of qsos.sort((a, b) => b.timestamp - a.timestamp).slice(0, 50)) {
    const when = new Date(qso.timestamp * 1000).toISOString().replace('T', ' ').slice(0, 16);
    const freq = qso.frequency ? `${qso.frequency.toFixed(3)} MHz` : qso.band;
    console.log(`  ${when}  ${qso.callsign.padEnd(10)} ${qso.mode.padEnd(6)} ${freq}`);
  }
  if (qsos.length > 50) console.log(`  … and ${qsos.length - 50} more`);
}

async function add(config: Config, args: string[]): Promise<void> {
  const [callsign, band, mode] = args;
  if (!callsign || !band || !mode) {
    throw new Error('Usage: add <callsign> <band> <mode> [--freq MHZ] [--rst-sent X] [--rst-rcvd X]');
  }

  const myCallsign = await whoami(config);
  const dataKey = await unlock(config);

  const qso = newQso({
    callsign,
    band,
    mode,
    myCallsign,
    frequencyMhz: numericFlag(args, '--freq'),
    rstSent: stringFlag(args, '--rst-sent'),
    rstReceived: stringFlag(args, '--rst-rcvd'),
    notes: stringFlag(args, '--notes'),
  });

  // A stable per-install device id. Real clients persist this; regenerating it
  // per run is harmless here but muddies the journal's provenance.
  const written = await addQsos(config, dataKey, [qso], `example-${randomUUID()}`);
  console.log(
    written > 0
      ? `Logged ${qso.callsign} on ${qso.band} ${qso.mode}.`
      : 'Already logged (idempotent retry).',
  );
}

/**
 * Prompt for the sync passphrase and derive the data key.
 *
 * Asked for every run and never written anywhere. Note what the user is being
 * asked to do: hand the passphrase that protects their entire log to software
 * that is not Carrier Wave. Say so, and mean it.
 */
async function unlock(config: Config): Promise<Uint8Array> {
  const keyBlob = await fetchKeyBlob(config);
  const rl = createInterface({ input: stdin, output: stdout });
  try {
    console.log(
      '\nYour log is end-to-end encrypted. This passphrase stays on this machine —\n' +
        'it is never sent to the server, and it is not saved.',
    );
    const passphrase = await rl.question('Sync passphrase: ');
    return await unlockDataKey(passphrase, keyBlob);
  } finally {
    rl.close();
  }
}

function stringFlag(args: string[], flag: string): string | undefined {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
}

function numericFlag(args: string[], flag: string): number | undefined {
  const raw = stringFlag(args, flag);
  if (raw === undefined) return undefined;
  const value = Number.parseFloat(raw);
  if (Number.isNaN(value)) throw new Error(`${flag} expects a number`);
  return value;
}

main().catch((err: unknown) => {
  console.error(`\n${err instanceof Error ? err.message : String(err)}`);
  process.exitCode = 1;
});
