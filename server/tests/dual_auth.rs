//! Dual-auth bridge: the legacy `require_auth` middleware accepts BOTH a Phase 5
//! OAuth JWT access token and a legacy `fd_` device token, so existing protected
//! endpoints work for OAuth clients without a hard cutover.
//!
//! Requires `TEST_DATABASE_URL` (migration 044 applied); skips otherwise.

#![cfg(test)]

use std::sync::Arc;

use axum::{
    body::Body,
    http::{Request, StatusCode},
    routing::get,
    Extension, Json, Router,
};
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use activities_server::auth::jwt::{JwtKeys, AUD_SOCIAL};
use activities_server::auth::middleware::{require_auth, ApiAuthState, AuthContext, OAuthVerifier};
use activities_server::auth::revocation::RevocationCache;
use activities_server::db::auth as dbauth;

const TEST_PRIV: &[u8] = b"-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIPvhZplQ+xojm0jKVT0hj5UeIhJseS3m04xy2YrlK1qe\n-----END PRIVATE KEY-----\n";
const TEST_PUB: &[u8] = b"-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAj4viocqz7AJdIwt15uC2eOnaRlfSc6xxmDmCn32TttY=\n-----END PUBLIC KEY-----\n";

async fn pool() -> Option<PgPool> {
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

fn unique_call() -> String {
    format!("D{}", &Uuid::new_v4().simple().to_string()[..7]).to_uppercase()
}

// A stand-in protected handler that echoes the established identity.
async fn whoami(Extension(ctx): Extension<AuthContext>) -> Json<Value> {
    Json(serde_json::json!({
        "callsign": ctx.callsign,
        "participantId": ctx.participant_id,
        "accountId": ctx.account_id,
    }))
}

fn router(pool: PgPool, jwt: Arc<JwtKeys>) -> Router {
    let state = ApiAuthState {
        pool: pool.clone(),
        oauth: Some(OAuthVerifier {
            jwt,
            cache: Arc::new(RevocationCache::new()),
        }),
    };
    Router::new()
        .route("/whoami", get(whoami))
        .layer(axum::middleware::from_fn_with_state(state, require_auth))
        .with_state(pool)
}

async fn body_json(resp: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(resp.into_body(), 1 << 20).await.unwrap();
    serde_json::from_slice(&bytes).unwrap_or(Value::Null)
}

#[tokio::test]
async fn jwt_authenticates_legacy_protected_route() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let jwt = Arc::new(JwtKeys::from_pem(TEST_PRIV, TEST_PUB, "test").unwrap());
    let cs = unique_call();
    let acct = dbauth::create_account_with_callsign(&pool, &cs, dbauth::METHOD_DIRECTORY, None)
        .await
        .unwrap();
    let access = jwt
        .mint_access(acct.id, AUD_SOCIAL, "social:read social:write account", &cs)
        .unwrap();

    let resp = router(pool.clone(), jwt.clone())
        .oneshot(
            Request::builder()
                .uri("/whoami")
                .header("authorization", format!("Bearer {access}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["callsign"], cs);
    assert_eq!(json["accountId"], acct.id.to_string());
    // A participants bridge row was resolved for the JWT identity.
    assert!(json["participantId"].is_string());
}

#[tokio::test]
async fn legacy_fd_token_still_authenticates() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let jwt = Arc::new(JwtKeys::from_pem(TEST_PRIV, TEST_PUB, "test").unwrap());
    let cs = unique_call();
    // Seed a legacy participant with an fd_ device token.
    let token = format!("fd_{}", Uuid::new_v4().simple());
    let pid = Uuid::new_v4();
    sqlx::query("INSERT INTO participants (id, callsign, device_token) VALUES ($1, $2, $3)")
        .bind(pid)
        .bind(&cs)
        .bind(&token)
        .execute(&pool)
        .await
        .unwrap();

    let resp = router(pool.clone(), jwt)
        .oneshot(
            Request::builder()
                .uri("/whoami")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let json = body_json(resp).await;
    assert_eq!(json["callsign"], cs);
    assert_eq!(json["participantId"], pid.to_string());
    // Legacy path → no account linkage.
    assert!(json["accountId"].is_null());
}

#[tokio::test]
async fn no_token_is_unauthorized() {
    let Some(pool) = pool().await else {
        eprintln!("TEST_DATABASE_URL not set; skipping");
        return;
    };
    let jwt = Arc::new(JwtKeys::from_pem(TEST_PRIV, TEST_PUB, "test").unwrap());
    let resp = router(pool.clone(), jwt)
        .oneshot(Request::builder().uri("/whoami").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}
