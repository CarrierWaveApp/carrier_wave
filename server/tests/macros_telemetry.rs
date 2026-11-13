//! Integration tests for POST /v1/macros/:slug/run-event (CAR-271 T6).
//!
//! Exercises:
//!   * Unauth POST → 401
//!   * Auth POST against an unknown slug → 400 (validation)
//!   * Auth POST × 61 in <60s → first 60 succeed (204), rest 429
//!
//! Skips when TEST_DATABASE_URL isn't set.

#![cfg(test)]

use activities_server::auth;
use activities_server::handlers;
use axum::{
    body::Body,
    http::{Request, StatusCode},
    middleware,
    routing::post,
    Extension, Router,
};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

async fn pool() -> Option<PgPool> {
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

async fn seed_participant(pool: &PgPool) -> (String, Uuid) {
    let token = format!("dev-token-{}", Uuid::new_v4());
    let id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO participants (id, callsign, device_token) VALUES ($1, $2, $3)",
    )
    .bind(id)
    .bind(format!("TEST{}", &token[10..14].to_uppercase()))
    .bind(&token)
    .execute(pool)
    .await
    .unwrap();
    (token, id)
}

async fn seed_macro(pool: &PgPool, slug: &str) {
    sqlx::query(
        "INSERT INTO macros (id, slug, name, capabilities, args, steps, format, status, tags, applies_to) \
         VALUES ($1, $2, 'test', '{}'::jsonb, '[]'::jsonb, '[]'::jsonb, 2, 'approved', $3, $4)",
    )
    .bind(Uuid::new_v4())
    .bind(slug)
    .bind(vec!["test".to_string()])
    .bind(vec!["civ".to_string()])
    .execute(pool)
    .await
    .unwrap();
}

async fn cleanup(pool: &PgPool, slug: &str, participant_id: Uuid) {
    sqlx::query("DELETE FROM macros WHERE slug = $1")
        .bind(slug)
        .execute(pool)
        .await
        .ok();
    sqlx::query("DELETE FROM participants WHERE id = $1")
        .bind(participant_id)
        .execute(pool)
        .await
        .ok();
}

fn router(pool: PgPool) -> Router {
    let limiter = handlers::macros_telemetry::build_rate_limiter();
    Router::new()
        .route(
            "/v1/macros/:slug/run-event",
            post(handlers::macros_telemetry::run_event),
        )
        .layer(Extension(limiter))
        .layer(middleware::from_fn_with_state(
            auth::middleware::ApiAuthState {
                pool: pool.clone(),
                oauth: None,
            },
            auth::require_auth,
        ))
        .with_state(pool)
}

fn run_event_request(token: &str, slug: &str) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(format!("/v1/macros/{slug}/run-event"))
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .body(Body::from(r#"{"success": true}"#))
        .unwrap()
}

#[tokio::test]
async fn unauthenticated_returns_401() {
    let Some(pool) = pool().await else { return };
    let slug = format!("test-tel-401-{}", Uuid::new_v4());
    seed_macro(&pool, &slug).await;

    let resp = router(pool.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/macros/{slug}/run-event"))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"success": true}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

    sqlx::query("DELETE FROM macros WHERE slug = $1")
        .bind(&slug)
        .execute(&pool)
        .await
        .ok();
}

#[tokio::test]
async fn authenticated_success_inserts_event() {
    let Some(pool) = pool().await else { return };
    let slug = format!("test-tel-ok-{}", Uuid::new_v4());
    seed_macro(&pool, &slug).await;
    let (token, participant_id) = seed_participant(&pool).await;

    let resp = router(pool.clone())
        .oneshot(run_event_request(&token, &slug))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    let count: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM macro_run_events ev \
         JOIN macros m ON m.id = ev.macro_id \
         WHERE m.slug = $1",
    )
    .bind(&slug)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count.0, 1);

    cleanup(&pool, &slug, participant_id).await;
}

#[tokio::test]
async fn rate_limit_after_sixty_per_minute() {
    let Some(pool) = pool().await else { return };
    let slug = format!("test-tel-rl-{}", Uuid::new_v4());
    seed_macro(&pool, &slug).await;
    let (token, participant_id) = seed_participant(&pool).await;
    let app = router(pool.clone());

    let mut success = 0;
    let mut rate_limited = 0;
    for _ in 0..70 {
        let resp = app
            .clone()
            .oneshot(run_event_request(&token, &slug))
            .await
            .unwrap();
        match resp.status() {
            StatusCode::NO_CONTENT => success += 1,
            StatusCode::TOO_MANY_REQUESTS => rate_limited += 1,
            other => panic!("unexpected status {other}"),
        }
    }
    assert_eq!(success, 60, "expected exactly 60 successes, got {success}");
    assert_eq!(rate_limited, 10, "expected 10 rate-limit responses, got {rate_limited}");

    cleanup(&pool, &slug, participant_id).await;
}

#[tokio::test]
async fn unknown_slug_returns_400() {
    let Some(pool) = pool().await else { return };
    let (token, participant_id) = seed_participant(&pool).await;
    let app = router(pool.clone());
    let resp = app
        .oneshot(run_event_request(&token, "nonexistent-slug-xyz"))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    cleanup(&pool, "nonexistent-slug-xyz", participant_id).await;
}
