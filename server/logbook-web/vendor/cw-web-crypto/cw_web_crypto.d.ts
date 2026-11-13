/* tslint:disable */
/* eslint-disable */

/**
 * Stateful KiwiSDR frame decoder for one websocket connection. Carries the
 * IMA ADPCM state across frames and applies server-sent
 * `audio_adpcm_state=index,predictor` resets.
 */
export class KiwiAudioDecoder {
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Classify one binary websocket payload. SND frames decode to PCM
     * (compressed frames advance the internal ADPCM state); everything else
     * is treated as UTF-8 text and classified per the stream-text rules.
     */
    handleFrame(data: Uint8Array): KiwiFrameEvent;
    constructor();
}

/**
 * One classified websocket payload. `kind` is one of:
 *
 * - `"audio"` — `samples` (Int16 PCM) and `sMeter` are set.
 * - `"adpcmReset"` — server reset the ADPCM state (already applied).
 * - `"redirect"` — the receiver wants us elsewhere; reconnect or bail.
 * - `"disconnected"` — server-initiated disconnect (`too_busy>0`, `MSG down`,
 *   inactivity timeout); `text` carries the raw message.
 * - `"text"` — non-actionable text (handshake `MSG` lines land here; run
 *   [`kiwi_check_server_error`] / [`kiwi_parse_msg_value`] over `text`).
 * - `"none"` — an unusable binary frame (short/IQ/empty SND).
 */
export class KiwiFrameEvent {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    readonly kind: string;
    /**
     * Raw s-meter reading for `"audio"` events (dBm = value / 10 − 127).
     */
    readonly sMeter: number | undefined;
    /**
     * Decoded Int16 PCM samples for `"audio"` events.
     */
    readonly samples: Int16Array | undefined;
    /**
     * The UTF-8 text of a non-SND payload (KiwiSDR sends MSG text inside
     * binary websocket frames).
     */
    readonly text: string | undefined;
}

/**
 * A parsed set of decrypted QSOs, ready to filter by `.cwquery` repeatedly.
 */
export class LogbookIndex {
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Indices of the rows matching `query` (in index order). An empty/whitespace
     * query matches everything. A syntax error returns a `JsError` carrying the
     * parser's message so the UI can show it inline.
     */
    filter(query: string): Uint32Array;
    /**
     * Parse the decrypted QSOs (a JSON array in load order). Row indices returned
     * by [`filter`](Self::filter) refer to this order.
     */
    constructor(qsos_json: string);
    /**
     * Validate a query without running it. Returns the parser error message, or
     * `null` when the query is valid — for live syntax feedback while typing.
     */
    validate(query: string): string | undefined;
    readonly is_empty: boolean;
    /**
     * Number of indexed rows.
     */
    readonly len: number;
}

/**
 * Open a sealed journal blob and return the plaintext `JournalPayload` JSON.
 *
 * `data_key` must be the 32 bytes from [`open_escrow`]; `ciphertext` is the raw
 * blob body downloaded from the presigned R2 URL. Decrypts with
 * ChaCha20Poly1305, then gunzips (legacy blobs are raw JSON with no gzip
 * header, so those pass through unchanged).
 */
export function decrypt_blob(data_key: Uint8Array, ciphertext: Uint8Array): string;

/**
 * Check a handshake-phase server message. Returns `null` when the message is
 * benign, otherwise a short human-readable error. A redirect is reported as
 * `"redirect:<target>"` so the caller can distinguish it. **`too_busy=0` is
 * informational and returns `null`.**
 */
export function kiwiCheckServerError(message: string): string | undefined;

/**
 * Extract `key=` from a `MSG key=value` message (e.g. `sample_rate`).
 */
export function kiwiParseMsgValue(message: string, key: string): string | undefined;

/**
 * Build the `SET mod=` tune command for a Carrier Wave mode string.
 * `frequency_mhz` disambiguates SSB (LSB below 10 MHz, USB at or above); the
 * CW carrier offset is applied by the shared mode table.
 */
export function kiwiTuneCommand(frequency_khz: number, mode: string, frequency_mhz?: number | null): string;

/**
 * Recover the 32-byte data key from `passphrase` + the escrow envelope.
 *
 * `kdf_params_json` is the JSON object stored under `kdfParams` by the server
 * (`{"salt":[..16..],"m_cost":..,"t_cost":..,"p_cost":..}`); `wrapped_key_b64`
 * is the base64 `wrappedKey`. Fails on a wrong passphrase (the wrapped key does
 * not authenticate under the derived KEK).
 */
export function open_escrow(passphrase: string, kdf_params_json: string, wrapped_key_b64: string): Uint8Array;

/**
 * Parse the Skywavelinux directory JS mirror (`var kiwisdr_com = [ … ];`)
 * into a JSON array of receivers. Inactive/offline entries are dropped;
 * garbage input yields `[]`.
 */
export function parseKiwiDirectory(js_text: string): string;

/**
 * Rank receivers near a point: filter to `max_km`, annotate `distanceKm`,
 * sort nearest-first, cap at `limit`. With `lat`/`lon` omitted the list is
 * passed through uncapped by distance (just truncated), for spots with no
 * usable coordinates. `receivers_json` is the output of
 * [`parse_kiwi_directory`].
 */
export function rankReceiversNear(receivers_json: string, lat: number | null | undefined, lon: number | null | undefined, max_km: number, limit: number): string;

/**
 * Seal a plaintext `JournalPayload` JSON into a journal blob.
 *
 * The inverse of [`decrypt_blob`]: gzip the JSON, then ChaCha20Poly1305-seal
 * it under `data_key`. The returned bytes are exactly what the presigned R2
 * upload URL expects. Mirrors the `compress`/`aead::seal` step in
 * `cw-sync/src/http_transport.rs::push`.
 */
export function seal_blob(data_key: Uint8Array, payload_json: string): Uint8Array;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly decrypt_blob: (a: number, b: number, c: number, d: number) => [number, number, number, number];
    readonly open_escrow: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number, number, number];
    readonly seal_blob: (a: number, b: number, c: number, d: number) => [number, number, number, number];
    readonly __wbg_kiwiaudiodecoder_free: (a: number, b: number) => void;
    readonly __wbg_kiwiframeevent_free: (a: number, b: number) => void;
    readonly kiwiCheckServerError: (a: number, b: number) => [number, number];
    readonly kiwiParseMsgValue: (a: number, b: number, c: number, d: number) => [number, number];
    readonly kiwiTuneCommand: (a: number, b: number, c: number, d: number, e: number) => [number, number];
    readonly kiwiaudiodecoder_handleFrame: (a: number, b: number, c: number) => number;
    readonly kiwiaudiodecoder_new: () => number;
    readonly kiwiframeevent_kind: (a: number) => [number, number];
    readonly kiwiframeevent_sMeter: (a: number) => number;
    readonly kiwiframeevent_samples: (a: number) => [number, number];
    readonly kiwiframeevent_text: (a: number) => [number, number];
    readonly parseKiwiDirectory: (a: number, b: number) => [number, number];
    readonly rankReceiversNear: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => [number, number, number, number];
    readonly __wbg_logbookindex_free: (a: number, b: number) => void;
    readonly logbookindex_filter: (a: number, b: number, c: number) => [number, number, number, number];
    readonly logbookindex_is_empty: (a: number) => number;
    readonly logbookindex_len: (a: number) => number;
    readonly logbookindex_new: (a: number, b: number) => [number, number, number];
    readonly logbookindex_validate: (a: number, b: number, c: number) => [number, number];
    readonly __wbindgen_exn_store: (a: number) => void;
    readonly __externref_table_alloc: () => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
