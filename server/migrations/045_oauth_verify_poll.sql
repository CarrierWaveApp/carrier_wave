-- Phase 5 — OAuth magic-link polling return path (O4 "build both").
--
-- The universal-link return path delivers the emailed `code` back into the app,
-- which then redeems it at /v1/auth/token. The polling return path needs a
-- different handle: the app never sees the email, so verify/start hands it an
-- opaque `poll_token`. The app polls /v1/auth/verify/poll with that token + its
-- PKCE verifier; once the magic link has been clicked (consumed_at set), the
-- poll endpoint issues tokens directly. Only the SHA-256 hash is stored, like
-- the code itself — the plaintext is returned to the app once.
--
-- Design: docs/plans/2026-06-21-phase5-oauth-overhaul.md (§8, O4).
ALTER TABLE email_verifications ADD COLUMN poll_token_hash BYTEA;
CREATE INDEX idx_email_verifications_poll ON email_verifications (poll_token_hash);
