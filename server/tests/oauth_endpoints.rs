//! HTTP integration tests for the Phase 5 OAuth endpoints (`/v1/auth/*`).
//!
//! Require a live Postgres pointed to by `TEST_DATABASE_URL` (with migration
//! 044 applied). Skip silently when unset so `cargo test` stays green in CI
//! without a DB.

#![cfg(test)]

use std::sync::Arc;

use axum::{
    body::Body,
    http::{Request, StatusCode},
    routing::{delete, get, post},
    Extension, Router,
};
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use activities_server::auth::jwt::JwtKeys;
use activities_server::auth::jwt_middleware::{require_jwt_auth, JwtAuthState};
use activities_server::auth::mailer::Mailer;
use activities_server::auth::revocation::RevocationCache;
use activities_server::auth::directory::CallsignDirectory;
use activities_server::auth::tokens::{
    generate_poll_token, generate_verification_code, pkce_challenge_for,
};
use activities_server::db::auth as dbauth;
use activities_server::handlers::auth::AuthSettings;

const TEST_PRIV: &[u8] = b"-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIPvhZplQ+xojm0jKVT0hj5UeIhJseS3m04xy2YrlK1qe\n-----END PRIVATE KEY-----\n";
const TEST_PUB: &[u8] = b"-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAj4viocqz7AJdIwt15uC2eOnaRlfSc6xxmDmCn32TttY=\n-----END PUBLIC KEY-----\n";

