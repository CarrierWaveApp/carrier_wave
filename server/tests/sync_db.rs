//! Integration tests for the sync sequence-block reservation (Phase 2, Task 2.3).
//!
//! These tests require a live Postgres pointed to by `TEST_DATABASE_URL`. They
//! skip silently when the env var isn't set so `cargo test` stays green in CI
//! environments without a DB.

#![cfg(test)]

use std::collections::HashSet;

use activities_server::db::sync::reserve_block;
use sqlx::PgPool;
use uuid::Uuid;

async fn pool() -> Option<PgPool> {
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

async fn cleanup(pool: &PgPool, tenant: Uuid) {
    sqlx::query("DELETE FROM sync_cursor WHERE tenant_id = $1")
        .bind(tenant)
        .execute(pool)
        .await
        .unwrap();
}

/// Two sequential `reserve_block(.., 3)` calls return 1 then 4 (gap-free,
/// monotonic). The seed insert sets last_seq = 3, so the first block is [1,3]
/// and the second is [4,6].
#[tokio::test]
async fn reserve_block_is_gap_free_and_monotonic() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };
    let tenant = Uuid::new_v4();
    cleanup(&pool, tenant).await;

    let first = reserve_block(&pool, tenant, 3).await.unwrap();
    assert_eq!(first, 1, "first block should start at seq 1");

    let second = reserve_block(&pool, tenant, 3).await.unwrap();
    assert_eq!(second, 4, "second block should start right after the first");

    cleanup(&pool, tenant).await;
}

/// A concurrent pair of reservations must never overlap: with 20 spawned tasks
/// each reserving a block of 5, all 100 reserved seqs are distinct and cover
/// exactly 1..=100.
#[tokio::test]
async fn concurrent_reservations_never_overlap() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };
    let tenant = Uuid::new_v4();
    cleanup(&pool, tenant).await;

    const TASKS: i64 = 20;
    const WIDTH: i64 = 5;

    let mut handles = Vec::new();
    for _ in 0..TASKS {
        let pool = pool.clone();
        handles.push(tokio::spawn(async move {
            reserve_block(&pool, tenant, WIDTH).await.unwrap()
        }));
    }

    let mut all_seqs: HashSet<i64> = HashSet::new();
    for handle in handles {
        let first = handle.await.unwrap();
        // The block is [first, first + WIDTH - 1]; record every seq in it.
        for seq in first..first + WIDTH {
            assert!(
                all_seqs.insert(seq),
                "seq {seq} was reserved twice (overlap)"
            );
        }
    }

    let expected: HashSet<i64> = (1..=TASKS * WIDTH).collect();
    assert_eq!(
        all_seqs,
        expected,
        "reserved seqs must be exactly 1..={} with no gaps",
        TASKS * WIDTH
    );

    cleanup(&pool, tenant).await;
}

// ---- Orphan adoption (legacy participant tenants) ---------------------------

use activities_server::db::auth as dbauth;
use activities_server::db::sync::{
    adopt_orphan_tenant, insert_entries, list_orphan_tenants, tenant_usage,
};

/// Random test callsign so parallel runs never collide on the unique index.
fn test_callsign() -> String {
    format!("W6{}", &Uuid::new_v4().simple().to_string()[..6].to_uppercase())
}

async fn insert_participant(pool: &PgPool, callsign: &str) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query("INSERT INTO participants (id, callsign, device_token) VALUES ($1, $2, $3)")
        .bind(id)
        .bind(callsign)
        .bind(format!("fd_test_{id}"))
        .execute(pool)
        .await
        .unwrap();
    id
}

async fn seed_orphan_data(pool: &PgPool, tenant: Uuid, entries: i64) {
    let first = reserve_block(pool, tenant, entries).await.unwrap();
    let ids: Vec<Uuid> = (0..entries).map(|_| Uuid::new_v4()).collect();
    let rows: Vec<(Uuid, i64, &str, &str, &str, &str, i64)> = ids
        .iter()
        .enumerate()
        .map(|(offset, id)| (*id, first + offset as i64, "k", "qso", "upsert", "hash", 10))
        .collect();
    insert_entries(pool, tenant, &rows).await.unwrap();
}

async fn cleanup_all(pool: &PgPool, tenants: &[Uuid]) {
    for tenant in tenants {
        for table in ["sync_entry", "sync_cursor", "sync_key_blob"] {
            sqlx::query(&format!("DELETE FROM {table} WHERE tenant_id = $1"))
                .bind(tenant)
                .execute(pool)
                .await
                .unwrap();
        }
    }
}

/// An orphan (participant tenant with sync data) shows up in the listing with
/// its callsign, entry stats, and the adoption-target account id once the
/// callsign gets an account. Adoption re-keys all rows onto the account tenant.
#[tokio::test]
async fn orphan_listing_and_adoption_happy_path() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };

    let callsign = test_callsign();
    let participant = insert_participant(&pool, &callsign).await;
    seed_orphan_data(&pool, participant, 3).await;

    // Listed as an orphan, with no account yet.
    let orphans = list_orphan_tenants(&pool).await.unwrap();
    let mine = orphans
        .iter()
        .find(|o| o.participant_id == participant)
        .expect("orphan should be listed");
    assert_eq!(mine.callsign, callsign);
    assert_eq!(mine.entry_count, 3);
    assert_eq!(mine.total_bytes, 30);
    assert_eq!(mine.last_seq, 3);
    assert!(!mine.has_key_blob);
    assert_eq!(mine.account_id, None);

    // The user signs in → an account owns the callsign → it becomes the target.
    let account = dbauth::create_account_with_callsign(
        &pool,
        &callsign,
        dbauth::METHOD_USER,
        Some("orphan@example.com"),
    )
    .await
    .unwrap();
    let orphans = list_orphan_tenants(&pool).await.unwrap();
    let mine = orphans.iter().find(|o| o.participant_id == participant).unwrap();
    assert_eq!(mine.account_id, Some(account.id));

    // Adopt: rows move, orphan disappears, account tenant has the data.
    let moved = adopt_orphan_tenant(&pool, participant, account.id).await.unwrap();
    assert_eq!(moved, 3);
    let usage = tenant_usage(&pool, account.id).await.unwrap();
    assert_eq!(usage.entry_count, 3);
    assert!(usage.has_cursor);
    let orphans = list_orphan_tenants(&pool).await.unwrap();
    assert!(!orphans.iter().any(|o| o.participant_id == participant));

    cleanup_all(&pool, &[participant, account.id]).await;
}

/// `tenant_usage` reports non-empty targets so the adopt handler can refuse
/// with 409 instead of merging two journals.
#[tokio::test]
async fn tenant_usage_flags_non_empty_target() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };

    let tenant = Uuid::new_v4();
    cleanup(&pool, tenant).await;

    let empty = tenant_usage(&pool, tenant).await.unwrap();
    assert_eq!(empty.entry_count, 0);
    assert!(!empty.has_cursor);
    assert!(!empty.has_key_blob);

    seed_orphan_data(&pool, tenant, 2).await;
    let used = tenant_usage(&pool, tenant).await.unwrap();
    assert_eq!(used.entry_count, 2);
    assert!(used.has_cursor);

    cleanup_all(&pool, &[tenant]).await;
}
