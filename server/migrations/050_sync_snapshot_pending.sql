-- CAR-334 — Two-phase sync snapshots.
--
-- `POST /v1/sync/snapshot` used to move `sync_cursor.snapshot_seq` and GC the
-- journal BEFORE the client had uploaded a single snapshot byte. Any failure
-- between the response and the PUT left the tenant pointing at an object that
-- does not exist, with the entries it superseded already deleted — unrecoverable
-- on an E2E-blind server.
--
-- A snapshot now starts life as a row here (phase 1: presign + record intent).
-- The live pointer on `sync_cursor` only moves, and GC only runs, when the
-- client calls `POST /v1/sync/snapshot/commit` and the server has confirmed the
-- object exists in the blob store (phase 2). Rows that are never committed are
-- harmless: nothing reads them for bootstrap/changes, and they are purged once
-- `expires_at` passes (on the tenant's next snapshot request).
CREATE TABLE sync_snapshot_pending (
    -- Opaque handle the client echoes back on commit.
    snapshot_id  UUID        PRIMARY KEY,
    tenant_id    UUID        NOT NULL,
    -- Journal seq this snapshot folds up to (inclusive). Validated at phase 1
    -- to lie in (current snapshot_seq, last_seq]; re-validated at commit.
    seq          BIGINT      NOT NULL,
    -- Object-store key the PUT was presigned for. Unique per attempt so a stale
    -- object from an earlier abandoned attempt can never satisfy a later
    -- commit's existence check.
    blob_key     TEXT        NOT NULL,
    -- Client-declared ciphertext size/hash, if supplied at phase 1. Size is
    -- checked against the stored object at commit; hash must match on commit.
    byte_size    BIGINT,
    content_hash TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at   TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_sync_snapshot_pending_tenant ON sync_snapshot_pending (tenant_id);
