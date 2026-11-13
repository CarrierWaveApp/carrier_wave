//! OAuth account / device / refresh-token persistence — Phase 5.
//!
//! The security-critical logic lives here: account creation (with the deferred
//! primary-callsign FK), `assert_account_owns_callsign` (F6 IDOR guard), and
//! idempotent refresh rotation with family reuse-detection (F4).
//!
//! Design: docs/plans/2026-06-21-phase5-oauth-overhaul.md (§5, §7, §9).

use chrono::{DateTime, Duration, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::tokens::{
    generate_refresh_token, hash_code, hash_token, verify_pkce, FAMILY_MAX_AGE_DAYS,
    REFRESH_TTL_DAYS, ROTATION_GRACE_SECS,
};
use crate::error::AppError;

/// Magic-link verification lifetime.
pub const VERIFICATION_TTL_MINUTES: i64 = 15;

/// Verification tiers (D6). Only `directory_email` may inherit legacy
/// callsign-keyed data or affect competitive surfaces.
pub const METHOD_DIRECTORY: &str = "directory_email";
pub const METHOD_USER: &str = "user_email";

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Account {
    pub id: Uuid,
    pub primary_callsign: String,
    pub status: String,
    pub tokens_valid_after: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Device {
    pub id: Uuid,
    pub account_id: Uuid,
    pub device_name: Option<String>,
    pub platform: Option<String>,
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct RefreshToken {
    pub id: Uuid,
    pub device_id: Uuid,
    pub account_id: Uuid,
    pub family_id: Uuid,
    pub scopes: String,
    pub issued_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
    pub family_started_at: DateTime<Utc>,
    pub rotated_at: Option<DateTime<Utc>>,
    pub revoked_at: Option<DateTime<Utc>>,
}

/// Plaintext refresh token + its persisted row. Plaintext is returned to the
/// client exactly once.
pub struct IssuedRefresh {
    pub token: String,
    pub row: RefreshToken,
}

/// Outcome of presenting a refresh token for rotation.
pub enum RotationOutcome {
    /// Normal rotation (or in-grace replay) — a fresh pair was issued.
    Rotated(IssuedRefresh),
    /// Token was replayed outside the grace window (or a revoked token was
    /// presented): the whole family is now revoked. Force re-auth (F4).
    ReuseDetected,
    /// Unknown, expired, or past-absolute-age token. Force re-auth, no revoke.
    Invalid,
}

/// Create a brand-new account whose first verified callsign is `callsign`.
/// Account + first callsign land in one transaction (the primary-callsign FK is
/// `DEFERRABLE INITIALLY DEFERRED`).
pub async fn create_account_with_callsign(
    pool: &PgPool,
    callsign: &str,
    method: &str,
    email: Option<&str>,
) -> Result<Account, AppError> {
    let callsign = callsign.to_uppercase();
    let mut tx = pool.begin().await?;

    let account_id = Uuid::new_v4();
    let account = sqlx::query_as::<_, Account>(
        r#"
        INSERT INTO accounts (id, primary_callsign)
        VALUES ($1, $2)
        RETURNING id, primary_callsign, status, tokens_valid_after, created_at
        "#,
    )
    .bind(account_id)
    .bind(&callsign)
    .fetch_one(&mut *tx)
    .await?;

    insert_callsign(&mut tx, account_id, &callsign, method, email).await?;

    tx.commit().await?;
    Ok(account)
}

/// Fetch an account by id.
pub async fn get_account(pool: &PgPool, id: Uuid) -> Result<Option<Account>, AppError> {
    let account = sqlx::query_as::<_, Account>(
        r#"
        SELECT id, primary_callsign, status, tokens_valid_after, created_at
        FROM accounts WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;
    Ok(account)
}

/// Attach an additional verified callsign to an existing account (D8).
pub async fn attach_callsign(
    pool: &PgPool,
    account_id: Uuid,
    callsign: &str,
    method: &str,
    email: Option<&str>,
) -> Result<(), AppError> {
    let callsign = callsign.to_uppercase();
    let mut tx = pool.begin().await?;
    insert_callsign(&mut tx, account_id, &callsign, method, email).await?;
    tx.commit().await?;
    Ok(())
}

async fn insert_callsign(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    account_id: Uuid,
    callsign: &str,
    method: &str,
    email: Option<&str>,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        INSERT INTO account_callsigns (account_id, callsign, verification_method, verified_email)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind(account_id)
    .bind(callsign)
    .bind(method)
    .bind(email)
    .execute(&mut **tx)
    .await
    .map_err(|e| {
        if let sqlx::Error::Database(ref db) = e {
            // Either the global case-insensitive unique index or the PK.
            if db.is_unique_violation() {
                return AppError::CallsignTaken {
                    callsign: callsign.to_string(),
                };
            }
        }
        AppError::Database(e)
    })?;
    Ok(())
}

/// The verification tier under which `account_id` holds `callsign`, or `None`
/// if it doesn't hold it at all.
pub async fn account_callsign_method(
    pool: &PgPool,
    account_id: Uuid,
    callsign: &str,
) -> Result<Option<String>, AppError> {
    let method = sqlx::query_scalar::<_, String>(
        r#"
        SELECT verification_method FROM account_callsigns
        WHERE account_id = $1 AND UPPER(callsign) = UPPER($2)
        "#,
    )
    .bind(account_id)
    .bind(callsign)
    .fetch_optional(pool)
    .await?;
    Ok(method)
}

/// An existing account that already holds a callsign, with the address it
/// verified that callsign under. Used to route a new-device sign-in's magic link
/// to the account's ON-FILE email (never a fresh user-supplied one — that would
/// be account takeover).
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct CallsignAccount {
    pub account_id: Uuid,
    pub verified_email: Option<String>,
    pub method: String,
}

/// The account that already owns `callsign` (case-insensitive), if any. `None`
/// means the callsign is unclaimed → onboarding a new account.
pub async fn find_account_for_callsign(
    pool: &PgPool,
    callsign: &str,
) -> Result<Option<CallsignAccount>, AppError> {
    let row = sqlx::query_as::<_, CallsignAccount>(
        r#"
        SELECT account_id, verified_email, verification_method AS method
        FROM account_callsigns
        WHERE UPPER(callsign) = UPPER($1)
        "#,
    )
    .bind(callsign)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// F6 IDOR guard: every callsign-scoped mutation must call this. Returns
/// `Forbidden` if the account hasn't verified the callsign.
pub async fn assert_account_owns_callsign(
    pool: &PgPool,
    account_id: Uuid,
    callsign: &str,
) -> Result<(), AppError> {
    match account_callsign_method(pool, account_id, callsign).await? {
        Some(_) => Ok(()),
        None => Err(AppError::Forbidden),
    }
}

/// Register a new client install.
pub async fn create_device(
    pool: &PgPool,
    account_id: Uuid,
    device_name: Option<&str>,
    platform: Option<&str>,
) -> Result<Device, AppError> {
    let device = sqlx::query_as::<_, Device>(
        r#"
        INSERT INTO devices (id, account_id, device_name, platform)
        VALUES ($1, $2, $3, $4)
        RETURNING id, account_id, device_name, platform
        "#,
    )
    .bind(Uuid::new_v4())
    .bind(account_id)
    .bind(device_name)
    .bind(platform)
    .fetch_one(pool)
    .await?;
    Ok(device)
}

/// Issue the first refresh token of a new family (new device login).
pub async fn issue_initial_refresh(
    pool: &PgPool,
    device_id: Uuid,
    account_id: Uuid,
    scopes: &str,
) -> Result<IssuedRefresh, AppError> {
    let now = Utc::now();
    insert_refresh(pool, device_id, account_id, Uuid::new_v4(), scopes, now).await
}

async fn insert_refresh(
    executor: &PgPool,
    device_id: Uuid,
    account_id: Uuid,
    family_id: Uuid,
    scopes: &str,
    family_started_at: DateTime<Utc>,
) -> Result<IssuedRefresh, AppError> {
    let token = generate_refresh_token();
    let hash = hash_token(&token);
    let now = Utc::now();
    let row = sqlx::query_as::<_, RefreshToken>(
        r#"
        INSERT INTO refresh_tokens
            (id, device_id, account_id, family_id, token_hash, scopes, issued_at, expires_at, family_started_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING id, device_id, account_id, family_id, scopes, issued_at, expires_at,
                  family_started_at, rotated_at, revoked_at
        "#,
    )
    .bind(Uuid::new_v4())
    .bind(device_id)
    .bind(account_id)
    .bind(family_id)
    .bind(&hash)
    .bind(scopes)
    .bind(now)
    .bind(now + Duration::days(REFRESH_TTL_DAYS))
    .bind(family_started_at)
    .fetch_one(executor)
    .await?;
    Ok(IssuedRefresh { token, row })
}

/// Rotate a presented refresh token (F4). Idempotent within the grace window so
/// concurrent/retried refreshes from app+widget+watch don't self-DoS; replay
/// outside the window (or of a revoked token) revokes the whole family.
pub async fn rotate_refresh(pool: &PgPool, presented: &str) -> Result<RotationOutcome, AppError> {
    let hash = hash_token(presented);
    let now = Utc::now();
    let mut tx = pool.begin().await?;

    let Some(row) = sqlx::query_as::<_, RefreshToken>(
        r#"
        SELECT id, device_id, account_id, family_id, scopes, issued_at, expires_at,
               family_started_at, rotated_at, revoked_at
        FROM refresh_tokens WHERE token_hash = $1
        "#,
    )
    .bind(&hash)
    .fetch_optional(&mut *tx)
    .await?
    else {
        return Ok(RotationOutcome::Invalid);
    };

    // Serialize concurrent rotations within the family.
    sqlx::query("SELECT 1 FROM refresh_tokens WHERE family_id = $1 FOR UPDATE")
        .bind(row.family_id)
        .execute(&mut *tx)
        .await?;

    // Past the absolute family lifetime → force full re-auth (F12).
    if now > row.family_started_at + Duration::days(FAMILY_MAX_AGE_DAYS) {
        revoke_family_tx(&mut tx, row.family_id, "absolute_age").await?;
        tx.commit().await?;
        return Ok(RotationOutcome::Invalid);
    }

    // Presenting a revoked token = reuse on a dead family.
    if row.revoked_at.is_some() {
        revoke_family_tx(&mut tx, row.family_id, "reuse_detected").await?;
        tx.commit().await?;
        return Ok(RotationOutcome::ReuseDetected);
    }

    if let Some(rotated_at) = row.rotated_at {
        // Already-rotated token re-presented.
        let within_grace = now <= rotated_at + Duration::seconds(ROTATION_GRACE_SECS);
        if within_grace {
            // Concurrent/retried refresh — rotate whatever is currently live
            // instead of revoking (idempotent-enough; never self-DoS).
            if let Some(live) = live_token_in_family(&mut tx, row.family_id).await? {
                let issued = rotate_one_tx(&mut tx, &live).await?;
                tx.commit().await?;
                return Ok(RotationOutcome::Rotated(issued));
            }
        }
        revoke_family_tx(&mut tx, row.family_id, "reuse_detected").await?;
        tx.commit().await?;
        return Ok(RotationOutcome::ReuseDetected);
    }

    // The live token. Expired by the sliding window → re-auth, no revoke.
    if now > row.expires_at {
        tx.commit().await?;
        return Ok(RotationOutcome::Invalid);
    }

    let issued = rotate_one_tx(&mut tx, &row).await?;
    tx.commit().await?;
    Ok(RotationOutcome::Rotated(issued))
}

async fn live_token_in_family(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    family_id: Uuid,
) -> Result<Option<RefreshToken>, AppError> {
    let row = sqlx::query_as::<_, RefreshToken>(
        r#"
        SELECT id, device_id, account_id, family_id, scopes, issued_at, expires_at,
               family_started_at, rotated_at, revoked_at
        FROM refresh_tokens
        WHERE family_id = $1 AND rotated_at IS NULL AND revoked_at IS NULL
        "#,
    )
    .bind(family_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row)
}

/// Mark `row` rotated and insert its successor (same family/device/account/scopes).
async fn rotate_one_tx(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    row: &RefreshToken,
) -> Result<IssuedRefresh, AppError> {
    let token = generate_refresh_token();
    let hash = hash_token(&token);
    let now = Utc::now();
    let new_id = Uuid::new_v4();

    // Order matters across two constraints: retire the old row FIRST so the
    // "one live per family" partial unique index isn't violated, but link
    // `replaced_by` LAST (after the successor exists) so the self-FK holds.
    sqlx::query("UPDATE refresh_tokens SET rotated_at = $1 WHERE id = $2")
        .bind(now)
        .bind(row.id)
        .execute(&mut **tx)
        .await?;

    sqlx::query(
        r#"
        INSERT INTO refresh_tokens
            (id, device_id, account_id, family_id, token_hash, scopes, issued_at, expires_at, family_started_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        "#,
    )
    .bind(new_id)
    .bind(row.device_id)
    .bind(row.account_id)
    .bind(row.family_id)
    .bind(&hash)
    .bind(&row.scopes)
    .bind(now)
    .bind(now + Duration::days(REFRESH_TTL_DAYS))
    .bind(row.family_started_at)
    .execute(&mut **tx)
    .await?;

    sqlx::query("UPDATE refresh_tokens SET replaced_by = $1 WHERE id = $2")
        .bind(new_id)
        .bind(row.id)
        .execute(&mut **tx)
        .await?;

    let new_row = sqlx::query_as::<_, RefreshToken>(
        r#"
        SELECT id, device_id, account_id, family_id, scopes, issued_at, expires_at,
               family_started_at, rotated_at, revoked_at
        FROM refresh_tokens WHERE id = $1
        "#,
    )
    .bind(new_id)
    .fetch_one(&mut **tx)
    .await?;

    Ok(IssuedRefresh {
        token,
        row: new_row,
    })
}

async fn revoke_family_tx(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    family_id: Uuid,
    reason: &str,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        UPDATE refresh_tokens
        SET revoked_at = NOW(), revoked_reason = $2
        WHERE family_id = $1 AND revoked_at IS NULL
        "#,
    )
    .bind(family_id)
    .bind(reason)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

/// Revoke a single device's family (logout this device).
pub async fn revoke_family(pool: &PgPool, family_id: Uuid, reason: &str) -> Result<(), AppError> {
    let mut tx = pool.begin().await?;
    revoke_family_tx(&mut tx, family_id, reason).await?;
    tx.commit().await?;
    Ok(())
}

/// Revoke every family for an account AND bump `tokens_valid_after` so any
/// still-valid access JWT is rejected on its next use (logout everywhere).
pub async fn revoke_account(pool: &PgPool, account_id: Uuid, reason: &str) -> Result<(), AppError> {
    let mut tx = pool.begin().await?;
    sqlx::query(
        r#"
        UPDATE refresh_tokens SET revoked_at = NOW(), revoked_reason = $2
        WHERE account_id = $1 AND revoked_at IS NULL
        "#,
    )
    .bind(account_id)
    .bind(reason)
    .execute(&mut *tx)
    .await?;
    sqlx::query("UPDATE accounts SET tokens_valid_after = NOW() WHERE id = $1")
        .bind(account_id)
        .execute(&mut *tx)
        .await?;
    // Propagate to every instance's revocation cache (D10/F3). Fires on commit.
    sqlx::query("SELECT pg_notify($1, $2)")
        .bind(crate::auth::revocation::REVOCATION_CHANNEL)
        .bind(account_id.to_string())
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(())
}

/// A device row for the account's session list.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceSummary {
    pub id: Uuid,
    pub device_name: Option<String>,
    pub platform: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_seen_at: DateTime<Utc>,
}

/// List an account's registered devices, newest-seen first.
pub async fn list_devices(pool: &PgPool, account_id: Uuid) -> Result<Vec<DeviceSummary>, AppError> {
    let rows = sqlx::query_as::<_, DeviceSummary>(
        r#"
        SELECT id, device_name, platform, created_at, last_seen_at
        FROM devices WHERE account_id = $1
        ORDER BY last_seen_at DESC
        "#,
    )
    .bind(account_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Revoke a specific device for an account: revoke its refresh families and
/// delete the device. Returns whether a device was removed (ownership-scoped, F6).
pub async fn revoke_device(
    pool: &PgPool,
    account_id: Uuid,
    device_id: Uuid,
) -> Result<bool, AppError> {
    let mut tx = pool.begin().await?;
    sqlx::query(
        r#"
        UPDATE refresh_tokens SET revoked_at = NOW(), revoked_reason = 'device_removed'
        WHERE device_id = $1 AND account_id = $2 AND revoked_at IS NULL
        "#,
    )
    .bind(device_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await?;
    let res = sqlx::query("DELETE FROM devices WHERE id = $1 AND account_id = $2")
        .bind(device_id)
        .bind(account_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(res.rows_affected() > 0)
}

/// What a successfully-exchanged verification proves.
pub struct VerificationClaim {
    pub callsign: String,
    pub email: String,
    pub method: String,
    /// Set when this was an attach-to-existing-account flow (D8); `None` = onboarding.
    pub account_id: Option<Uuid>,
}

/// Create a magic-link verification challenge. `code` plaintext is emailed; only
/// its hash is stored. `pkce_challenge` binds redemption to the requesting
/// device (F8). `poll_token` plaintext is returned to the app by verify/start
/// (only its hash is stored) so it can poll for completion (O4). `account_id`
/// non-null = attach-to-existing-account (D8).
#[allow(clippy::too_many_arguments)]
pub async fn create_email_verification(
    pool: &PgPool,
    callsign: &str,
    email: &str,
    code: &str,
    method: &str,
    account_id: Option<Uuid>,
    pkce_challenge: &str,
    poll_token: &str,
    request_ip: Option<&str>,
) -> Result<(), AppError> {
    let now = Utc::now();
    sqlx::query(
        r#"
        INSERT INTO email_verifications
            (id, callsign, email, code_hash, method, account_id, pkce_challenge, poll_token_hash, request_ip, expires_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        "#,
    )
    .bind(Uuid::new_v4())
    .bind(callsign.to_uppercase())
    .bind(email)
    .bind(hash_code(code))
    .bind(method)
    .bind(account_id)
    .bind(pkce_challenge)
    .bind(hash_token(poll_token))
    .bind(request_ip)
    .bind(now + Duration::minutes(VERIFICATION_TTL_MINUTES))
    .execute(pool)
    .await?;
    Ok(())
}

/// Mark the magic link clicked (verify/complete). Single-use, attempt-bounded,
/// not-yet-expired. Returns whether a pending verification matched.
pub async fn mark_verification_clicked(pool: &PgPool, code: &str) -> Result<bool, AppError> {
    let affected = sqlx::query(
        r#"
        UPDATE email_verifications
        SET consumed_at = NOW(), attempts = attempts + 1
        WHERE code_hash = $1 AND consumed_at IS NULL AND expires_at > NOW()
        "#,
    )
    .bind(hash_code(code))
    .execute(pool)
    .await?;
    Ok(affected.rows_affected() == 1)
}

/// Exchange a clicked verification for its claim, enforcing PKCE device binding
/// (F8). Consumes the row (single-use). `Ok(None)` = no clicked, unexpired row;
/// `Err(Forbidden)` = PKCE mismatch (stolen link without the app's verifier).
pub async fn exchange_verification(
    pool: &PgPool,
    code: &str,
    pkce_verifier: &str,
) -> Result<Option<VerificationClaim>, AppError> {
    #[derive(sqlx::FromRow)]
    struct Row {
        id: Uuid,
        callsign: String,
        email: String,
        method: String,
        account_id: Option<Uuid>,
        pkce_challenge: String,
    }

    let mut tx = pool.begin().await?;
    let Some(row) = sqlx::query_as::<_, Row>(
        r#"
        SELECT id, callsign, email, method, account_id, pkce_challenge
        FROM email_verifications
        WHERE code_hash = $1 AND consumed_at IS NOT NULL AND expires_at > NOW()
        FOR UPDATE
        "#,
    )
    .bind(hash_code(code))
    .fetch_optional(&mut *tx)
    .await?
    else {
        return Ok(None);
    };

    if !verify_pkce(pkce_verifier, &row.pkce_challenge) {
        // Don't consume — let the legitimate app retry with the right verifier
        // until expiry. The leaked-link holder still can't proceed.
        return Err(AppError::Forbidden);
    }

    // Single-use: delete on successful exchange.
    sqlx::query("DELETE FROM email_verifications WHERE id = $1")
        .bind(row.id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    Ok(Some(VerificationClaim {
        callsign: row.callsign,
        email: row.email,
        method: row.method,
        account_id: row.account_id,
    }))
}

/// Outcome of polling a verification by its poll token (O4).
pub enum PollResult {
    /// No matching clicked-and-unexpired verification yet. The app keeps polling
    /// and times out on its own. Returned for unknown / not-yet-clicked / expired
    /// tokens alike, so every poll looks identical until success (no deliverability
    /// enumeration — F7).
    Pending,
    /// The link was clicked and the PKCE verifier matched — issue tokens.
    Claim(VerificationClaim),
}

/// Poll a verification by its `poll_token` (O4 polling return path). Returns
/// `Claim` only when the magic link has been clicked (`consumed_at` set), the
/// row is unexpired, and the presented PKCE verifier matches (F8); the row is
/// then consumed (single-use). Anything else — unknown token, link not yet
/// clicked, expired — is `Pending` so the poll surface never leaks whether a
/// callsign was deliverable (F7). A clicked row with a mismatched verifier is
/// `Forbidden` (a poll-token holder without the app's verifier), not consumed,
/// so the legitimate app can still complete.
pub async fn poll_verification(
    pool: &PgPool,
    poll_token: &str,
    pkce_verifier: &str,
) -> Result<PollResult, AppError> {
    #[derive(sqlx::FromRow)]
    struct Row {
        id: Uuid,
        callsign: String,
        email: String,
        method: String,
        account_id: Option<Uuid>,
        pkce_challenge: String,
    }

    let mut tx = pool.begin().await?;
    let Some(row) = sqlx::query_as::<_, Row>(
        r#"
        SELECT id, callsign, email, method, account_id, pkce_challenge
        FROM email_verifications
        WHERE poll_token_hash = $1 AND consumed_at IS NOT NULL AND expires_at > NOW()
        FOR UPDATE
        "#,
    )
    .bind(hash_token(poll_token))
    .fetch_optional(&mut *tx)
    .await?
    else {
        return Ok(PollResult::Pending);
    };

    if !verify_pkce(pkce_verifier, &row.pkce_challenge) {
        return Err(AppError::Forbidden);
    }

    sqlx::query("DELETE FROM email_verifications WHERE id = $1")
        .bind(row.id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    Ok(PollResult::Claim(VerificationClaim {
        callsign: row.callsign,
        email: row.email,
        method: row.method,
        account_id: row.account_id,
    }))
}

/// Purge consumed/expired verifications (retention; call periodically — F10/PII).
pub async fn purge_expired_verifications(pool: &PgPool) -> Result<u64, AppError> {
    let res = sqlx::query(
        "DELETE FROM email_verifications WHERE expires_at < NOW() - INTERVAL '7 days' OR consumed_at IS NOT NULL AND created_at < NOW() - INTERVAL '7 days'",
    )
    .execute(pool)
    .await?;
    Ok(res.rows_affected())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auth::tokens::{generate_poll_token, generate_verification_code, pkce_challenge_for};

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

    #[tokio::test]
    async fn create_account_and_ownership_guard() {
        db_test!(pool => {
            let cs = unique_call();
            let acct = create_account_with_callsign(&pool, &cs, METHOD_DIRECTORY, Some("a@b.c"))
                .await.unwrap();
            assert_eq!(acct.primary_callsign, cs);
            // Owns its callsign (directory tier).
            assert_eq!(account_callsign_method(&pool, acct.id, &cs).await.unwrap().as_deref(), Some(METHOD_DIRECTORY));
            assert!(assert_account_owns_callsign(&pool, acct.id, &cs).await.is_ok());
            // Does NOT own a different callsign → Forbidden (F6).
            assert!(matches!(assert_account_owns_callsign(&pool, acct.id, "ZZ9ZZ").await, Err(AppError::Forbidden)));
        });
    }

    #[tokio::test]
    async fn callsign_claim_is_exclusive() {
        db_test!(pool => {
            let cs = unique_call();
            create_account_with_callsign(&pool, &cs, METHOD_DIRECTORY, None).await.unwrap();
            // A second account can't claim the same callsign (land-grab guard).
            let err = create_account_with_callsign(&pool, &cs.to_lowercase(), METHOD_USER, None).await;
            assert!(matches!(err, Err(AppError::CallsignTaken { .. })));
        });
    }

    #[tokio::test]
    async fn find_account_for_callsign_returns_owner() {
        db_test!(pool => {
            let cs = unique_call();
            let acct = create_account_with_callsign(&pool, &cs, METHOD_USER, Some("a@b.co"))
                .await.unwrap();
            // Case-insensitive lookup returns the owner + its on-file email/tier.
            let found = find_account_for_callsign(&pool, &cs.to_lowercase()).await.unwrap().unwrap();
            assert_eq!(found.account_id, acct.id);
            assert_eq!(found.verified_email.as_deref(), Some("a@b.co"));
            assert_eq!(found.method, METHOD_USER);
            // An unclaimed callsign → None (onboarding territory).
            assert!(find_account_for_callsign(&pool, "ZZ9ZZ").await.unwrap().is_none());
        });
    }

    #[tokio::test]
    async fn attach_second_callsign_records_tier() {
        db_test!(pool => {
            let cs1 = unique_call();
            let cs2 = unique_call();
            let acct = create_account_with_callsign(&pool, &cs1, METHOD_DIRECTORY, None).await.unwrap();
            attach_callsign(&pool, acct.id, &cs2, METHOD_USER, Some("u@x.y")).await.unwrap();
            assert_eq!(account_callsign_method(&pool, acct.id, &cs2).await.unwrap().as_deref(), Some(METHOD_USER));
        });
    }

    #[tokio::test]
    async fn refresh_rotation_happy_path_and_grace_replay() {
        db_test!(pool => {
            let cs = unique_call();
            let acct = create_account_with_callsign(&pool, &cs, METHOD_DIRECTORY, None).await.unwrap();
            let dev = create_device(&pool, acct.id, Some("iPhone"), Some("ios")).await.unwrap();
            let first = issue_initial_refresh(&pool, dev.id, acct.id, "sync:read").await.unwrap();

            // Normal rotation issues a new token.
            let out = rotate_refresh(&pool, &first.token).await.unwrap();
            let second = match out { RotationOutcome::Rotated(i) => i, _ => panic!("expected Rotated") };
            assert_ne!(first.token, second.token);

            // Re-presenting the OLD token within the grace window must NOT revoke
            // the family — it returns a fresh token (F4 self-DoS guard).
            let out2 = rotate_refresh(&pool, &first.token).await.unwrap();
            assert!(matches!(out2, RotationOutcome::Rotated(_)));
        });
    }

    #[tokio::test]
    async fn refresh_reuse_outside_grace_revokes_family() {
        db_test!(pool => {
            let cs = unique_call();
            let acct = create_account_with_callsign(&pool, &cs, METHOD_DIRECTORY, None).await.unwrap();
            let dev = create_device(&pool, acct.id, None, None).await.unwrap();
            let first = issue_initial_refresh(&pool, dev.id, acct.id, "sync:read").await.unwrap();
            let _second = rotate_refresh(&pool, &first.token).await.unwrap();

            // Simulate the grace window having elapsed by ageing the rotation.
            sqlx::query("UPDATE refresh_tokens SET rotated_at = NOW() - INTERVAL '120 seconds' WHERE family_id = $1 AND rotated_at IS NOT NULL")
                .bind(first.row.family_id).execute(&pool).await.unwrap();

            // Replaying the old token now is true reuse → family revoked.
            let out = rotate_refresh(&pool, &first.token).await.unwrap();
            assert!(matches!(out, RotationOutcome::ReuseDetected));

            // The (previously live) successor is now revoked too.
            let live = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM refresh_tokens WHERE family_id = $1 AND revoked_at IS NULL")
                .bind(first.row.family_id).fetch_one(&pool).await.unwrap();
            assert_eq!(live, 0);
        });
    }

    #[tokio::test]
    async fn unknown_token_is_invalid() {
        db_test!(pool => {
            assert!(matches!(rotate_refresh(&pool, "cwr_deadbeef").await.unwrap(), RotationOutcome::Invalid));
        });
    }

    #[tokio::test]
    async fn verification_flow_with_pkce_binding() {
        db_test!(pool => {
            let cs = unique_call();
            let code = generate_verification_code();
            let verifier = "app-device-verifier-xyz";
            let challenge = pkce_challenge_for(verifier);
            let poll = generate_poll_token();
            create_email_verification(&pool, &cs, "u@x.y", &code, METHOD_USER, None, &challenge, &poll, Some("1.2.3.4"))
                .await.unwrap();

            // Can't exchange before the link is clicked.
            assert!(exchange_verification(&pool, &code, verifier).await.unwrap().is_none());

            // Click the link.
            assert!(mark_verification_clicked(&pool, &code).await.unwrap());
            // Clicking again fails (single-use of the click).
            assert!(!mark_verification_clicked(&pool, &code).await.unwrap());

            // Wrong PKCE verifier (leaked link without the app) → Forbidden (F8).
            assert!(matches!(exchange_verification(&pool, &code, "stolen-no-verifier").await, Err(AppError::Forbidden)));

            // Correct verifier → claim, and the row is consumed.
            let claim = exchange_verification(&pool, &code, verifier).await.unwrap().unwrap();
            assert_eq!(claim.callsign, cs);
            assert_eq!(claim.method, METHOD_USER);
            assert!(claim.account_id.is_none());
            assert!(exchange_verification(&pool, &code, verifier).await.unwrap().is_none());
        });
    }

    #[tokio::test]
    async fn poll_flow_pending_until_clicked_then_claims() {
        db_test!(pool => {
            let cs = unique_call();
            let code = generate_verification_code();
            let verifier = "app-device-verifier-poll";
            let challenge = pkce_challenge_for(verifier);
            let poll = generate_poll_token();
            create_email_verification(&pool, &cs, "u@x.y", &code, METHOD_USER, None, &challenge, &poll, None)
                .await.unwrap();

            // Unknown poll token → Pending (no enumeration, F7).
            assert!(matches!(poll_verification(&pool, "cwp_nope", verifier).await.unwrap(), PollResult::Pending));
            // Known token, link not yet clicked → Pending.
            assert!(matches!(poll_verification(&pool, &poll, verifier).await.unwrap(), PollResult::Pending));

            // Click the link, then poll with a wrong verifier → Forbidden, row NOT consumed.
            assert!(mark_verification_clicked(&pool, &code).await.unwrap());
            assert!(matches!(poll_verification(&pool, &poll, "stolen-no-verifier").await, Err(AppError::Forbidden)));

            // Correct verifier → Claim, and the row is consumed (next poll Pending).
            let result = poll_verification(&pool, &poll, verifier).await.unwrap();
            let claim = match result { PollResult::Claim(c) => c, PollResult::Pending => panic!("expected Claim") };
            assert_eq!(claim.callsign, cs);
            assert!(claim.account_id.is_none());
            assert!(matches!(poll_verification(&pool, &poll, verifier).await.unwrap(), PollResult::Pending));
        });
    }
}
