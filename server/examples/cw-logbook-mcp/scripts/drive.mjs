// Minimal MCP host, for testing this server without an MCP client attached.
//
// Speaks JSON-RPC over stdio exactly as Claude Code or Claude Desktop would:
// initialize -> notifications/initialized -> tools/list -> tools/call. Use it to
// check a change end-to-end instead of round-tripping through a real host.
//
//   DRIVE_CALLS='[["whoami",{}],["log_summary",{}]]' npm run drive
//
// Environment (CW_CLIENT_ID, CW_BASE_URL, CW_TOKEN_FILE, CW_SYNC_PASSPHRASE) is
// passed straight through to the server under test.
import { spawn } from 'node:child_process';

const child = spawn('node', ['dist/index.js'], {
  stdio: ['pipe', 'pipe', 'inherit'],
  env: { ...process.env },
});

let buf = '';
const pending = new Map();
child.stdout.on('data', (d) => {
  buf += d.toString();
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    const msg = JSON.parse(line);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  }
});

let id = 0;
const send = (method, params) => new Promise((res) => {
  const rid = ++id;
  pending.set(rid, res);
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: rid, method, params }) + '\n');
});
const notify = (method, params) =>
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n');

const init = await send('initialize', {
  protocolVersion: '2024-11-05',
  capabilities: {},
  clientInfo: { name: 'drive', version: '0' },
});
console.log('server:', JSON.stringify(init.result.serverInfo));
notify('notifications/initialized', {});

const tools = await send('tools/list', {});
console.log('\ntools:');
for (const t of tools.result.tools) {
  console.log(`  ${t.name.padEnd(14)} ${(t.description || '').split('\n')[0].slice(0, 78)}`);
}

for (const [name, args] of JSON.parse(process.env.DRIVE_CALLS || '[]')) {
  const r = await send('tools/call', { name, arguments: args });
  const out = r.result?.content?.[0]?.text ?? JSON.stringify(r.error ?? r.result);
  console.log(`\n--- ${name}(${JSON.stringify(args)}) ${r.result?.isError ? '[isError]' : ''} ---`);
  console.log(out.length > 1400 ? out.slice(0, 1400) + '\n…truncated' : out);
}

child.kill();
