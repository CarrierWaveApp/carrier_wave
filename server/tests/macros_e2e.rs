//! End-to-end sanity check for the macros stack (CAR-271 T10 acceptance).
//!
//! Walks `server/seed_macros/`, POSTs each starter through the admin
//! endpoint (running through the verifier + slug/tag/band-plan
//! validators), then fetches the catalog back via the public endpoint
//! and asserts every starter round-trips.
//!
//! Skips when TEST_DATABASE_URL isn't set.

#![cfg(test)]

use activities_server::{auth, handlers};
use axum::{
    body::Body,
    http::{Request, StatusCode},
    middleware,
    routing::{get, post, put},
    Router,
};
use serde_json::Value;
use sqlx::PgPool;
use std::fs;
use std::path::PathBuf;
use tower::ServiceExt;

const TEST_ADMIN_TOKEN: &str = "e2e-admin-token";

async fn pool() -> Option<PgPool> {
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

fn admin_router(pool: PgPool) -> Router {
    Router::new()
        .route(
            "/v1/admin/macros",
            post(handlers::macros_admin::create_macro)
                .get(handlers::macros_admin::list_macros),
        )
        .route(
            "/v1/admin/macros/:slug",
            put(handlers::macros_admin::update_macro)
                .patch(handlers::macros_admin::patch_macro)
                .delete(handlers::macros_admin::delete_macro),
        )
        .layer(middleware::from_fn_with_state(
            TEST_ADMIN_TOKEN.to_string(),
            auth::require_admin,
        ))
        .with_state(pool)
}

fn public_router(pool: PgPool) -> Router {
    Router::new()
        .route(
            "/v1/macros",
            get(handlers::macros::list_macros),
        )
        .route(
            "/v1/macros/:slug",
            get(handlers::macros::get_macro),
        )
        .with_state(pool)
}

async fn json_body(resp: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(resp.into_body(), 1024 * 1024)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

#[tokio::test]
async fn seed_corpus_round_trips_admin_to_public() {
    let Some(pool) = pool().await else { return };

    // ---------------------------------------------------------------
    // 1. POST every seed_macros/*.cwmacro through the admin endpoint.
    // ---------------------------------------------------------------
    let seed_dir =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("seed_macros");
    let mut seed_paths: Vec<PathBuf> = fs::read_dir(&seed_dir)
        .expect("seed_macros dir exists")
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("cwmacro"))
        .collect();
    seed_paths.sort();
    assert!(!seed_paths.is_empty(), "expected starter macros");

    // Pre-clean to make repeated test runs deterministic.
    sqlx::query("DELETE FROM macros WHERE slug = ANY($1)")
        .bind(seed_paths
            .iter()
            .filter_map(|p| {
                let data = fs::read_to_string(p).ok()?;
                let v: Value = serde_json::from_str(&data).ok()?;
                v["slug"].as_str().map(|s| s.to_string())
            })
            .collect::<Vec<_>>())
        .execute(&pool)
        .await
        .ok();

    let admin = admin_router(pool.clone());
    for path in &seed_paths {
        let body = fs::read_to_string(path)
            .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        let req = Request::builder()
            .method("POST")
            .uri("/v1/admin/macros")
            .header("authorization", format!("Bearer {TEST_ADMIN_TOKEN}"))
            .header("content-type", "application/json")
            .body(Body::from(body))
            .unwrap();
        let resp = admin.clone().oneshot(req).await.unwrap();
        assert!(
            matches!(resp.status(), StatusCode::CREATED | StatusCode::OK),
            "{}: status {}",
            path.display(),
            resp.status()
        );
    }

    // ---------------------------------------------------------------
    // 2. List via the public endpoint — every starter must show up.
    // ---------------------------------------------------------------
    let public = public_router(pool.clone());
    let req = Request::builder()
        .uri("/v1/macros?limit=200")
        .body(Body::empty())
        .unwrap();
    let resp = public.clone().oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = json_body(resp).await;
    let entries = body["entries"].as_array().expect("entries array");
    let listed_slugs: Vec<&str> = entries.iter().filter_map(|e| e["slug"].as_str()).collect();
    for path in &seed_paths {
        let data = fs::read_to_string(path).unwrap();
        let parsed: Value = serde_json::from_str(&data).unwrap();
        let slug = parsed["slug"].as_str().expect("slug");
        assert!(
            listed_slugs.contains(&slug),
            "starter `{slug}` missing from /v1/macros listing"
        );
    }

    // ---------------------------------------------------------------
    // 3. Fetch each starter via /v1/macros/:slug and assert the spec
    //    survives the round-trip (steps array length matches).
    // ---------------------------------------------------------------
    for path in &seed_paths {
        let data = fs::read_to_string(path).unwrap();
        let parsed: Value = serde_json::from_str(&data).unwrap();
        let slug = parsed["slug"].as_str().expect("slug");
        let expected_steps = parsed["steps"].as_array().map(|a| a.len()).unwrap_or(0);

        let req = Request::builder()
            .uri(format!("/v1/macros/{slug}"))
            .body(Body::empty())
            .unwrap();
        let resp = public.clone().oneshot(req).await.unwrap();
        assert_eq!(
            resp.status(),
            StatusCode::OK,
            "{slug} GET status {}",
            resp.status()
        );
        let body = json_body(resp).await;
        let got_steps = body["spec"]["steps"]
            .as_array()
            .map(|a| a.len())
            .unwrap_or(0);
        assert_eq!(
            got_steps, expected_steps,
            "{slug} steps mismatch: expected {expected_steps}, got {got_steps}"
        );
    }

    // Cleanup so the test stays repeatable.
    sqlx::query("DELETE FROM macros WHERE slug = ANY($1)")
        .bind(seed_paths
            .iter()
            .filter_map(|p| {
                let data = fs::read_to_string(p).ok()?;
                let v: Value = serde_json::from_str(&data).ok()?;
                v["slug"].as_str().map(|s| s.to_string())
            })
            .collect::<Vec<_>>())
        .execute(&pool)
        .await
        .ok();
}
