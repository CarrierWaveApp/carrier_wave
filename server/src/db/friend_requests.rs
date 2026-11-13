use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::{FriendRequest, FriendRequestWithCallsigns, Friendship};

pub async fn create_friend_request(
    pool: &PgPool,
    from_user_id: Uuid,
    to_user_id: Uuid,
) -> Result<FriendRequestWithCallsigns, AppError> {
    let request = sqlx::query_as::<_, FriendRequestWithCallsigns>(
        r#"
        -- CAR-332: friend_requests has UNIQUE(from_user_id, to_user_id). A bare
        -- INSERT hit the constraint (HTTP 500, no recovery) whenever a terminal-
        -- state row already existed — i.e. after a decline, or after an unfriend
        -- left an 'accepted' row behind. Revive the existing row to 'pending'
        -- instead so re-sending a request always works.
        INSERT INTO friend_requests (from_user_id, to_user_id)
        VALUES ($1, $2)
        ON CONFLICT (from_user_id, to_user_id) DO UPDATE
            SET status = 'pending', requested_at = now(), responded_at = NULL
        RETURNING
            friend_requests.id,
            friend_requests.from_user_id,
            (SELECT callsign FROM users WHERE id = friend_requests.from_user_id) as from_callsign,
            friend_requests.to_user_id,
            (SELECT callsign FROM users WHERE id = friend_requests.to_user_id) as to_callsign,
            friend_requests.status,
            friend_requests.requested_at,
            friend_requests.responded_at
        "#,
    )
    .bind(from_user_id)
    .bind(to_user_id)
    .fetch_one(pool)
    .await?;

    Ok(request)
}

pub async fn get_friend_request(
    pool: &PgPool,
    request_id: Uuid,
) -> Result<Option<FriendRequest>, AppError> {
    let request = sqlx::query_as::<_, FriendRequest>(
        r#"
        SELECT id, from_user_id, to_user_id, status, requested_at, responded_at
        FROM friend_requests
        WHERE id = $1
        "#,
    )
    .bind(request_id)
    .fetch_optional(pool)
    .await?;

    Ok(request)
}

pub async fn get_friend_request_with_callsigns(
    pool: &PgPool,
    request_id: Uuid,
) -> Result<Option<FriendRequestWithCallsigns>, AppError> {
    let request = sqlx::query_as::<_, FriendRequestWithCallsigns>(
        r#"
        SELECT
            fr.id,
            fr.from_user_id,
            (SELECT callsign FROM users WHERE id = fr.from_user_id) as from_callsign,
            fr.to_user_id,
            (SELECT callsign FROM users WHERE id = fr.to_user_id) as to_callsign,
            fr.status,
            fr.requested_at,
            fr.responded_at
        FROM friend_requests fr
        WHERE fr.id = $1
        "#,
    )
    .bind(request_id)
    .fetch_optional(pool)
    .await?;

    Ok(request)
}

pub async fn get_pending_request_between(
    pool: &PgPool,
    user_id_1: Uuid,
    user_id_2: Uuid,
) -> Result<Option<FriendRequest>, AppError> {
    let request = sqlx::query_as::<_, FriendRequest>(
        r#"
        SELECT id, from_user_id, to_user_id, status, requested_at, responded_at
        FROM friend_requests
        WHERE status = 'pending'
          AND ((from_user_id = $1 AND to_user_id = $2)
               OR (from_user_id = $2 AND to_user_id = $1))
        "#,
    )
    .bind(user_id_1)
    .bind(user_id_2)
    .fetch_optional(pool)
    .await?;

    Ok(request)
}

pub async fn are_friends(
    pool: &PgPool,
    user_id_1: Uuid,
    user_id_2: Uuid,
) -> Result<bool, AppError> {
    let friendship = sqlx::query_as::<_, Friendship>(
        r#"
        SELECT id, user_id, friend_id, created_at
        FROM friendships
        WHERE (user_id = $1 AND friend_id = $2)
           OR (user_id = $2 AND friend_id = $1)
        "#,
    )
    .bind(user_id_1)
    .bind(user_id_2)
    .fetch_optional(pool)
    .await?;

    Ok(friendship.is_some())
}

pub async fn accept_friend_request(
    pool: &PgPool,
    request_id: Uuid,
) -> Result<Option<FriendRequestWithCallsigns>, AppError> {
    let mut tx = pool.begin().await?;

    // Update request status
    let request = sqlx::query_as::<_, FriendRequestWithCallsigns>(
        r#"
        UPDATE friend_requests
        SET status = 'accepted', responded_at = now()
        WHERE id = $1 AND status = 'pending'
        RETURNING
            id,
            from_user_id,
            (SELECT callsign FROM users WHERE id = friend_requests.from_user_id) as from_callsign,
            to_user_id,
            (SELECT callsign FROM users WHERE id = friend_requests.to_user_id) as to_callsign,
            status,
            requested_at,
            responded_at
        "#,
    )
    .bind(request_id)
    .fetch_optional(&mut *tx)
    .await?;

    if let Some(ref req) = request {
        // Create bidirectional friendship entries
        sqlx::query(
            r#"
            INSERT INTO friendships (user_id, friend_id)
            VALUES ($1, $2), ($2, $1)
            ON CONFLICT DO NOTHING
            "#,
        )
        .bind(req.from_user_id)
        .bind(req.to_user_id)
        .execute(&mut *tx)
        .await?;
    }

    tx.commit().await?;
    Ok(request)
}

