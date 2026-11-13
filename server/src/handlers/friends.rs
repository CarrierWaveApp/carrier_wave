use axum::{
    extract::{Extension, State},
    http::StatusCode,
};

use crate::extractors::{Json, Path};
use sqlx::PgPool;

use crate::auth::AuthContext;
use crate::config::Config;
use crate::db;
use crate::error::AppError;
use crate::models::{CreateFriendRequestBody, FriendInviteResponse, FriendRequestResponse};

use super::DataResponse;

/// GET /v1/friends/invite-link
/// Generate a new friend invite link for the authenticated user
pub async fn get_invite_link(
    State(pool): State<PgPool>,
    Extension(config): Extension<Config>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<DataResponse<FriendInviteResponse>>, AppError> {
    // Get or create user record for this callsign
    let user = db::get_or_create_user(&pool, &auth.callsign).await?;

    // Create a new invite
    let invite = db::create_friend_invite(&pool, user.id, config.invite_expiry_days).await?;

    Ok(Json(DataResponse {
        data: invite.into_response(&config.invite_base_url),
    }))
}

/// POST /v1/friends/requests
/// Create a friend request either by user ID or invite token
pub async fn create_friend_request(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Json(body): Json<CreateFriendRequestBody>,
) -> Result<(StatusCode, Json<DataResponse<FriendRequestResponse>>), AppError> {
    // Get or create user record for the sender
    let sender = db::get_or_create_user(&pool, &auth.callsign).await?;

    // Determine the target user
    let target_user_id = match (&body.to_user_id, &body.invite_token) {
        (Some(user_id), None) => {
            // Direct user ID specified
            let target = db::get_user_by_id(&pool, *user_id)
                .await?
                .ok_or(AppError::UserNotFound { user_id: *user_id })?;
            target.id
        }
        (None, Some(token)) => {
            // Invite token specified
            let invite = db::get_valid_friend_invite(&pool, token)
                .await?
                .ok_or_else(|| AppError::FriendInviteNotFound {
                    token: token.clone(),
                })?;

            // Mark the invite as used
            db::mark_invite_used(&pool, token, sender.id).await?;

            invite.user_id
        }
        (Some(_), Some(_)) => {
            return Err(AppError::Validation {
                message: "Provide either toUserId or inviteToken, not both".to_string(),
            });
        }
        (None, None) => {
            return Err(AppError::Validation {
                message: "Either toUserId or inviteToken is required".to_string(),
            });
        }
    };

    // Cannot friend yourself
    if sender.id == target_user_id {
        return Err(AppError::CannotFriendSelf);
    }

    // Check if already friends
    if db::are_friends(&pool, sender.id, target_user_id).await? {
        return Err(AppError::AlreadyFriends);
    }

    // Check if a pending request already exists (in either direction)
    if db::get_pending_request_between(&pool, sender.id, target_user_id)
        .await?
        .is_some()
    {
        return Err(AppError::FriendRequestExists);
    }

    // Create the friend request
    let request = db::create_friend_request(&pool, sender.id, target_user_id).await?;

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: request.into(),
        }),
    ))
}

/// POST /v1/friends/suggestions
/// Given a list of callsigns, return which ones are registered users
/// (excluding already-friends and pending requests)
pub async fn get_friend_suggestions(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Json(body): Json<crate::models::FriendSuggestionsBody>,
) -> Result<Json<DataResponse<Vec<crate::models::FriendSuggestionResponse>>>, AppError> {
    if body.callsigns.is_empty() {
        return Ok(Json(DataResponse { data: vec![] }));
    }

    // Cap at 100 callsigns to prevent abuse
    let callsigns: Vec<String> = body.callsigns.into_iter().take(100).collect();

    // Get or create user record for the authenticated user
    let user = db::get_or_create_user(&pool, &auth.callsign).await?;

    // Find registered users from the provided callsigns
    let suggested_users = db::find_suggested_friends(&pool, user.id, &callsigns).await?;

    let suggestions = suggested_users
        .into_iter()
        .map(|u| crate::models::FriendSuggestionResponse {
            user_id: u.id,
            callsign: u.callsign,
        })
        .collect();

    Ok(Json(DataResponse { data: suggestions }))
}

