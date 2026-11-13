use std::sync::Arc;

use axum::{
    extract::{MatchedPath, Request, State},
    middleware::Next,
    response::Response,
};
use sqlx::{FromRow, PgPool};
use subtle::ConstantTimeEq;

use crate::auth::jwt::{JwtKeys, AUD_SOCIAL};
use crate::auth::revocation::RevocationCache;
use crate::auth::scope_map;
use crate::error::AppError;

#[derive(Debug, Clone)]
pub struct AuthContext {
    pub callsign: String,
    pub participant_id: uuid::Uuid,
    /// Set when the request authenticated via a Phase 5 OAuth access token
    /// (`None` for legacy `fd_` device tokens). Lets handlers that have been
    /// migrated prefer the unified identity while old ones keep using callsign /
    /// participant_id unchanged.
    pub account_id: Option<uuid::Uuid>,
    /// The registered OAuth client acting on the user's behalf, when this is a
    /// third-party token. `None` for first-party app tokens and legacy `fd_`
    /// tokens. Handlers that must never be driven by a third party can assert on
    /// this, but they rarely need to — [`enforce_third_party_scope`] has already
    /// refused anything not in the scope map.
    pub client_id: Option<String>,
    /// Scopes carried by the access token. Empty for legacy `fd_` tokens.
    pub scopes: Vec<String>,
}

/// Default-deny gate for third-party tokens.
///
/// First-party callers (`client_id == None`) pass through untouched — this
/// cannot regress the shipping apps. A third-party token is admitted only when
/// the matched route is listed in [`scope_map::THIRD_PARTY_SCOPES`] AND the
/// token actually carries the required scope.
///
/// `matched_path` is `None` when axum could not resolve a route. That falls
/// closed: no path, no permission.
fn third_party_allowed(
    method: &str,
    matched_path: Option<&str>,
    ctx: &AuthContext,
) -> Result<(), AppError> {
    if ctx.client_id.is_none() {
        return Ok(());
    }

    let required = matched_path
        .and_then(|path| scope_map::required_scope(method, path))
        .ok_or(AppError::Forbidden)?;

    if ctx.scopes.iter().any(|s| s == required) {
        Ok(())
    } else {
        Err(AppError::Forbidden)
    }
}

/// [`third_party_allowed`] against a live request. Split so the policy itself is
/// unit-testable without fabricating an axum `MatchedPath`, which has no public
/// constructor.
fn enforce_third_party_scope(req: &Request, ctx: &AuthContext) -> Result<(), AppError> {
    let matched = req.extensions().get::<MatchedPath>();
    third_party_allowed(
        req.method().as_str(),
        matched.map(|m| m.as_str()),
        ctx,
    )
}

/// Verifier shared by the dual-auth middleware (legacy routes) and the new
/// `/v1/auth/*` routes. Present only when JWT signing keys are configured.
#[derive(Clone)]
pub struct OAuthVerifier {
    pub jwt: Arc<JwtKeys>,
    pub cache: Arc<RevocationCache>,
}

/// State for the social-API auth middleware: the pool plus an optional OAuth
/// verifier. When `oauth` is `None`, only legacy `fd_` tokens are accepted.
#[derive(Clone)]
pub struct ApiAuthState {
    pub pool: PgPool,
    pub oauth: Option<OAuthVerifier>,
}

#[derive(Debug, FromRow)]
struct ParticipantRow {
    id: uuid::Uuid,
    callsign: String,
}

fn bearer(req: &Request) -> Option<String> {
    req.headers()
        .get("authorization")?
        .to_str()
        .ok()?
        .strip_prefix("Bearer ")
        .map(|s| s.to_string())
}

pub async fn optional_auth(
    State(state): State<ApiAuthState>,
    mut req: Request,
    next: Next,
) -> Result<Response, AppError> {
    if let Some(token) = bearer(&req) {
        // Lenient: a bad/expired token on a public route proceeds anonymously
        // (preserves pre-OAuth behavior for these endpoints). A third-party
        // token without permission for this route is treated the same way — the
        // route is public, so it still answers, just not as an authenticated
        // caller. Downgrading rather than 403-ing keeps public routes public.
        if let Ok(Some(ctx)) = authenticate(&state, &token).await {
            if enforce_third_party_scope(&req, &ctx).is_ok() {
                req.extensions_mut().insert(ctx);
            }
        }
    }
    Ok(next.run(req).await)
}

pub async fn require_auth(
    State(state): State<ApiAuthState>,
    mut req: Request,
    next: Next,
) -> Result<Response, AppError> {
    let token = bearer(&req).ok_or(AppError::InvalidToken)?;
    let ctx = authenticate(&state, &token)
        .await?
        .ok_or(AppError::InvalidToken)?;
    enforce_third_party_scope(&req, &ctx)?;
    req.extensions_mut().insert(ctx);
    Ok(next.run(req).await)
}

