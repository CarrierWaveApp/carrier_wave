-- Phase 2 — Sync journal schema (E2E-blind append-only log).
--
-- The server assigns monotonic per-tenant sequence numbers and stores opaque
-- ciphertext blobs in object storage. It NEVER parses payloads: it keeps only
-- plaintext metadata (tenant, seq, type, op, size, hash) plus a blob pointer.
--
-- Tenant identity = AuthContext.account_id (fallback participant_id); the client
-- never supplies the tenant id. Sequence type is BIGINT (i64).
--
-- Design: docs/superpowers/plans/2026-06-30-sync-server.md (Phase 2).
--
-- NOTE: hash-partitioning sync_entry by tenant_id is deferred for v1. We ship
-- unpartitioned first and add partitioning later if write volume requires it.

-- Append-only journal of encrypted entries. PK (tenant_id, seq) makes the log
-- gap-free and monotonic per tenant; the seq is reserved via sync_cursor.
CREATE TABLE sync_entry (
    tenant_id       UUID        NOT NULL,
    seq             BIGINT      NOT NULL,
    -- The client-generated id (JournalPayload.id); doubles as the idempotency
    -- key so a re-push of the same entry does not allocate a fresh seq.
    client_entry_id UUID        NOT NULL,
    entity_type     TEXT        NOT NULL,            -- e.g. "qso"
    op              TEXT        NOT NULL,            -- e.g. "upsert" | "delete"
    blob_key        TEXT        NOT NULL,            -- object-store key for ciphertext
    byte_size       BIGINT      NOT NULL,
    content_hash    TEXT        NOT NULL,            -- sha256 of ciphertext
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, seq),
    UNIQUE (tenant_id, client_entry_id)
);
-- changes_since(tenant, since) walks the log in seq order; PK already covers it.

-- Per-tenant sequence allocator + snapshot pointer. last_seq is the high-water
-- mark; a block reservation bumps it by N atomically and returns the new value.
CREATE TABLE sync_cursor (
    tenant_id         UUID        PRIMARY KEY,
    last_seq          BIGINT      NOT NULL DEFAULT 0,
    -- Pointer to the most recent full snapshot (for bootstrap / log compaction).
    snapshot_seq      BIGINT,
    snapshot_blob_key TEXT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Passphrase-escrow envelope for the tenant's E2E data key. The server stores
-- the wrapped key + KDF params opaquely; it can never unwrap it (E2E-blind).
CREATE TABLE sync_key_blob (
    tenant_id   UUID        PRIMARY KEY,
    wrapped_key BYTEA       NOT NULL,                -- AEAD-wrapped data key
    kdf_params  JSONB       NOT NULL,                -- Argon2id params + salt
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
