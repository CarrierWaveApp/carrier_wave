//! Persistence for the third-party OAuth 2.0 / OIDC provider.
//!
//! Everything single-use here (authorization codes, device codes) is stored
//! HASHED and consumed with a conditional `UPDATE … WHERE consumed_at IS NULL
//! RETURNING`, so redemption is atomic under concurrency and a replay is
//! distinguishable from a first use rather than racing it.
//!
//! Schema: `migrations/047_oauth_provider.sql`.

use chrono::{DateTime, Duration, Utc};
use rand::Rng;
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use subtle::ConstantTimeEq;
use uuid::Uuid;

use crate::error::AppError;

/// Authorization codes are exchanged immediately; a long life is pure attack
/// surface. RFC 6749 §4.1.2 recommends a maximum of 10 minutes; 60 seconds is
/// plenty for a redirect.
const AUTH_CODE_TTL_SECS: i64 = 60;
/// Long enough for someone to walk to another device and type the user code.
const DEVICE_CODE_TTL_SECS: i64 = 15 * 60;
/// Baseline polling interval handed to device-grant clients (RFC 8628 §3.2).
const DEVICE_POLL_INTERVAL_SECS: i32 = 5;

fn hash(value: &str) -> Vec<u8> {
    Sha256::digest(value.as_bytes()).to_vec()
}

// ---- clients ---------------------------------------------------------------

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OAuthClient {
    pub client_id: String,
    pub client_secret_hash: Option<Vec<u8>>,
    pub name: String,
    pub description: Option<String>,
    pub homepage_url: Option<String>,
    pub redirect_uris: Vec<String>,
    pub allowed_scopes: String,
    pub grant_types: String,
    pub status: String,
}

impl OAuthClient {
    pub fn is_active(&self) -> bool {
        self.status == "active"
    }

    /// Public clients hold no secret and must prove possession with PKCE alone.
    pub fn is_public(&self) -> bool {
        self.client_secret_hash.is_none()
    }

    /// Exact-match redirect check. No wildcards, no prefix matching, no
    /// normalization — every relaxation of this rule has its own CVE history.
    pub fn allows_redirect(&self, uri: &str) -> bool {
        self.redirect_uris.iter().any(|u| u == uri)
    }

    pub fn allows_grant(&self, grant: &str) -> bool {
        self.grant_types.split_whitespace().any(|g| g == grant)
    }

    /// Intersect a request's scopes with what this client is permitted to ask
    /// for. A client can always request less than its ceiling, never more.
    pub fn clamp_scopes(&self, requested: &[String]) -> Vec<String> {
        let allowed: Vec<&str> = self.allowed_scopes.split_whitespace().collect();
        requested
            .iter()
            .filter(|s| allowed.contains(&s.as_str()))
            .cloned()
            .collect()
    }

    /// Constant-time secret check. `false` for public clients — they must not be
    /// able to authenticate by presenting no secret where one is expected.
    pub fn verify_secret(&self, presented: &str) -> bool {
        match &self.client_secret_hash {
            Some(expected) => hash(presented).ct_eq(expected).unwrap_u8() == 1,
            None => false,
        }
    }
}

const CLIENT_COLUMNS: &str = "client_id, client_secret_hash, name, description, homepage_url, \
                              redirect_uris, allowed_scopes, grant_types, status";

