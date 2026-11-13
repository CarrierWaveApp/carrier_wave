// Library surface, so other packages reuse this protocol code rather than
// reimplementing Argon2id / blob framing / journal folding and drifting from it.
//
// The CLI in `cli.ts` is one consumer; `../cw-logbook-mcp` is another.

export { api, accessToken, configFromEnv, login, tokenFilePath, type Config, type Tokens } from './oauth.js';
export { decryptBlob, sealBlob, unlockDataKey } from './crypto.js';
export { addQsos, fetchKeyBlob, loadQsos, newQso } from './log.js';
export { filterQsos, validateQuery, QUERY_FIELDS } from './query.js';
export * from './types.js';
