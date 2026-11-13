-- Phase 5 — OAuth2 auth overhaul (CAR, gating piece for cw-sync).
--
-- Replaces the static `fd_` device token (participants.device_token) with a
-- unified account identity + OAuth2-style tokens: short-lived EdDSA JWT access
-- tokens (stateless, not stored) and opaque rotating refresh tokens (hashed at
-- rest). Callsign ownership is proven via email magic-link before tokens issue.
--
-- Design: docs/plans/2026-06-21-phase5-oauth-overhaul.md (§7 schema).
-- This migration is ADDITIVE — it does not touch the legacy `participants`
-- auth path, which keeps working until the §13-step-7 middleware swap + cutover.

-- The unified identity. Callsign is a verified ATTRIBUTE (account_callsigns),
-- not the primary key, so a callsign change keeps one stable account.id.
CREATE TABLE accounts (
    id                 UUID PRIMARY KEY,
    primary_callsign   TEXT NOT NULL,
    status             TEXT NOT NULL DEFAULT 'active',   -- active | suspended
    -- Emergency/global kill: access JWTs with iat < this are rejected (F3).
    tokens_valid_after TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Verified callsigns held by an account (multi-callsign from day one, D8).
CREATE TABLE account_callsigns (
    account_id          UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    callsign            TEXT NOT NULL,
    verification_method TEXT NOT NULL,                   -- directory_email | user_email
    verified_email      TEXT,                            -- audit/PII (see retention below)
    verified_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (account_id, callsign)
);
-- One account per callsign, case-insensitive. NOTE: claim is exclusive +
-- permanent; FCC reassignment is an admin transfer/release flow (O7), not a
-- silent re-point. The cutover land-grab is disarmed by D6 (directory-email
-- required to inherit legacy callsign-keyed data).
CREATE UNIQUE INDEX uq_account_callsigns_callsign ON account_callsigns (UPPER(callsign));

-- primary_callsign must be a callsign this account actually verified (F10).
-- DEFERRABLE so the account + its first callsign can be inserted in one tx.
ALTER TABLE accounts
    ADD CONSTRAINT accounts_primary_callsign_fk
    FOREIGN KEY (id, primary_callsign)
    REFERENCES account_callsigns (account_id, callsign)
    DEFERRABLE INITIALLY DEFERRED;

-- Email magic-link verification challenges.
CREATE TABLE email_verifications (
    id             UUID PRIMARY KEY,
    callsign       TEXT NOT NULL,
    email          TEXT NOT NULL,
    code_hash      BYTEA NOT NULL,                       -- sha256 of the one-time code
    method         TEXT NOT NULL,                        -- directory_email | user_email
    -- non-null = attach the callsign to this existing account (D8); null = onboarding.
    account_id     UUID REFERENCES accounts(id) ON DELETE CASCADE,
    pkce_challenge TEXT NOT NULL,                        -- S256 of the app's verifier (F8)
    request_ip     TEXT,                                 -- forensics (stored as text; avoids sqlx ipnetwork feature)
    attempts       INT NOT NULL DEFAULT 0,               -- code-check attempts; locked at MAX
    expires_at     TIMESTAMPTZ NOT NULL,                 -- now() + 15 min
    consumed_at    TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_email_verifications_callsign ON email_verifications (callsign);
CREATE INDEX idx_email_verifications_expires ON email_verifications (expires_at);
-- RETENTION (F10/PII): purge consumed + expired rows on a schedule; do not
-- retain verification emails indefinitely.

-- A registered client install.
CREATE TABLE devices (
    id           UUID PRIMARY KEY,
    account_id   UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    device_name  TEXT,
    platform     TEXT,                                   -- ios | macos | android
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_devices_account ON devices (account_id);
-- Per-account device cap enforced in app logic; prune LRU to bound family growth.

-- Rotating refresh tokens (one live per family/device).
CREATE TABLE refresh_tokens (
    id                UUID PRIMARY KEY,
    device_id         UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    account_id        UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    family_id         UUID NOT NULL,                     -- rotation chain
    token_hash        BYTEA NOT NULL UNIQUE,             -- sha256(plaintext)
    scopes            TEXT NOT NULL,                     -- space-delimited
    replaced_by       UUID REFERENCES refresh_tokens(id),-- successor (idempotent replay, F4)
    issued_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at        TIMESTAMPTZ NOT NULL,              -- sliding (60d)
    family_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),-- absolute-lifetime anchor (F12)
    rotated_at        TIMESTAMPTZ,                       -- set when superseded
    revoked_at        TIMESTAMPTZ,                       -- set on explicit/forced revoke
    revoked_reason    TEXT,                              -- logout | reuse_detected | admin | cutover
    last_used_ip      TEXT
);
CREATE INDEX idx_refresh_tokens_family ON refresh_tokens (family_id);
-- "One live token per family" as a DB invariant (F10), not just convention.
CREATE UNIQUE INDEX uq_refresh_live_per_family ON refresh_tokens (family_id)
    WHERE rotated_at IS NULL AND revoked_at IS NULL;

-- Emergency access-token denylist (NOT the hot path; multi-instance propagation
-- via LISTEN/NOTIFY, D10). Prune past expires_at.
CREATE TABLE revoked_jti (
    jti        TEXT PRIMARY KEY,
    expires_at TIMESTAMPTZ NOT NULL
);

-- Link legacy participants to the new identity as accounts are created. Kept
-- nullable; the legacy `device_token` path is retired at cutover, not here.
ALTER TABLE participants ADD COLUMN account_id UUID REFERENCES accounts(id) ON DELETE SET NULL;
