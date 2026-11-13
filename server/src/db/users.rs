use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::User;

pub async fn get_user_by_callsign(pool: &PgPool, callsign: &str) -> Result<Option<User>, AppError> {
    let user = sqlx::query_as::<_, User>(
        r#"
        SELECT id, callsign, created_at
        FROM users
        WHERE callsign = $1
        "#,
    )
    .bind(callsign)
    .fetch_optional(pool)
    .await?;

    Ok(user)
}

pub async fn get_user_by_id(pool: &PgPool, user_id: Uuid) -> Result<Option<User>, AppError> {
    let user = sqlx::query_as::<_, User>(
        r#"
        SELECT id, callsign, created_at
        FROM users
        WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    Ok(user)
}

pub async fn search_users(pool: &PgPool, query: &str, limit: i64) -> Result<Vec<User>, AppError> {
    let pattern = format!("%{}%", query.to_uppercase());
    let users = sqlx::query_as::<_, User>(
        r#"
        SELECT id, callsign, created_at
        FROM users
        WHERE UPPER(callsign) LIKE $1
        ORDER BY callsign
        LIMIT $2
        "#,
    )
    .bind(&pattern)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(users)
}

/// Delete a user account and all associated data.
/// Deletes from callsign-based tables (no FK cascade) first,
/// then deletes the user row (which cascades to friend_requests,
/// friendships, friend_invites, and activities).
/// Also deletes participant records (auth tokens).
pub async fn delete_user_account(pool: &PgPool, callsign: &str) -> Result<u64, AppError> {
    let callsign_upper = callsign.to_uppercase();

    let mut tx = pool.begin().await?;

    // Delete from callsign-based tables (no FK cascade from users)
    sqlx::query("DELETE FROM participants WHERE callsign = $1")
        .bind(&callsign_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("DELETE FROM challenge_participants WHERE callsign = $1")
        .bind(&callsign_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("DELETE FROM progress WHERE callsign = $1")
        .bind(&callsign_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("DELETE FROM earned_badges WHERE callsign = $1")
        .bind(&callsign_upper)
        .execute(&mut *tx)
        .await?;

    // Delete user row (cascades to: friend_requests, friendships,
    // friend_invites, activities)
    let result = sqlx::query("DELETE FROM users WHERE callsign = $1")
        .bind(&callsign_upper)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;

    Ok(result.rows_affected())
}

pub async fn get_user_counts(pool: &PgPool) -> Result<(i64, i64, i64), AppError> {
    let row = sqlx::query_as::<_, (i64, i64, i64)>(
        r#"
        SELECT
            COUNT(*) AS total,
            COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days') AS last_7,
            COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days') AS last_30
        FROM users
        "#,
    )
    .fetch_one(pool)
    .await?;

    Ok(row)
}

pub async fn get_active_users_by_hour(
    pool: &PgPool,
    days: i32,
) -> Result<Vec<crate::models::UserCountByHour>, AppError> {
    let rows = sqlx::query_as::<_, crate::models::UserCountByHour>(
        r#"
        SELECT date_trunc('hour', created_at) AS hour,
               COUNT(DISTINCT callsign) AS count
        FROM activities
        WHERE created_at >= NOW() - make_interval(days => $1)
        GROUP BY hour
        ORDER BY hour
        "#,
    )
    .bind(days)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Change a user's callsign across all callsign-keyed tables in a single transaction.
/// Records the change in callsign_history for audit.
/// Does NOT update pota_activations or pota_hunter_qsos (external data).
pub async fn change_callsign(
    pool: &PgPool,
    user_id: Uuid,
    old_callsign: &str,
    new_callsign: &str,
    // The caller's authenticated account, if any. Legacy `fd_` device tokens
    // carry `None`. Used to gate the Phase 5 identity rewrite (CAR-307).
    caller_account_id: Option<Uuid>,
) -> Result<User, AppError> {
    let old_upper = old_callsign.to_uppercase();
    let new_upper = new_callsign.to_uppercase();

    // Phase 5 OAuth identity. `accounts.primary_callsign` is what every token
    // re-mint stamps into the JWT `cs` claim and what the auth middleware
    // resolves the acting callsign from — left stale, every later request acts
    // as the old callsign (and recreates participants/users rows under it).
    //
    // SECURITY (CAR-307): re-pointing a verified callsign and `primary_callsign`
    // silently transfers a Phase 5 account's identity — migration 044 documents
    // the claim as "exclusive + permanent". Only the account that actually owns
    // the old callsign may do this, and only by proving control of it: gate the
    // identity rewrite on the caller's authenticated `account_id` matching the
    // account resolved from the old callsign.
    //
    // CAR-349: when the old callsign IS account-owned but the caller can't prove
    // it (legacy `fd_` token → `None`, or a different account), refuse outright
    // instead of renaming only the legacy callsign-keyed tables. The partial
    // rename left `users`/`participants` under the new call while the account
    // kept acting as the old one — a split identity the client experienced as
    // "the callsign reverts on every restart" and friends saw as the old call.
    let owning_account = sqlx::query_scalar::<_, Uuid>(
        "SELECT account_id FROM account_callsigns WHERE UPPER(callsign) = UPPER($1)",
    )
    .bind(&old_upper)
    .fetch_optional(pool)
    .await?;
    let identity_account = match (owning_account, caller_account_id) {
        (None, _) => None,
        (Some(owner), Some(caller)) if owner == caller => Some(owner),
        (Some(_), _) => return Err(AppError::Forbidden),
    };

    // Check if new callsign is already taken
    let existing = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM users WHERE callsign = $1 AND id != $2",
    )
    .bind(&new_upper)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    if let Some(renamed_user_id) = existing {
        // CAR-349 repair: if the row holding the new callsign is *this user's
        // own* earlier half-applied rename (old → new recorded in
        // callsign_history for that row) and the caller owns the old callsign,
        // this is the split identity described above, not a collision. Finish
        // the job: re-point the account, then fold whatever accrued under the
        // stale old-callsign row back into the renamed one.
        let Some(account_id) = identity_account else {
            return Err(AppError::CallsignTaken {
                callsign: new_upper,
            });
        };
        let half_applied = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM callsign_history WHERE user_id = $1 AND old_callsign = $2 AND new_callsign = $3)",
        )
        .bind(renamed_user_id)
        .bind(&old_upper)
        .bind(&new_upper)
        .fetch_one(pool)
        .await?;
        if !half_applied {
            return Err(AppError::CallsignTaken {
                callsign: new_upper,
            });
        }
        return repair_half_applied_callsign_change(
            pool,
            account_id,
            user_id,
            renamed_user_id,
            &old_upper,
            &new_upper,
        )
        .await;
    }

    let mut tx = pool.begin().await?;

    // Update all callsign-keyed tables
    sqlx::query("UPDATE participants SET callsign = $1 WHERE callsign = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE challenge_participants SET callsign = $1 WHERE callsign = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE progress SET callsign = $1 WHERE callsign = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE earned_badges SET callsign = $1 WHERE callsign = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE activities SET callsign = $1 WHERE callsign = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE club_members SET callsign = $1 WHERE callsign = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE events SET submitted_by = $1 WHERE submitted_by = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE spots SET callsign = $1 WHERE callsign = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE upload_error_telemetry SET callsign = $1 WHERE callsign = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE user_achievements SET callsign = $1 WHERE callsign = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE spot_markers SET callsign = $1 WHERE callsign = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE macros SET author_callsign = $1 WHERE author_callsign = $2")
        .bind(&new_upper)
        .bind(&old_upper)
        .execute(&mut *tx)
        .await?;

    // The /v1/clubs ETag fingerprint is GREATEST(clubs.updated_at,
    // club_members.joined_at); rewriting club_members.callsign moves neither,
    // so without this bump clients keep getting 304s with the old callsign in
    // the roster.
    sqlx::query(
        "UPDATE clubs SET updated_at = NOW() WHERE id IN (SELECT club_id FROM club_members WHERE callsign = $1)",
    )
    .bind(&new_upper)
    .execute(&mut *tx)
    .await?;

    // Re-point the verified-callsign claim and the primary (ownership was
    // established above), then bump `tokens_valid_after` so outstanding access
    // tokens carrying the old `cs` die now instead of at natural expiry.
    // Refresh tokens stay valid, so devices recover silently with tokens
    // minted under the new call. A pure legacy user (old callsign never
    // verified by any account) has no identity to move.
    if let Some(account_id) = identity_account {
        rewrite_account_identity(&mut tx, account_id, &old_upper, &new_upper).await?;
    }

    // Update the users table last
    let user = sqlx::query_as::<_, User>(
        r#"
        UPDATE users SET callsign = $1
        WHERE id = $2
        RETURNING id, callsign, created_at
        "#,
    )
    .bind(&new_upper)
    .bind(user_id)
    .fetch_one(&mut *tx)
    .await?;

    // Record the change in history
    sqlx::query(
        r#"
        INSERT INTO callsign_history (user_id, old_callsign, new_callsign)
        VALUES ($1, $2, $3)
        "#,
    )
    .bind(user_id)
    .bind(&old_upper)
    .bind(&new_upper)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    Ok(user)
}

/// Move a Phase 5 account's verified callsign + primary from `old` to `new`
/// and revoke its outstanding access tokens. Caller has already established
/// that `account_id` owns `old`. The global unique index on
/// UPPER(account_callsigns.callsign) still refuses a call already claimed by
/// another account.
async fn rewrite_account_identity(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    account_id: Uuid,
    old_upper: &str,
    new_upper: &str,
) -> Result<(), AppError> {
    sqlx::query(
        "UPDATE account_callsigns SET callsign = $1 WHERE account_id = $2 AND UPPER(callsign) = UPPER($3)",
    )
    .bind(new_upper)
    .bind(account_id)
    .bind(old_upper)
    .execute(&mut **tx)
    .await
    .map_err(|e| {
        if let sqlx::Error::Database(ref db) = e {
            if db.is_unique_violation() {
                return AppError::CallsignTaken {
                    callsign: new_upper.to_string(),
                };
            }
        }
        AppError::Database(e)
    })?;

    sqlx::query(
        "UPDATE accounts SET primary_callsign = $1, tokens_valid_after = NOW() WHERE id = $2",
    )
    .bind(new_upper)
    .bind(account_id)
    .execute(&mut **tx)
    .await?;

    // Propagate the token kill to every instance's revocation cache
    // (D10/F3). Fires on commit.
    sqlx::query("SELECT pg_notify($1, $2)")
        .bind(crate::auth::revocation::REVOCATION_CHANNEL)
        .bind(account_id.to_string())
        .execute(&mut **tx)
        .await?;

    Ok(())
}

/// CAR-349: finish a callsign change that an earlier legacy-token request
/// half-applied. `renamed_user_id` already carries `new` (with the old → new
/// rename in callsign_history); `stale_user_id` is the row the middleware /
/// handlers recreated under `old` while the account still pointed there.
/// Re-points the account identity, then merges the stale row (friendships,
/// requests, activities, callsign-keyed rows, participants) into the renamed
/// one and deletes it. Returns the surviving user.
async fn repair_half_applied_callsign_change(
    pool: &PgPool,
    account_id: Uuid,
    stale_user_id: Uuid,
    renamed_user_id: Uuid,
    old_upper: &str,
    new_upper: &str,
) -> Result<User, AppError> {
    let mut tx = pool.begin().await?;
    rewrite_account_identity(&mut tx, account_id, old_upper, new_upper).await?;
    tx.commit().await?;

    merge_previous_account(pool, renamed_user_id, stale_user_id, old_upper, new_upper).await?;

    get_user_by_id(pool, renamed_user_id)
        .await?
        .ok_or(AppError::UserNotFound {
            user_id: renamed_user_id,
        })
}

/// Merge an old (previous callsign) user account into the current user.
/// Transfers all UUID-keyed data (friendships, friend_requests, activities)
/// and callsign-keyed data from the old user to the current user,
/// then deletes the old user record.
pub async fn merge_previous_account(
    pool: &PgPool,
    current_user_id: Uuid,
    old_user_id: Uuid,
    old_callsign: &str,
    new_callsign: &str,
) -> Result<(), AppError> {
    let mut tx = pool.begin().await?;

    // Transfer UUID-keyed relationships: friendships
    // Re-point old_user's friendships to current_user (skip duplicates)
    sqlx::query(
        r#"
        UPDATE friendships SET user_id = $1
        WHERE user_id = $2
        AND NOT EXISTS (
            SELECT 1 FROM friendships f2
            WHERE f2.user_id = $1 AND f2.friend_id = friendships.friend_id
        )
        "#,
    )
    .bind(current_user_id)
    .bind(old_user_id)
    .execute(&mut *tx)
    .await?;

    // Also transfer where old user is the friend side
    sqlx::query(
        r#"
        UPDATE friendships SET friend_id = $1
        WHERE friend_id = $2
        AND NOT EXISTS (
            SELECT 1 FROM friendships f2
            WHERE f2.friend_id = $1 AND f2.user_id = friendships.user_id
        )
        "#,
    )
    .bind(current_user_id)
    .bind(old_user_id)
    .execute(&mut *tx)
    .await?;

    // Transfer friend_requests
    sqlx::query(
        r#"
        UPDATE friend_requests SET from_user_id = $1
        WHERE from_user_id = $2
        AND NOT EXISTS (
            SELECT 1 FROM friend_requests f2
            WHERE f2.from_user_id = $1 AND f2.to_user_id = friend_requests.to_user_id
        )
        "#,
    )
    .bind(current_user_id)
    .bind(old_user_id)
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        r#"
        UPDATE friend_requests SET to_user_id = $1
        WHERE to_user_id = $2
        AND NOT EXISTS (
            SELECT 1 FROM friend_requests f2
            WHERE f2.to_user_id = $1 AND f2.from_user_id = friend_requests.from_user_id
        )
        "#,
    )
    .bind(current_user_id)
    .bind(old_user_id)
    .execute(&mut *tx)
    .await?;

    // Transfer activities (UUID-keyed via user_id)
    sqlx::query("UPDATE activities SET user_id = $1, callsign = $3 WHERE user_id = $2")
        .bind(current_user_id)
        .bind(old_user_id)
        .bind(new_callsign)
        .execute(&mut *tx)
        .await?;

    // Transfer callsign-keyed data from old callsign
    sqlx::query(
        "UPDATE challenge_participants SET callsign = $1 WHERE callsign = $2",
    )
    .bind(new_callsign)
    .bind(old_callsign)
    .execute(&mut *tx)
    .await?;

    sqlx::query("UPDATE progress SET callsign = $1 WHERE callsign = $2")
        .bind(new_callsign)
        .bind(old_callsign)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE earned_badges SET callsign = $1 WHERE callsign = $2")
        .bind(new_callsign)
        .bind(old_callsign)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE club_members SET callsign = $1 WHERE callsign = $2")
        .bind(new_callsign)
        .bind(old_callsign)
        .execute(&mut *tx)
        .await?;

    sqlx::query("UPDATE spots SET callsign = $1 WHERE callsign = $2")
        .bind(new_callsign)
        .bind(old_callsign)
        .execute(&mut *tx)
        .await?;

    // Record the merge in callsign_history
    sqlx::query(
        r#"
        INSERT INTO callsign_history (user_id, old_callsign, new_callsign)
        VALUES ($1, $2, $3)
        "#,
    )
    .bind(current_user_id)
    .bind(old_callsign)
    .bind(new_callsign)
    .execute(&mut *tx)
    .await?;

    // Delete old user's remaining orphaned data then the user itself.
    // CASCADE handles friendships/friend_requests that weren't transferred (duplicates).
    sqlx::query("DELETE FROM participants WHERE callsign = $1")
        .bind(old_callsign)
        .execute(&mut *tx)
        .await?;

    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(old_user_id)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;

    Ok(())
}

pub async fn get_or_create_user(pool: &PgPool, callsign: &str) -> Result<User, AppError> {
    let user = sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (callsign)
        VALUES ($1)
        ON CONFLICT (callsign) DO UPDATE SET callsign = EXCLUDED.callsign
        RETURNING id, callsign, created_at
        "#,
    )
    .bind(callsign)
    .fetch_one(pool)
    .await?;

    Ok(user)
}