async fn pool() -> Option<PgPool> {
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

fn router(pool: PgPool) -> Router {
    router_with_cache(pool, Arc::new(RevocationCache::new()))
}

fn router_with_cache(pool: PgPool, cache: Arc<RevocationCache>) -> Router {
    let jwt = Arc::new(JwtKeys::from_pem(TEST_PRIV, TEST_PUB, "test").unwrap());
    let settings = Arc::new(AuthSettings {
        base_url: "https://test.local".to_string(),
    });
    let jwt_state = JwtAuthState {
        pool: pool.clone(),
        jwt: jwt.clone(),
        cache,
    };
    let public = Router::new()
        .route(
            "/v1/auth/verify/start",
            post(activities_server::handlers::auth::verify_start),
        )
        .route(
            "/v1/auth/verify/complete",
            get(activities_server::handlers::auth::verify_complete),
        )
        .route(
            "/v1/auth/verify/poll",
            post(activities_server::handlers::auth::verify_poll),
        )
        .route(
            "/v1/auth/token",
            post(activities_server::handlers::auth::issue_token),
        )
        .route(
            "/v1/auth/token/refresh",
            post(activities_server::handlers::auth::refresh_token),
        )
        .route(
            "/v1/auth/logout",
            post(activities_server::handlers::auth::logout),
        )
        .layer(Extension(jwt))
        .layer(Extension(Arc::new(Mailer::Null)))
        .layer(Extension(Arc::new(CallsignDirectory::Null)))
        .layer(Extension(settings));
    let authed = Router::new()
        .route(
            "/v1/auth/logout/all",
            post(activities_server::handlers::auth::logout_all),
        )
        .route(
            "/v1/auth/devices",
            get(activities_server::handlers::auth::list_devices),
        )
        .route(
            "/v1/auth/devices/:id",
            delete(activities_server::handlers::auth::delete_device),
        )
        .layer(axum::middleware::from_fn_with_state(
            jwt_state,
            require_jwt_auth,
        ));
    public.merge(authed).with_state(pool)
}

fn unique_call() -> String {
    format!("T{}", &Uuid::new_v4().simple().to_string()[..7]).to_uppercase()
}

fn post_json(uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(uri)
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

async fn body_json(resp: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(resp.into_body(), 1 << 20).await.unwrap();
    serde_json::from_slice(&bytes).unwrap_or(Value::Null)
}

fn complete(code: &str) -> Request<Body> {
    Request::builder()
        .uri(format!("/v1/auth/verify/complete?code={code}"))
        .body(Body::empty())
        .unwrap()
}

fn get_auth(uri: &str, bearer: &str) -> Request<Body> {
    Request::builder()
        .method("GET")
        .uri(uri)
        .header("authorization", format!("Bearer {bearer}"))
        .body(Body::empty())
        .unwrap()
}

/// Drive the full onboarding flow and return `(access, refresh)`.
async fn onboard(pool: &PgPool, app: Router) -> (String, String) {
    let cs = unique_call();
    let code = generate_verification_code();
    let verifier = "device-verifier-onboard";
    let challenge = pkce_challenge_for(verifier);
    dbauth::create_email_verification(
        pool,
        &cs,
        "a@b.co",
        &code,
        dbauth::METHOD_USER,
        None,
        &challenge,
        &generate_poll_token(),
        None,
    )
    .await
    .unwrap();
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/v1/auth/verify/complete?code={code}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let resp = app
        .oneshot(post_json(
            "/v1/auth/token",
            serde_json::json!({ "code": code, "pkceVerifier": verifier, "deviceName": "iPhone", "platform": "ios" }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    let json = body_json(resp).await;
    (
        json["access"].as_str().unwrap().to_string(),
        json["refresh"].as_str().unwrap().to_string(),
    )
}

/// Onboard a specific callsign/email and return `(account_id, access, refresh)`.
async fn onboard_full(pool: &PgPool, app: Router, cs: &str, email: &str) -> (Uuid, String, String) {
    let code = generate_verification_code();
    let verifier = "device-verifier-onboard-full";
    let challenge = pkce_challenge_for(verifier);
    dbauth::create_email_verification(
        pool,
        cs,
        email,
        &code,
        dbauth::METHOD_USER,
        None,
        &challenge,
        &generate_poll_token(),
        None,
    )
    .await
    .unwrap();
    let resp = app.clone().oneshot(complete(&code)).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let resp = app
        .oneshot(post_json(
            "/v1/auth/token",
            serde_json::json!({ "code": code, "pkceVerifier": verifier, "deviceName": "iPhone A", "platform": "ios" }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    let json = body_json(resp).await;
    let account_id = Uuid::parse_str(json["accountId"].as_str().unwrap()).unwrap();
    (
        account_id,
        json["access"].as_str().unwrap().to_string(),
        json["refresh"].as_str().unwrap().to_string(),
    )
}

/// A bare verify/start for a callsign that already belongs to an account must
/// bind the verification to that account and address the magic link to the
/// account's ON-FILE email — a fresh user-supplied address is ignored (no
/// takeover of someone else's callsign via a second device).
#[tokio::test]
async fn verify_start_for_existing_callsign_binds_account_and_keeps_on_file_email() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let cs = unique_call();
    let (account_id, _access, _refresh) =
        onboard_full(&pool, router(pool.clone()), &cs, "a@b.co").await;

    // Second device verifies the SAME callsign, supplying a different address.
    let challenge = pkce_challenge_for("device-verifier-B");
    let resp = router(pool.clone())
        .oneshot(post_json(
            "/v1/auth/verify/start",
            serde_json::json!({ "callsign": cs, "email": "attacker@evil.example", "pkceChallenge": challenge }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::ACCEPTED);

    let (bound, email, method) = sqlx::query_as::<_, (Option<Uuid>, String, String)>(
        "SELECT account_id, email, method FROM email_verifications WHERE UPPER(callsign) = $1 ORDER BY created_at DESC LIMIT 1",
    )
    .bind(&cs)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(bound, Some(account_id));
    assert_eq!(email, "a@b.co");
    assert_eq!(method, "user_email");
}

/// A new device whose verification is bound to an account that already owns the
/// callsign signs IN — minting a second device + token pair (201, not the D8
/// 204 attach) — so the account ends up with two independent device sessions.
#[tokio::test]
async fn second_device_signs_into_existing_account() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let cs = unique_call();
    let (account_id, access_a, _refresh_a) =
        onboard_full(&pool, router(pool.clone()), &cs, "a@b.co").await;

    // Device B: a verification bound to the SAME account (as verify/start would
    // produce for an already-owned callsign), then exchange it at /token.
    let code = generate_verification_code();
    let verifier = "device-verifier-signin-B";
    let challenge = pkce_challenge_for(verifier);
    dbauth::create_email_verification(
        &pool,
        &cs,
        "a@b.co",
        &code,
        dbauth::METHOD_USER,
        Some(account_id),
        &challenge,
        &generate_poll_token(),
        None,
    )
    .await
    .unwrap();
    let resp = router(pool.clone()).oneshot(complete(&code)).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Sign-in mints a fresh pair (201) on the SAME account — not a 204 attach.
    let resp = router(pool.clone())
        .oneshot(post_json(
            "/v1/auth/token",
            serde_json::json!({ "code": code, "pkceVerifier": verifier, "deviceName": "iPad B", "platform": "ios" }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    let json = body_json(resp).await;
    assert!(json["refresh"].as_str().unwrap().starts_with("cwr_"));
    assert_eq!(json["accountId"].as_str().unwrap(), account_id.to_string());

    // The account now lists TWO devices (device A's access token can see both).
    let resp = router(pool.clone())
        .oneshot(get_auth("/v1/auth/devices", &access_a))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["data"].as_array().unwrap().len(), 2);
}

#[tokio::test]
async fn devices_list_and_revoke() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let (access, _refresh) = onboard(&pool, router(pool.clone())).await;

    // List devices — onboarding registered exactly one.
    let resp = router(pool.clone())
        .oneshot(get_auth("/v1/auth/devices", &access))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    let devices = json["data"].as_array().unwrap();
    assert_eq!(devices.len(), 1);
    let device_id = devices[0]["id"].as_str().unwrap().to_string();

    // No bearer → 401.
    let resp = router(pool.clone())
        .oneshot(
            Request::builder()
                .uri("/v1/auth/devices")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

    // Delete the device.
    let resp = router(pool.clone())
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/auth/devices/{device_id}"))
                .header("authorization", format!("Bearer {access}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    let resp = router(pool.clone())
        .oneshot(get_auth("/v1/auth/devices", &access))
        .await
        .unwrap();
    let json = body_json(resp).await;
    assert_eq!(json["data"].as_array().unwrap().len(), 0);
}

#[tokio::test]
async fn logout_all_revokes_refresh_families() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let (access, refresh) = onboard(&pool, router(pool.clone())).await;

    // Access works before logout-all (cache empty).
    let resp = router(pool.clone())
        .oneshot(get_auth("/v1/auth/devices", &access))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Logout everywhere.
    let resp = router(pool.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/logout/all")
                .header("authorization", format!("Bearer {access}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    // The device's refresh family is revoked → refresh now fails (deterministic).
    let resp = router(pool.clone())
        .oneshot(post_json(
            "/v1/auth/token/refresh",
            serde_json::json!({ "refresh": refresh }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    // The cache-based access-token (epoch) rejection path is unit-tested in
    // auth::revocation::tests::cache_reflects_account_epoch_after_refresh.
}

#[tokio::test]
async fn verify_start_returns_202_and_records_row() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let app = router(pool.clone());
    let cs = unique_call();
    let challenge = pkce_challenge_for("verifier-abc");
    let resp = app
        .oneshot(post_json(
            "/v1/auth/verify/start",
            serde_json::json!({ "callsign": cs, "email": "a@b.co", "pkceChallenge": challenge }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::ACCEPTED);

    let count = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM email_verifications WHERE UPPER(callsign) = $1",
    )
    .bind(&cs)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count, 1);
}

#[tokio::test]
async fn full_onboarding_then_refresh_then_logout() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let cs = unique_call();
    let code = generate_verification_code();
    let verifier = "device-verifier-123";
    let challenge = pkce_challenge_for(verifier);

    // Seed a verification with a known code (verify/start emails the code; the
    // NullMailer doesn't surface it to the test, so we create it directly).
    dbauth::create_email_verification(
        &pool,
        &cs,
        "a@b.co",
        &code,
        dbauth::METHOD_USER,
        None,
        &challenge,
        &generate_poll_token(),
        None,
    )
    .await
    .unwrap();

    // Click the magic link.
    let app = router(pool.clone());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(format!("/v1/auth/verify/complete?code={code}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    assert_eq!(resp.headers().get("referrer-policy").unwrap(), "no-referrer");

    // Wrong PKCE verifier at /token → 401 (F8 device binding).
    let app = router(pool.clone());
    let resp = app
        .oneshot(post_json(
            "/v1/auth/token",
            serde_json::json!({ "code": code, "pkceVerifier": "wrong" }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Correct verifier → 201 + token pair.
    let app = router(pool.clone());
    let resp = app
        .oneshot(post_json(
            "/v1/auth/token",
            serde_json::json!({ "code": code, "pkceVerifier": verifier, "deviceName": "iPhone", "platform": "ios" }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    let json = body_json(resp).await;
    let access = json["access"].as_str().unwrap().to_string();
    let refresh = json["refresh"].as_str().unwrap().to_string();
    assert!(!access.is_empty());
    assert!(refresh.starts_with("cwr_"));

    // The access token verifies for cw-social.
    let keys = JwtKeys::from_pem(TEST_PRIV, TEST_PUB, "test").unwrap();
    let claims = keys
        .verify_access(&access, activities_server::auth::jwt::AUD_SOCIAL, None)
        .unwrap();
    assert_eq!(claims.cs, cs);

    // Refresh rotates the token.
    let app = router(pool.clone());
    let resp = app
        .oneshot(post_json(
            "/v1/auth/token/refresh",
            serde_json::json!({ "refresh": refresh }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    let refresh2 = json["refresh"].as_str().unwrap().to_string();
    assert_ne!(refresh, refresh2);

    // Logout revokes the family.
    let app = router(pool.clone());
    let resp = app
        .oneshot(post_json(
            "/v1/auth/logout",
            serde_json::json!({ "refresh": refresh2 }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    // A refresh after logout fails (401).
    let app = router(pool.clone());
    let resp = app
        .oneshot(post_json(
            "/v1/auth/token/refresh",
            serde_json::json!({ "refresh": refresh2 }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn verify_start_prefers_directory_email_over_user_supplied() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let cs = unique_call();
    // The directory has an on-file address for this callsign.
    let mut map = std::collections::HashMap::new();
    map.insert(cs.clone(), "onfile@directory.example".to_string());

    let jwt = Arc::new(JwtKeys::from_pem(TEST_PRIV, TEST_PUB, "test").unwrap());
    let settings = Arc::new(AuthSettings {
        base_url: "https://test.local".to_string(),
    });
    let app = Router::new()
        .route(
            "/v1/auth/verify/start",
            post(activities_server::handlers::auth::verify_start),
        )
        .layer(Extension(jwt))
        .layer(Extension(Arc::new(Mailer::Null)))
        .layer(Extension(Arc::new(CallsignDirectory::Fixed(map))))
        .layer(Extension(settings))
        .with_state(pool.clone());

    // The attacker supplies a different email; the directory address must win
    // (F1/D6 — user-supplied can't redirect a directory-resolvable callsign).
    let challenge = pkce_challenge_for("v");
    let resp = app
        .oneshot(post_json(
            "/v1/auth/verify/start",
            serde_json::json!({ "callsign": cs, "email": "attacker@evil.example", "pkceChallenge": challenge }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::ACCEPTED);

    let (method, email) = sqlx::query_as::<_, (String, String)>(
        "SELECT method, email FROM email_verifications WHERE UPPER(callsign) = $1 ORDER BY created_at DESC LIMIT 1",
    )
    .bind(&cs)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(method, "directory_email");
    assert_eq!(email, "onfile@directory.example");
}

#[tokio::test]
async fn poll_returns_pending_then_issues_tokens() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let cs = unique_call();
    let code = generate_verification_code();
    let verifier = "device-verifier-poll-http";
    let challenge = pkce_challenge_for(verifier);
    let poll = generate_poll_token();
    dbauth::create_email_verification(
        &pool,
        &cs,
        "a@b.co",
        &code,
        dbauth::METHOD_USER,
        None,
        &challenge,
        &poll,
        None,
    )
    .await
    .unwrap();

    // Poll before the link is clicked → 202 Pending.
    let resp = router(pool.clone())
        .oneshot(post_json(
            "/v1/auth/verify/poll",
            serde_json::json!({ "pollToken": poll, "pkceVerifier": verifier }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::ACCEPTED);

    // Click the magic link.
    let resp = router(pool.clone())
        .oneshot(
            Request::builder()
                .uri(format!("/v1/auth/verify/complete?code={code}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Poll now → 201 + token pair (mints identically to /token).
    let resp = router(pool.clone())
        .oneshot(post_json(
            "/v1/auth/verify/poll",
            serde_json::json!({ "pollToken": poll, "pkceVerifier": verifier, "deviceName": "iPad", "platform": "ios" }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    let json = body_json(resp).await;
    assert!(json["refresh"].as_str().unwrap().starts_with("cwr_"));

    // The verification was consumed — a second poll is back to 202 Pending.
    let resp = router(pool.clone())
        .oneshot(post_json(
            "/v1/auth/verify/poll",
            serde_json::json!({ "pollToken": poll, "pkceVerifier": verifier }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::ACCEPTED);
}
