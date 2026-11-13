-- Third-party OAuth 2.0 / OpenID Connect provider.
--
-- Phase 5 (044) made the server issue tokens to its OWN apps via magic-link.
-- This migration makes it an authorization server for OTHER people's apps:
-- registered clients, an authorization-code flow with real RFC 7636 PKCE, the
-- RFC 8628 device grant, and persistent per-(account, client) consent.
--
-- Registration is CURATED — there is no self-serve portal and no dynamic
-- registration endpoint. Rows are inserted by an admin (POST /v1/admin/oauth/clients).
-- The consent screen is the only thing standing between a user and a hostile
-- client, so who gets a client_id is a human decision.
--
-- The log itself stays E2E-encrypted: these tokens authorize ACCESS to a
-- tenant's opaque journal, never decryption. The sync passphrase is entered in
-- the client and never reaches this server.

-- A registered third-party application.
CREATE TABLE oauth_clients (
    client_id          TEXT PRIMARY KEY,
    -- sha256 of the client secret. NULL = public client (native/SPA/CLI), which
    -- MUST use PKCE and is never trusted with a secret it cannot protect.
    client_secret_hash BYTEA,
    name               TEXT NOT NULL,                     -- shown on the consent screen
    description        TEXT,
    homepage_url       TEXT,
    -- Exact-match redirect targets (no wildcards, no prefix matching — the
    -- classic open-redirect / code-interception hole).
    redirect_uris      TEXT[] NOT NULL DEFAULT '{}',
    -- Space-delimited ceiling. A request may ask for less, never for more.
    allowed_scopes     TEXT NOT NULL DEFAULT 'openid profile',
    grant_types        TEXT NOT NULL DEFAULT 'authorization_code refresh_token device_code',
    status             TEXT NOT NULL DEFAULT 'active',    -- active | suspended
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by         TEXT                               -- admin note / contact
);

-- Short-lived authorization codes (RFC 6749 §4.1) with mandatory PKCE.
CREATE TABLE oauth_authorization_codes (
    code_hash      BYTEA PRIMARY KEY,                     -- sha256 of the code
    client_id      TEXT NOT NULL REFERENCES oauth_clients(client_id) ON DELETE CASCADE,
    account_id     UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    redirect_uri   TEXT NOT NULL,                         -- must match at exchange
    scopes         TEXT NOT NULL,                         -- what the user actually consented to
    -- RFC 7636 S256: base64url(sha256(verifier)), NOT the hex variant the
    -- magic-link poll flow uses (auth/tokens.rs::pkce_challenge_for). Third
    -- parties use standard libraries; they get the standard encoding.
    code_challenge TEXT NOT NULL,
    nonce          TEXT,                                  -- OIDC replay binding for the id_token
    expires_at     TIMESTAMPTZ NOT NULL,                  -- now() + 60s
    consumed_at    TIMESTAMPTZ,                           -- single use; replay is an attack signal
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_oauth_codes_expires ON oauth_authorization_codes (expires_at);

-- RFC 8628 device authorization grant, for CLIs and headless boxes that cannot
-- host a redirect listener.
CREATE TABLE oauth_device_codes (
    device_code_hash BYTEA PRIMARY KEY,
    -- Short human-typed code (e.g. "KRWG-ZPTL"). Unique so the verification
    -- page can find the pending request from what the user reads off a terminal.
    user_code        TEXT NOT NULL UNIQUE,
    client_id        TEXT NOT NULL REFERENCES oauth_clients(client_id) ON DELETE CASCADE,
    scopes           TEXT NOT NULL,
    -- Set when the user approves on the verification page.
    account_id       UUID REFERENCES accounts(id) ON DELETE CASCADE,
    approved_at      TIMESTAMPTZ,
    denied_at        TIMESTAMPTZ,
    consumed_at      TIMESTAMPTZ,                         -- device_code exchanged for tokens
    interval_secs    INT NOT NULL DEFAULT 5,              -- client poll interval
    last_polled_at   TIMESTAMPTZ,                         -- drives slow_down (§3.5)
    expires_at       TIMESTAMPTZ NOT NULL,                -- now() + 15 min
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_oauth_device_codes_expires ON oauth_device_codes (expires_at);

-- Persistent consent. Re-authorizing a client for scopes it already holds skips
-- the prompt; asking for anything new prompts again.
CREATE TABLE oauth_grants (
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    client_id  TEXT NOT NULL REFERENCES oauth_clients(client_id) ON DELETE CASCADE,
    scopes     TEXT NOT NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,
    PRIMARY KEY (account_id, client_id)
);

-- Ties a `devices` row (and therefore its refresh-token family) to the client
-- that owns it. NULL for first-party app installs, which is exactly what makes
-- "is this a third-party token?" answerable at refresh time. Revoking a grant
-- cascades to the device and its refresh tokens.
ALTER TABLE devices ADD COLUMN oauth_client_id TEXT
    REFERENCES oauth_clients(client_id) ON DELETE CASCADE;
CREATE INDEX idx_devices_oauth_client ON devices (oauth_client_id)
    WHERE oauth_client_id IS NOT NULL;
