//! EdDSA (Ed25519) JWT access tokens — Phase 5 OAuth overhaul (D7).
//!
//! Access tokens are stateless and short-lived (15 min): they verify
//! cryptographically with no per-request DB hit. Asymmetric (EdDSA) so any
//! future service (e.g. `cw-sync`) can verify with the published public key
//! without sharing a secret. The signing key is provided via env as PEM.
//!
//! Design: docs/plans/2026-06-21-phase5-oauth-overhaul.md (§5).

use base64::Engine;
use chrono::Utc;
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::AppError;

/// Access-token lifetime. Short, so revocation is mostly "wait for expiry".
pub const ACCESS_TTL_SECS: i64 = 15 * 60;

/// Clock-skew tolerance for `exp`/`iat`/`nbf` validation (F5).
const LEEWAY_SECS: u64 = 60;

/// Token issuer — must match between mint and verify.
pub const ISSUER: &str = "https://activities.carrierwave.app";

/// Audiences. A token minted for one audience is rejected by a verifier
/// expecting another (F5 — no cross-service token reuse).
pub const AUD_SYNC: &str = "cw-sync";
pub const AUD_SOCIAL: &str = "cw-social";

/// Claim set carried by an access JWT.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    /// Issuer.
    pub iss: String,
    /// Subject — the stable `accounts.id`.
    pub sub: Uuid,
    /// Audience — the service this token is for.
    pub aud: String,
    /// Space-delimited scopes.
    pub scope: String,
    /// Primary callsign — convenience only, NON-AUTHORITATIVE. Never authorize
    /// on this; always resolve via `account_callsigns` (F5/F6).
    pub cs: String,
    /// Issued-at (unix seconds).
    pub iat: i64,
    /// Expiry (unix seconds).
    pub exp: i64,
    /// Unique token id (for the emergency denylist).
    pub jti: Uuid,
    /// Registered OAuth client this token was minted for. `None` on first-party
    /// tokens (the magic-link/device flow the apps use).
    ///
    /// This one bit decides the whole authorization posture: a token WITH a
    /// `cid` is a third party acting on the user's behalf and is default-denied
    /// on every route not explicitly listed in [`crate::auth::scope_map`]. A
    /// token without one keeps the pre-existing full-surface behavior, so
    /// shipping apps are unaffected.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cid: Option<String>,
}

impl Claims {
    /// Scopes as a borrowed iterator.
    pub fn scopes(&self) -> impl Iterator<Item = &str> {
        self.scope.split_ascii_whitespace()
    }

    /// Whether the token carries `scope`.
    pub fn has_scope(&self, scope: &str) -> bool {
        self.scopes().any(|s| s == scope)
    }
}

/// Claim set carried by an OIDC ID token.
///
/// Identity claims only. `cs`/`callsign` is the ham-radio-specific claim other
/// services will actually care about; `preferred_username` mirrors it so
/// off-the-shelf OIDC clients show something sensible without special-casing us.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IdTokenClaims {
    pub iss: String,
    pub sub: Uuid,
    /// Audience — the OAuth client this token was issued to.
    pub aud: String,
    pub iat: i64,
    pub exp: i64,
    /// When the user actually authenticated (not when this token was minted).
    pub auth_time: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub nonce: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at_hash: Option<String>,
    /// Primary callsign. Non-authoritative for authorization, same as `Claims::cs`.
    pub callsign: String,
    pub preferred_username: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email_verified: Option<bool>,
}

/// Inputs to [`JwtKeys::mint_id_token`]. A struct rather than a positional
/// argument list because half of these are interchangeable `&str`s — callsign,
/// email, and nonce would transpose silently.
pub struct IdTokenRequest<'a> {
    pub account_id: Uuid,
    pub client_id: &'a str,
    pub primary_callsign: &'a str,
    pub email: Option<&'a str>,
    pub nonce: Option<&'a str>,
    /// When the user actually authenticated, as a unix timestamp.
    pub auth_time: i64,
    /// The access token issued alongside this ID token; hashed into `at_hash`.
    pub access_token: &'a str,
}

/// ID-token lifetime. Longer than an access token because it is an assertion
/// about a past authentication, not a bearer credential for this API.
pub const ID_TOKEN_TTL_SECS: i64 = 60 * 60;

/// OIDC `at_hash`: base64url of the left-most half of SHA-256(access_token).
fn at_hash(access_token: &str) -> String {
    use sha2::{Digest, Sha256};
    let digest = Sha256::digest(access_token.as_bytes());
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&digest[..16])
}

/// Loaded signing + verifying keys with a key id (for rotation via `kid`).
pub struct JwtKeys {
    encoding: EncodingKey,
    decoding: DecodingKey,
    kid: String,
    /// Raw 32-byte Ed25519 public key, for the published JWKS (`x` claim).
    public_raw: Vec<u8>,
}

