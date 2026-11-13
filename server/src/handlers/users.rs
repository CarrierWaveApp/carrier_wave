use axum::extract::{Query, State};
use serde::Deserialize;
use sqlx::PgPool;

use crate::db;
use crate::error::AppError;
use crate::extractors::Json;
use crate::models::UserSearchResponse;

use super::DataResponse;

#[derive(Debug, Deserialize)]
pub struct SearchUsersQuery {
    pub q: String,
}

/// GET /v1/users/search?q=...
/// Search for users by callsign (public, no auth required)
pub async fn search_users(
    State(pool): State<PgPool>,
    Query(query): Query<SearchUsersQuery>,
) -> Result<Json<DataResponse<Vec<UserSearchResponse>>>, AppError> {
    if query.q.len() < 2 {
        return Ok(Json(DataResponse { data: vec![] }));
    }

    let users = db::search_users(&pool, &query.q, 20).await?;

    let results: Vec<UserSearchResponse> = users.into_iter().map(|u| u.into()).collect();

    Ok(Json(DataResponse { data: results }))
}

use crate::auth::AuthContext;
use crate::models::{AdminStatsResponse, RegisterRequest, RegisterResponse, UserCountByHour};
use axum::http::StatusCode;
use axum::Extension;
use serde::Serialize;

/// GET /v1/admin/stats — aggregate user statistics (admin only)
pub async fn admin_stats(
    State(pool): State<PgPool>,
) -> Result<Json<DataResponse<AdminStatsResponse>>, AppError> {
    let (total, last_7, last_30) = db::get_user_counts(&pool).await?;

    Ok(Json(DataResponse {
        data: AdminStatsResponse {
            total_users: total,
            users_last_7_days: last_7,
            users_last_30_days: last_30,
        },
    }))
}

#[derive(Debug, Deserialize)]
pub struct UserCountsByHourQuery {
    pub days: Option<i32>,
}

/// GET /v1/admin/stats/users-by-hour — active users per hour (admin only)
pub async fn admin_users_by_hour(
    State(pool): State<PgPool>,
    Query(query): Query<UserCountsByHourQuery>,
) -> Result<Json<DataResponse<Vec<UserCountByHour>>>, AppError> {
    let days = query.days.unwrap_or(30).clamp(1, 365);
    let data = db::get_active_users_by_hour(&pool, days).await?;

    Ok(Json(DataResponse { data }))
}

