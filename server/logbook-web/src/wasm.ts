// Loads the cw-web-crypto WASM module (the exact Rust E2E crypto, compiled to
// wasm) and re-exports the two primitives the viewer needs. Import the .wasm as
// a URL so Vite fingerprints + serves it; init() is idempotent-guarded here.
import init, {
  open_escrow,
  decrypt_blob,
  seal_blob,
  LogbookIndex,
  KiwiAudioDecoder,
  kiwiCheckServerError,
  kiwiParseMsgValue,
  kiwiTuneCommand,
  parseKiwiDirectory,
  rankReceiversNear,
} from 'cw-web-crypto';
import wasmUrl from 'cw-web-crypto/cw_web_crypto_bg.wasm?url';

export { LogbookIndex, KiwiAudioDecoder };
// KiwiSDR helpers are synchronous once the module is initialized; callers on
// hot paths (per-websocket-frame decode) await initCrypto() once up front and
// then use these directly.
export { kiwiCheckServerError, kiwiParseMsgValue, kiwiTuneCommand };

let ready: Promise<void> | null = null;

export function initCrypto(): Promise<void> {
  if (!ready) {
    // Options-object form (wasm-bindgen ≥0.2.100); a bare URL is deprecated.
    ready = init({ module_or_path: wasmUrl }).then(() => undefined);
  }
  return ready;
}

/** Recover the 32-byte data key from the passphrase + escrow envelope. */
export async function openEscrow(
  passphrase: string,
  kdfParamsJson: string,
  wrappedKeyB64: string,
): Promise<Uint8Array> {
  await initCrypto();
  return open_escrow(passphrase, kdfParamsJson, wrappedKeyB64);
}

/** Decrypt one sealed journal blob → plaintext JournalPayload JSON string. */
export async function decryptBlob(
  dataKey: Uint8Array,
  ciphertext: Uint8Array,
): Promise<string> {
  await initCrypto();
  return decrypt_blob(dataKey, ciphertext);
}

/** Seal a JournalPayload JSON string into an upload-ready journal blob. */
export async function sealBlob(dataKey: Uint8Array, payloadJson: string): Promise<Uint8Array> {
  await initCrypto();
  return seal_blob(dataKey, payloadJson);
}

/**
 * Build a LogbookIndex over the decrypted QSOs. The index parses the QSO JSON
 * once; `.filter(query)` then runs the shared `.cwquery` engine and returns the
 * matching row indices. `.validate(query)` returns a parse-error message or null.
 */
export async function createLogbookIndex(qsosJson: string): Promise<LogbookIndex> {
  await initCrypto();
  return new LogbookIndex(qsosJson);
}

/** Stateful KiwiSDR frame decoder (shared Rust ADPCM + protocol parsing). */
export async function createKiwiDecoder(): Promise<KiwiAudioDecoder> {
  await initCrypto();
  return new KiwiAudioDecoder();
}

/** Parse the raw KiwiSDR directory JS into a JSON array of receivers. */
export async function parseKiwiDirectoryJson(jsText: string): Promise<string> {
  await initCrypto();
  return parseKiwiDirectory(jsText);
}

/**
 * Rank receivers near a point (filter to maxKm, annotate distanceKm, sort
 * nearest-first, cap at limit). Pass null coordinates for a plain capped list.
 */
export async function rankKiwiReceivers(
  receiversJson: string,
  lat: number | null,
  lon: number | null,
  maxKm: number,
  limit: number,
): Promise<string> {
  await initCrypto();
  return rankReceiversNear(receiversJson, lat, lon, maxKm, limit);
}