impl JwtKeys {
    /// Build from PEM strings (PKCS#8 private, SPKI public) and a key id.
    pub fn from_pem(private_pem: &[u8], public_pem: &[u8], kid: impl Into<String>) -> Result<Self, AppError> {
        let encoding = EncodingKey::from_ed_pem(private_pem)
            .map_err(|e| AppError::Internal(format!("invalid JWT private key: {e}")))?;
        let decoding = DecodingKey::from_ed_pem(public_pem)
            .map_err(|e| AppError::Internal(format!("invalid JWT public key: {e}")))?;
        let public_raw = parse_ed25519_public_raw(public_pem)?;
        Ok(Self {
            encoding,
            decoding,
            kid: kid.into(),
            public_raw,
        })
    }

    /// The published JWK Set for this signing key (EdDSA / OKP / Ed25519). Served
    /// at `/.well-known/jwks.json` so any verifier (e.g. the future `cw-sync`
    /// service) can validate access tokens by `kid` without sharing a secret.
    pub fn jwks(&self) -> serde_json::Value {
        let public = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&self.public_raw);
        serde_json::json!({
            "keys": [{
                "kty": "OKP",
                "crv": "Ed25519",
                "use": "sig",
                "alg": "EdDSA",
                "kid": self.kid,
                "x": public,
            }]
        })
    }

    /// Load from env: `JWT_ED25519_PRIVATE_PEM`, `JWT_ED25519_PUBLIC_PEM`, `JWT_KID`.
    pub fn from_env() -> Result<Self, AppError> {
        let private = std::env::var("JWT_ED25519_PRIVATE_PEM")
            .map_err(|_| AppError::Internal("JWT_ED25519_PRIVATE_PEM not set".into()))?;
        let public = std::env::var("JWT_ED25519_PUBLIC_PEM")
            .map_err(|_| AppError::Internal("JWT_ED25519_PUBLIC_PEM not set".into()))?;
        let kid = std::env::var("JWT_KID").unwrap_or_else(|_| "v1".into());
        Self::from_pem(private.as_bytes(), public.as_bytes(), kid)
    }

    /// Mint a signed first-party access token for `account_id` / `aud`.
    pub fn mint_access(
        &self,
        account_id: Uuid,
        aud: &str,
        scopes: &str,
        primary_callsign: &str,
    ) -> Result<String, AppError> {
        self.mint_access_for_client(account_id, aud, scopes, primary_callsign, None)
    }

    /// Mint an access token, optionally on behalf of a registered OAuth client.
    ///
    /// Passing `Some(client_id)` marks the token third-party, which activates
    /// default-deny scope gating in the auth middleware. Never pass `None` for a
    /// token handed to someone else's application.
    pub fn mint_access_for_client(
        &self,
        account_id: Uuid,
        aud: &str,
        scopes: &str,
        primary_callsign: &str,
        client_id: Option<&str>,
    ) -> Result<String, AppError> {
        let now = Utc::now().timestamp();
        let claims = Claims {
            iss: ISSUER.to_string(),
            sub: account_id,
            aud: aud.to_string(),
            scope: scopes.to_string(),
            cs: primary_callsign.to_string(),
            iat: now,
            exp: now + ACCESS_TTL_SECS,
            jti: Uuid::new_v4(),
            cid: client_id.map(str::to_string),
        };
        let mut header = Header::new(Algorithm::EdDSA);
        header.kid = Some(self.kid.clone());
        encode(&header, &claims, &self.encoding)
            .map_err(|e| AppError::Internal(format!("JWT encode failed: {e}")))
    }

    /// Mint an OIDC ID token for `client_id`.
    ///
    /// Distinct from an access token in every way that matters: the audience is
    /// the client (not a service), it carries identity claims rather than
    /// scopes, and it is meant to be consumed and discarded by the client — not
    /// presented back to this API. `access_token` is hashed into `at_hash` so a
    /// client can bind the two together (OIDC Core §3.1.3.6).
    pub fn mint_id_token(&self, req: IdTokenRequest<'_>) -> Result<String, AppError> {
        let now = Utc::now().timestamp();
        let claims = IdTokenClaims {
            iss: ISSUER.to_string(),
            sub: req.account_id,
            aud: req.client_id.to_string(),
            iat: now,
            exp: now + ID_TOKEN_TTL_SECS,
            auth_time: req.auth_time,
            nonce: req.nonce.map(str::to_string),
            at_hash: Some(at_hash(req.access_token)),
            callsign: req.primary_callsign.to_string(),
            preferred_username: req.primary_callsign.to_string(),
            email: req.email.map(str::to_string),
            email_verified: req.email.map(|_| true),
        };
        let mut header = Header::new(Algorithm::EdDSA);
        header.kid = Some(self.kid.clone());
        encode(&header, &claims, &self.encoding)
            .map_err(|e| AppError::Internal(format!("id_token encode failed: {e}")))
    }

    /// Verify a token for `expected_aud`. Enforces the full policy (F5):
    /// EdDSA only, required `aud`/`iss`/`exp`/`sub`, clock-skew leeway. If
    /// `tokens_valid_after` is set, tokens minted before it are rejected (the
    /// cheap emergency-revocation epoch, F3).
    pub fn verify_access(
        &self,
        token: &str,
        expected_aud: &str,
        tokens_valid_after: Option<i64>,
    ) -> Result<Claims, AppError> {
        // Algorithm is hardcoded — `decode` will reject any other `alg`,
        // closing the asymmetric/symmetric confusion attack.
        let mut validation = Validation::new(Algorithm::EdDSA);
        validation.leeway = LEEWAY_SECS;
        validation.set_audience(&[expected_aud]);
        validation.set_issuer(&[ISSUER]);
        validation.set_required_spec_claims(&["exp", "aud", "iss", "sub"]);

        let data = decode::<Claims>(token, &self.decoding, &validation)
            .map_err(|_| AppError::InvalidToken)?;

        if let Some(epoch) = tokens_valid_after {
            if data.claims.iat < epoch {
                return Err(AppError::InvalidToken);
            }
        }
        Ok(data.claims)
    }
}

