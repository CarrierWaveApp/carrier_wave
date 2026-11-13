//! OAuth2 auth endpoints — Phase 5 (`/v1/auth/*`).
//!
//! Magic-link verification (callsign ownership, D6) → account + token issuance
//! (EdDSA access + opaque rotating refresh, D4/D7) → refresh rotation with
//! reuse detection (F4). These are ADDITIVE: existing routes keep the legacy
//! `fd_` middleware until the §13-step-7 swap.
//!
//! Design: docs/plans/2026-06-21-phase5-oauth-overhaul.md (§8).

use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{Html, IntoResponse};
use axum::Extension;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::auth::directory::CallsignDirectory;
use crate::auth::jwt::{JwtKeys, ACCESS_TTL_SECS, AUD_SOCIAL, AUD_SYNC};
use crate::auth::jwt_middleware::JwtAuthContext;
use crate::auth::mailer::Mailer;
use crate::auth::tokens::{generate_poll_token, generate_verification_code};
use crate::db::auth as dbauth;
use crate::error::AppError;
use crate::extractors::Json;

use super::DataResponse;

/// Per-request settings the auth handlers need beyond the pool.
pub struct AuthSettings {
    pub base_url: String,
}

const ALLOWED_SCOPES: &[&str] = &[
    "sync:read",
    "sync:write",
    "social:read",
    "social:write",
    "account",
];

const MAX_CALLSIGN_LEN: usize = 16;
const MAX_EMAIL_LEN: usize = 254;

/// Keep only known scopes; default to the full set for an empty request.
fn sanitize_scopes(requested: Option<&str>) -> String {
    let kept: Vec<&str> = requested
        .unwrap_or("")
        .split_whitespace()
        .filter(|s| ALLOWED_SCOPES.contains(s))
        .collect();
    if kept.is_empty() {
        ALLOWED_SCOPES.join(" ")
    } else {
        kept.join(" ")
    }
}

fn validate_aud(aud: Option<&str>) -> Result<&'static str, AppError> {
    match aud {
        None | Some(AUD_SOCIAL) => Ok(AUD_SOCIAL),
        Some(AUD_SYNC) => Ok(AUD_SYNC),
        Some(_) => Err(AppError::Validation {
            message: "unknown audience".into(),
        }),
    }
}

// ---- verify/start -------------------------------------------------------

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VerifyStartRequest {
    pub callsign: String,
    /// Optional fallback address. Used only when the directory has no on-file
    /// email for the callsign (then the weaker `user_email` tier applies).
    pub email: Option<String>,
    /// PKCE S256 challenge (hex) the app commits to (F8 device binding).
    pub pkce_challenge: String,
}

fn valid_email(email: &str) -> bool {
    !email.is_empty() && email.chars().count() <= MAX_EMAIL_LEN && email.contains('@')
}

