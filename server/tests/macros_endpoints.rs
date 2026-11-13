//! Integration tests for the Phase 1 public macros endpoints (CAR-271 T5).
//!
//! These tests require a live Postgres pointed to by `TEST_DATABASE_URL`.
//! They skip silently when the env var isn't set so `cargo test` stays
//! green in CI environments without a DB.

#![cfg(test)]

use axum::{
    body::Body,
    http::{Request, StatusCode},
    routing::get,
    Router,
};
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

async fn pool() -> Option<PgPool> {
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

/// Hits the actual production wiring (`activities-server`'s handler module)
/// for `/v1/macros*` paths. Insulates the test from route-path typos.
fn router(pool: PgPool) -> Router {
    Router::new()
        .route(
            "/v1/macros",
            get(activities_server::handlers::macros::list_macros),
        )
        .route(
            "/v1/macros/versions",
            get(activities_server::handlers::macros::versions_for_slugs),
        )
        .route(
            "/v1/macros/tombstones",
            get(activities_server::handlers::macros::tombstones),
        )
        .route(
            "/v1/macros/:slug",
            get(activities_server::handlers::macros::get_macro),
        )
        .route(
            "/v1/macros/:slug/versions",
            get(activities_server::handlers::macros::list_macro_versions),
        )
        .with_state(pool)
}

async fn seed(pool: &PgPool, slug: &str, status: &str) {
    sqlx::query(
        "INSERT INTO macros (id, slug, name, capabilities, args, steps, format, status, \
                             tags, applies_to) \
         VALUES ($1, $2, 'test', '{}'::jsonb, '[]'::jsonb, '[]'::jsonb, 2, $3, $4, $5)",
    )
    .bind(Uuid::new_v4())
    .bind(slug)
    .bind(status)
    .bind(vec!["cw".to_string(), "test".to_string()])
    .bind(vec!["civ".to_string()])
    .execute(pool)
    .await
    .unwrap();
}

async fn cleanup(pool: &PgPool, slug: &str) {
    sqlx::query("DELETE FROM macros WHERE slug = $1")
        .bind(slug)
        .execute(pool)
        .await
        .ok();
}

async fn body_json(resp: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(resp.into_body(), 1024 * 1024)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

#[tokio::test]
async fn list_returns_only_approved() {
    let Some(pool) = pool().await else { return };
    let slug_a = format!("test-list-a-{}", Uuid::new_v4());
    let slug_b = format!("test-list-b-{}", Uuid::new_v4());
    seed(&pool, &slug_a, "approved").await;
    seed(&pool, &slug_b, "pending").await;

    let app = router(pool.clone());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!("/v1/macros?search={slug_a}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    let entries = json["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0]["slug"], slug_a);

    cleanup(&pool, &slug_a).await;
    cleanup(&pool, &slug_b).await;
}

#[tokio::test]
async fn list_filters_by_tag() {
    let Some(pool) = pool().await else { return };
    let slug = format!("test-tag-{}", Uuid::new_v4());
    let unique_tag = format!("tagfilter{}", Uuid::new_v4().simple());
    sqlx::query(
        "INSERT INTO macros (id, slug, name, capabilities, args, steps, format, status, tags, applies_to) \
         VALUES ($1, $2, 'test', '{}'::jsonb, '[]'::jsonb, '[]'::jsonb, 2, 'approved', $3, $4)",
    )
    .bind(Uuid::new_v4())
    .bind(&slug)
    .bind(vec![unique_tag.clone()])
    .bind(vec!["civ".to_string()])
    .execute(&pool)
    .await
    .unwrap();

    let app = router(pool.clone());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!("/v1/macros?tag={unique_tag}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["entries"].as_array().unwrap().len(), 1);

    cleanup(&pool, &slug).await;
}

#[tokio::test]
async fn list_filters_by_max_format() {
    let Some(pool) = pool().await else { return };
    let slug = format!("test-fmt-{}", Uuid::new_v4());
    seed(&pool, &slug, "approved").await;

    let app = router(pool.clone());
    // max_format=1 -> format=2 row is excluded.
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!("/v1/macros?search={slug}&max_format=1"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let json = body_json(resp).await;
    assert!(json["entries"].as_array().unwrap().is_empty());

    cleanup(&pool, &slug).await;
}

#[tokio::test]
async fn get_by_slug_returns_full_document() {
    let Some(pool) = pool().await else { return };
    let slug = format!("test-get-{}", Uuid::new_v4());
    seed(&pool, &slug, "approved").await;

    let app = router(pool.clone());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!("/v1/macros/{slug}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["slug"], slug);
    assert_eq!(json["format"], 2);
    assert!(json["spec"]["steps"].is_array());

    cleanup(&pool, &slug).await;
}

#[tokio::test]
async fn versions_for_slugs_returns_per_slug_map() {
    let Some(pool) = pool().await else { return };
    let slug_a = format!("test-versions-a-{}", Uuid::new_v4());
    let slug_b = format!("test-versions-b-{}", Uuid::new_v4());
    seed(&pool, &slug_a, "approved").await;
    seed(&pool, &slug_b, "pending").await;

    let app = router(pool.clone());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!("/v1/macros/versions?slugs={slug_a},{slug_b},nope"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    // slug_b is pending and `nope` doesn't exist — both omitted.
    assert!(json.get(&slug_a).is_some());
    assert!(json.get(&slug_b).is_none());
    assert_eq!(json[&slug_a]["format"], 2);
    assert_eq!(json[&slug_a]["version"], 1);

    cleanup(&pool, &slug_a).await;
    cleanup(&pool, &slug_b).await;
}

#[tokio::test]
async fn tombstones_endpoint_returns_recent() {
    let Some(pool) = pool().await else { return };
    let slug = format!("test-tomb-{}", Uuid::new_v4());
    seed(&pool, &slug, "approved").await;
    activities_server::db::macros::set_status(&pool, &slug, "withdrawn", Some("test"))
        .await
        .unwrap();

    let app = router(pool.clone());
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/v1/macros/tombstones")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    let entries = json["entries"].as_array().unwrap();
    assert!(entries.iter().any(|e| e["slug"] == slug));

    cleanup(&pool, &slug).await;
}
