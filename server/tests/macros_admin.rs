//! Integration tests for the admin macros endpoints (CAR-271 T7).
//!
//! Skips silently when `TEST_DATABASE_URL` isn't set.

#![cfg(test)]

use activities_server::{auth, handlers};
use axum::{
    body::Body,
    http::{Request, StatusCode},
    middleware,
    routing::{post, put},
    Router,
};
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

async fn pool() -> Option<PgPool> {
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

const TEST_ADMIN_TOKEN: &str = "test-admin-token-for-integration";

fn router(pool: PgPool) -> Router {
    let create = post(handlers::macros_admin::create_macro)
        .get(handlers::macros_admin::list_macros);
    let mutate = put(handlers::macros_admin::update_macro)
        .patch(handlers::macros_admin::patch_macro)
        .delete(handlers::macros_admin::delete_macro);
    Router::new()
        .route("/v1/admin/macros", create)
        .route("/v1/admin/macros/:slug", mutate)
        .layer(middleware::from_fn_with_state(
            TEST_ADMIN_TOKEN.to_string(),
            auth::require_admin,
        ))
        .with_state(pool)
}

fn admin(req: Request<Body>) -> Request<Body> {
    let (mut parts, body) = req.into_parts();
    parts
        .headers
        .insert("authorization", format!("Bearer {TEST_ADMIN_TOKEN}").parse().unwrap());
    Request::from_parts(parts, body)
}

fn sample_payload(slug: &str) -> Value {
    json!({
        "slug": slug,
        "name": "Sample",
        "icon": "waveform",
        "description": "test",
        "tags": ["cw"],
        "appliesTo": ["civ"],
        "capabilities": { "transmits": false, "changesFrequency": false, "changesMode": false, "changesPower": false, "usesRawBytes": false },
        "args": [],
        "steps": [{ "kind": "delay", "durationMs": 100 }],
        "format": 2,
        "status": "approved"
    })
}

async fn body_json(resp: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(resp.into_body(), 1024 * 1024)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap_or(json!(null))
}

async fn cleanup(pool: &PgPool, slug: &str) {
    sqlx::query("DELETE FROM macros WHERE slug = $1")
        .bind(slug)
        .execute(pool)
        .await
        .ok();
}

#[tokio::test]
async fn unauth_create_returns_401() {
    let Some(pool) = pool().await else { return };
    let slug = format!("admin-test-401-{}", Uuid::new_v4());
    let req = Request::builder()
        .method("POST")
        .uri("/v1/admin/macros")
        .header("content-type", "application/json")
        .body(Body::from(sample_payload(&slug).to_string()))
        .unwrap();
    let resp = router(pool.clone()).oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    cleanup(&pool, &slug).await;
}

#[tokio::test]
async fn create_then_bump_then_patch_then_delete() {
    let Some(pool) = pool().await else { return };
    let slug = format!("admin-test-flow-{}", Uuid::new_v4());
    let app = router(pool.clone());

    // CREATE
    let req = admin(
        Request::builder()
            .method("POST")
            .uri("/v1/admin/macros")
            .header("content-type", "application/json")
            .body(Body::from(sample_payload(&slug).to_string()))
            .unwrap(),
    );
    let resp = app.clone().oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    let body = body_json(resp).await;
    assert_eq!(body["version"], 1);

    // BUMP (same POST -> 200 OK + version 2)
    let req = admin(
        Request::builder()
            .method("POST")
            .uri("/v1/admin/macros")
            .header("content-type", "application/json")
            .body(Body::from(sample_payload(&slug).to_string()))
            .unwrap(),
    );
    let resp = app.clone().oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_json(resp).await;
    assert_eq!(body["version"], 2);

    // PATCH status=withdrawn
    let req = admin(
        Request::builder()
            .method("PATCH")
            .uri(format!("/v1/admin/macros/{slug}"))
            .header("content-type", "application/json")
            .body(Body::from(
                json!({ "status": "withdrawn", "moderator_notes": "test" }).to_string(),
            ))
            .unwrap(),
    );
    let resp = app.clone().oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_json(resp).await;
    assert_eq!(body["status"], "withdrawn");

    // DELETE
    let req = admin(
        Request::builder()
            .method("DELETE")
            .uri(format!("/v1/admin/macros/{slug}"))
            .body(Body::empty())
            .unwrap(),
    );
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn create_rejects_bad_verifier_spec() {
    let Some(pool) = pool().await else { return };
    let slug = format!("admin-test-bad-{}", Uuid::new_v4());
    let mut payload = sample_payload(&slug);
    // Make `sendCW` non-ASCII so verifier rejects.
    payload["steps"] = json!([{ "kind": "sendCW", "text": "CQ — DE W6JY" }]);
    payload["capabilities"]["transmits"] = json!(true);
    let req = admin(
        Request::builder()
            .method("POST")
            .uri("/v1/admin/macros")
            .header("content-type", "application/json")
            .body(Body::from(payload.to_string()))
            .unwrap(),
    );
    let resp = router(pool.clone()).oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    cleanup(&pool, &slug).await;
}

#[tokio::test]
async fn list_returns_all_statuses() {
    let Some(pool) = pool().await else { return };
    let slug = format!("admin-test-list-{}", Uuid::new_v4());
    sqlx::query(
        "INSERT INTO macros (id, slug, name, capabilities, args, steps, format, status, tags, applies_to) \
         VALUES ($1, $2, 'list', '{}'::jsonb, '[]'::jsonb, '[]'::jsonb, 2, 'pending', '{}', '{civ}')",
    )
    .bind(Uuid::new_v4())
    .bind(&slug)
    .execute(&pool)
    .await
    .unwrap();

    let req = admin(
        Request::builder()
            .uri("/v1/admin/macros?status=pending")
            .body(Body::empty())
            .unwrap(),
    );
    let resp = router(pool.clone()).oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_json(resp).await;
    assert!(body["entries"].as_array().unwrap().iter().any(|e| e["slug"] == slug));

    cleanup(&pool, &slug).await;
}

#[tokio::test]
async fn put_path_mismatch_rejected() {
    let Some(pool) = pool().await else { return };
    let slug = format!("admin-test-put-{}", Uuid::new_v4());
    let payload = sample_payload(&slug);
    let req = admin(
        Request::builder()
            .method("PUT")
            .uri("/v1/admin/macros/different-slug")
            .header("content-type", "application/json")
            .body(Body::from(payload.to_string()))
            .unwrap(),
    );
    let resp = router(pool).oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