/// Shared verify/start logic for onboarding, new-device sign-in, and the authed
/// multi-callsign add flow. Resolves the target address + tier + which account
/// (if any) the verification binds to:
///
/// - **Authed attach** (`account_id` Some): adding a NEW callsign to the bearer's
///   account (D8). Directory-else-user-supplied, bound to that account.
/// - **Sign-in** (unauthed, callsign ALREADY owned by an account): a new device
///   joining the existing account. The link goes to the account's ON-FILE address
///   (directory if resolvable, else the email it verified under) — NEVER a fresh
///   user-supplied one, which would be account takeover. Bound to the owner so
///   `/token` mints a device on it.
/// - **Onboarding** (unauthed, callsign unclaimed): directory-else-user-supplied,
///   no account binding (creates one at `/token`).
///
/// Always best-effort (caller returns 202 regardless, so failures don't leak
/// validity, F7). Directory tier (D6/F1) always wins over a user-supplied address.
#[allow(clippy::too_many_arguments)]
async fn start_verification(
    pool: &PgPool,
    directory: &CallsignDirectory,
    mailer: &Mailer,
    settings: &AuthSettings,
    callsign: &str,
    user_email: Option<&str>,
    pkce_challenge: &str,
    poll_token: &str,
    account_id: Option<uuid::Uuid>,
) -> Result<(), AppError> {
    let callsign = callsign.trim();
    if callsign.is_empty() || callsign.chars().count() > MAX_CALLSIGN_LEN {
        return Err(AppError::Validation {
            message: "valid callsign required".into(),
        });
    }
    if pkce_challenge.len() != 64 || !pkce_challenge.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(AppError::Validation {
            message: "invalid pkceChallenge".into(),
        });
    }

    // A bare verify (no bearer) for a callsign that already belongs to an account
    // isn't onboarding — it's signing a new device into that account.
    let existing = if account_id.is_none() {
        dbauth::find_account_for_callsign(pool, callsign).await?
    } else {
        None
    };

    // Prefer the directory (stronger tier). A resolver error degrades to None.
    let directory_email = directory.resolve_email(callsign).await.unwrap_or(None);

    let (email, method, bind_account) = if let Some(existing) = existing {
        // Sign-in: address the account's ON-FILE email only (directory-else-stored).
        match directory_email {
            Some(dir) => (dir, dbauth::METHOD_DIRECTORY.to_string(), Some(existing.account_id)),
            None => match existing.verified_email {
                Some(stored) => (stored, existing.method, Some(existing.account_id)),
                // No deliverable address on file — 202 anyway (no leak).
                None => return Ok(()),
            },
        }
    } else {
        // Onboarding (no account) or authed attach (bind to the bearer's account).
        match directory_email {
            Some(dir) => (dir, dbauth::METHOD_DIRECTORY.to_string(), account_id),
            None => match user_email.map(str::trim).filter(|e| valid_email(e)) {
                Some(user) => (user.to_string(), dbauth::METHOD_USER.to_string(), account_id),
                // Nothing deliverable — return Ok so the caller still 202s (no leak).
                None => return Ok(()),
            },
        }
    };

    let code = generate_verification_code();
    dbauth::create_email_verification(
        pool,
        callsign,
        &email,
        &code,
        &method,
        bind_account,
        pkce_challenge,
        poll_token,
        None,
    )
    .await?;

    let link = format!("{}/v1/auth/verify/complete?code={}", settings.base_url, code);
    if let Err(e) = mailer.send_magic_link(&email, &link).await {
        tracing::warn!("magic link send failed: {e}");
    }
    Ok(())
}

/// Returned by both verify/start flows: the opaque poll token the app presents
/// to verify/poll (O4). Always returned — even when nothing was deliverable — so
/// its presence never reveals whether the callsign resolved (F7).
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VerifyStartResponse {
    pub poll_token: String,
}

/// POST /v1/auth/verify/start — onboarding magic link. Always 202 with a poll
/// token (no callsign/account enumeration, F7).
pub async fn verify_start(
    State(pool): State<PgPool>,
    Extension(mailer): Extension<Arc<Mailer>>,
    Extension(settings): Extension<Arc<AuthSettings>>,
    Extension(directory): Extension<Arc<CallsignDirectory>>,
    Json(req): Json<VerifyStartRequest>,
) -> Result<(StatusCode, Json<VerifyStartResponse>), AppError> {
    let poll_token = generate_poll_token();
    start_verification(
        &pool,
        &directory,
        &mailer,
        &settings,
        &req.callsign,
        req.email.as_deref(),
        &req.pkce_challenge,
        &poll_token,
        None,
    )
    .await?;
    Ok((StatusCode::ACCEPTED, Json(VerifyStartResponse { poll_token })))
}

// ---- verify/complete ----------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct VerifyCompleteQuery {
    pub code: String,
}

/// GET /v1/auth/verify/complete?code=... — the link target. Marks the code
/// clicked (single-use), then renders a STATIC page (no user content) with
/// `Referrer-Policy: no-referrer` + a strict CSP so the code can't leak via
/// referrer/XSS (F8/F9). The code is not yet a credential — the app must still
/// present the PKCE verifier to /token.
pub async fn verify_complete(
    State(pool): State<PgPool>,
    Query(query): Query<VerifyCompleteQuery>,
) -> impl IntoResponse {
    let ok = dbauth::mark_verification_clicked(&pool, &query.code)
        .await
        .unwrap_or(false);
    (
        [
            ("referrer-policy", "no-referrer"),
            ("content-security-policy", "default-src 'none'; style-src 'unsafe-inline'; img-src data:"),
            ("cache-control", "no-store"),
        ],
        Html(render_verify_page(ok)),
    )
}

