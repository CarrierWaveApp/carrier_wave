# WebSDR bridge fails for kiwisdr.com-proxied receivers

**Date:** 2026-07-03
**Status:** Fixed (`server/src/handlers/websdr.rs`)

## Symptom

Web logbook Spots page, Safari:

```
WebSocket connection to 'wss://activities.carrierwave.app/v1/websdr/stream?host=21832.proxy.kiwisdr.com&port=8073' failed: The network connection was lost.
```

## Investigation

1. **nginx / deploy ruled out.** A hand-rolled HTTP/1.1 upgrade request against
   production returned `101 Switching Protocols` — the nginx websocket block
   and the deployed 0.4.86 build are fine. The server then sent
   `MSG cw_proxy_error=connect_failed` and closed, i.e. the *upstream* connect
   from the Hetzner box to the receiver failed. (First curl attempt returned
   400 — curl defaults to HTTP/2, where `Upgrade` doesn't exist. Use
   `--http1.1` when testing websocket handshakes.)
2. **Receiver reachable, but behind a redirect chain.** Receivers listed as
   `NNNN.proxy.kiwisdr.com:8073` are fronted by an frp redirector:
   - `ws://21832.proxy.kiwisdr.com:8073/ws/kiwi/{ts}/SND` → **HTTP/1.0** 307 →
     `http://21832.proxy2.kiwisdr.com/ws/kiwi/{ts}/snd` (port 80, path lowercased)
   - that lighttpd → 307 → `http://21832.proxy2.kiwisdr.com:8073/...`
   - only the final hop completes the 101 handshake.
3. **Why the bridge failed:** `tokio_tungstenite::connect_async` doesn't follow
   redirects. Worse, the frp hop answers with **HTTP/1.0**, which tungstenite
   rejects as `ProtocolError::WrongHttpVersion` *before* exposing the response
   — so even redirect-aware `Error::Http` handling never sees the `Location`.

## Fix

`connect_following_redirects` in the websdr handler:

- follows up to 3 redirect hops (`Error::Http` 3xx → read `Location`;
  `WrongHttpVersion` → re-issue as a plain HTTP GET via a
  `redirect::Policy::none()` reqwest client to read the `Location`),
- maps `http(s)` Locations to `ws(s)`, resolves absolute-path Locations,
- re-runs `validate_target` (SSRF) on every hop before connecting.

Verified against the live receiver with the `#[ignore]`d
`live_redirect_connect` test (`cargo test live_redirect_connect -- --ignored`).

## Follow-up: silent stream after the redirect fix (found on staging)

0.4.87 connected but streamed nothing. The frp redirector **lowercases the
path** in its Location (`/ws/kiwi/{ts}/SND` → `.../snd`); the receiver
completes the websocket handshake for a lowercased stream name but never
attaches the stream — silence, no error. Verified by probing the receiver
directly: `/SND` answers `SET auth` with MSG frames, `/snd` answers nothing.
Fixed in 0.4.88 (`preserve_path_case`): when a redirect changes only the
path's case, keep our casing. The `live_redirect_connect` test now
authenticates and requires a protocol reply, so a handshake-only "success"
fails the test.

**Lesson:** for stream bridges, "connected" is not verified — demand payload.

## Notes

- Not verified whether the shared cw-core SDR client (iOS Spots listening)
  handles this same proxy redirect chain — worth checking against a
  `NNNN.proxy.kiwisdr.com` receiver.
- Warm-up asset fetches use the default reqwest client, which follows the same
  redirects on its own — the per-IP `web_served` counter still gets warmed on
  the real receiver.
