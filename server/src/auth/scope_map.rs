//! Which routes a THIRD-PARTY OAuth token may reach, and under what scope.
//!
//! # Default-deny
//!
//! A token minted for a registered OAuth client carries a `cid` claim
//! ([`crate::auth::jwt::Claims::cid`]). Such a token is refused on every route
//! that is not listed in [`THIRD_PARTY_SCOPES`] — the absence of an entry is
//! itself the policy. First-party tokens (no `cid`) are unaffected and keep the
//! full surface they have always had, so this file cannot regress the shipping
//! apps.
//!
//! That inversion is the whole point. Annotating routes individually
//! (`.route_layer(RequireScope(..))`) reads better at the definition site but
//! cannot express default-deny: a route with no annotation runs no check at all,
//! so forgetting one silently exposes it. Here, forgetting one denies it.
//!
//! # Widening the surface
//!
//! Third parties start with the log and identity. To expose more, move a path
//! from [`FIRST_PARTY_ONLY`] into [`THIRD_PARTY_SCOPES`] with a scope, add the
//! scope to [`ALL_SCOPES`], and audit the handler for anything that assumes a
//! first-party caller. [`FIRST_PARTY_ONLY`] is deliberately exhaustive so it
//! doubles as the audit checklist.
//!
//! The `scope_map_covers_every_route` test enforces that every `.route()` in
//! `main.rs` appears in exactly one of the two lists, so a new route cannot be
//! added without someone deciding which side it belongs on.

/// Every scope this server will issue. A client's `allowed_scopes` and a token's
/// granted scopes are both filtered against this, so an unknown scope string can
/// never become an authorization.
pub const ALL_SCOPES: &[&str] = &[
    // OIDC identity.
    "openid",
    "profile",
    "email",
    // The log. `sync:*` rather than `log:*` because that is what the existing
    // token issuance already emits (handlers/auth.rs) and what first-party
    // tokens already carry.
    "sync:read",
    "sync:write",
];

/// Human-readable consent-screen copy, per scope. Anything not described here
/// cannot be consented to, because the user would be approving a bare string.
pub const SCOPE_DESCRIPTIONS: &[(&str, &str)] = &[
    ("openid", "Confirm your Carrier Wave account"),
    ("profile", "See your callsign and public profile"),
    ("email", "See the email address on your account"),
    (
        "sync:read",
        "Download your encrypted log. The app still needs your sync passphrase to read it — this server cannot decrypt it and neither can anyone without that passphrase.",
    ),
    (
        "sync:write",
        "Add and update QSOs in your log, and upload encrypted log data",
    ),
];

/// Routes reachable by a third-party token, and the scope each requires.
///
/// Paths are written WITHOUT the `/v1` prefix, matching how they appear in
/// `main.rs`; [`required_scope`] normalizes the matched path before lookup.
pub const THIRD_PARTY_SCOPES: &[(&str, &str, &str)] = &[
    // --- The log (E2E-encrypted; these move ciphertext only) ---------------
    ("GET", "/sync/bootstrap", "sync:read"),
    ("GET", "/sync/changes", "sync:read"),
    // Returns the passphrase-wrapped key envelope, not a key. Useless without
    // the user's passphrase, which never reaches this server.
    ("GET", "/sync/key", "sync:read"),
    ("POST", "/sync/push", "sync:write"),
    ("POST", "/sync/snapshot", "sync:write"),
    ("POST", "/sync/snapshot/commit", "sync:write"),
    ("PUT", "/sync/key", "sync:write"),
    // --- Identity -----------------------------------------------------------
    ("GET", "/oauth/userinfo", "openid"),
];