pub async fn decline_friend_request(
    pool: &PgPool,
    request_id: Uuid,
) -> Result<Option<FriendRequest>, AppError> {
    let request = sqlx::query_as::<_, FriendRequest>(
        r#"
        UPDATE friend_requests
        SET status = 'declined', responded_at = now()
        WHERE id = $1 AND status = 'pending'
        RETURNING id, from_user_id, to_user_id, status, requested_at, responded_at
        "#,
    )
    .bind(request_id)
    .fetch_optional(pool)
    .await?;

    Ok(request)
}

/// Find registered users from a list of callsigns, excluding:
/// - The requesting user
/// - Users already friends with the requester
/// - Users with pending friend requests (either direction)
pub async fn find_suggested_friends(
    pool: &PgPool,
    user_id: Uuid,
    callsigns: &[String],
) -> Result<Vec<crate::models::User>, AppError> {
    if callsigns.is_empty() {
        return Ok(vec![]);
    }

    let users = sqlx::query_as::<_, crate::models::User>(
        r#"
        SELECT u.id, u.callsign, u.created_at
        FROM users u
        WHERE UPPER(u.callsign) = ANY(
            SELECT UPPER(unnest($2::text[]))
        )
        AND u.id != $1
        AND u.id NOT IN (
            SELECT friend_id FROM friendships WHERE user_id = $1
        )
        AND u.id NOT IN (
            SELECT to_user_id FROM friend_requests
            WHERE from_user_id = $1 AND status = 'pending'
            UNION
            SELECT from_user_id FROM friend_requests
            WHERE to_user_id = $1 AND status = 'pending'
        )
        "#,
    )
    .bind(user_id)
    .bind(callsigns)
    .fetch_all(pool)
    .await?;

    Ok(users)
}

/// A friend entry with callsign, for the friends list response.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct FriendWithCallsign {
    pub friendship_id: Uuid,
    pub user_id: Uuid,
    pub callsign: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// Get all accepted friends for a user.
pub async fn get_friends_for_user(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<Vec<FriendWithCallsign>, AppError> {
    let friends = sqlx::query_as::<_, FriendWithCallsign>(
        r#"
        SELECT f.id as friendship_id, u.id as user_id, u.callsign, f.created_at
        FROM friendships f
        JOIN users u ON u.id = f.friend_id
        WHERE f.user_id = $1
        ORDER BY u.callsign
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(friends)
}

/// Get all pending friend requests for a user (both incoming and outgoing).
pub async fn get_pending_requests_for_user(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<Vec<FriendRequestWithCallsigns>, AppError> {
    let requests = sqlx::query_as::<_, FriendRequestWithCallsigns>(
        r#"
        SELECT
            fr.id,
            fr.from_user_id,
            (SELECT callsign FROM users WHERE id = fr.from_user_id) as from_callsign,
            fr.to_user_id,
            (SELECT callsign FROM users WHERE id = fr.to_user_id) as to_callsign,
            fr.status,
            fr.requested_at,
            fr.responded_at
        FROM friend_requests fr
        WHERE fr.status = 'pending'
          AND (fr.from_user_id = $1 OR fr.to_user_id = $1)
        ORDER BY fr.requested_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(requests)
}

/// Remove a friendship (both directions) by friendship ID.
/// Returns true if the friendship existed and was removed.
pub async fn remove_friendship(
    pool: &PgPool,
    friendship_id: Uuid,
    user_id: Uuid,
) -> Result<bool, AppError> {
    // First verify this friendship belongs to the requesting user
    let friendship = sqlx::query_as::<_, Friendship>(
        r#"
        SELECT id, user_id, friend_id, created_at
        FROM friendships
        WHERE id = $1 AND user_id = $2
        "#,
    )
    .bind(friendship_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    let Some(friendship) = friendship else {
        return Ok(false);
    };

    // CAR-332: delete both friendship directions AND the now-stale friend_requests
    // rows in one transaction. Previously the 'accepted' request row was left
    // behind, so after unfriending, a fresh request tripped the unique constraint
    // and the two users could never re-friend.
    let mut tx = pool.begin().await?;

    sqlx::query(
        r#"
        DELETE FROM friendships
        WHERE (user_id = $1 AND friend_id = $2)
           OR (user_id = $2 AND friend_id = $1)
        "#,
    )
    .bind(friendship.user_id)
    .bind(friendship.friend_id)
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        r#"
        DELETE FROM friend_requests
        WHERE (from_user_id = $1 AND to_user_id = $2)
           OR (from_user_id = $2 AND to_user_id = $1)
        "#,
    )
    .bind(friendship.user_id)
    .bind(friendship.friend_id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    Ok(true)
}