/// Carrier Wave brand chrome for the verify landing page. Deliberately
/// self-contained — inline `<style>` + inline SVG only, no external fetches —
/// so it renders under the strict `default-src 'none'` CSP above.
const VERIFY_STYLE: &str = "\
:root{--cw-orange:#a855f7;--cw-orange-bright:#c084fc;--cw-cyan:#67e8f9;\
--cw-bg-1:#070b14;--cw-bg-2:#0f1729;--cw-text:#f8fafc;\
--cw-muted:rgba(148,163,184,.78);--cw-faint:rgba(148,163,184,.45);\
--cw-card-border:rgba(168,85,247,.20);\
--cw-card-shadow:0 30px 60px rgba(0,0,0,.55),0 0 0 1px rgba(168,85,247,.10)}\
*{margin:0;padding:0;box-sizing:border-box}\
html,body{height:100%}\
body{font-family:-apple-system,BlinkMacSystemFont,\"Segoe UI\",Roboto,Helvetica,Arial,sans-serif;\
background:radial-gradient(1200px 600px at 20% -10%,rgba(168,85,247,.20),transparent 70%),\
radial-gradient(900px 600px at 90% 10%,rgba(103,232,249,.10),transparent 65%),\
linear-gradient(180deg,var(--cw-bg-1) 0%,var(--cw-bg-2) 50%,var(--cw-bg-1) 100%);\
color:var(--cw-text);min-height:100vh;display:flex;flex-direction:column;\
align-items:center;justify-content:center;padding:2rem 1.25rem}\
.brand-bar{display:flex;align-items:center;gap:.65rem;margin-bottom:1.5rem;\
letter-spacing:.32em;text-transform:uppercase;font-size:.78rem;font-weight:700;\
color:rgba(241,245,249,.85)}\
.brand-bar img{width:34px;height:34px;border-radius:8px;flex:0 0 auto;\
box-shadow:0 4px 14px rgba(168,85,247,.35)}\
.brand-bar b{color:var(--cw-orange);font-weight:800}\
.card{width:100%;max-width:460px;background:linear-gradient(160deg,#0c1426,#16213a);\
border:1px solid var(--cw-card-border);border-radius:1.5rem;\
padding:2.25rem 1.85rem 2rem;box-shadow:var(--cw-card-shadow);\
position:relative;overflow:hidden;text-align:center}\
.card::before{content:\"\";position:absolute;left:0;right:0;top:0;height:3px;\
background:linear-gradient(90deg,transparent,var(--cw-orange) 30%,var(--cw-orange-bright) 70%,transparent);\
opacity:.85}\
.status{width:64px;height:64px;margin:0 auto 1.1rem;display:block}\
.status circle{stroke-width:3}\
.status path{stroke-width:4;stroke-linecap:round;stroke-linejoin:round}\
.status.ok circle{fill:rgba(103,232,249,.12);stroke:var(--cw-cyan)}\
.status.ok path{stroke:var(--cw-cyan)}\
.status.err circle{fill:rgba(248,113,113,.12);stroke:#f87171}\
.status.err path{stroke:#f87171}\
.kicker{font-size:.72rem;font-weight:700;letter-spacing:.42em;text-transform:uppercase;\
color:var(--cw-faint);margin-bottom:.75rem}\
.headline{font-size:clamp(1.6rem,5vw,2rem);font-weight:800;letter-spacing:.01em;\
margin-bottom:.6rem}\
.message{font-size:1rem;line-height:1.55;color:var(--cw-muted);max-width:34ch;margin:0 auto}\
.foot{text-align:center;color:var(--cw-faint);font-size:.72rem;letter-spacing:.18em;\
text-transform:uppercase;margin-top:1.5rem}\
.foot b{color:var(--cw-orange);font-weight:700}";

/// The real Carrier Wave app icon (base64 PNG), inlined as a `data:` URI so the
/// page stays self-contained under the strict CSP. Source of truth is the iOS
/// asset `swift/ios/CarrierWave/Assets.xcassets/AppIcon.appiconset/AppIcon.png`,
/// downscaled to 120px; regenerate with `sips -Z 120 … | base64` if it changes.
const VERIFY_ICON_B64: &str = include_str!("app_icon.b64");