/// Every other route in `main.rs`: first-party tokens (and admin tokens) only.
///
/// Exhaustive by construction — see the `scope_map_covers_every_route` test.
/// Public routes appear here too: they are not third-party-reachable *as an
/// authenticated caller*, though an unauthenticated request reaches them
/// normally, which is unchanged behavior.
pub const FIRST_PARTY_ONLY: &[&str] = &[
    "/.well-known/apple-app-site-association",
    "/.well-known/jwks.json",
    "/.well-known/oauth-authorization-server",
    "/.well-known/openid-configuration",
    "/account",
    "/account/callsign",
    "/account/claim-previous",
    "/achievements",
    "/activities",
    "/activities/:id",
    "/admin/achievements/:id/award",
    "/admin/achievements/:id/award/:callsign",
    "/admin/achievements/:id/award/batch",
    "/admin/achievements/backfill",
    "/admin/badges/:id",
    "/admin/boundaries",
    "/admin/challenges",
    "/admin/challenges/:id",
    "/admin/challenges/:id/badges",
    "/admin/challenges/:id/invites",
    "/admin/clubs",
    "/admin/clubs/:id",
    "/admin/clubs/:id/import-notes",
    "/admin/clubs/:id/logo",
    "/admin/clubs/:id/members",
    "/admin/clubs/:id/members/:callsign",
    "/admin/contests",
    "/admin/contests/:id",
    "/admin/contests/validate",
    "/admin/equipment",
    "/admin/equipment/:id",
    "/admin/equipment/submissions",
    "/admin/equipment/submissions/:id/review",
    "/admin/events",
    "/admin/events/:id",
    "/admin/events/:id/review",
    "/admin/events/submitter/:callsign",
    "/admin/invites/:token",
    "/admin/macros",
    "/admin/macros/:slug",
    "/admin/metrickit",
    "/admin/oauth/clients",
    "/admin/oauth/clients/:client_id",
    "/admin/programs",
    "/admin/programs/:slug",
    "/admin/spots/:id",
    "/admin/stats",
    "/admin/stats/users-by-hour",
    "/admin/sync/orphans",
    "/admin/sync/orphans/:participant_id/adopt",
    "/admin/telemetry/upload-errors",
    "/admin/trails/status",
    "/auth/callsigns/verify/start",
    "/auth/devices",
    "/auth/devices/:id",
    "/auth/logout",
    "/auth/logout/all",
    "/auth/token",
    "/auth/token/refresh",
    "/auth/verify/complete",
    "/auth/verify/poll",
    "/auth/verify/start",
    "/badges/:id/image",
    "/callsign-enrichment/:callsign",
    "/callsign-enrichment/dataset",
    "/challenges",
    "/challenges/:id",
    "/challenges/:id/join",
    "/challenges/:id/leaderboard",
    "/challenges/:id/leave",
    "/challenges/:id/participants/:callsign",
    "/challenges/:id/progress",
    "/clubs",
    "/clubs/:id",
    "/clubs/:id/activity",
    "/clubs/:id/logo",
    "/clubs/:id/notes",
    "/clubs/:id/status",
    "/clubs/membership",
    "/clubs/sync",
    "/contests",
    "/contests/:id",
    "/diagnostics",
    "/equipment/catalog",
    "/equipment/search",
    "/equipment/submissions",
    "/events",
    "/events/:id",
    "/events/mine",
    "/feed",
    "/friends",
    "/friends/:id",
    "/friends/invite-link",
    "/friends/requests",
    "/friends/requests/:id/accept",
    "/friends/requests/:id/decline",
    "/friends/requests/pending",
    "/friends/suggestions",
    "/health",
    "/invite/:token",
    "/link/act/:token",
    "/link/call/:callsign",
    "/link/park/:reference",
    "/link/qso/:token",
    "/link/static/link-card.js",
    "/link/sum/:reference",
    "/macros",
    "/macros/:slug",
    "/macros/:slug/run-event",
    "/macros/:slug/versions",
    "/macros/tombstones",
    "/macros/versions",
    "/metrics",
    // The OAuth flow itself is first-party: these are driven by the user's
    // browser session or by client credentials, never by a bearer access token.
    "/oauth/authorize",
    "/oauth/authorize/decision",
    "/oauth/device",
    "/oauth/device/code",
    "/oauth/device/decision",
    "/oauth/grants",
    "/oauth/grants/:client_id",
    "/oauth/revoke",
    "/oauth/token",
    "/parks/boundaries",
    "/parks/boundaries/:reference",
    "/parks/boundaries/status",
    "/participants/:callsign/challenges",
    "/pota/stats/activator",
    "/pota/stats/hunter",
    "/pota/stats/park/:reference",
    "/pota/stats/rankings/activators",
    "/pota/stats/state/:state",
    "/pota/stats/status",
    "/programs",
    "/programs/:slug",
    "/propagation/p2p",
    "/propagation/wheel",
    "/rbn/skimmers",
    "/rbn/spots",
    "/rbn/stats",
    "/register",
    "/satellites/amsat-status",
    "/satellites/amsat-status/activity",
    "/satellites/amsat-status/reports",
    "/sota/zones",
    "/spot-markers",
    "/spots",
    "/spots/:id",
    "/telemetry/equipment-usage",
    "/telemetry/upload-errors",
    "/trails",
    "/trails/:reference",
    "/trails/status",
    "/twilio/sms",
    "/users/:callsign/achievements",
    "/users/me/achievements/signal",
    "/users/search",
    "/websdr/directory",
    "/websdr/status",
    "/websdr/stream",
];

