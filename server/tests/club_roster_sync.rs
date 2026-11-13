//! Club roster reconciliation + ETag fingerprint movement.
//!
//! These tests require a live Postgres pointed to by `TEST_DATABASE_URL` with
//! the club migrations applied. They skip silently when the env var isn't set
//! so `cargo test` stays green in CI without a database.

use activities_server::db::clubs;
use sqlx::PgPool;
use uuid::Uuid;

async fn pool() -> Option<PgPool> {
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

async fn fingerprint(pool: &PgPool, callsign: &str) -> i64 {
    clubs::get_clubs_fingerprint(pool, &[callsign.to_string()])
        .await
        .unwrap()
}

async fn roster(pool: &PgPool, club_id: Uuid) -> Vec<(String, String)> {
    let mut rows: Vec<(String, String)> =
        sqlx::query_as("SELECT callsign, role FROM club_members WHERE club_id = $1")
            .bind(club_id)
            .fetch_all(pool)
            .await
            .unwrap();
    rows.sort();
    rows
}

/// The fingerprint has one-second resolution; make sure the next mutation
/// lands in a later second so a bump is observable.
async fn next_second() {
    tokio::time::sleep(std::time::Duration::from_millis(1100)).await;
}

#[tokio::test]
async fn reconcile_adds_drops_members_and_keeps_admins() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };
    let name = format!("roster-test-{}", Uuid::new_v4());
    let club = clubs::create_club(&pool, &name, None, None)
        .await
        .unwrap();

    clubs::add_members(
        &pool,
        club.id,
        &[
            ("ADMIN1".into(), "admin".into()),
            ("STAYS".into(), "member".into()),
            ("LEAVES".into(), "member".into()),
        ],
    )
    .await
    .unwrap();

    let before = fingerprint(&pool, "STAYS").await;
    next_second().await;

    // Upstream list: STAYS is still there, LEAVES is gone, NEWBIE joined.
    // ADMIN1 is not in the file but must survive.
    let outcome = clubs::reconcile_roster(
        &pool,
        club.id,
        &["STAYS".to_string(), "NEWBIE".to_string()],
    )
    .await
    .unwrap();

    assert_eq!(outcome.added, vec!["NEWBIE".to_string()]);
    assert_eq!(outcome.removed, vec!["LEAVES".to_string()]);
    assert_eq!(outcome.unchanged, 2, "ADMIN1 + STAYS");
    assert_eq!(
        roster(&pool, club.id).await,
        vec![
            ("ADMIN1".to_string(), "admin".to_string()),
            ("NEWBIE".to_string(), "member".to_string()),
            ("STAYS".to_string(), "member".to_string()),
        ]
    );
    assert!(
        fingerprint(&pool, "STAYS").await > before,
        "reconcile must move the clubs ETag"
    );

    // Re-running with the same list is a no-op and doesn't bump the ETag.
    let after = fingerprint(&pool, "STAYS").await;
    next_second().await;
    let again = clubs::reconcile_roster(
        &pool,
        club.id,
        &["STAYS".to_string(), "NEWBIE".to_string()],
    )
    .await
    .unwrap();
    assert!(again.added.is_empty() && again.removed.is_empty());
    assert_eq!(fingerprint(&pool, "STAYS").await, after);

    clubs::record_roster_sync(&pool, club.id, "ok").await.unwrap();
    let status: (Option<String>,) =
        sqlx::query_as("SELECT roster_sync_status FROM clubs WHERE id = $1")
            .bind(club.id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(status.0.as_deref(), Some("ok"));

    clubs::delete_club(&pool, club.id).await.unwrap();
}

#[tokio::test]
async fn removal_and_role_change_move_the_etag() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };
    let name = format!("roster-test-{}", Uuid::new_v4());
    let club = clubs::create_club(&pool, &name, None, None)
        .await
        .unwrap();
    clubs::add_members(
        &pool,
        club.id,
        &[
            ("FIRST".into(), "member".into()),
            ("SECOND".into(), "member".into()),
        ],
    )
    .await
    .unwrap();

    // Removing a member who is NOT the latest joiner used to leave the
    // fingerprint unchanged (MAX(joined_at) didn't move).
    let before = fingerprint(&pool, "SECOND").await;
    next_second().await;
    assert!(clubs::remove_member(&pool, club.id, "first").await.unwrap());
    let after_remove = fingerprint(&pool, "SECOND").await;
    assert!(after_remove > before, "removal must move the clubs ETag");

    next_second().await;
    assert!(clubs::update_member_role(&pool, club.id, "second", "admin")
        .await
        .unwrap());
    assert!(
        fingerprint(&pool, "SECOND").await > after_remove,
        "role change must move the clubs ETag"
    );

    // A no-op removal of an unknown callsign must not bump anything.
    let stable = fingerprint(&pool, "SECOND").await;
    next_second().await;
    assert!(!clubs::remove_member(&pool, club.id, "NOBODY").await.unwrap());
    assert_eq!(fingerprint(&pool, "SECOND").await, stable);

    clubs::delete_club(&pool, club.id).await.unwrap();
}
