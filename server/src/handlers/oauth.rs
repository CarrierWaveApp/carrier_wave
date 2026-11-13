//! Third-party OAuth 2.0 / OpenID Connect provider endpoints (`/v1/oauth/*`).
//!
//! Distinct from `handlers::auth`, which issues tokens to Carrier Wave's OWN
//! apps via email magic-link. This module issues tokens to OTHER people's
//! applications, on a user's behalf, with scopes the user consented to.
//!
//! # What a token here does and does not buy
//!
//! The log is end-to-end encrypted. A token minted here authorizes ACCESS to a
//! tenant's opaque journal — listing entries, downloading ciphertext, pushing
//! new ciphertext. It does not and cannot authorize DECRYPTION: the data key is
//! derived from the user's sync passphrase via Argon2id, client-side, and never
//! reaches this server. A third-party client must ask the user for that
//! passphrase itself.
//!
//! That is a deliberate accepted risk. It means users type their sync passphrase
//! into third-party UI, which is the credential-phishing shape OAuth normally
//! exists to prevent, and there is no key-rotation path today, so an abused
//! passphrase cannot be recovered from. Curated client registration is the
//! mitigation: `oauth_clients` rows are created by an admin, not self-serve.
//!
//! # Error format
//!
//! OAuth errors follow RFC 6749 §5.2 (`{"error": "...", "error_description":
//! "..."}`), NOT this server's usual `{data}`/`{error:{code}}` envelope, because
//! off-the-shelf client libraries parse the RFC shape.
//!
//! Spec: `docs/features/oauth-api.md`. Schema: `migrations/047_oauth_provider.sql`.

use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::{Extension, Form};
use base64::Engine;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::auth::jwt::{IdTokenRequest, JwtKeys, ACCESS_TTL_SECS, AUD_SOCIAL, ISSUER};
use crate::auth::middleware::AuthContext;
use crate::auth::scope_map;
use crate::db::auth as dbauth;
use crate::db::oauth as dboauth;
use crate::error::AppError;
use crate::handlers::auth::AuthSettings;

use super::DataResponse;

/// Grant type identifier for RFC 8628. The spec uses the full URN; the short
/// form is accepted too because people type it.
const DEVICE_CODE_GRANT: &str = "urn:ietf:params:oauth:grant-type:device_code";

// ---- RFC 6749 §5.2 errors --------------------------------------------------

/// An OAuth protocol error, serialized in the shape client libraries expect.
pub struct OAuthError {
    status: StatusCode,
    error: &'static str,
    description: String,
}

impl OAuthError {
    fn new(status: StatusCode, error: &'static str, description: impl Into<String>) -> Self {
        Self {
            status,
            error,
            description: description.into(),
        }
    }

    pub fn invalid_request(description: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, "invalid_request", description)
    }

    pub fn invalid_client(description: impl Into<String>) -> Self {
        Self::new(StatusCode::UNAUTHORIZED, "invalid_client", description)
    }

    /// Covers bad/expired/replayed codes and bad refresh tokens. Deliberately
    /// undifferentiated — telling a caller *which* it was is an oracle.
    pub fn invalid_grant(description: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, "invalid_grant", description)
    }

    pub fn unsupported_grant_type(description: impl Into<String>) -> Self {
        Self::new(
            StatusCode::BAD_REQUEST,
            "unsupported_grant_type",
            description,
        )
    }

    pub fn invalid_scope(description: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, "invalid_scope", description)
    }

    pub fn access_denied(description: impl Into<String>) -> Self {
        Self::new(StatusCode::FORBIDDEN, "access_denied", description)
    }

    /// RFC 8628 §3.5 — the user has not decided yet.
    fn authorization_pending() -> Self {
        Self::new(
            StatusCode::BAD_REQUEST,
            "authorization_pending",
            "the user has not yet approved this request",
        )
    }

    /// RFC 8628 §3.5 — polling faster than `interval`.
    fn slow_down() -> Self {
        Self::new(
            StatusCode::BAD_REQUEST,
            "slow_down",
            "polling too frequently; increase the interval",
        )
    }

    fn expired_token() -> Self {
        Self::new(
            StatusCode::BAD_REQUEST,
            "expired_token",
            "this code has expired; start a new authorization",
        )
    }
}

impl IntoResponse for OAuthError {
    fn into_response(self) -> Response {
        let body = serde_json::json!({
            "error": self.error,
            "error_description": self.description,
        });
        // RFC 6749 §5.1: token responses must not be cached.
        (
            self.status,
            [
                (header::CACHE_CONTROL, "no-store"),
                (header::PRAGMA, "no-cache"),
            ],
            axum::Json(body),
        )
            .into_response()
    }
}

// ---- discovery -------------------------------------------------------------