pub async fn get_client(pool: &PgPool, client_id: &str) -> Result<Option<OAuthClient>, AppError> {
    let row = sqlx::query_as::<_, OAuthClient>(&format!(
        "SELECT {CLIENT_COLUMNS} FROM oauth_clients WHERE client_id = $1"
    ))
    .bind(client_id)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// Fetch a client that is allowed to transact right now. Suspended and unknown
/// clients are indistinguishable to the caller, on purpose.
pub async fn get_active_client(pool: &PgPool, client_id: &str) -> Result<OAuthClient, AppError> {
    get_client(pool, client_id)
        .await?
        .filter(OAuthClient::is_active)
        .ok_or(AppError::Validation {
            message: "unknown client".into(),
        })
}

pub async fn list_clients(pool: &PgPool) -> Result<Vec<OAuthClient>, AppError> {
    let rows = sqlx::query_as::<_, OAuthClient>(&format!(
        "SELECT {CLIENT_COLUMNS} FROM oauth_clients ORDER BY created_at DESC"
    ))
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub struct NewClient<'a> {
    pub client_id: &'a str,
    pub name: &'a str,
    pub description: Option<&'a str>,
    pub homepage_url: Option<&'a str>,
    pub redirect_uris: &'a [String],
    pub allowed_scopes: &'a str,
    pub grant_types: &'a str,
    pub created_by: Option<&'a str>,
}

/// Register a client. Returns the generated secret in plaintext exactly once
/// (`None` for a public client), because it is only ever stored hashed.
pub async fn create_client(
    pool: &PgPool,
    new: NewClient<'_>,
    confidential: bool,
) -> Result<(OAuthClient, Option<String>), AppError> {
    let secret = confidential.then(generate_client_secret);
    let secret_hash = secret.as_deref().map(hash);

    let client = sqlx::query_as::<_, OAuthClient>(&format!(
        r#"
        INSERT INTO oauth_clients
            (client_id, client_secret_hash, name, description, homepage_url,
             redirect_uris, allowed_scopes, grant_types, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING {CLIENT_COLUMNS}
        "#
    ))
    .bind(new.client_id)
    .bind(secret_hash)
    .bind(new.name)
    .bind(new.description)
    .bind(new.homepage_url)
    .bind(new.redirect_uris)
    .bind(new.allowed_scopes)
    .bind(new.grant_types)
    .bind(new.created_by)
    .fetch_one(pool)
    .await?;

    Ok((client, secret))
}

/// Suspend a client. Deliberately not a delete: the `oauth_grants` and `devices`
/// rows that reference it are the audit trail of who granted what, and a
/// suspended client stops working immediately anyway.
pub async fn suspend_client(pool: &PgPool, client_id: &str) -> Result<bool, AppError> {
    let result = sqlx::query("UPDATE oauth_clients SET status = 'suspended' WHERE client_id = $1")
        .bind(client_id)
        .execute(pool)
        .await?;
    Ok(result.rows_affected() > 0)
}

// ---- authorization codes ---------------------------------------------------

pub struct AuthCodeRecord {
    pub client_id: String,
    pub account_id: Uuid,
    pub redirect_uri: String,
    pub scopes: String,
    pub code_challenge: String,
    pub nonce: Option<String>,
}

#[derive(sqlx::FromRow)]
struct AuthCodeRow {
    client_id: String,
    account_id: Uuid,
    redirect_uri: String,
    scopes: String,
    code_challenge: String,
    nonce: Option<String>,
}

/// Mint a single-use authorization code. The plaintext goes to the browser via
/// the redirect; only its hash is stored.
pub async fn create_authorization_code(
    pool: &PgPool,
    client_id: &str,
    account_id: Uuid,
    redirect_uri: &str,
    scopes: &str,
    code_challenge: &str,
    nonce: Option<&str>,
) -> Result<String, AppError> {
    let code = generate_opaque_token();
    sqlx::query(
        r#"
        INSERT INTO oauth_authorization_codes
            (code_hash, client_id, account_id, redirect_uri, scopes, code_challenge, nonce, expires_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        "#,
    )
    .bind(hash(&code))
    .bind(client_id)
    .bind(account_id)
    .bind(redirect_uri)
    .bind(scopes)
    .bind(code_challenge)
    .bind(nonce)
    .bind(Utc::now() + Duration::seconds(AUTH_CODE_TTL_SECS))
    .execute(pool)
    .await?;
    Ok(code)
}

/// Atomically consume a code. Returns `None` for unknown, expired, or
/// already-consumed codes — the caller must not distinguish them to the client.
pub async fn consume_authorization_code(
    pool: &PgPool,
    code: &str,
) -> Result<Option<AuthCodeRecord>, AppError> {
    let row = sqlx::query_as::<_, AuthCodeRow>(
        r#"
        UPDATE oauth_authorization_codes
        SET consumed_at = NOW()
        WHERE code_hash = $1 AND consumed_at IS NULL AND expires_at > NOW()
        RETURNING client_id, account_id, redirect_uri, scopes, code_challenge, nonce
        "#,
    )
    .bind(hash(code))
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| AuthCodeRecord {
        client_id: r.client_id,
        account_id: r.account_id,
        redirect_uri: r.redirect_uri,
        scopes: r.scopes,
        code_challenge: r.code_challenge,
        nonce: r.nonce,
    }))
}

// ---- device grant ----------------------------------------------------------

pub struct IssuedDeviceCode {
    pub device_code: String,
    pub user_code: String,
    pub expires_in: i64,
    pub interval: i32,
}

#[derive(sqlx::FromRow)]
pub struct DeviceCodeRow {
    pub client_id: String,
    pub scopes: String,
    pub account_id: Option<Uuid>,
    pub approved_at: Option<DateTime<Utc>>,
    pub denied_at: Option<DateTime<Utc>>,
    pub consumed_at: Option<DateTime<Utc>>,
    pub interval_secs: i32,
    pub last_polled_at: Option<DateTime<Utc>>,
    pub expires_at: DateTime<Utc>,
}

pub async fn create_device_code(
    pool: &PgPool,
    client_id: &str,
    scopes: &str,
) -> Result<IssuedDeviceCode, AppError> {
    let device_code = generate_opaque_token();
    let user_code = generate_user_code();

    sqlx::query(
        r#"
        INSERT INTO oauth_device_codes
            (device_code_hash, user_code, client_id, scopes, interval_secs, expires_at)
        VALUES ($1, $2, $3, $4, $5, $6)
        "#,
    )
    .bind(hash(&device_code))
    .bind(&user_code)
    .bind(client_id)
    .bind(scopes)
    .bind(DEVICE_POLL_INTERVAL_SECS)
    .bind(Utc::now() + Duration::seconds(DEVICE_CODE_TTL_SECS))
    .execute(pool)
    .await?;

    Ok(IssuedDeviceCode {
        device_code,
        user_code,
        expires_in: DEVICE_CODE_TTL_SECS,
        interval: DEVICE_POLL_INTERVAL_SECS,
    })
}

/// Look up a pending device authorization by the code the user typed.
pub async fn find_device_code_by_user_code(
    pool: &PgPool,
    user_code: &str,
) -> Result<Option<DeviceCodeRow>, AppError> {
    let row = sqlx::query_as::<_, DeviceCodeRow>(
        r#"
        SELECT client_id, scopes, account_id, approved_at, denied_at, consumed_at,
               interval_secs, last_polled_at, expires_at
        FROM oauth_device_codes
        WHERE user_code = $1 AND expires_at > NOW()
        "#,
    )
    .bind(normalize_user_code(user_code))
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// Record the user's decision on the verification page.
pub async fn decide_device_code(
    pool: &PgPool,
    user_code: &str,
    account_id: Uuid,
    approved: bool,
    scopes: &str,
) -> Result<bool, AppError> {
    let result = sqlx::query(
        r#"
        UPDATE oauth_device_codes
        SET account_id  = $2,
            scopes      = CASE WHEN $3 THEN $4 ELSE scopes END,
            approved_at = CASE WHEN $3 THEN NOW() ELSE NULL END,
            denied_at   = CASE WHEN $3 THEN NULL ELSE NOW() END
        WHERE user_code = $1
          AND expires_at > NOW()
          AND approved_at IS NULL
          AND denied_at IS NULL
        "#,
    )
    .bind(normalize_user_code(user_code))
    .bind(account_id)
    .bind(approved)
    .bind(scopes)
    .execute(pool)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Poll outcome for `grant_type=device_code`, mapped 1:1 onto RFC 8628 §3.5.
pub enum DevicePollOutcome {
    /// User has not decided yet.
    Pending,
    /// Client polled faster than `interval` — it must back off.
    SlowDown,
    /// User approved; the device code is now consumed.
    Approved { account_id: Uuid, scopes: String },
    Denied,
    /// Unknown or expired.
    Invalid,
}

/// Poll (and, on approval, atomically consume) a device code.
pub async fn poll_device_code(
    pool: &PgPool,
    device_code: &str,
) -> Result<DevicePollOutcome, AppError> {
    let code_hash = hash(device_code);
    let mut tx = pool.begin().await?;

    let Some(row) = sqlx::query_as::<_, DeviceCodeRow>(
        r#"
        SELECT client_id, scopes, account_id, approved_at, denied_at, consumed_at,
               interval_secs, last_polled_at, expires_at
        FROM oauth_device_codes
        WHERE device_code_hash = $1
        FOR UPDATE
        "#,
    )
    .bind(&code_hash)
    .fetch_optional(&mut *tx)
    .await?
    else {
        return Ok(DevicePollOutcome::Invalid);
    };

    if row.expires_at <= Utc::now() || row.consumed_at.is_some() {
        return Ok(DevicePollOutcome::Invalid);
    }

    // Rate-limit before resolving state, so an over-eager client is told to slow
    // down rather than being handed tokens on a too-fast poll.
    if let Some(last) = row.last_polled_at {
        if Utc::now() - last < Duration::seconds(row.interval_secs as i64) {
            sqlx::query("UPDATE oauth_device_codes SET last_polled_at = NOW() WHERE device_code_hash = $1")
                .bind(&code_hash)
                .execute(&mut *tx)
                .await?;
            tx.commit().await?;
            return Ok(DevicePollOutcome::SlowDown);
        }
    }

    sqlx::query("UPDATE oauth_device_codes SET last_polled_at = NOW() WHERE device_code_hash = $1")
        .bind(&code_hash)
        .execute(&mut *tx)
        .await?;

    if row.denied_at.is_some() {
        tx.commit().await?;
        return Ok(DevicePollOutcome::Denied);
    }

    let outcome = match (row.approved_at, row.account_id) {
        (Some(_), Some(account_id)) => {
            sqlx::query(
                "UPDATE oauth_device_codes SET consumed_at = NOW() WHERE device_code_hash = $1",
            )
            .bind(&code_hash)
            .execute(&mut *tx)
            .await?;
            DevicePollOutcome::Approved {
                account_id,
                scopes: row.scopes,
            }
        }
        _ => DevicePollOutcome::Pending,
    };

    tx.commit().await?;
    Ok(outcome)
}

// ---- consent ---------------------------------------------------------------

/// Scopes this account has already granted this client, if any.
pub async fn get_grant(
    pool: &PgPool,
    account_id: Uuid,
    client_id: &str,
) -> Result<Option<String>, AppError> {
    let scopes: Option<(String,)> = sqlx::query_as(
        r#"
        SELECT scopes FROM oauth_grants
        WHERE account_id = $1 AND client_id = $2 AND revoked_at IS NULL
        "#,
    )
    .bind(account_id)
    .bind(client_id)
    .fetch_optional(pool)
    .await?;
    Ok(scopes.map(|(s,)| s))
}

/// Record consent. Re-granting revives a previously revoked grant, which is what
/// the user is asking for by going through the prompt again.
pub async fn upsert_grant(
    pool: &PgPool,
    account_id: Uuid,
    client_id: &str,
    scopes: &str,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        INSERT INTO oauth_grants (account_id, client_id, scopes)
        VALUES ($1, $2, $3)
        ON CONFLICT (account_id, client_id)
        DO UPDATE SET scopes = EXCLUDED.scopes, granted_at = NOW(), revoked_at = NULL
        "#,
    )
    .bind(account_id)
    .bind(client_id)
    .bind(scopes)
    .execute(pool)
    .await?;
    Ok(())
}

#[derive(Debug, serde::Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct GrantSummary {
    pub client_id: String,
    pub client_name: String,
    pub scopes: String,
    pub granted_at: DateTime<Utc>,
}

/// The "connected apps" list for an account.
pub async fn list_grants(pool: &PgPool, account_id: Uuid) -> Result<Vec<GrantSummary>, AppError> {
    let rows = sqlx::query_as::<_, GrantSummary>(
        r#"
        SELECT g.client_id, c.name AS client_name, g.scopes, g.granted_at
        FROM oauth_grants g
        JOIN oauth_clients c ON c.client_id = g.client_id
        WHERE g.account_id = $1 AND g.revoked_at IS NULL
        ORDER BY g.granted_at DESC
        "#,
    )
    .bind(account_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Revoke a grant and everything issued under it.
///
/// Deleting the client's `devices` rows cascades to their refresh tokens, so the
/// client cannot mint another access token. Already-issued access tokens stay
/// valid until they expire (15 minutes) — that is the standard trade for
/// stateless verification, and `revoked_jti` remains the emergency lever.
pub async fn revoke_grant(
    pool: &PgPool,
    account_id: Uuid,
    client_id: &str,
) -> Result<bool, AppError> {
    let mut tx = pool.begin().await?;

    let result = sqlx::query(
        r#"
        UPDATE oauth_grants SET revoked_at = NOW()
        WHERE account_id = $1 AND client_id = $2 AND revoked_at IS NULL
        "#,
    )
    .bind(account_id)
    .bind(client_id)
    .execute(&mut *tx)
    .await?;

    sqlx::query("DELETE FROM devices WHERE account_id = $1 AND oauth_client_id = $2")
        .bind(account_id)
        .bind(client_id)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;
    Ok(result.rows_affected() > 0)
}

// ---- client-owned device installs -----------------------------------------

/// Create the `devices` row representing one client's authorization for one
/// account, so third-party refresh tokens reuse the existing rotation machinery
/// (`db::auth::rotate_refresh`) untouched.
pub async fn create_client_device(
    pool: &PgPool,
    account_id: Uuid,
    client_id: &str,
    client_name: &str,
) -> Result<Uuid, AppError> {
    let id: (Uuid,) = sqlx::query_as(
        r#"
        INSERT INTO devices (id, account_id, device_name, platform, oauth_client_id)
        VALUES ($1, $2, $3, 'oauth', $4)
        RETURNING id
        "#,
    )
    .bind(Uuid::new_v4())
    .bind(account_id)
    .bind(client_name)
    .bind(client_id)
    .fetch_one(pool)
    .await?;
    Ok(id.0)
}

/// Which client owns the device install behind a *presented* refresh token.
///
/// Checked BEFORE rotation so the first-party refresh endpoint can reject a
/// third-party token without having already consumed it — rotating and then
/// refusing would burn the client's only refresh token and strand it.
pub async fn client_id_for_refresh(
    pool: &PgPool,
    presented: &str,
) -> Result<Option<String>, AppError> {
    let row: Option<(Option<String>,)> = sqlx::query_as(
        r#"
        SELECT d.oauth_client_id
        FROM refresh_tokens r
        JOIN devices d ON d.id = r.device_id
        WHERE r.token_hash = $1
        "#,
    )
    .bind(hash(presented))
    .fetch_optional(pool)
    .await?;
    Ok(row.and_then(|(c,)| c))
}

/// Which client owns a device install, if any.
///
/// This is what makes a third-party refresh token recognizable at refresh time.
/// Without it, presenting one to the first-party `/v1/auth/token/refresh` would
/// mint a token with no `cid` — a third party escalating itself to full access.
pub async fn device_client_id(
    pool: &PgPool,
    device_id: Uuid,
) -> Result<Option<String>, AppError> {
    let row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT oauth_client_id FROM devices WHERE id = $1")
            .bind(device_id)
            .fetch_optional(pool)
            .await?;
    Ok(row.and_then(|(c,)| c))
}

/// Revoke a single presented refresh token (RFC 7009). Revokes the whole
/// rotation family, since a family is one client's continuous authorization and
/// leaving a sibling live would defeat the revocation.
pub async fn revoke_refresh_for_client(pool: &PgPool, presented: &str) -> Result<bool, AppError> {
    let result = sqlx::query(
        r#"
        UPDATE refresh_tokens
        SET revoked_at = NOW(), revoked_reason = 'client_revocation'
        WHERE family_id = (SELECT family_id FROM refresh_tokens WHERE token_hash = $1)
          AND revoked_at IS NULL
        "#,
    )
    .bind(hash(presented))
    .execute(pool)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// The verified email on file for an account, used for the OIDC `email` claim.
///
/// Prefers the address the account's primary callsign was verified under, and
/// falls back to any verified address it holds.
pub async fn account_email(pool: &PgPool, account_id: Uuid) -> Result<Option<String>, AppError> {
    let email: Option<(Option<String>,)> = sqlx::query_as(
        r#"
        SELECT ac.verified_email
        FROM account_callsigns ac
        JOIN accounts a ON a.id = ac.account_id
        WHERE ac.account_id = $1 AND ac.verified_email IS NOT NULL
        ORDER BY (UPPER(ac.callsign) = UPPER(a.primary_callsign)) DESC, ac.verified_at ASC
        LIMIT 1
        "#,
    )
    .bind(account_id)
    .fetch_optional(pool)
    .await?;
    Ok(email.and_then(|(e,)| e))
}

// ---- token generation ------------------------------------------------------

const OPAQUE_ALPHABET: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

/// Ambiguity-free alphabet for codes a human reads aloud and retypes: no
/// 0/O, 1/I/L, 2/Z, 5/S, 8/B.
const USER_CODE_ALPHABET: &[u8] = b"ACDEFGHJKMNPQRTUVWXY34679";

fn generate_opaque_token() -> String {
    let mut rng = rand::thread_rng();
    (0..48)
        .map(|_| OPAQUE_ALPHABET[rng.gen_range(0..OPAQUE_ALPHABET.len())] as char)
        .collect()
}

fn generate_client_secret() -> String {
    let mut rng = rand::thread_rng();
    let body: String = (0..40)
        .map(|_| OPAQUE_ALPHABET[rng.gen_range(0..OPAQUE_ALPHABET.len())] as char)
        .collect();
    format!("cws_{body}")
}

/// `XXXX-XXXX` — ~25^8 ≈ 2^37 possibilities, over a 15-minute window, behind the
/// per-IP governor.
fn generate_user_code() -> String {
    let mut rng = rand::thread_rng();
    let pick = |rng: &mut rand::rngs::ThreadRng| {
        USER_CODE_ALPHABET[rng.gen_range(0..USER_CODE_ALPHABET.len())] as char
    };
    let left: String = (0..4).map(|_| pick(&mut rng)).collect();
    let right: String = (0..4).map(|_| pick(&mut rng)).collect();
    format!("{left}-{right}")
}

/// Accept what a human actually types: lowercase, missing dash, stray spaces.
pub fn normalize_user_code(input: &str) -> String {
    let cleaned: String = input
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .map(|c| c.to_ascii_uppercase())
        .collect();
    if cleaned.len() == 8 {
        format!("{}-{}", &cleaned[..4], &cleaned[4..])
    } else {
        cleaned
    }
}

/// Purge expired single-use codes. Called from the same maintenance sweep as
/// `db::auth::purge_expired_verifications`.
pub async fn purge_expired_codes(pool: &PgPool) -> Result<u64, AppError> {
    let codes = sqlx::query("DELETE FROM oauth_authorization_codes WHERE expires_at < NOW()")
        .execute(pool)
        .await?
        .rows_affected();
    let devices = sqlx::query("DELETE FROM oauth_device_codes WHERE expires_at < NOW()")
        .execute(pool)
        .await?
        .rows_affected();
    Ok(codes + devices)
}

#[cfg(test)]
mod db_tests {
    use super::*;
    use crate::db::auth as dbauth;

    async fn pool_for_test() -> Option<PgPool> {
        let url = std::env::var("TEST_DATABASE_URL").ok()?;
        PgPool::connect(&url).await.ok()
    }

    macro_rules! db_test {
        ($pool:ident => $body:block) => {{
            let Some($pool) = pool_for_test().await else {
                eprintln!("TEST_DATABASE_URL not set; skipping");
                return;
            };
            $body
        }};
    }

    fn unique_call() -> String {
        format!("T{}", &Uuid::new_v4().simple().to_string()[..7]).to_uppercase()
    }

    fn unique_client_id() -> String {
        format!("cli-{}", &Uuid::new_v4().simple().to_string()[..8])
    }

    async fn seed_client(pool: &PgPool, confidential: bool) -> (OAuthClient, Option<String>) {
        let id = unique_client_id();
        create_client(
            pool,
            NewClient {
                client_id: &id,
                name: "Test Client",
                description: None,
                homepage_url: None,
                redirect_uris: &["https://app.example/cb".to_string()],
                allowed_scopes: "openid sync:read sync:write",
                grant_types: "authorization_code refresh_token device_code",
                created_by: Some("tests"),
            },
            confidential,
        )
        .await
        .expect("create client")
    }

    async fn seed_account(pool: &PgPool) -> Uuid {
        dbauth::create_account_with_callsign(pool, &unique_call(), "directory_email", Some("a@b.c"))
            .await
            .expect("create account")
            .id
    }

    #[tokio::test]
    async fn client_secret_is_stored_hashed_and_verifies() {
        db_test!(pool => {
            let (client, secret) = seed_client(&pool, true).await;
            let secret = secret.expect("confidential client gets a secret");

            let fetched = get_active_client(&pool, &client.client_id).await.unwrap();
            assert!(fetched.verify_secret(&secret));
            assert!(!fetched.verify_secret("cws_wrong"));
            // The plaintext must not be recoverable from the row.
            assert_ne!(fetched.client_secret_hash.unwrap(), secret.as_bytes());
        });
    }

    #[tokio::test]
    async fn public_client_has_no_secret() {
        db_test!(pool => {
            let (client, secret) = seed_client(&pool, false).await;
            assert!(secret.is_none());
            let fetched = get_active_client(&pool, &client.client_id).await.unwrap();
            assert!(fetched.is_public());
        });
    }

    #[tokio::test]
    async fn suspended_clients_stop_transacting() {
        db_test!(pool => {
            let (client, _) = seed_client(&pool, false).await;
            assert!(suspend_client(&pool, &client.client_id).await.unwrap());
            // Still readable for admin listing, but not usable in a flow.
            assert!(get_client(&pool, &client.client_id).await.unwrap().is_some());
            assert!(get_active_client(&pool, &client.client_id).await.is_err());
        });
    }

    /// The single-use guarantee that makes a stolen authorization code useless
    /// after the legitimate client has redeemed it.
    #[tokio::test]
    async fn authorization_code_is_single_use() {
        db_test!(pool => {
            let (client, _) = seed_client(&pool, false).await;
            let account_id = seed_account(&pool).await;

            let code = create_authorization_code(
                &pool, &client.client_id, account_id,
                "https://app.example/cb", "openid sync:read", "challenge", Some("nonce123"),
            ).await.unwrap();

            let first = consume_authorization_code(&pool, &code).await.unwrap();
            let first = first.expect("first redemption succeeds");
            assert_eq!(first.account_id, account_id);
            assert_eq!(first.scopes, "openid sync:read");
            assert_eq!(first.code_challenge, "challenge");
            assert_eq!(first.nonce.as_deref(), Some("nonce123"));

            // Replay yields nothing.
            assert!(consume_authorization_code(&pool, &code).await.unwrap().is_none());
        });
    }

    #[tokio::test]
    async fn unknown_authorization_code_is_rejected() {
        db_test!(pool => {
            assert!(consume_authorization_code(&pool, "not-a-real-code").await.unwrap().is_none());
        });
    }

    #[tokio::test]
    async fn device_code_approval_flow() {
        db_test!(pool => {
            let (client, _) = seed_client(&pool, false).await;
            let account_id = seed_account(&pool).await;

            let issued = create_device_code(&pool, &client.client_id, "openid sync:read")
                .await.unwrap();

            // Nothing decided yet.
            assert!(matches!(
                poll_device_code(&pool, &issued.device_code).await.unwrap(),
                DevicePollOutcome::Pending
            ));

            // Polling again immediately trips the interval guard.
            assert!(matches!(
                poll_device_code(&pool, &issued.device_code).await.unwrap(),
                DevicePollOutcome::SlowDown
            ));

            assert!(decide_device_code(
                &pool, &issued.user_code, account_id, true, "openid sync:read",
            ).await.unwrap());

            // Clear the interval guard so the next poll is not a slow_down.
            sqlx::query("UPDATE oauth_device_codes SET last_polled_at = NOW() - INTERVAL '1 hour' WHERE user_code = $1")
                .bind(&issued.user_code).execute(&pool).await.unwrap();

            match poll_device_code(&pool, &issued.device_code).await.unwrap() {
                DevicePollOutcome::Approved { account_id: got, scopes } => {
                    assert_eq!(got, account_id);
                    assert_eq!(scopes, "openid sync:read");
                }
                _ => panic!("expected approval"),
            }

            // Consumed: a second exchange of the same device code must fail.
            assert!(matches!(
                poll_device_code(&pool, &issued.device_code).await.unwrap(),
                DevicePollOutcome::Invalid
            ));
        });
    }

    #[tokio::test]
    async fn device_code_denial_is_terminal() {
        db_test!(pool => {
            let (client, _) = seed_client(&pool, false).await;
            let account_id = seed_account(&pool).await;
            let issued = create_device_code(&pool, &client.client_id, "openid").await.unwrap();

            assert!(decide_device_code(&pool, &issued.user_code, account_id, false, "openid")
                .await.unwrap());

            // A second decision on the same code is refused, so an attacker who
            // learns a user code cannot flip a denial into an approval.
            assert!(!decide_device_code(&pool, &issued.user_code, account_id, true, "openid")
                .await.unwrap());

            sqlx::query("UPDATE oauth_device_codes SET last_polled_at = NULL WHERE user_code = $1")
                .bind(&issued.user_code).execute(&pool).await.unwrap();
            assert!(matches!(
                poll_device_code(&pool, &issued.device_code).await.unwrap(),
                DevicePollOutcome::Denied
            ));
        });
    }

    #[tokio::test]
    async fn user_code_lookup_accepts_what_a_human_types() {
        db_test!(pool => {
            let (client, _) = seed_client(&pool, false).await;
            let issued = create_device_code(&pool, &client.client_id, "openid").await.unwrap();

            let sloppy = issued.user_code.to_lowercase().replace('-', "");
            let found = find_device_code_by_user_code(&pool, &sloppy).await.unwrap();
            assert!(found.is_some(), "lowercase, dash-less code should still resolve");
        });
    }

    #[tokio::test]
    async fn grants_round_trip_and_revocation_drops_client_devices() {
        db_test!(pool => {
            let (client, _) = seed_client(&pool, false).await;
            let account_id = seed_account(&pool).await;

            upsert_grant(&pool, account_id, &client.client_id, "openid sync:read").await.unwrap();
            assert_eq!(
                get_grant(&pool, account_id, &client.client_id).await.unwrap().as_deref(),
                Some("openid sync:read")
            );

            // Re-granting widens in place rather than creating a second row.
            upsert_grant(&pool, account_id, &client.client_id, "openid sync:read sync:write")
                .await.unwrap();
            let listed = list_grants(&pool, account_id).await.unwrap();
            assert_eq!(listed.len(), 1);
            assert_eq!(listed[0].scopes, "openid sync:read sync:write");
            assert_eq!(listed[0].client_name, "Test Client");

            // A device install + refresh token, as issued after consent.
            let device_id = create_client_device(&pool, account_id, &client.client_id, "Test Client")
                .await.unwrap();
            let refresh = dbauth::issue_initial_refresh(&pool, device_id, account_id, "sync:read")
                .await.unwrap();
            assert_eq!(
                client_id_for_refresh(&pool, &refresh.token).await.unwrap().as_deref(),
                Some(client.client_id.as_str())
            );

            assert!(revoke_grant(&pool, account_id, &client.client_id).await.unwrap());
            assert!(get_grant(&pool, account_id, &client.client_id).await.unwrap().is_none());
            assert!(list_grants(&pool, account_id).await.unwrap().is_empty());
            // The refresh token went with the device, so the client cannot mint again.
            assert!(client_id_for_refresh(&pool, &refresh.token).await.unwrap().is_none());
        });
    }

    /// First-party installs must remain distinguishable from client-owned ones —
    /// this is what `/v1/auth/token/refresh` keys its third-party rejection on.
    #[tokio::test]
    async fn first_party_refresh_tokens_have_no_client() {
        db_test!(pool => {
            let account_id = seed_account(&pool).await;
            let device = dbauth::create_device(&pool, account_id, Some("iPhone"), Some("ios"))
                .await.unwrap();
            let refresh = dbauth::issue_initial_refresh(&pool, device.id, account_id, "sync:read")
                .await.unwrap();

            assert!(client_id_for_refresh(&pool, &refresh.token).await.unwrap().is_none());
            assert!(device_client_id(&pool, device.id).await.unwrap().is_none());
        });
    }

    #[tokio::test]
    async fn revoking_a_refresh_token_kills_its_whole_family() {
        db_test!(pool => {
            let (client, _) = seed_client(&pool, false).await;
            let account_id = seed_account(&pool).await;
            let device_id = create_client_device(&pool, account_id, &client.client_id, "Test Client")
                .await.unwrap();
            let refresh = dbauth::issue_initial_refresh(&pool, device_id, account_id, "sync:read")
                .await.unwrap();

            assert!(revoke_refresh_for_client(&pool, &refresh.token).await.unwrap());
            assert!(matches!(
                dbauth::rotate_refresh(&pool, &refresh.token).await.unwrap(),
                dbauth::RotationOutcome::ReuseDetected | dbauth::RotationOutcome::Invalid
            ));
        });
    }

    #[tokio::test]
    async fn account_email_resolves_the_verified_address() {
        db_test!(pool => {
            let cs = unique_call();
            let account = dbauth::create_account_with_callsign(
                &pool, &cs, "directory_email", Some("op@example.com"),
            ).await.unwrap();
            assert_eq!(
                account_email(&pool, account.id).await.unwrap().as_deref(),
                Some("op@example.com")
            );
        });
    }

    #[tokio::test]
    async fn expired_codes_are_purged() {
        db_test!(pool => {
            let (client, _) = seed_client(&pool, false).await;
            let account_id = seed_account(&pool).await;
            let code = create_authorization_code(
                &pool, &client.client_id, account_id,
                "https://app.example/cb", "openid", "challenge", None,
            ).await.unwrap();

            // Scoped to THIS test's client: tests share a database and run in
            // parallel, so an unqualified UPDATE would expire codes out from
            // under whatever else is mid-flight.
            sqlx::query(
                "UPDATE oauth_authorization_codes SET expires_at = NOW() - INTERVAL '1 hour' \
                 WHERE client_id = $1",
            )
            .bind(&client.client_id)
            .execute(&pool).await.unwrap();
            purge_expired_codes(&pool).await.unwrap();

            assert!(consume_authorization_code(&pool, &code).await.unwrap().is_none());
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn client(secret_hash: Option<Vec<u8>>, scopes: &str, redirects: &[&str]) -> OAuthClient {
        OAuthClient {
            client_id: "test".into(),
            client_secret_hash: secret_hash,
            name: "Test".into(),
            description: None,
            homepage_url: None,
            redirect_uris: redirects.iter().map(|s| s.to_string()).collect(),
            allowed_scopes: scopes.into(),
            grant_types: "authorization_code refresh_token".into(),
            status: "active".into(),
        }
    }

    #[test]
    fn redirect_match_is_exact() {
        let c = client(None, "openid", &["https://app.example/cb"]);
        assert!(c.allows_redirect("https://app.example/cb"));
        // Prefix, subpath, and query variants are all rejected — these are the
        // shapes used to smuggle codes to an attacker-controlled endpoint.
        assert!(!c.allows_redirect("https://app.example/cb/evil"));
        assert!(!c.allows_redirect("https://app.example/cb?x=1"));
        assert!(!c.allows_redirect("https://app.example"));
        assert!(!c.allows_redirect("https://evil.example/cb"));
    }

    #[test]
    fn scopes_clamp_to_the_client_ceiling() {
        let c = client(None, "openid sync:read", &[]);
        let requested = vec![
            "openid".to_string(),
            "sync:read".to_string(),
            "sync:write".to_string(),
        ];
        assert_eq!(c.clamp_scopes(&requested), vec!["openid", "sync:read"]);
    }

    #[test]
    fn public_client_cannot_authenticate_with_a_secret() {
        let c = client(None, "openid", &[]);
        assert!(!c.verify_secret(""));
        assert!(!c.verify_secret("anything"));
    }

    #[test]
    fn confidential_client_verifies_its_secret() {
        let secret = "cws_abc123";
        let c = client(Some(hash(secret)), "openid", &[]);
        assert!(c.verify_secret(secret));
        assert!(!c.verify_secret("cws_wrong"));
    }

    #[test]
    fn grant_type_gate() {
        let c = client(None, "openid", &[]);
        assert!(c.allows_grant("authorization_code"));
        assert!(!c.allows_grant("device_code"));
    }

    #[test]
    fn user_codes_avoid_ambiguous_characters() {
        for _ in 0..200 {
            let code = generate_user_code();
            assert_eq!(code.len(), 9);
            assert_eq!(code.as_bytes()[4], b'-');
            for c in code.chars().filter(|c| *c != '-') {
                assert!(
                    !"01I2S5B8OLZ".contains(c),
                    "ambiguous character {c} in user code {code}"
                );
            }
        }
    }

    #[test]
    fn user_code_normalization_is_forgiving() {
        assert_eq!(normalize_user_code("krwg-zptl"), "KRWG-ZPTL");
        assert_eq!(normalize_user_code("krwgzptl"), "KRWG-ZPTL");
        assert_eq!(normalize_user_code(" KRWG ZPTL "), "KRWG-ZPTL");
    }
}
