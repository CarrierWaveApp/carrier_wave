// The encryption boundary.
//
// Everything here happens on THIS machine. The server holds ciphertext and a
// passphrase-wrapped key envelope; it never sees the passphrase or the data key,
// and it could not decrypt a QSO if it wanted to.
//
// The primitives come from `cw-web-crypto`, a WebAssembly build of the same
// Rust (`cw-crypto`) the iOS, macOS, and Android apps use — so a blob written
// here is byte-compatible with one written by the phone. Reimplementing
// Argon2id + ChaCha20-Poly1305 + gzip framing by hand is possible but is where
// interop bugs come from.

import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const require = createRequire(import.meta.url);

interface CwCrypto {
  initSync(module: { module: BufferSource }): unknown;
  open_escrow(passphrase: string, kdfParamsJson: string, wrappedKeyB64: string): Uint8Array;
  decrypt_blob(dataKey: Uint8Array, ciphertext: Uint8Array): string;
  seal_blob(dataKey: Uint8Array, payloadJson: string): Uint8Array;
}

let wasm: CwCrypto | undefined;

/**
 * Load the WASM module.
 *
 * The vendored package is built with wasm-bindgen's `web` target, which expects
 * to fetch its `.wasm` over HTTP. In Node we read the file and hand over the
 * bytes with `initSync` instead.
 */
async function load(): Promise<CwCrypto> {
  if (wasm) return wasm;

  const entry = require.resolve('cw-web-crypto');
  const module = (await import(entry)) as unknown as CwCrypto;
  const bytes = readFileSync(join(dirname(entry), 'cw_web_crypto_bg.wasm'));
  module.initSync({ module: bytes });

  wasm = module;
  return module;
}

/**
 * Recover the 32-byte data key from the user's passphrase and the server's
 * escrow envelope (Argon2id → KEK → unwrap).
 *
 * A wrong passphrase fails here, because the wrapped key does not authenticate
 * under the derived KEK. There is no way to distinguish "wrong passphrase" from
 * "corrupt envelope", and no recovery path: if the user has forgotten it, the
 * log cannot be read by anyone, including us.
 */
export async function unlockDataKey(
  passphrase: string,
  keyBlob: { wrappedKey: string; kdfParams: unknown },
): Promise<Uint8Array> {
  const crypto = await load();
  try {
    return crypto.open_escrow(
      passphrase,
      JSON.stringify(keyBlob.kdfParams),
      keyBlob.wrappedKey,
    );
  } catch (err) {
    // Surface the underlying message rather than assuming "wrong passphrase".
    // A malformed envelope, bad base64, or unexpected KDF parameters all fail
    // here too, and collapsing them into one friendly string turns a five-minute
    // diagnosis into an afternoon of guessing at the passphrase.
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(
      `Could not unlock the log: ${detail}. If that reads as an authentication ` +
        'or AEAD failure, the passphrase is wrong; anything else points at the ' +
        'escrow envelope itself.',
    );
  }
}

/** ChaCha20-Poly1305 open + gunzip → `JournalPayload` JSON. */
export async function decryptBlob(
  dataKey: Uint8Array,
  ciphertext: Uint8Array,
): Promise<string> {
  const crypto = await load();
  return crypto.decrypt_blob(dataKey, ciphertext);
}

/** gzip + ChaCha20-Poly1305 seal — exactly what the upload URL expects. */
export async function sealBlob(
  dataKey: Uint8Array,
  payloadJson: string,
): Promise<Uint8Array> {
  const crypto = await load();
  return crypto.seal_blob(dataKey, payloadJson);
}