/// `GET /.well-known/openid-configuration` and its RFC 8414 alias.
///
/// NOTE: `issuer` is the compiled-in [`ISSUER`], which is what tokens actually
/// carry in `iss`, while the endpoint URLs come from the configured base URL. On
/// a deployment whose base URL differs from `ISSUER` (staging), strict OIDC
/// clients that require issuer/host agreement will object. Making `ISSUER`
/// configurable is the real fix and is out of scope here.
pub async fn discovery(Extension(settings): Extension<Arc<AuthSettings>>) -> impl IntoResponse {
    let base = settings.base_url.trim_end_matches('/');
    axum::Json(serde_json::json!({
        "issuer": ISSUER,
        "authorization_endpoint": format!("{base}/v1/oauth/authorize"),
        "token_endpoint": format!("{base}/v1/oauth/token"),
        "userinfo_endpoint": format!("{base}/v1/oauth/userinfo"),
        "revocation_endpoint": format!("{base}/v1/oauth/revoke"),
        "device_authorization_endpoint": format!("{base}/v1/oauth/device/code"),
        "jwks_uri": format!("{base}/.well-known/jwks.json"),
        "scopes_supported": scope_map::ALL_SCOPES,
        "response_types_supported": ["code"],
        "grant_types_supported": ["authorization_code", "refresh_token", DEVICE_CODE_GRANT],
        "subject_types_supported": ["public"],
        "id_token_signing_alg_values_supported": ["EdDSA"],
        "token_endpoint_auth_methods_supported": ["client_secret_basic", "client_secret_post", "none"],
        // PKCE is required, not merely supported — see `verify_pkce`.
        "code_challenge_methods_supported": ["S256"],
        "claims_supported": [
            "iss", "sub", "aud", "exp", "iat", "auth_time", "nonce", "at_hash",
            "callsign", "preferred_username", "email", "email_verified"
        ],
    }))
}

// ---- authorization request -------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct AuthorizeParams {
    pub client_id: String,
    pub redirect_uri: String,
    pub response_type: String,
    #[serde(default)]
    pub scope: Option<String>,
    #[serde(default)]
    pub state: Option<String>,
    pub code_challenge: String,
    #[serde(default)]
    pub code_challenge_method: Option<String>,
    #[serde(default)]
    pub nonce: Option<String>,
}

/// A validated authorization request: the client exists, the redirect is
/// registered, and the requested scopes have been clamped to what the client is
/// allowed to ask for.
pub struct ValidatedAuthorize {
    pub client: dboauth::OAuthClient,
    pub scopes: Vec<String>,
}

/// Validate an authorization request.
///
/// Returns `Err` only for the two failures that must NOT redirect (RFC 6749
/// §4.1.2.1): unknown client and unregistered redirect URI. Redirecting on those
/// would turn this endpoint into an open redirector and could hand an
/// authorization code to whoever supplied the URI. Every other failure is
/// reported back to the client via the redirect.
pub async fn validate_authorize(
    pool: &PgPool,
    params: &AuthorizeParams,
) -> Result<ValidatedAuthorize, OAuthError> {
    let client = dboauth::get_client(pool, &params.client_id)
        .await
        .map_err(|_| OAuthError::invalid_request("client lookup failed"))?
        .filter(dboauth::OAuthClient::is_active)
        .ok_or_else(|| OAuthError::invalid_client("unknown or suspended client"))?;

    if !client.allows_redirect(&params.redirect_uri) {
        return Err(OAuthError::invalid_request(
            "redirect_uri is not registered for this client",
        ));
    }

    let requested = scope_map::sanitize(params.scope.as_deref().unwrap_or("openid"));
    let scopes = client.clamp_scopes(&requested);

    Ok(ValidatedAuthorize { client, scopes })
}

/// Problems that are reported to the client by redirecting with `error=`.
fn authorize_redirect_error(params: &AuthorizeParams, scopes: &[String]) -> Option<&'static str> {
    if params.response_type != "code" {
        return Some("unsupported_response_type");
    }
    // PKCE is mandatory for every client, public or confidential. A confidential
    // client gains nothing by skipping it and the code-interception attack it
    // prevents applies to redirect flows generally.
    if params.code_challenge.is_empty() {
        return Some("invalid_request");
    }
    match params.code_challenge_method.as_deref() {
        // `plain` is not accepted: it offers no protection against an attacker
        // who can already see the authorization request.
        Some("S256") => {}
        _ => return Some("invalid_request"),
    }
    if scopes.is_empty() {
        return Some("invalid_scope");
    }
    None
}

/// Build the redirect back to the client, preserving `state` (the client's CSRF
/// binding, which must be echoed exactly).
fn redirect_url(base: &str, params: &[(&str, &str)], state: Option<&str>) -> String {
    let mut url = String::from(base);
    url.push(if base.contains('?') { '&' } else { '?' });
    let mut first = true;
    let mut push = |key: &str, value: &str| {
        if !first {
            url.push('&');
        }
        first = false;
        url.push_str(&urlencode(key));
        url.push('=');
        url.push_str(&urlencode(value));
    };
    for (k, v) in params {
        push(k, v);
    }
    if let Some(state) = state {
        push("state", state);
    }
    url
}