fn render_verify_page(ok: bool) -> String {
    let logo = format!(
        "<img src=\"data:image/png;base64,{}\" alt=\"Carrier Wave\" width=\"34\" height=\"34\">",
        VERIFY_ICON_B64.trim_end()
    );
    let (kicker, headline, message, status) = if ok {
        (
            "Account · Verified",
            "Callsign verified",
            "Return to the Carrier Wave app to finish signing in.",
            "<svg class=\"status ok\" viewBox=\"0 0 64 64\" fill=\"none\" aria-hidden=\"true\">\
             <circle cx=\"32\" cy=\"32\" r=\"26\"/>\
             <path d=\"M21 33l7.5 7.5L43 25\"/></svg>",
        )
    } else {
        (
            "Account · Link expired",
            "Link expired",
            "This verification link is invalid or has expired. Request a new one in the app.",
            "<svg class=\"status err\" viewBox=\"0 0 64 64\" fill=\"none\" aria-hidden=\"true\">\
             <circle cx=\"32\" cy=\"32\" r=\"26\"/>\
             <path d=\"M32 19v18\"/><path d=\"M32 45v.5\"/></svg>",
        )
    };

    format!(
        "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">\
         <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\
         <title>Carrier Wave</title><style>{VERIFY_STYLE}</style></head><body>\
         <div class=\"brand-bar\">{logo}<span><b>Carrier Wave</b></span></div>\
         <div class=\"card\"><div class=\"kicker\">{kicker}</div>{status}\
         <div class=\"headline\">{headline}</div>\
         <p class=\"message\">{message}</p></div>\
         <div class=\"foot\"><b>Carrier Wave</b> &middot; ham radio, signal first</div>\
         </body></html>"
    )
}

// ---- JWKS ----------------------------------------------------------------

/// GET /.well-known/jwks.json — the published EdDSA public key set. Lets any
/// verifier (the future `cw-sync` service) validate access tokens by `kid`
/// without sharing a secret. Cacheable; rotates only when the signing key does.
pub async fn jwks(Extension(jwt): Extension<Arc<JwtKeys>>) -> impl IntoResponse {
    (
        [
            ("content-type", "application/json"),
            ("cache-control", "public, max-age=3600"),
        ],
        jwt.jwks().to_string(),
    )
}