/// Authenticate a bearer token via either path:
/// 1. **OAuth JWT** (when configured and the token isn't a legacy `fd_`): verify
///    the EdDSA access token, check the revocation cache, then resolve/ensure a
///    `participants` row for the acting callsign so existing callsign- and
///    `participant_id`-keyed handlers keep working unchanged (the transition
///    bridge — analogous to SwiftData-as-replica).
/// 2. **Legacy `fd_` device token**: the original `participants.device_token` lookup.
pub async fn authenticate(
    state: &ApiAuthState,
    token: &str,
) -> Result<Option<AuthContext>, AppError> {
    if let Some(oauth) = &state.oauth {
        if !token.starts_with("fd_") {
            if let Ok(claims) = oauth.jwt.verify_access(token, AUD_SOCIAL, None) {
                if oauth
                    .cache
                    .token_revoked(claims.sub, claims.iat, &claims.jti.to_string())
                {
                    return Ok(None);
                }
                // Resolve the acting callsign from the account, NOT `claims.cs`
                // — the claim is non-authoritative (jwt.rs) and goes stale when
                // the user changes callsign; trusting it here recreated a
                // participants row under the old call. A missing account means
                // the token outlived its identity → reject.
                let Some(acting_callsign) = sqlx::query_scalar::<_, String>(
                    "SELECT primary_callsign FROM accounts WHERE id = $1",
                )
                .bind(claims.sub)
                .fetch_optional(&state.pool)
                .await?
                else {
                    return Ok(None);
                };
                let (participant, _) =
                    crate::db::get_or_create_participant(&state.pool, &acting_callsign, None)
                        .await?;
                let scopes = claims.scopes().map(str::to_string).collect();
                return Ok(Some(AuthContext {
                    callsign: participant.callsign,
                    participant_id: participant.id,
                    account_id: Some(claims.sub),
                    client_id: claims.cid.clone(),
                    scopes,
                }));
            }
            // Not a valid JWT — fall through to the legacy path (handles the
            // case where a non-fd_ legacy token format ever existed).
        }
    }
    legacy_validate(&state.pool, token).await
}

async fn legacy_validate(pool: &PgPool, token: &str) -> Result<Option<AuthContext>, AppError> {
    let participant = sqlx::query_as::<_, ParticipantRow>(
        r#"
        UPDATE participants
        SET last_seen_at = now()
        WHERE device_token = $1
        RETURNING id, callsign
        "#,
    )
    .bind(token)
    .fetch_optional(pool)
    .await?;

    Ok(participant.map(|p| AuthContext {
        callsign: p.callsign,
        participant_id: p.id,
        account_id: None,
        client_id: None,
        scopes: Vec::new(),
    }))
}

pub async fn require_admin(
    State(admin_token): State<String>,
    req: Request,
    next: Next,
) -> Result<Response, AppError> {
    let auth_header = req
        .headers()
        .get("authorization")
        .ok_or(AppError::InvalidToken)?;

    let auth_str = auth_header.to_str().map_err(|_| AppError::InvalidToken)?;

    let token = auth_str
        .strip_prefix("Bearer ")
        .ok_or(AppError::InvalidToken)?;

    // Constant-time comparison so a timing side-channel can't be used to
    // brute-force the admin token byte-by-byte. CAR-144.
    if token.as_bytes().ct_eq(admin_token.as_bytes()).unwrap_u8() != 1 {
        return Err(AppError::InvalidToken);
    }

    Ok(next.run(req).await)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx(client_id: Option<&str>, scopes: &[&str]) -> AuthContext {
        AuthContext {
            callsign: "W6JY".into(),
            participant_id: uuid::Uuid::nil(),
            account_id: Some(uuid::Uuid::nil()),
            client_id: client_id.map(str::to_string),
            scopes: scopes.iter().map(|s| s.to_string()).collect(),
        }
    }

    /// The invariant that keeps the shipping apps working: a token with no
    /// `cid` is never gated, on any route, regardless of scopes.
    #[test]
    fn first_party_tokens_are_never_gated() {
        let first_party = ctx(None, &[]);
        assert!(third_party_allowed("GET", Some("/v1/friends"), &first_party).is_ok());
        assert!(third_party_allowed("POST", Some("/v1/clubs"), &first_party).is_ok());
        assert!(third_party_allowed("GET", None, &first_party).is_ok());
    }

    /// The reason the scope map is a map and not per-route annotations: a route
    /// nobody classified must deny, not default to allow.
    #[test]
    fn third_party_denied_on_unlisted_routes() {
        let third = ctx(Some("app"), &["sync:read", "social:read"]);
        assert!(third_party_allowed("GET", Some("/v1/friends"), &third).is_err());
        assert!(third_party_allowed("GET", Some("/v1/feed"), &third).is_err());
        assert!(third_party_allowed("POST", Some("/v1/clubs"), &third).is_err());
    }

    #[test]
    fn third_party_allowed_on_listed_route_with_scope() {
        let third = ctx(Some("app"), &["sync:read"]);
        assert!(third_party_allowed("GET", Some("/v1/sync/bootstrap"), &third).is_ok());
    }

    #[test]
    fn third_party_denied_without_the_required_scope() {
        // Read-only client cannot push, even though the route is listed.
        let reader = ctx(Some("app"), &["sync:read"]);
        assert!(third_party_allowed("POST", Some("/v1/sync/push"), &reader).is_err());
    }

    /// A route is gated per method: read access must not imply write access
    /// just because the paths happen to collide.
    #[test]
    fn method_is_part_of_the_key() {
        let reader = ctx(Some("app"), &["sync:read"]);
        assert!(third_party_allowed("GET", Some("/v1/sync/key"), &reader).is_ok());
        assert!(third_party_allowed("PUT", Some("/v1/sync/key"), &reader).is_err());
    }

    /// If routing produced no matched path there is nothing to authorize
    /// against, so the request must fail rather than fall through.
    #[test]
    fn missing_matched_path_denies_third_parties() {
        let third = ctx(Some("app"), &["sync:read"]);
        assert!(third_party_allowed("GET", None, &third).is_err());
    }

    /// Scope strings are compared exactly — no prefix or wildcard semantics that
    /// would let `sync:readonly` or `sync:` satisfy `sync:read`.
    #[test]
    fn scope_matching_is_exact() {
        let odd = ctx(Some("app"), &["sync:read:extra", "sync:"]);
        assert!(third_party_allowed("GET", Some("/v1/sync/bootstrap"), &odd).is_err());
    }
}