/// Percent-encode for a query-string value. Conservative allowlist: anything not
/// explicitly unreserved gets encoded.
fn urlencode(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.as_bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(*byte as char)
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

// ---- consent decision ------------------------------------------------------

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DecisionRequest {
    #[serde(flatten)]
    pub params: AuthorizeParams,
    /// `true` to grant, `false` to decline.
    pub approve: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DecisionResponse {
    /// Where the browser should navigate next. Always a registered redirect URI.
    pub redirect_url: String,
}

/// `POST /v1/oauth/authorize/decision` — record the user's consent decision and
/// mint an authorization code.
///
/// Requires a first-party bearer token: the acting user is whoever signed in on
/// the consent page. Every parameter is re-validated here rather than trusted
/// from the rendered page, because the page's inputs are entirely
/// attacker-controllable.
pub async fn authorize_decision(
    State(pool): State<PgPool>,
    Extension(ctx): Extension<AuthContext>,
    axum::Json(req): axum::Json<DecisionRequest>,
) -> Result<axum::Json<DecisionResponse>, OAuthError> {
    let account_id = ctx
        .account_id
        .ok_or_else(|| OAuthError::access_denied("an account-backed session is required"))?;

    let validated = validate_authorize(&pool, &req.params).await?;

    if let Some(error) = authorize_redirect_error(&req.params, &validated.scopes) {
        return Ok(axum::Json(DecisionResponse {
            redirect_url: redirect_url(
                &req.params.redirect_uri,
                &[("error", error)],
                req.params.state.as_deref(),
            ),
        }));
    }

    if !req.approve {
        return Ok(axum::Json(DecisionResponse {
            redirect_url: redirect_url(
                &req.params.redirect_uri,
                &[("error", "access_denied")],
                req.params.state.as_deref(),
            ),
        }));
    }

    let scopes = validated.scopes.join(" ");
    dboauth::upsert_grant(&pool, account_id, &validated.client.client_id, &scopes)
        .await
        .map_err(|_| OAuthError::invalid_request("could not record consent"))?;

    let code = dboauth::create_authorization_code(
        &pool,
        &validated.client.client_id,
        account_id,
        &req.params.redirect_uri,
        &scopes,
        &req.params.code_challenge,
        req.params.nonce.as_deref(),
    )
    .await
    .map_err(|_| OAuthError::invalid_request("could not issue authorization code"))?;

    Ok(axum::Json(DecisionResponse {
        redirect_url: redirect_url(
            &req.params.redirect_uri,
            &[("code", &code)],
            req.params.state.as_deref(),
        ),
    }))
}

// ---- token endpoint --------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct TokenRequest {
    pub grant_type: String,
    #[serde(default)]
    pub code: Option<String>,
    #[serde(default)]
    pub redirect_uri: Option<String>,
    #[serde(default)]
    pub code_verifier: Option<String>,
    #[serde(default)]
    pub refresh_token: Option<String>,
    #[serde(default)]
    pub device_code: Option<String>,
    #[serde(default)]
    pub client_id: Option<String>,
    #[serde(default)]
    pub client_secret: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct TokenResponse {
    pub access_token: String,
    pub token_type: &'static str,
    pub expires_in: i64,
    pub refresh_token: String,
    pub scope: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id_token: Option<String>,
}

/// Client credentials as presented on a token-style endpoint, from either the
/// Basic header or form fields.
struct PresentedCredentials<'a> {
    client_id: Option<&'a str>,
    client_secret: Option<&'a str>,
}

/// Resolve and authenticate the calling client.
///
/// Accepts HTTP Basic (RFC 6749 §2.3.1, the preferred form) or form parameters.
/// A confidential client MUST present its secret; a public client MUST NOT, and
/// relies on PKCE instead.
async fn authenticate_client(
    pool: &PgPool,
    headers: &HeaderMap,
    presented: PresentedCredentials<'_>,
) -> Result<dboauth::OAuthClient, OAuthError> {
    let basic = parse_basic_auth(headers);
    let (client_id, secret) = match (&basic, presented.client_id) {
        // Basic wins: it is the RFC-preferred form, and honoring a form
        // `client_id` that disagrees with the header would be confusing at best.
        (Some((id, secret)), _) => (id.clone(), Some(secret.clone())),
        (None, Some(id)) => (id.to_string(), presented.client_secret.map(str::to_string)),
        (None, None) => {
            return Err(OAuthError::invalid_client("client_id is required"));
        }
    };

    let client = dboauth::get_active_client(pool, &client_id)
        .await
        .map_err(|_| OAuthError::invalid_client("unknown or suspended client"))?;

    if client.is_public() {
        if secret.is_some() {
            return Err(OAuthError::invalid_client(
                "this client is registered as public and must not send a secret",
            ));
        }
    } else {
        let presented = secret.ok_or_else(|| OAuthError::invalid_client("client_secret required"))?;
        if !client.verify_secret(&presented) {
            return Err(OAuthError::invalid_client("bad client credentials"));
        }
    }

    Ok(client)
}

fn parse_basic_auth(headers: &HeaderMap) -> Option<(String, String)> {
    let raw = headers.get(header::AUTHORIZATION)?.to_str().ok()?;
    let encoded = raw.strip_prefix("Basic ")?;
    let decoded = base64::engine::general_purpose::STANDARD.decode(encoded).ok()?;
    let text = String::from_utf8(decoded).ok()?;
    let (id, secret) = text.split_once(':')?;
    Some((id.to_string(), secret.to_string()))
}

/// RFC 7636 S256: `base64url_nopad(sha256(verifier)) == challenge`.
///
/// This is the STANDARD encoding, deliberately different from the hex variant
/// `auth/tokens.rs::pkce_challenge_for` uses for the first-party magic-link poll
/// flow. Third parties use off-the-shelf OAuth libraries, and those libraries
/// emit base64url.
fn verify_pkce(verifier: &str, challenge: &str) -> bool {
    use sha2::{Digest, Sha256};
    // RFC 7636 §4.1 length bounds; also stops a trivially short verifier.
    if verifier.len() < 43 || verifier.len() > 128 {
        return false;
    }
    let digest = Sha256::digest(verifier.as_bytes());
    let computed = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(digest);
    // Both sides are derived from the same public challenge; a timing leak here
    // reveals nothing the attacker did not already supply.
    computed == challenge
}

/// `POST /v1/oauth/token` — exchange a grant for tokens.
pub async fn token(
    State(pool): State<PgPool>,
    Extension(jwt): Extension<Arc<JwtKeys>>,
    headers: HeaderMap,
    Form(req): Form<TokenRequest>,
) -> Result<Response, OAuthError> {
    let client = authenticate_client(
        &pool,
        &headers,
        PresentedCredentials {
            client_id: req.client_id.as_deref(),
            client_secret: req.client_secret.as_deref(),
        },
    )
    .await?;

    let response = match req.grant_type.as_str() {
        "authorization_code" => authorization_code_grant(&pool, &jwt, &client, &req).await?,
        "refresh_token" => refresh_token_grant(&pool, &jwt, &client, &req).await?,
        DEVICE_CODE_GRANT | "device_code" => device_code_grant(&pool, &jwt, &client, &req).await?,
        other => {
            return Err(OAuthError::unsupported_grant_type(format!(
                "unsupported grant_type: {other}"
            )))
        }
    };

    Ok((
        StatusCode::OK,
        [
            (header::CACHE_CONTROL, "no-store"),
            (header::PRAGMA, "no-cache"),
        ],
        axum::Json(response),
    )
        .into_response())
}

async fn authorization_code_grant(
    pool: &PgPool,
    jwt: &JwtKeys,
    client: &dboauth::OAuthClient,
    req: &TokenRequest,
) -> Result<TokenResponse, OAuthError> {
    if !client.allows_grant("authorization_code") {
        return Err(OAuthError::unsupported_grant_type(
            "this client may not use the authorization_code grant",
        ));
    }

    let code = req
        .code
        .as_deref()
        .ok_or_else(|| OAuthError::invalid_request("code is required"))?;
    let verifier = req
        .code_verifier
        .as_deref()
        .ok_or_else(|| OAuthError::invalid_request("code_verifier is required"))?;

    let record = dboauth::consume_authorization_code(pool, code)
        .await
        .map_err(|_| OAuthError::invalid_grant("code exchange failed"))?
        .ok_or_else(|| OAuthError::invalid_grant("invalid, expired, or already-used code"))?;

    // A code issued to one client must not be redeemable by another.
    if record.client_id != client.client_id {
        return Err(OAuthError::invalid_grant("code was issued to another client"));
    }

    // RFC 6749 §4.1.3: redirect_uri must match the authorization request.
    match req.redirect_uri.as_deref() {
        Some(uri) if uri == record.redirect_uri => {}
        _ => {
            return Err(OAuthError::invalid_grant(
                "redirect_uri does not match the authorization request",
            ))
        }
    }

    if !verify_pkce(verifier, &record.code_challenge) {
        return Err(OAuthError::invalid_grant("PKCE verification failed"));
    }

    issue_tokens(
        pool,
        jwt,
        client,
        record.account_id,
        &record.scopes,
        record.nonce.as_deref(),
    )
    .await
}

async fn refresh_token_grant(
    pool: &PgPool,
    jwt: &JwtKeys,
    client: &dboauth::OAuthClient,
    req: &TokenRequest,
) -> Result<TokenResponse, OAuthError> {
    if !client.allows_grant("refresh_token") {
        return Err(OAuthError::unsupported_grant_type(
            "this client may not use the refresh_token grant",
        ));
    }

    let presented = req
        .refresh_token
        .as_deref()
        .ok_or_else(|| OAuthError::invalid_request("refresh_token is required"))?;

    // Bind the token to the calling client BEFORE rotating, so a mismatched
    // caller cannot burn someone else's refresh token.
    let owner = dboauth::client_id_for_refresh(pool, presented)
        .await
        .map_err(|_| OAuthError::invalid_grant("refresh failed"))?;
    if owner.as_deref() != Some(client.client_id.as_str()) {
        return Err(OAuthError::invalid_grant(
            "refresh token was not issued to this client",
        ));
    }

    let issued = match dbauth::rotate_refresh(pool, presented).await {
        Ok(dbauth::RotationOutcome::Rotated(issued)) => issued,
        // Reuse revokes the whole family; the client must re-authorize.
        Ok(_) => return Err(OAuthError::invalid_grant("refresh token is no longer valid")),
        Err(_) => return Err(OAuthError::invalid_grant("refresh failed")),
    };

    // Consent can be revoked between refreshes. Honor that immediately rather
    // than waiting for the refresh token to expire.
    let granted = dboauth::get_grant(pool, issued.row.account_id, &client.client_id)
        .await
        .map_err(|_| OAuthError::invalid_grant("refresh failed"))?
        .ok_or_else(|| OAuthError::invalid_grant("this authorization has been revoked"))?;

    // Never widen on refresh: the effective scopes are the intersection of what
    // the token carries, what the user still grants, and the client's ceiling.
    let carried = scope_map::sanitize(&issued.row.scopes);
    let still_granted: Vec<String> = carried
        .into_iter()
        .filter(|s| granted.split_whitespace().any(|g| g == s))
        .collect();
    let scopes = client.clamp_scopes(&still_granted);
    if scopes.is_empty() {
        return Err(OAuthError::invalid_scope(
            "no granted scopes remain for this client",
        ));
    }

    let account = dbauth::get_account(pool, issued.row.account_id)
        .await
        .map_err(|_| OAuthError::invalid_grant("refresh failed"))?
        .ok_or_else(|| OAuthError::invalid_grant("account no longer exists"))?;

    let scope_str = scopes.join(" ");
    let access = jwt
        .mint_access_for_client(
            account.id,
            AUD_SOCIAL,
            &scope_str,
            &account.primary_callsign,
            Some(&client.client_id),
        )
        .map_err(|_| OAuthError::invalid_grant("token minting failed"))?;

    Ok(TokenResponse {
        access_token: access,
        token_type: "Bearer",
        expires_in: ACCESS_TTL_SECS,
        refresh_token: issued.token,
        scope: scope_str,
        // ID tokens assert a fresh authentication; a refresh is not one.
        id_token: None,
    })
}

async fn device_code_grant(
    pool: &PgPool,
    jwt: &JwtKeys,
    client: &dboauth::OAuthClient,
    req: &TokenRequest,
) -> Result<TokenResponse, OAuthError> {
    if !client.allows_grant("device_code") && !client.allows_grant(DEVICE_CODE_GRANT) {
        return Err(OAuthError::unsupported_grant_type(
            "this client may not use the device grant",
        ));
    }

    let device_code = req
        .device_code
        .as_deref()
        .ok_or_else(|| OAuthError::invalid_request("device_code is required"))?;

    match dboauth::poll_device_code(pool, device_code)
        .await
        .map_err(|_| OAuthError::invalid_grant("device authorization failed"))?
    {
        dboauth::DevicePollOutcome::Pending => Err(OAuthError::authorization_pending()),
        dboauth::DevicePollOutcome::SlowDown => Err(OAuthError::slow_down()),
        dboauth::DevicePollOutcome::Denied => {
            Err(OAuthError::access_denied("the user declined this request"))
        }
        dboauth::DevicePollOutcome::Invalid => Err(OAuthError::expired_token()),
        dboauth::DevicePollOutcome::Approved { account_id, scopes } => {
            issue_tokens(pool, jwt, client, account_id, &scopes, None).await
        }
    }
}

/// Mint the access/refresh/id triple for a freshly authorized client.
///
/// The refresh token rides the existing first-party rotation machinery
/// (`db::auth::rotate_refresh`, with reuse detection and family revocation) by
/// creating a `devices` row that is tagged with this client. That tag is what
/// makes the token recognizable as third-party at refresh time.
async fn issue_tokens(
    pool: &PgPool,
    jwt: &JwtKeys,
    client: &dboauth::OAuthClient,
    account_id: uuid::Uuid,
    scopes: &str,
    nonce: Option<&str>,
) -> Result<TokenResponse, OAuthError> {
    let account = dbauth::get_account(pool, account_id)
        .await
        .map_err(|_| OAuthError::invalid_grant("account lookup failed"))?
        .ok_or_else(|| OAuthError::invalid_grant("account no longer exists"))?;

    let device_id = dboauth::create_client_device(pool, account_id, &client.client_id, &client.name)
        .await
        .map_err(|_| OAuthError::invalid_grant("could not register the client install"))?;

    let refresh = dbauth::issue_initial_refresh(pool, device_id, account_id, scopes)
        .await
        .map_err(|_| OAuthError::invalid_grant("could not issue a refresh token"))?;

    let access = jwt
        .mint_access_for_client(
            account.id,
            AUD_SOCIAL,
            scopes,
            &account.primary_callsign,
            Some(&client.client_id),
        )
        .map_err(|_| OAuthError::invalid_grant("token minting failed"))?;

    // `openid` is what turns an OAuth authorization into an OIDC login.
    let id_token = if scopes.split_whitespace().any(|s| s == "openid") {
        let email = if scopes.split_whitespace().any(|s| s == "email") {
            dboauth::account_email(pool, account_id).await.ok().flatten()
        } else {
            None
        };
        Some(
            jwt.mint_id_token(IdTokenRequest {
                account_id: account.id,
                client_id: &client.client_id,
                primary_callsign: &account.primary_callsign,
                email: email.as_deref(),
                nonce,
                auth_time: chrono::Utc::now().timestamp(),
                access_token: &access,
            })
            .map_err(|_| OAuthError::invalid_grant("id_token minting failed"))?,
        )
    } else {
        None
    };

    Ok(TokenResponse {
        access_token: access,
        token_type: "Bearer",
        expires_in: ACCESS_TTL_SECS,
        refresh_token: refresh.token,
        scope: scopes.to_string(),
        id_token,
    })
}

// ---- device authorization (RFC 8628) ---------------------------------------

#[derive(Debug, Deserialize)]
pub struct DeviceCodeRequest {
    #[serde(default)]
    pub client_id: Option<String>,
    #[serde(default)]
    pub client_secret: Option<String>,
    #[serde(default)]
    pub scope: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct DeviceCodeResponse {
    pub device_code: String,
    pub user_code: String,
    pub verification_uri: String,
    /// Same page with the code pre-filled, for clients that can render a QR.
    pub verification_uri_complete: String,
    pub expires_in: i64,
    pub interval: i32,
}

/// `POST /v1/oauth/device/code` — start a device authorization.
pub async fn device_code(
    State(pool): State<PgPool>,
    Extension(settings): Extension<Arc<AuthSettings>>,
    headers: HeaderMap,
    Form(req): Form<DeviceCodeRequest>,
) -> Result<Response, OAuthError> {
    let client = authenticate_client(
        &pool,
        &headers,
        PresentedCredentials {
            client_id: req.client_id.as_deref(),
            client_secret: req.client_secret.as_deref(),
        },
    )
    .await?;

    if !client.allows_grant("device_code") && !client.allows_grant(DEVICE_CODE_GRANT) {
        return Err(OAuthError::unsupported_grant_type(
            "this client may not use the device grant",
        ));
    }

    let requested = scope_map::sanitize(req.scope.as_deref().unwrap_or("openid"));
    let scopes = client.clamp_scopes(&requested);
    if scopes.is_empty() {
        return Err(OAuthError::invalid_scope("no valid scopes requested"));
    }

    let issued = dboauth::create_device_code(&pool, &client.client_id, &scopes.join(" "))
        .await
        .map_err(|_| OAuthError::invalid_request("could not start device authorization"))?;

    let base = settings.base_url.trim_end_matches('/');
    let verification_uri = format!("{base}/v1/oauth/device");
    let verification_uri_complete =
        format!("{verification_uri}?user_code={}", urlencode(&issued.user_code));

    Ok((
        StatusCode::OK,
        [(header::CACHE_CONTROL, "no-store")],
        axum::Json(DeviceCodeResponse {
            device_code: issued.device_code,
            user_code: issued.user_code,
            verification_uri,
            verification_uri_complete,
            expires_in: issued.expires_in,
            interval: issued.interval,
        }),
    )
        .into_response())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceDecisionRequest {
    pub user_code: String,
    pub approve: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceDecisionResponse {
    pub approved: bool,
    pub client_name: String,
}

/// `POST /v1/oauth/device/decision` — record the user's decision for a device
/// authorization. Requires a first-party bearer token.
pub async fn device_decision(
    State(pool): State<PgPool>,
    Extension(ctx): Extension<AuthContext>,
    axum::Json(req): axum::Json<DeviceDecisionRequest>,
) -> Result<axum::Json<DeviceDecisionResponse>, OAuthError> {
    let account_id = ctx
        .account_id
        .ok_or_else(|| OAuthError::access_denied("an account-backed session is required"))?;

    let pending = dboauth::find_device_code_by_user_code(&pool, &req.user_code)
        .await
        .map_err(|_| OAuthError::invalid_request("lookup failed"))?
        .ok_or_else(|| OAuthError::invalid_grant("unknown or expired code"))?;

    if pending.approved_at.is_some() || pending.denied_at.is_some() {
        return Err(OAuthError::invalid_grant("this code was already used"));
    }

    let client = dboauth::get_active_client(&pool, &pending.client_id)
        .await
        .map_err(|_| OAuthError::invalid_client("unknown or suspended client"))?;

    // Re-clamp at decision time: the client's ceiling may have been tightened
    // since the device code was issued.
    let scopes = client
        .clamp_scopes(&scope_map::sanitize(&pending.scopes))
        .join(" ");
    if req.approve && scopes.is_empty() {
        return Err(OAuthError::invalid_scope("no grantable scopes remain"));
    }

    let updated = dboauth::decide_device_code(
        &pool,
        &req.user_code,
        account_id,
        req.approve,
        &scopes,
    )
    .await
    .map_err(|_| OAuthError::invalid_request("could not record the decision"))?;

    if !updated {
        return Err(OAuthError::invalid_grant("unknown or expired code"));
    }

    if req.approve {
        dboauth::upsert_grant(&pool, account_id, &client.client_id, &scopes)
            .await
            .map_err(|_| OAuthError::invalid_request("could not record consent"))?;
    }

    Ok(axum::Json(DeviceDecisionResponse {
        approved: req.approve,
        client_name: client.name,
    }))
}

// ---- userinfo --------------------------------------------------------------

#[derive(Debug, Serialize)]
pub struct UserInfo {
    pub sub: uuid::Uuid,
    pub callsign: String,
    pub preferred_username: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub email_verified: Option<bool>,
}

/// `GET /v1/oauth/userinfo` — OIDC UserInfo.
///
/// The one third-party-reachable identity endpoint (`openid` scope). `email` is
/// included only when that scope was granted too.
pub async fn userinfo(
    State(pool): State<PgPool>,
    Extension(ctx): Extension<AuthContext>,
) -> Result<axum::Json<UserInfo>, AppError> {
    let account_id = ctx.account_id.ok_or(AppError::AccountRequired)?;
    let account = dbauth::get_account(&pool, account_id)
        .await?
        .ok_or(AppError::InvalidToken)?;

    let email = if ctx.scopes.iter().any(|s| s == "email") {
        dboauth::account_email(&pool, account_id).await.ok().flatten()
    } else {
        None
    };

    Ok(axum::Json(UserInfo {
        sub: account.id,
        callsign: account.primary_callsign.clone(),
        preferred_username: account.primary_callsign,
        email_verified: email.as_ref().map(|_| true),
        email,
    }))
}

// ---- revocation (RFC 7009) -------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct RevokeRequest {
    pub token: String,
    #[serde(default)]
    pub client_id: Option<String>,
    #[serde(default)]
    pub client_secret: Option<String>,
}

/// `POST /v1/oauth/revoke` — revoke a refresh token.
///
/// RFC 7009 §2.2 requires 200 even for an unknown token, so a caller cannot use
/// this endpoint to probe which tokens exist.
pub async fn revoke(
    State(pool): State<PgPool>,
    headers: HeaderMap,
    Form(req): Form<RevokeRequest>,
) -> Result<Response, OAuthError> {
    let client = authenticate_client(
        &pool,
        &headers,
        PresentedCredentials {
            client_id: req.client_id.as_deref(),
            client_secret: req.client_secret.as_deref(),
        },
    )
    .await?;

    // Only revoke a token that belongs to the calling client.
    if let Ok(Some(owner)) = dboauth::client_id_for_refresh(&pool, &req.token).await {
        if owner == client.client_id {
            let _ = dboauth::revoke_refresh_for_client(&pool, &req.token).await;
        }
    }

    Ok(StatusCode::OK.into_response())
}

// ---- connected apps (first-party account management) -----------------------

/// `GET /v1/oauth/grants` — the account's connected applications.
pub async fn list_grants(
    State(pool): State<PgPool>,
    Extension(ctx): Extension<AuthContext>,
) -> Result<axum::Json<DataResponse<Vec<dboauth::GrantSummary>>>, AppError> {
    let account_id = ctx.account_id.ok_or(AppError::AccountRequired)?;
    let grants = dboauth::list_grants(&pool, account_id).await?;
    Ok(axum::Json(DataResponse { data: grants }))
}

/// `DELETE /v1/oauth/grants/:client_id` — disconnect an application.
///
/// Drops the client's refresh tokens immediately. Access tokens it already holds
/// remain valid for up to [`ACCESS_TTL_SECS`]; that is the cost of stateless
/// verification, and `revoked_jti` is the lever for the cases that cannot wait.
pub async fn revoke_grant(
    State(pool): State<PgPool>,
    Extension(ctx): Extension<AuthContext>,
    Path(client_id): Path<String>,
) -> Result<StatusCode, AppError> {
    let account_id = ctx.account_id.ok_or(AppError::AccountRequired)?;
    let removed = dboauth::revoke_grant(&pool, account_id, &client_id).await?;
    if removed {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::Forbidden)
    }
}

// ---- admin: curated client registration ------------------------------------

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateClientRequest {
    pub client_id: String,
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub homepage_url: Option<String>,
    #[serde(default)]
    pub redirect_uris: Vec<String>,
    #[serde(default)]
    pub scopes: Option<String>,
    #[serde(default)]
    pub grant_types: Option<String>,
    /// `true` issues a client secret (server-side apps); `false` registers a
    /// public client that must rely on PKCE (native apps, SPAs, CLIs).
    #[serde(default)]
    pub confidential: bool,
    #[serde(default)]
    pub created_by: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateClientResponse {
    pub client_id: String,
    pub name: String,
    pub scopes: String,
    pub grant_types: String,
    pub redirect_uris: Vec<String>,
    /// Returned exactly once — only the hash is stored.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_secret: Option<String>,
}

/// `POST /v1/admin/oauth/clients` — register a client.
///
/// Curated by design: there is no self-serve portal and no RFC 7591 dynamic
/// registration. The consent screen's only real protection is that a human
/// approved the name shown on it.
pub async fn create_client(
    State(pool): State<PgPool>,
    axum::Json(req): axum::Json<CreateClientRequest>,
) -> Result<(StatusCode, axum::Json<CreateClientResponse>), AppError> {
    if req.client_id.trim().is_empty() || req.name.trim().is_empty() {
        return Err(AppError::Validation {
            message: "clientId and name are required".into(),
        });
    }

    let scopes = scope_map::sanitize(req.scopes.as_deref().unwrap_or("openid profile"));
    if scopes.is_empty() {
        return Err(AppError::Validation {
            message: format!("no known scopes requested; valid: {:?}", scope_map::ALL_SCOPES),
        });
    }

    // A redirect-based client with no registered redirect can never complete a
    // flow; catching it here beats debugging it later.
    let grant_types = req
        .grant_types
        .clone()
        .unwrap_or_else(|| "authorization_code refresh_token".to_string());
    if grant_types.split_whitespace().any(|g| g == "authorization_code")
        && req.redirect_uris.is_empty()
    {
        return Err(AppError::Validation {
            message: "authorization_code clients need at least one redirectUri".into(),
        });
    }

    let (client, secret) = dboauth::create_client(
        &pool,
        dboauth::NewClient {
            client_id: req.client_id.trim(),
            name: req.name.trim(),
            description: req.description.as_deref(),
            homepage_url: req.homepage_url.as_deref(),
            redirect_uris: &req.redirect_uris,
            allowed_scopes: &scopes.join(" "),
            grant_types: &grant_types,
            created_by: req.created_by.as_deref(),
        },
        req.confidential,
    )
    .await?;

    Ok((
        StatusCode::CREATED,
        axum::Json(CreateClientResponse {
            client_id: client.client_id,
            name: client.name,
            scopes: client.allowed_scopes,
            grant_types: client.grant_types,
            redirect_uris: client.redirect_uris,
            client_secret: secret,
        }),
    ))
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdminClientSummary {
    pub client_id: String,
    pub name: String,
    pub description: Option<String>,
    pub redirect_uris: Vec<String>,
    pub scopes: String,
    pub grant_types: String,
    pub status: String,
    pub confidential: bool,
}

/// `GET /v1/admin/oauth/clients` — list registered clients.
pub async fn list_clients(
    State(pool): State<PgPool>,
) -> Result<axum::Json<DataResponse<Vec<AdminClientSummary>>>, AppError> {
    let clients = dboauth::list_clients(&pool)
        .await?
        .into_iter()
        .map(|c| AdminClientSummary {
            confidential: !c.is_public(),
            client_id: c.client_id,
            name: c.name,
            description: c.description,
            redirect_uris: c.redirect_uris,
            scopes: c.allowed_scopes,
            grant_types: c.grant_types,
            status: c.status,
        })
        .collect();
    Ok(axum::Json(DataResponse { data: clients }))
}

/// `DELETE /v1/admin/oauth/clients/:client_id` — suspend a client.
pub async fn suspend_client(
    State(pool): State<PgPool>,
    Path(client_id): Path<String>,
) -> Result<StatusCode, AppError> {
    if dboauth::suspend_client(&pool, &client_id).await? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::Validation {
            message: "unknown client".into(),
        })
    }
}

// ---- shared query type for the HTML pages ----------------------------------

/// Query params for the consent page. Everything is optional so a malformed link
/// renders a readable error instead of a 400 with no explanation.
#[derive(Debug, Deserialize)]
pub struct ConsentPageQuery {
    #[serde(default)]
    pub client_id: Option<String>,
    #[serde(default)]
    pub redirect_uri: Option<String>,
    #[serde(default)]
    pub response_type: Option<String>,
    #[serde(default)]
    pub scope: Option<String>,
    #[serde(default)]
    pub state: Option<String>,
    #[serde(default)]
    pub code_challenge: Option<String>,
    #[serde(default)]
    pub code_challenge_method: Option<String>,
    #[serde(default)]
    pub nonce: Option<String>,
}

/// `GET /v1/oauth/authorize` — the consent screen.
pub async fn authorize_page(
    State(pool): State<PgPool>,
    Query(query): Query<ConsentPageQuery>,
) -> Response {
    super::oauth_pages::render_authorize(&pool, query).await
}

#[derive(Debug, Deserialize)]
pub struct DevicePageQuery {
    #[serde(default)]
    pub user_code: Option<String>,
}

/// `GET /v1/oauth/device` — the device-grant verification screen.
pub async fn device_page(Query(query): Query<DevicePageQuery>) -> Response {
    super::oauth_pages::render_device(query.user_code.as_deref())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pkce_s256_roundtrip_uses_base64url() {
        // Canonical RFC 7636 Appendix B vector.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        let challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
        assert!(verify_pkce(verifier, challenge));
    }

    #[test]
    fn pkce_rejects_wrong_verifier() {
        let challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
        assert!(!verify_pkce(
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            challenge
        ));
    }

    #[test]
    fn pkce_rejects_out_of_range_verifier_lengths() {
        // Too short to carry the required entropy (RFC 7636 §4.1).
        assert!(!verify_pkce("short", "irrelevant"));
        assert!(!verify_pkce(&"a".repeat(129), "irrelevant"));
    }

    #[test]
    fn redirect_preserves_state_and_encodes_values() {
        let url = redirect_url(
            "https://app.example/cb",
            &[("code", "abc/123")],
            Some("st ate&x"),
        );
        assert_eq!(
            url,
            "https://app.example/cb?code=abc%2F123&state=st%20ate%26x"
        );
    }

    #[test]
    fn redirect_appends_to_an_existing_query_string() {
        let url = redirect_url("https://app.example/cb?next=1", &[("code", "z")], None);
        assert_eq!(url, "https://app.example/cb?next=1&code=z");
    }

    #[test]
    fn authorize_rejects_plain_pkce_and_missing_challenge() {
        let base = AuthorizeParams {
            client_id: "c".into(),
            redirect_uri: "https://app.example/cb".into(),
            response_type: "code".into(),
            scope: None,
            state: None,
            code_challenge: "abc".into(),
            code_challenge_method: Some("S256".into()),
            nonce: None,
        };
        let scopes = vec!["openid".to_string()];
        assert_eq!(authorize_redirect_error(&base, &scopes), None);

        let plain = AuthorizeParams {
            code_challenge_method: Some("plain".into()),
            ..base
        };
        assert_eq!(
            authorize_redirect_error(&plain, &scopes),
            Some("invalid_request")
        );

        let missing = AuthorizeParams {
            code_challenge: String::new(),
            ..plain
        };
        assert_eq!(
            authorize_redirect_error(&missing, &scopes),
            Some("invalid_request")
        );
    }

    #[test]
    fn authorize_rejects_non_code_response_type_and_empty_scopes() {
        let params = AuthorizeParams {
            client_id: "c".into(),
            redirect_uri: "https://app.example/cb".into(),
            response_type: "token".into(),
            scope: None,
            state: None,
            code_challenge: "abc".into(),
            code_challenge_method: Some("S256".into()),
            nonce: None,
        };
        assert_eq!(
            authorize_redirect_error(&params, &["openid".to_string()]),
            Some("unsupported_response_type")
        );

        let code_params = AuthorizeParams {
            response_type: "code".into(),
            ..params
        };
        assert_eq!(
            authorize_redirect_error(&code_params, &[]),
            Some("invalid_scope")
        );
    }

    #[test]
    fn basic_auth_parsing() {
        let mut headers = HeaderMap::new();
        let encoded = base64::engine::general_purpose::STANDARD.encode("id:secret");
        headers.insert(
            header::AUTHORIZATION,
            format!("Basic {encoded}").parse().unwrap(),
        );
        assert_eq!(
            parse_basic_auth(&headers),
            Some(("id".to_string(), "secret".to_string()))
        );
    }

    #[test]
    fn basic_auth_ignores_bearer() {
        let mut headers = HeaderMap::new();
        headers.insert(header::AUTHORIZATION, "Bearer abc".parse().unwrap());
        assert_eq!(parse_basic_auth(&headers), None);
    }
}
