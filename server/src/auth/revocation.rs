//! Emergency revocation propagation — Phase 5 (D10/F3).
//!
//! Access JWTs verify with no per-request DB hit; revocation before natural
//! expiry works via an in-process cache of (a) per-account `tokens_valid_after`
//! epochs and (b) explicitly denied `jti`s. The cache is correct across a
//! horizontal pool because every instance refreshes on a Postgres
//! `LISTEN/NOTIFY` signal (channel `auth_revocation`), so a revoke on instance A
//! is visible on instance B within a NOTIFY round-trip (sub-second).
//!
//! Design: docs/plans/2026-06-21-phase5-oauth-overhaul.md (§9).

use std::collections::{HashMap, HashSet};
use std::sync::RwLock;

use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;

/// The Postgres notification channel revocations are announced on.
pub const REVOCATION_CHANNEL: &str = "auth_revocation";

#[derive(Default)]
pub struct RevocationCache {
    /// account_id -> `tokens_valid_after` as unix seconds.
    epochs: RwLock<HashMap<Uuid, i64>>,
    /// Explicitly denied access-token jti strings.
    jtis: RwLock<HashSet<String>>,
}

impl RevocationCache {
    pub fn new() -> Self {
        Self::default()
    }

    /// Reload the full revocation state from the DB. Cheap (revocations are
    /// rare and the rows are pruned), so it's fine to call on every NOTIFY.
    pub async fn refresh(&self, pool: &PgPool) -> Result<(), AppError> {
        let epoch_rows = sqlx::query_as::<_, (Uuid, chrono::DateTime<chrono::Utc>)>(
            "SELECT id, tokens_valid_after FROM accounts WHERE tokens_valid_after IS NOT NULL",
        )
        .fetch_all(pool)
        .await?;
        let jti_rows = sqlx::query_scalar::<_, String>(
            "SELECT jti FROM revoked_jti WHERE expires_at > NOW()",
        )
        .fetch_all(pool)
        .await?;

        let new_epochs: HashMap<Uuid, i64> = epoch_rows
            .into_iter()
            .map(|(id, ts)| (id, ts.timestamp()))
            .collect();
        let new_jtis: HashSet<String> = jti_rows.into_iter().collect();

        // Brief writes, no await held.
        *self.epochs.write().unwrap() = new_epochs;
        *self.jtis.write().unwrap() = new_jtis;
        Ok(())
    }

    /// Whether a token with these claims is revoked: minted before the account's
    /// kill epoch, or its `jti` is explicitly denied.
    pub fn token_revoked(&self, account_id: Uuid, iat: i64, jti: &str) -> bool {
        if let Some(epoch) = self.epochs.read().unwrap().get(&account_id) {
            if iat < *epoch {
                return true;
            }
        }
        self.jtis.read().unwrap().contains(jti)
    }
}

/// Background task: LISTEN on the revocation channel and refresh the cache on
/// every notification. Reconnects on listener error. Spawn once at startup.
pub async fn run_revocation_listener(
    pool: PgPool,
    cache: std::sync::Arc<RevocationCache>,
) {
    loop {
        match sqlx::postgres::PgListener::connect_with(&pool).await {
            Ok(mut listener) => {
                if let Err(e) = listener.listen(REVOCATION_CHANNEL).await {
                    tracing::warn!("revocation LISTEN failed: {e}; retrying");
                    continue;
                }
                // Warm the cache on (re)connect so we don't miss anything.
                if let Err(e) = cache.refresh(&pool).await {
                    tracing::warn!("revocation cache warm failed: {e}");
                }
                loop {
                    match listener.recv().await {
                        Ok(_notification) => {
                            if let Err(e) = cache.refresh(&pool).await {
                                tracing::warn!("revocation cache refresh failed: {e}");
                            }
                        }
                        Err(e) => {
                            tracing::warn!("revocation listener dropped: {e}; reconnecting");
                            break;
                        }
                    }
                }
            }
            Err(e) => {
                tracing::warn!("revocation listener connect failed: {e}");
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn pool_for_test() -> Option<PgPool> {
        let url = std::env::var("TEST_DATABASE_URL").ok()?;
        PgPool::connect(&url).await.ok()
    }

    #[tokio::test]
    async fn cache_reflects_account_epoch_after_refresh() {
        let Some(pool) = pool_for_test().await else {
            eprintln!("TEST_DATABASE_URL not set; skipping");
            return;
        };
        use crate::db::auth as dbauth;
        let cs = format!("R{}", &Uuid::new_v4().simple().to_string()[..7]).to_uppercase();
        let acct = dbauth::create_account_with_callsign(&pool, &cs, dbauth::METHOD_DIRECTORY, None)
            .await
            .unwrap();

        let cache = RevocationCache::new();
        cache.refresh(&pool).await.unwrap();
        let now = chrono::Utc::now().timestamp();
        // No epoch yet → a token minted "now" is fine.
        assert!(!cache.token_revoked(acct.id, now, "jti-1"));

        // Revoke everything for the account, then refresh.
        dbauth::revoke_account(&pool, acct.id, "test").await.unwrap();
        cache.refresh(&pool).await.unwrap();
        // A token minted just before the kill epoch is now rejected.
        assert!(cache.token_revoked(acct.id, now - 1, "jti-1"));
    }
}