/// GET /v1/friends
/// List all accepted friends for the authenticated user
pub async fn list_friends(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<DataResponse<Vec<crate::models::FriendResponse>>>, AppError> {
    let user = db::get_or_create_user(&pool, &auth.callsign).await?;
    let friends = db::get_friends_for_user(&pool, user.id).await?;

    let data = friends
        .into_iter()
        .map(|f| crate::models::FriendResponse {
            friendship_id: f.friendship_id,
            callsign: f.callsign,
            user_id: f.user_id,
            accepted_at: f.created_at,
        })
        .collect();

    Ok(Json(DataResponse { data }))
}

/// GET /v1/friends/requests/pending
/// List all pending friend requests (incoming and outgoing) for the authenticated user
pub async fn list_pending_requests(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<DataResponse<crate::models::PendingRequestsResponse>>, AppError> {
    let user = db::get_or_create_user(&pool, &auth.callsign).await?;
    let requests = db::get_pending_requests_for_user(&pool, user.id).await?;

    let mut incoming = Vec::new();
    let mut outgoing = Vec::new();

    for req in requests {
        let response: crate::models::FriendRequestResponse = req.clone().into();
        if req.to_user_id == user.id {
            incoming.push(response);
        } else {
            outgoing.push(response);
        }
    }

    Ok(Json(DataResponse {
        data: crate::models::PendingRequestsResponse { incoming, outgoing },
    }))
}

/// POST /v1/friends/requests/:id/accept
/// Accept a pending friend request
pub async fn accept_friend_request(
    State(pool): State<PgPool>,
    Path(request_id): Path<uuid::Uuid>,
    Extension(auth): Extension<AuthContext>,
) -> Result<
    (
        StatusCode,
        Json<DataResponse<crate::models::FriendRequestResponse>>,
    ),
    AppError,
> {
    let user = db::get_or_create_user(&pool, &auth.callsign).await?;

    // Verify the request exists and is addressed to this user
    let request = db::get_friend_request(&pool, request_id)
        .await?
        .ok_or(AppError::FriendRequestNotFound { request_id })?;

    if request.to_user_id != user.id {
        return Err(AppError::Forbidden);
    }

    // Idempotent: if already accepted, return the existing record so a duplicate
    // tap (or a retry from a 2nd device) doesn't surface a 404 to the client.
    let accepted = if request.status == "accepted" {
        db::get_friend_request_with_callsigns(&pool, request_id)
            .await?
            .ok_or(AppError::FriendRequestNotFound { request_id })?
    } else {
        db::accept_friend_request(&pool, request_id)
            .await?
            .ok_or(AppError::FriendRequestNotFound { request_id })?
    };

    Ok((
        StatusCode::OK,
        Json(DataResponse {
            data: accepted.into(),
        }),
    ))
}

/// POST /v1/friends/requests/:id/decline
/// Decline a pending friend request
pub async fn decline_friend_request(
    State(pool): State<PgPool>,
    Path(request_id): Path<uuid::Uuid>,
    Extension(auth): Extension<AuthContext>,
) -> Result<StatusCode, AppError> {
    let user = db::get_or_create_user(&pool, &auth.callsign).await?;

    // Verify the request exists and is addressed to this user
    let request = db::get_friend_request(&pool, request_id)
        .await?
        .ok_or(AppError::FriendRequestNotFound { request_id })?;

    if request.to_user_id != user.id {
        return Err(AppError::Forbidden);
    }

    db::decline_friend_request(&pool, request_id)
        .await?
        .ok_or(AppError::FriendRequestNotFound { request_id })?;

    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /v1/friends/:id
/// Remove an existing friend
pub async fn remove_friend(
    State(pool): State<PgPool>,
    Path(friendship_id): Path<uuid::Uuid>,
    Extension(auth): Extension<AuthContext>,
) -> Result<StatusCode, AppError> {
    let user = db::get_or_create_user(&pool, &auth.callsign).await?;

    let removed = db::remove_friendship(&pool, friendship_id, user.id).await?;

    if !removed {
        return Err(AppError::FriendshipNotFound { friendship_id });
    }

    Ok(StatusCode::NO_CONTENT)
}
