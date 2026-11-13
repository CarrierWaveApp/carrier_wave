# Carrier Wave — Domain & Architecture Glossary

Domain language and architectural vocabulary for the Carrier Wave codebase. Add a term here when a deepening refactor or grilling session names a concept the team should reuse — entries should answer "what does this word mean *in this codebase*?" not just generic ham-radio terms.

Format: short heading, one paragraph definition, and a pointer to where the concept lives in the code.

---

## Architecture

### Repair

A one-time mutation over the local SwiftData store, gated for idempotency by a UserDefaults key. Repairs run either at app launch (registered in the iOS app target) or on demand from the Dashboard's repair section. A Repair is *not* a sync operation, *not* a migration, and *not* a runtime feature — it is a finite, idempotent backfill or fix that recovers from a past bug or schema change. See `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Repair/`.

### BatchedRewrite

A Repair shape: predicate-driven scan with a per-row mutation, no cross-row state. The runner owns the batching invariants (fresh `ModelContext` per batch, `BoundedDescriptor` ≤ 1,000, save only when the batch produced mutations, cooperative yield between batches). Use this when each row's fix can be decided in isolation. See `BatchedRewrite.swift`.

### CrossBatchMerge

A Repair shape: collect Sendable snapshots across all batches, group/match them to produce merge actions, then re-fetch winners + losers in a save context to mutate winner and delete loser. Use this when the fix requires cross-row state — dedup, merge, two-fer reconciliation. The seam is split into `plan() → apply(_:)` so callers get dry-run for free. See `CrossBatchMerge.swift`.

### Repair Registry

The list of (Repair, gate key) pairs the iOS app target runs at launch. Today this lives in `DataRepairService` (a static enum); future work may name it more sharply. The registry is *not* part of the seam — it lives in the iOS target and may reference iOS-only services like `KeychainHelper`. The seams in `CarrierWaveData/Repair/` know nothing about gating, keychain, or launch flow.
