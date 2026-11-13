# Investigation: KiwiSDR Redirect Causes Errors and Reconnect Loops

**Date:** 2026-02-13
**Status:** Resolved
**Outcome:** Follow KiwiSDR protocol redirects instead of treating them as errors

## Problem Statement

kiwisdr.kfsdr.com:8073 sometimes shows a "redirection" error when attempting to connect, and when it does connect, the session reconnects every ~10 seconds.

## Root Cause

Two related issues:

1. **Handshake redirect treated as error:** `KiwiSDRClient.checkForServerError` throws `KiwiSDRError.serverRedirect` when the server sends `MSG redirect=<url>`. Per the KiwiSDR protocol, the client should follow the redirect by connecting to the new host:port.

2. **Streaming redirect not detected:** `processTextMessage` does not check for `redirect` messages during streaming. If the server sends a redirect while streaming, it's silently ignored. The server then closes the connection, triggering a reconnect to the *original* server, which may redirect again — creating a cycle of connect → redirect (ignored) → drop → reconnect → repeat (~10 seconds per cycle).

## Resolution

1. Added `connectFollowingRedirects` helper that retries with the new host:port when a handshake redirect is received (up to 3 redirects).
2. Added redirect detection in `processTextMessage` to finish the audio stream on redirect, triggering an immediate reconnect.
3. Cached the effective host/port after following a redirect so subsequent reconnects go directly to the correct server.
4. Used `connectFollowingRedirects` in both `start()` and `reconnect()`.

## Files Changed

- `KiwiSDRClient.swift` — detect redirect in `processTextMessage`
- `WebSDRSession.swift` — add effectiveHost/effectivePort, refactor `start()` to use redirect-following connection
- `WebSDRSession+Internals.swift` — add `connectFollowingRedirects`, `parseRedirectTarget`, refactor `reconnect()`