/// Strip the `/v1` nest prefix so lookups match how routes are written in
/// `main.rs`. Axum reports the full matched path inside a nested router.
fn normalize(path: &str) -> &str {
    path.strip_prefix("/v1").unwrap_or(path)
}

/// The scope a third-party token needs for `(method, path)`, or `None` if the
/// route is not third-party-reachable at all.
///
/// `None` means DENY, not "no scope required".
pub fn required_scope(method: &str, path: &str) -> Option<&'static str> {
    let path = normalize(path);
    THIRD_PARTY_SCOPES
        .iter()
        .find(|(m, p, _)| *m == method && *p == path)
        .map(|(_, _, scope)| *scope)
}

/// Keep only scopes this server knows about, preserving request order and
/// dropping duplicates.
pub fn sanitize(requested: &str) -> Vec<String> {
    let mut kept: Vec<String> = Vec::new();
    for scope in requested.split_whitespace() {
        if ALL_SCOPES.contains(&scope) && !kept.iter().any(|s| s == scope) {
            kept.push(scope.to_string());
        }
    }
    kept
}

/// Consent-screen description for a scope.
pub fn describe(scope: &str) -> &'static str {
    SCOPE_DESCRIPTIONS
        .iter()
        .find(|(s, _)| *s == scope)
        .map(|(_, d)| *d)
        .unwrap_or("Unknown permission")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every `.route("…")` in `main.rs` must be classified as either
    /// third-party-reachable or first-party-only. Adding a route without
    /// deciding fails here rather than silently inheriting a default.
    ///
    /// Parses the source rather than the built `Router` because axum exposes no
    /// route enumeration. Crude, but it reads the same text a reviewer would.
    #[test]
    fn scope_map_covers_every_route() {
        let src = include_str!("../main.rs");
        let mut unclassified = Vec::new();

        for (idx, _) in src.match_indices(".route(") {
            let rest = &src[idx + ".route(".len()..];
            // Skip whitespace/newlines between `(` and the path literal.
            let rest = rest.trim_start();
            let Some(body) = rest.strip_prefix('"') else {
                continue;
            };
            let Some(end) = body.find('"') else { continue };
            let path = &body[..end];

            let known = THIRD_PARTY_SCOPES.iter().any(|(_, p, _)| *p == path)
                || FIRST_PARTY_ONLY.contains(&path);
            if !known && !unclassified.contains(&path) {
                unclassified.push(path);
            }
        }

        assert!(
            unclassified.is_empty(),
            "unclassified routes in main.rs — add each to THIRD_PARTY_SCOPES \
             (with a scope) or FIRST_PARTY_ONLY in auth/scope_map.rs: {unclassified:#?}"
        );
    }

    /// The inverse: a path listed here that no longer exists in `main.rs` is
    /// dead policy, and dead policy hides real gaps.
    #[test]
    fn no_stale_third_party_entries() {
        let src = include_str!("../main.rs");
        for (_, path, _) in THIRD_PARTY_SCOPES {
            assert!(
                src.contains(&format!("\"{path}\"")),
                "THIRD_PARTY_SCOPES lists {path}, which no longer exists in main.rs"
            );
        }
    }

    #[test]
    fn every_third_party_scope_is_known_and_described() {
        for (_, path, scope) in THIRD_PARTY_SCOPES {
            assert!(
                ALL_SCOPES.contains(scope),
                "{path} requires unknown scope {scope}"
            );
            assert_ne!(
                describe(scope),
                "Unknown permission",
                "scope {scope} has no consent-screen description"
            );
        }
    }

    #[test]
    fn unlisted_route_denies() {
        assert_eq!(required_scope("GET", "/v1/friends"), None);
        assert_eq!(required_scope("POST", "/v1/clubs"), None);
        // Right path, wrong method is still a deny.
        assert_eq!(required_scope("DELETE", "/v1/sync/key"), None);
    }

    #[test]
    fn sync_routes_resolve_with_and_without_the_v1_prefix() {
        assert_eq!(required_scope("GET", "/v1/sync/bootstrap"), Some("sync:read"));
        assert_eq!(required_scope("GET", "/sync/bootstrap"), Some("sync:read"));
        assert_eq!(required_scope("POST", "/v1/sync/push"), Some("sync:write"));
        assert_eq!(
            required_scope("POST", "/v1/sync/snapshot"),
            Some("sync:write")
        );
        assert_eq!(
            required_scope("POST", "/v1/sync/snapshot/commit"),
            Some("sync:write")
        );
    }

    #[test]
    fn sanitize_drops_unknown_scopes_and_duplicates() {
        assert_eq!(
            sanitize("openid sync:read bogus sync:read admin:*"),
            vec!["openid", "sync:read"]
        );
        assert!(sanitize("").is_empty());
    }
}