/// POST /v1/register
/// Register a user so they appear in friend search and get an auth token.
/// Creates rows in both users and participants tables.
pub async fn register(
    State(pool): State<PgPool>,
    Json(body): Json<RegisterRequest>,
) -> Result<(StatusCode, Json<DataResponse<RegisterResponse>>), AppError> {
    // CAR-339: normalize ONCE up front and use the same value for validation and
    // both writes. Previously the guards ran on the trimmed callsign but the raw,
    // untrimmed body was persisted — bypassing the length cap (leading spaces) and
    // diverging normalization (users vs participants), which later broke
    // change_callsign / claim_previous_account for mixed-case or padded inputs.
    let callsign = body.callsign.trim().to_uppercase();
    if callsign.is_empty() {
        return Err(AppError::Validation {
            message: "callsign is required".to_string(),
        });
    }
    // CAR-143: bound user-input length so an abusive caller can't push
    // multi-megabyte strings into the users / participants tables.
    if callsign.chars().count() > 16 {
        return Err(AppError::Validation {
            message: "callsign must be 16 characters or fewer".to_string(),
        });
    }
    if let Some(name) = body.device_name.as_deref() {
        if name.chars().count() > 128 {
            return Err(AppError::Validation {
                message: "deviceName must be 128 characters or fewer".to_string(),
            });
        }
    }

    // Create user record (for friend search)
    let user = db::get_or_create_user(&pool, &callsign).await?;

    // Create participant record (for auth token)
    let (participant, is_new) =
        db::get_or_create_participant(&pool, &callsign, body.device_name.as_deref()).await?;

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: RegisterResponse {
                user_id: user.id,
                // Only hand back a token when we actually minted a new participant.
                // See RegisterResponse::device_token (CAR-304 / CAR-313).
                device_token: if is_new {
                    Some(participant.device_token)
                } else {
                    None
                },
            },
        }),
    ))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChangeCallsignRequest {
    pub new_callsign: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChangeCallsignResponse {
    pub callsign: String,
}

/// PUT /v1/account/callsign
/// Change the authenticated user's callsign across all tables.
pub async fn change_callsign(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Json(body): Json<ChangeCallsignRequest>,
) -> Result<Json<DataResponse<ChangeCallsignResponse>>, AppError> {
    let new_callsign = body.new_callsign.trim().to_uppercase();

    if new_callsign.is_empty() {
        return Err(AppError::Validation {
            message: "newCallsign is required".to_string(),
        });
    }

    if new_callsign == auth.callsign {
        return Err(AppError::Validation {
            message: "new callsign must differ from current callsign".to_string(),
        });
    }

    // get_or_create rather than get: an account whose earlier change was only
    // half-applied (CAR-349) may have no `users` row under its acting callsign
    // yet, and the repair path in db::change_callsign needs one to fold in.
    let user = db::get_or_create_user(&pool, &auth.callsign).await?;

    let updated =
        db::change_callsign(&pool, user.id, &auth.callsign, &new_callsign, auth.account_id).await?;

    Ok(Json(DataResponse {
        data: ChangeCallsignResponse {
            callsign: updated.callsign,
        },
    }))
}

/// DELETE /v1/account
/// Delete the authenticated user's account and all associated data.
pub async fn delete_account(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
) -> Result<StatusCode, AppError> {
    let rows = db::delete_user_account(&pool, &auth.callsign).await?;

    if rows == 0 {
        return Err(AppError::UserNotFound {
            user_id: auth.participant_id,
        });
    }

    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaimPreviousRequest {
    pub previous_callsign: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaimPreviousResponse {
    pub merged: bool,
    pub previous_callsign: String,
}

/// POST /v1/account/claim-previous
/// Merge data from a previous callsign's account into the current user.
/// Used when a user changed their callsign before the app had server-side sync,
/// resulting in a new account that lost friends/challenges from the old one.
pub async fn claim_previous_account(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Json(body): Json<ClaimPreviousRequest>,
) -> Result<Json<DataResponse<ClaimPreviousResponse>>, AppError> {
    let previous = body.previous_callsign.trim().to_uppercase();

    if previous.is_empty() {
        return Err(AppError::Validation {
            message: "previousCallsign is required".to_string(),
        });
    }

    if previous == auth.callsign {
        return Err(AppError::Validation {
            message: "previousCallsign must differ from current callsign".to_string(),
        });
    }

    // SECURITY (CAR-301 / CAR-303): merge_previous_account absorbs and then
    // DELETES the account behind `previous`. A caller-supplied callsign string is
    // not proof of ownership, so require the caller to have *verified* the
    // previous callsign (account_callsigns) before we touch it. Legacy `fd_`
    // device tokens carry no account identity (`account_id == None`) and thus can
    // never satisfy this — self-serve claiming now requires an account-backed
    // (OAuth) session that has verified the previous callsign.
    let account_id = auth.account_id.ok_or(AppError::Forbidden)?;
    crate::db::auth::assert_account_owns_callsign(&pool, account_id, &previous).await?;

    // Look up the old user
    let old_user = db::get_user_by_callsign(&pool, &previous)
        .await?
        .ok_or(AppError::UserNotFound {
            user_id: auth.participant_id,
        })?;

    // Look up the current user
    let current_user = db::get_user_by_callsign(&pool, &auth.callsign)
        .await?
        .ok_or(AppError::UserNotFound {
            user_id: auth.participant_id,
        })?;

    // Merge old account into current
    db::merge_previous_account(
        &pool,
        current_user.id,
        old_user.id,
        &previous,
        &auth.callsign,
    )
    .await?;

    Ok(Json(DataResponse {
        data: ClaimPreviousResponse {
            merged: true,
            previous_callsign: previous,
        },
    }))
}
