//! CAR-349: `db::change_callsign` and Phase 5 account identity.
//!
//! A legacy `fd_` request used to rename only the callsign-keyed tables while
//! `accounts.primary_callsign` stayed on the old call, so every later OAuth
//! request acted as the old callsign. The change must now be all-or-nothing,
//! and an account already left in that split state must be repaired.
//!
//! Requires `TEST_DATABASE_URL` (migration 044 applied); skips otherwise.

#![cfg(test)]

use sqlx::PgPool;
use uuid::Uuid;

use activities_server::db;
use activities_server::db::auth as dbauth;
use activities_server::error::AppError;

async fn pool() -> Option<PgPool> {
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

fn unique_call() -> String {
    format!("D{}", &Uuid::new_v4().simple().to_string()[..7]).to_uppercase()
}

async fn primary_callsign(pool: &PgPool, account_id: Uuid) -> String {
    sqlx::query_scalar("SELECT primary_callsign FROM accounts WHERE id = $1")
        .bind(account_id)
        .fetch_one(pool)
        .await
        .unwrap()
}

async fn account_owns(pool: &PgPool, account_id: Uuid, callsign: &str) -> bool {
    dbauth::assert_account_owns_callsign(pool, account_id, callsign)
        .await
        .is_ok()
}

async fn users_under(pool: &PgPool, callsign: &str) -> i64 {
    sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE callsign = $1")
        .bind(callsign)
        .fetch_one(pool)
        .await
        .unwrap()
}

#[tokio::test]
async fn legacy_token_cannot_rename_an_account_owned_callsign() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let old = unique_call();
    let new = unique_call();
    let acct = dbauth::create_account_with_callsign(&pool, &old, dbauth::METHOD_DIRECTORY, None)
        .await
        .unwrap();
    let user = db::users::get_or_create_user(&pool, &old).await.unwrap();

    // Legacy device token → no account id → cannot prove ownership.
    let result = db::users::change_callsign(&pool, user.id, &old, &new, None).await;
    assert!(
        matches!(result, Err(AppError::Forbidden)),
        "expected Forbidden, got {result:?}"
    );

    // Nothing moved: no half-applied rename.
    let same = db::users::get_user_by_id(&pool, user.id).await.unwrap().unwrap();
    assert_eq!(same.callsign, old);
    assert_eq!(users_under(&pool, &new).await, 0);
    assert_eq!(primary_callsign(&pool, acct.id).await, old);
    assert!(account_owns(&pool, acct.id, &old).await);
}

#[tokio::test]
async fn account_caller_moves_users_row_and_identity_together() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let old = unique_call();
    let new = unique_call();
    let acct = dbauth::create_account_with_callsign(&pool, &old, dbauth::METHOD_DIRECTORY, None)
        .await
        .unwrap();
    let user = db::users::get_or_create_user(&pool, &old).await.unwrap();

    let updated = db::users::change_callsign(&pool, user.id, &old, &new, Some(acct.id))
        .await
        .unwrap();

    assert_eq!(updated.id, user.id);
    assert_eq!(updated.callsign, new);
    assert_eq!(users_under(&pool, &old).await, 0);
    assert_eq!(primary_callsign(&pool, acct.id).await, new);
    assert!(account_owns(&pool, acct.id, &new).await);
    assert!(!account_owns(&pool, acct.id, &old).await);
}

#[tokio::test]
async fn repairs_an_account_split_by_an_earlier_half_applied_change() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let old = unique_call();
    let new = unique_call();
    let acct = dbauth::create_account_with_callsign(&pool, &old, dbauth::METHOD_DIRECTORY, None)
        .await
        .unwrap();
    let renamed = db::users::get_or_create_user(&pool, &old).await.unwrap();

    // Reproduce the pre-fix half-apply: the users row was renamed and the
    // history recorded, but the account still points at the old callsign.
    sqlx::query("UPDATE users SET callsign = $1 WHERE id = $2")
        .bind(&new)
        .bind(renamed.id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO callsign_history (user_id, old_callsign, new_callsign) VALUES ($1, $2, $3)",
    )
    .bind(renamed.id)
    .bind(&old)
    .bind(&new)
    .execute(&pool)
    .await
    .unwrap();
    assert_eq!(primary_callsign(&pool, acct.id).await, old);

    // Meanwhile the middleware and handlers, acting as the old call, recreated
    // rows under it — and the operator made a friend from that identity.
    let stale = db::users::get_or_create_user(&pool, &old).await.unwrap();
    assert_ne!(stale.id, renamed.id);
    let (_participant, _) = db::participants::get_or_create_participant(&pool, &old, None)
        .await
        .unwrap();
    let friend = db::users::get_or_create_user(&pool, &unique_call()).await.unwrap();
    sqlx::query("INSERT INTO friendships (user_id, friend_id) VALUES ($1, $2)")
        .bind(stale.id)
        .bind(friend.id)
        .execute(&pool)
        .await
        .unwrap();

    // The fixed client retries the change with its account session.
    let repaired = db::users::change_callsign(&pool, stale.id, &old, &new, Some(acct.id))
        .await
        .unwrap();

    // One user, the originally renamed row, now carries the new callsign …
    assert_eq!(repaired.id, renamed.id);
    assert_eq!(repaired.callsign, new);
    assert_eq!(users_under(&pool, &old).await, 0);
    assert_eq!(users_under(&pool, &new).await, 1);
    // … the account identity followed …
    assert_eq!(primary_callsign(&pool, acct.id).await, new);
    assert!(account_owns(&pool, acct.id, &new).await);
    // … the friendship made under the stale identity moved with it …
    let friend_owner: Uuid = sqlx::query_scalar("SELECT user_id FROM friendships WHERE friend_id = $1")
        .bind(friend.id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(friend_owner, renamed.id);
    // … and no bridge row lingers under the old call.
    let stale_participants: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM participants WHERE callsign = $1")
            .bind(&old)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(stale_participants, 0);
}

#[tokio::test]
async fn a_genuinely_taken_callsign_is_still_refused() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let old = unique_call();
    let taken = unique_call();
    let acct = dbauth::create_account_with_callsign(&pool, &old, dbauth::METHOD_DIRECTORY, None)
        .await
        .unwrap();
    let user = db::users::get_or_create_user(&pool, &old).await.unwrap();
    let other = db::users::get_or_create_user(&pool, &taken).await.unwrap();

    let result = db::users::change_callsign(&pool, user.id, &old, &taken, Some(acct.id)).await;
    assert!(
        matches!(result, Err(AppError::CallsignTaken { .. })),
        "expected CallsignTaken, got {result:?}"
    );
    // The other operator's row is untouched and our identity did not move.
    let still = db::users::get_user_by_id(&pool, other.id).await.unwrap().unwrap();
    assert_eq!(still.callsign, taken);
    assert_eq!(primary_callsign(&pool, acct.id).await, old);
}