/// Extract the raw 32-byte Ed25519 public key from an SPKI PEM. For Ed25519 the
/// SubjectPublicKeyInfo DER is a fixed 44 bytes whose trailing 32 bytes are the
/// key, so we base64-decode the PEM body and take the last 32 bytes.
fn parse_ed25519_public_raw(public_pem: &[u8]) -> Result<Vec<u8>, AppError> {
    let text =
        std::str::from_utf8(public_pem).map_err(|_| AppError::Internal("public key not UTF-8".into()))?;
    let body: String = text.lines().filter(|line| !line.starts_with("-----")).collect();
    let der = base64::engine::general_purpose::STANDARD
        .decode(body.trim())
        .map_err(|e| AppError::Internal(format!("public key base64: {e}")))?;
    if der.len() < 32 {
        return Err(AppError::Internal("public key too short for Ed25519".into()));
    }
    Ok(der[der.len() - 32..].to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    // TEST-ONLY Ed25519 keypair (generated offline; never used in prod).
    const TEST_PRIV: &[u8] = b"-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIPvhZplQ+xojm0jKVT0hj5UeIhJseS3m04xy2YrlK1qe\n-----END PRIVATE KEY-----\n";
    const TEST_PUB: &[u8] = b"-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAj4viocqz7AJdIwt15uC2eOnaRlfSc6xxmDmCn32TttY=\n-----END PUBLIC KEY-----\n";

    fn keys() -> JwtKeys {
        JwtKeys::from_pem(TEST_PRIV, TEST_PUB, "test").expect("load test keys")
    }

    #[test]
    fn mint_then_verify_roundtrip() {
        let k = keys();
        let acct = Uuid::new_v4();
        let token = k
            .mint_access(acct, AUD_SYNC, "sync:read sync:write", "W6JY")
            .unwrap();
        let claims = k.verify_access(&token, AUD_SYNC, None).unwrap();
        assert_eq!(claims.sub, acct);
        assert_eq!(claims.cs, "W6JY");
        assert!(claims.has_scope("sync:read"));
        assert!(claims.has_scope("sync:write"));
        assert!(!claims.has_scope("social:write"));
    }

    #[test]
    fn wrong_audience_rejected() {
        let k = keys();
        let token = k
            .mint_access(Uuid::new_v4(), AUD_SOCIAL, "social:read", "W6JY")
            .unwrap();
        // Minted for cw-social, verified expecting cw-sync → rejected.
        assert!(k.verify_access(&token, AUD_SYNC, None).is_err());
    }

    #[test]
    fn tokens_valid_after_epoch_rejects_old_token() {
        let k = keys();
        let token = k
            .mint_access(Uuid::new_v4(), AUD_SYNC, "sync:read", "W6JY")
            .unwrap();
        // Epoch in the far future → every existing token is invalidated.
        let future = Utc::now().timestamp() + 3600;
        assert!(k.verify_access(&token, AUD_SYNC, Some(future)).is_err());
        // Epoch in the past → token still valid.
        let past = Utc::now().timestamp() - 3600;
        assert!(k.verify_access(&token, AUD_SYNC, Some(past)).is_ok());
    }

    #[test]
    fn jwks_exposes_ed25519_public_key() {
        let k = keys();
        let jwks = k.jwks();
        let key = &jwks["keys"][0];
        assert_eq!(key["kty"], "OKP");
        assert_eq!(key["crv"], "Ed25519");
        assert_eq!(key["alg"], "EdDSA");
        assert_eq!(key["kid"], "test");
        // `x` is the base64url (no pad) 32-byte raw public key.
        let raw = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(key["x"].as_str().unwrap())
            .unwrap();
        assert_eq!(raw.len(), 32);
    }

    #[test]
    fn tampered_token_rejected() {
        let k = keys();
        let mut token = k
            .mint_access(Uuid::new_v4(), AUD_SYNC, "sync:read", "W6JY")
            .unwrap();
        token.push('x');
        assert!(k.verify_access(&token, AUD_SYNC, None).is_err());
    }
}