// ---- token (issue) ------------------------------------------------------

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IssueTokenRequest {
    pub code: String,
    pub pkce_verifier: String,
    pub device_name: Option<String>,
    pub platform: Option<String>,
    pub scopes: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TokenResponse {
    pub access: String,
    pub refresh: String,
    pub expires_in: i64,
    pub account_id: uuid::Uuid,
}

/// Register a new device on `account` and mint its first refresh family + access
/// token → 201 with the pair. Shared by onboarding and new-device sign-in.
async fn issue_device_tokens(
    pool: &PgPool,
    jwt: &JwtKeys,
    account: &dbauth::Account,
    device_name: Option<&str>,
    platform: Option<&str>,
    scopes: Option<&str>,
) -> Result<axum::response::Response, AppError> {
    let device = dbauth::create_device(pool, account.id, device_name, platform).await?;
    let scopes = sanitize_scopes(scopes);
    let refresh = dbauth::issue_initial_refresh(pool, device.id, account.id, &scopes).await?;
    let access = jwt.mint_access(account.id, AUD_SOCIAL, &scopes, &account.primary_callsign)?;

    Ok((
        StatusCode::CREATED,
        Json(TokenResponse {
            access,
            refresh: refresh.token,
            expires_in: ACCESS_TTL_SECS,
            account_id: account.id,
        }),
    )
        .into_response())
}

/// Issue tokens from a proven verification claim. Shared by `/token` (code from
/// the universal-link return) and `/verify/poll` (poll-token return) so both O4
/// paths mint identically. Three outcomes by what the verification was bound to:
///
/// - **Sign-in** (bound account already owns the callsign): a new device joins
///   the existing account — mint a fresh device + token pair (201). This is the
///   multi-device path: every device gets its own refresh family.
/// - **Attach** (bound account, callsign NOT yet owned): D8 multi-callsign add on
///   an already-authed device — record the callsign, no new tokens (204).
/// - **Onboarding** (no bound account): create the account, then mint (201).
async fn issue_from_claim(
    pool: &PgPool,
    jwt: &JwtKeys,
    claim: dbauth::VerificationClaim,
    device_name: Option<&str>,
    platform: Option<&str>,
    scopes: Option<&str>,
) -> Result<axum::response::Response, AppError> {
    if let Some(account_id) = claim.account_id {
        // Already owns the callsign → new-device sign-in (mint a device + tokens).
        if dbauth::account_callsign_method(pool, account_id, &claim.callsign)
            .await?
            .is_some()
        {
            let account = dbauth::get_account(pool, account_id)
                .await?
                .ok_or(AppError::InvalidToken)?;
            return issue_device_tokens(pool, jwt, &account, device_name, platform, scopes).await;
        }
        // Attach flow (D8): the new callsign joins an existing account; no tokens.
        dbauth::attach_callsign(pool, account_id, &claim.callsign, &claim.method, Some(&claim.email))
            .await?;
        return Ok(StatusCode::NO_CONTENT.into_response());
    }

    // Onboarding: new account + device + refresh family + access token.
    let account =
        dbauth::create_account_with_callsign(pool, &claim.callsign, &claim.method, Some(&claim.email))
            .await?;
    issue_device_tokens(pool, jwt, &account, device_name, platform, scopes).await
}

/// POST /v1/auth/token — exchange a clicked verification (+ PKCE verifier) for
/// tokens. The universal-link return path: the app received the `code` from the
/// emailed link. Attach-to-existing-account (D8) returns 204; onboarding returns
/// 201 with the token pair.
pub async fn issue_token(
    State(pool): State<PgPool>,
    Extension(jwt): Extension<Arc<JwtKeys>>,
    Json(req): Json<IssueTokenRequest>,
) -> Result<axum::response::Response, AppError> {
    let claim = dbauth::exchange_verification(&pool, &req.code, &req.pkce_verifier)
        .await?
        .ok_or(AppError::InvalidToken)?;
    issue_from_claim(
        &pool,
        &jwt,
        claim,
        req.device_name.as_deref(),
        req.platform.as_deref(),
        req.scopes.as_deref(),
    )
    .await
}

// ---- verify/poll --------------------------------------------------------

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VerifyPollRequest {
    pub poll_token: String,
    pub pkce_verifier: String,
    pub device_name: Option<String>,
    pub platform: Option<String>,
    pub scopes: Option<String>,
}

/// POST /v1/auth/verify/poll — the polling return path (O4). The app, which
/// never sees the emailed link, presents the poll token from verify/start plus
/// its PKCE verifier. While the link is unclicked (or the token is unknown), this
/// returns 202 and the app keeps polling; once clicked it mints exactly like
/// `/token` — 201 with tokens (onboarding) or 204 (D8 attach).
pub async fn verify_poll(
    State(pool): State<PgPool>,
    Extension(jwt): Extension<Arc<JwtKeys>>,
    Json(req): Json<VerifyPollRequest>,
) -> Result<axum::response::Response, AppError> {
    match dbauth::poll_verification(&pool, &req.poll_token, &req.pkce_verifier).await? {
        dbauth::PollResult::Pending => Ok(StatusCode::ACCEPTED.into_response()),
        dbauth::PollResult::Claim(claim) => {
            issue_from_claim(
                &pool,
                &jwt,
                claim,
                req.device_name.as_deref(),
                req.platform.as_deref(),
                req.scopes.as_deref(),
            )
            .await
        }
    }
}

// ---- token/refresh ------------------------------------------------------

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RefreshRequest {
    pub refresh: String,
    /// Audience for the minted access token (default `cw-social`).
    pub aud: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RefreshResponse {
    pub access: String,
    pub refresh: String,
    pub expires_in: i64,
}

/// POST /v1/auth/token/refresh — rotate the refresh token and mint a fresh
/// access token for the requested audience. Reuse/invalid → 401 (F4).
///
/// FIRST-PARTY ONLY. Third-party refresh tokens must go to `/v1/oauth/token`,
/// which re-stamps the `cid` claim. Accepting one here would mint a token
/// *without* `cid`, and a token without `cid` bypasses the default-deny scope
/// gate entirely — a third party would escalate itself to full API access
/// simply by refreshing at the wrong endpoint.
pub async fn refresh_token(
    State(pool): State<PgPool>,
    Extension(jwt): Extension<Arc<JwtKeys>>,
    Json(req): Json<RefreshRequest>,
) -> Result<Json<RefreshResponse>, AppError> {
    let aud = validate_aud(req.aud.as_deref())?;

    // Checked before rotating: refusing after would consume the token and leave
    // the client with nothing to retry.
    if crate::db::oauth::client_id_for_refresh(&pool, &req.refresh)
        .await?
        .is_some()
    {
        return Err(AppError::Forbidden);
    }

    match dbauth::rotate_refresh(&pool, &req.refresh).await? {
        dbauth::RotationOutcome::Rotated(issued) => {
            let account = dbauth::get_account(&pool, issued.row.account_id)
                .await?
                .ok_or(AppError::InvalidToken)?;
            let access =
                jwt.mint_access(account.id, aud, &issued.row.scopes, &account.primary_callsign)?;
            Ok(Json(RefreshResponse {
                access,
                refresh: issued.token,
                expires_in: ACCESS_TTL_SECS,
            }))
        }
        dbauth::RotationOutcome::ReuseDetected | dbauth::RotationOutcome::Invalid => {
            Err(AppError::InvalidToken)
        }
    }
}

// ---- logout -------------------------------------------------------------

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogoutRequest {
    /// A live refresh token belonging to the device to log out.
    pub refresh: String,
}

/// POST /v1/auth/logout — revoke the presented refresh token's family (this
/// device). Idempotent: an unknown token still returns 204.
pub async fn logout(
    State(pool): State<PgPool>,
    Json(req): Json<LogoutRequest>,
) -> Result<StatusCode, AppError> {
    use crate::auth::tokens::hash_token;
    let hash = hash_token(&req.refresh);
    if let Some(family_id) = sqlx::query_scalar::<_, uuid::Uuid>(
        "SELECT family_id FROM refresh_tokens WHERE token_hash = $1",
    )
    .bind(&hash)
    .fetch_optional(&pool)
    .await?
    {
        dbauth::revoke_family(&pool, family_id, "logout").await?;
    }
    Ok(StatusCode::NO_CONTENT)
}

// ---- authenticated account management (behind require_jwt_auth) ----------

/// POST /v1/auth/logout/all — revoke every device + bump the account kill epoch
/// so all outstanding access tokens are rejected on next use (D10/F3).
pub async fn logout_all(
    State(pool): State<PgPool>,
    Extension(ctx): Extension<JwtAuthContext>,
) -> Result<StatusCode, AppError> {
    ctx.require_scope("account")?;
    dbauth::revoke_account(&pool, ctx.account_id, "logout_all").await?;
    Ok(StatusCode::NO_CONTENT)
}

/// GET /v1/auth/devices — list the authenticated account's sessions.
pub async fn list_devices(
    State(pool): State<PgPool>,
    Extension(ctx): Extension<JwtAuthContext>,
) -> Result<Json<DataResponse<Vec<dbauth::DeviceSummary>>>, AppError> {
    ctx.require_scope("account")?;
    let devices = dbauth::list_devices(&pool, ctx.account_id).await?;
    Ok(Json(DataResponse { data: devices }))
}

/// DELETE /v1/auth/devices/:id — revoke a specific device (ownership-scoped, F6).
/// Idempotent: returns 204 even if the device was already gone.
pub async fn delete_device(
    State(pool): State<PgPool>,
    Extension(ctx): Extension<JwtAuthContext>,
    Path(device_id): Path<uuid::Uuid>,
) -> Result<StatusCode, AppError> {
    ctx.require_scope("account")?;
    dbauth::revoke_device(&pool, ctx.account_id, device_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// POST /v1/auth/callsigns/verify/start — begin verifying an ADDITIONAL callsign
/// for the authenticated account (D8 multi-callsign). The resulting verification
/// carries this account_id, so /token attaches rather than onboarding.
pub async fn add_callsign_start(
    State(pool): State<PgPool>,
    Extension(ctx): Extension<JwtAuthContext>,
    Extension(mailer): Extension<Arc<Mailer>>,
    Extension(settings): Extension<Arc<AuthSettings>>,
    Extension(directory): Extension<Arc<CallsignDirectory>>,
    Json(req): Json<VerifyStartRequest>,
) -> Result<(StatusCode, Json<VerifyStartResponse>), AppError> {
    ctx.require_scope("account")?;
    let poll_token = generate_poll_token();
    start_verification(
        &pool,
        &directory,
        &mailer,
        &settings,
        &req.callsign,
        req.email.as_deref(),
        &req.pkce_challenge,
        &poll_token,
        Some(ctx.account_id),
    )
    .await?;
    Ok((StatusCode::ACCEPTED, Json(VerifyStartResponse { poll_token })))
}

