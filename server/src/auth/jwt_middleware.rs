//! JWT bearer auth middleware — Phase 5.
//!
//! Guards the new account-management endpoints. ADDITIVE: this does NOT replace
//! the legacy `fd_` `require_auth` middleware on existing routes (that swap is
//! §13 step 7). Verifies an EdDSA access token with no DB hit, then consults the
//! in-process [`RevocationCache`] for emergency revocation (D10/F3).

use std::sync::Arc;

use axum::{
    extract::{MatchedPath, Request, State},
    middleware::Next,
    response::Response,
};
use sqlx::PgPool;

use crate::auth::jwt::{JwtKeys, AUD_SOCIAL};
use crate::auth::revocation::RevocationCache;
use crate::auth::scope_map;
use crate::error::AppError;

/// State for the JWT middleware. Cheap to clone (everything behind Arc/pool).
#[derive(Clone)]
pub struct JwtAuthState {
    pub pool: PgPool,
    pub jwt: Arc<JwtKeys>,
    pub cache: Arc<RevocationCache>,
}

/// Identity established by a verified access token. Authorization decisions use
/// `account_id` + the scope set — never the non-authoritative `cs` claim (F5/F6).
#[derive(Debug, Clone)]
pub struct JwtAuthContext {
    pub account_id: uuid::Uuid,
    pub primary_callsign: String,
    pub scopes: Vec<String>,
    /// Registered OAuth client acting on the user's behalf; `None` when the
    /// user's own app is calling. See [`crate::auth::scope_map`].
    pub client_id: Option<String>,
}

impl JwtAuthContext {
    pub fn has_scope(&self, scope: &str) -> bool {
        self.scopes.iter().any(|s| s == scope)
    }

    /// Enforce a required scope or fail with 403.
    pub fn require_scope(&self, scope: &str) -> Result<(), AppError> {
        if self.has_scope(scope) {
            Ok(())
        } else {
            Err(AppError::Forbidden)
        }
    }
}

/// Require a valid `cw-social`-audience access token. Inserts a [`JwtAuthContext`].
pub async fn require_jwt_auth(
    State(state): State<JwtAuthState>,
    mut req: Request,
    next: Next,
) -> Result<Response, AppError> {
    let token = req
        .headers()
        .get("authorization")
        .and_then(|h| h.to_str().ok())
        .and_then(|s| s.strip_prefix("Bearer "))
        .ok_or(AppError::InvalidToken)?;

    // Epoch revocation is handled by the cache below, so pass None here.
    let claims = state.jwt.verify_access(token, AUD_SOCIAL, None)?;

    if state
        .cache
        .token_revoked(claims.sub, claims.iat, &claims.jti.to_string())
    {
        return Err(AppError::InvalidToken);
    }

    let ctx = JwtAuthContext {
        account_id: claims.sub,
        primary_callsign: claims.cs.clone(),
        scopes: claims.scopes().map(|s| s.to_string()).collect(),
        client_id: claims.cid.clone(),
    };

    // Default-deny for third parties, same policy as the dual-auth middleware.
    // The account-management routes this guards are all first-party-only, so in
    // practice any `cid` token is refused here — but the check goes through the
    // scope map so there is exactly one place that decides.
    if ctx.client_id.is_some() {
        let allowed = req
            .extensions()
            .get::<MatchedPath>()
            .and_then(|m| scope_map::required_scope(req.method().as_str(), m.as_str()))
            .is_some_and(|required| ctx.has_scope(required));
        if !allowed {
            return Err(AppError::Forbidden);
        }
    }

    req.extensions_mut().insert(ctx);
    Ok(next.run(req).await)
}
