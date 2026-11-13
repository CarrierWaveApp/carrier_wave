// src/error.rs
use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;
use uuid::Uuid;

#[allow(dead_code)]
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("Challenge not found")]
    ChallengeNotFound { challenge_id: Uuid },

    #[error("Badge not found")]
    BadgeNotFound { badge_id: Uuid },

    #[error("Invite not found")]
    InviteNotFound { token: String },

    #[error("User not found")]
    UserNotFound { user_id: Uuid },

    #[error("Friend invite not found or expired")]
    FriendInviteNotFound { token: String },

    #[error("Friend invite has already been used")]
    FriendInviteUsed { token: String },

    #[error("Activity not found")]
    ActivityNotFound { activity_id: Uuid },

    #[error("Program not found")]
    ProgramNotFound { slug: String },

    #[error("Spot not found")]
    SpotNotFound { spot_id: uuid::Uuid },

    #[error("Club not found")]
    ClubNotFound { club_id: Uuid },

    #[error("Club member not found")]
    ClubMemberNotFound { club_id: Uuid, callsign: String },

    #[error("Park not found")]
    ParkNotFound { reference: String },

    #[error("Trail not found")]
    TrailNotFound { reference: String },

    #[error("Equipment not found")]
    EquipmentNotFound { equipment_id: String },

    #[error("Contest definition not found")]
    ContestDefinitionNotFound { contest_id: String },

    #[error("Invalid contest definition")]
    InvalidContestDefinition {
        message: String,
        problems: Vec<crate::models::contest_definition::ValidationProblem>,
    },

    #[error("Event not found")]
    EventNotFound { event_id: Uuid },

    #[error("Cannot modify another user's event")]
    EventNotOwned { event_id: Uuid },

    #[error("Maximum pending events reached (10)")]
    MaxPendingEvents,

    #[error("Invalid review action")]
    InvalidEventReview { message: String },

    #[error("Callsign already taken")]
    CallsignTaken { callsign: String },

    #[error("Active self-spot already exists for this program")]
    SelfSpotExists,

    #[error("Program does not support this capability")]
    CapabilityNotSupported {
        capability: String,
        program_slug: String,
    },

    #[error("Friend request not found")]
    FriendRequestNotFound { request_id: Uuid },

    #[error("Friendship not found")]
    FriendshipNotFound { friendship_id: Uuid },

    #[error("Already friends with this user")]
    AlreadyFriends,

    #[error("Friend request already exists")]
    FriendRequestExists,

    #[error("Cannot send friend request to yourself")]
    CannotFriendSelf,

    #[error("Already joined this challenge")]
    AlreadyJoined,

    #[error("Not participating in this challenge")]
    NotParticipating,

    #[error("Invite token required")]
    InviteRequired,

    #[error("Invite token expired")]
    InviteExpired,

    #[error("Invite token exhausted")]
    InviteExhausted,

    #[error("Challenge at maximum participants")]
    MaxParticipants,

    #[error("Challenge has ended")]
    ChallengeEnded,

    #[error("Invalid or revoked token")]
    InvalidToken,

    #[error("A Carrier Wave account is required — sign in with your email to sync")]
    AccountRequired,

    #[error("Forbidden")]
    Forbidden,

    #[error("Not modified")]
    NotModified,

    #[error("Rate limit exceeded")]
    RateLimited,

    #[error("Validation error: {message}")]
    Validation { message: String },

    #[error("Database error")]
    Database(#[from] sqlx::Error),

    #[error("Sync sequence conflict")]
    SyncSequenceConflict,

    #[error(
        "No pending snapshot with that id — it was never started, has expired, or was superseded"
    )]
    SyncSnapshotNotFound { snapshot_id: Uuid },

    #[error("Snapshot blob has not been uploaded yet — PUT the bytes to uploadUrl, then commit")]
    SyncSnapshotNotUploaded { snapshot_id: Uuid },

    #[error("Snapshot blob does not match what was declared")]
    SyncSnapshotMismatch { message: String },

    #[error("Target account already has sync data — merge manually")]
    SyncAdoptConflict {
        entry_count: i64,
        has_cursor: bool,
        has_key_blob: bool,
    },

    #[error("No account owns this callsign yet — the user must sign in first")]
    SyncAdoptNoAccount { callsign: String },

    #[error("Storage error")]
    Storage(String),

    #[error("Internal server error")]
    Internal(String),
}

#[derive(Serialize)]
struct ErrorResponse {
    error: ErrorBody,
}

#[derive(Serialize)]
struct ErrorBody {
    code: &'static str,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    details: Option<serde_json::Value>,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        // 304 Not Modified returns an empty body
        if matches!(self, Self::NotModified) {
            return StatusCode::NOT_MODIFIED.into_response();
        }

        let (status, code, details) = match &self {
            Self::ChallengeNotFound { challenge_id } => (
                StatusCode::NOT_FOUND,
                "CHALLENGE_NOT_FOUND",
                Some(serde_json::json!({ "challengeId": challenge_id })),
            ),
            Self::ActivityNotFound { activity_id } => (
                StatusCode::NOT_FOUND,
                "ACTIVITY_NOT_FOUND",
                Some(serde_json::json!({ "activityId": activity_id })),
            ),
            Self::BadgeNotFound { badge_id } => (
                StatusCode::NOT_FOUND,
                "BADGE_NOT_FOUND",
                Some(serde_json::json!({ "badgeId": badge_id })),
            ),
            Self::ProgramNotFound { slug } => (
                StatusCode::NOT_FOUND,
                "PROGRAM_NOT_FOUND",
                Some(serde_json::json!({ "slug": slug })),
            ),
            Self::SpotNotFound { spot_id } => (
                StatusCode::NOT_FOUND,
                "SPOT_NOT_FOUND",
                Some(serde_json::json!({ "spotId": spot_id })),
            ),
            Self::ClubNotFound { club_id } => (
                StatusCode::NOT_FOUND,
                "CLUB_NOT_FOUND",
                Some(serde_json::json!({ "clubId": club_id })),
            ),
            Self::ClubMemberNotFound {
                club_id, callsign, ..
            } => (
                StatusCode::NOT_FOUND,
                "CLUB_MEMBER_NOT_FOUND",
                Some(serde_json::json!({ "clubId": club_id, "callsign": callsign })),
            ),
            Self::ParkNotFound { reference } => (
                StatusCode::NOT_FOUND,
                "PARK_NOT_FOUND",
                Some(serde_json::json!({ "reference": reference })),
            ),
            Self::TrailNotFound { reference } => (
                StatusCode::NOT_FOUND,
                "TRAIL_NOT_FOUND",
                Some(serde_json::json!({ "reference": reference })),
            ),
            Self::EquipmentNotFound { ref equipment_id } => (
                StatusCode::NOT_FOUND,
                "EQUIPMENT_NOT_FOUND",
                Some(serde_json::json!({ "equipmentId": equipment_id })),
            ),
            Self::ContestDefinitionNotFound { ref contest_id } => (
                StatusCode::NOT_FOUND,
                "CONTEST_DEFINITION_NOT_FOUND",
                Some(serde_json::json!({ "contestId": contest_id })),
            ),
            Self::InvalidContestDefinition { message, problems } => (
                StatusCode::BAD_REQUEST,
                "INVALID_CONTEST_DEFINITION",
                Some(serde_json::json!({ "message": message, "problems": problems })),
            ),
            Self::EventNotFound { event_id } => (
                StatusCode::NOT_FOUND,
                "EVENT_NOT_FOUND",
                Some(serde_json::json!({ "eventId": event_id })),
            ),
            Self::EventNotOwned { event_id } => (
                StatusCode::FORBIDDEN,
                "EVENT_NOT_OWNED",
                Some(serde_json::json!({ "eventId": event_id })),
            ),
            Self::MaxPendingEvents => (
                StatusCode::TOO_MANY_REQUESTS,
                "MAX_PENDING_EVENTS",
                None,
            ),
            Self::InvalidEventReview { .. } => (
                StatusCode::BAD_REQUEST,
                "INVALID_EVENT_REVIEW",
                None,
            ),
            Self::CallsignTaken { ref callsign } => (
                StatusCode::CONFLICT,
                "CALLSIGN_TAKEN",
                Some(serde_json::json!({ "callsign": callsign })),
            ),
            Self::SelfSpotExists => (StatusCode::CONFLICT, "SELF_SPOT_EXISTS", None),
            Self::CapabilityNotSupported {
                capability,
                program_slug,
            } => (
                StatusCode::UNPROCESSABLE_ENTITY,
                "CAPABILITY_NOT_SUPPORTED",
                Some(serde_json::json!({
                    "capability": capability,
                    "programSlug": program_slug,
                })),
            ),
            Self::InviteNotFound { token } => (
                StatusCode::NOT_FOUND,
                "INVITE_NOT_FOUND",
                Some(serde_json::json!({ "token": token })),
            ),
            Self::UserNotFound { user_id } => (
                StatusCode::NOT_FOUND,
                "USER_NOT_FOUND",
                Some(serde_json::json!({ "userId": user_id })),
            ),
            Self::FriendInviteNotFound { token } => (
                StatusCode::NOT_FOUND,
                "FRIEND_INVITE_NOT_FOUND",
                Some(serde_json::json!({ "token": token })),
            ),
            Self::FriendInviteUsed { token } => (
                StatusCode::GONE,
                "FRIEND_INVITE_USED",
                Some(serde_json::json!({ "token": token })),
            ),
            Self::FriendRequestNotFound { request_id } => (
                StatusCode::NOT_FOUND,
                "FRIEND_REQUEST_NOT_FOUND",
                Some(serde_json::json!({ "requestId": request_id })),
            ),
            Self::FriendshipNotFound { friendship_id } => (
                StatusCode::NOT_FOUND,
                "FRIENDSHIP_NOT_FOUND",
                Some(serde_json::json!({ "friendshipId": friendship_id })),
            ),
            Self::AlreadyFriends => (StatusCode::CONFLICT, "ALREADY_FRIENDS", None),
            Self::FriendRequestExists => (StatusCode::CONFLICT, "FRIEND_REQUEST_EXISTS", None),
            Self::CannotFriendSelf => {
                (StatusCode::UNPROCESSABLE_ENTITY, "CANNOT_FRIEND_SELF", None)
            }
            Self::AlreadyJoined => (StatusCode::CONFLICT, "ALREADY_JOINED", None),
            Self::NotParticipating => (StatusCode::FORBIDDEN, "NOT_PARTICIPATING", None),
            Self::InviteRequired => (StatusCode::FORBIDDEN, "INVITE_REQUIRED", None),
            Self::InviteExpired => (StatusCode::FORBIDDEN, "INVITE_EXPIRED", None),
            Self::InviteExhausted => (StatusCode::FORBIDDEN, "INVITE_EXHAUSTED", None),
            Self::MaxParticipants => (StatusCode::FORBIDDEN, "MAX_PARTICIPANTS", None),
            Self::ChallengeEnded => (StatusCode::BAD_REQUEST, "CHALLENGE_ENDED", None),
            Self::InvalidToken => (StatusCode::UNAUTHORIZED, "INVALID_TOKEN", None),
            Self::AccountRequired => (StatusCode::FORBIDDEN, "ACCOUNT_REQUIRED", None),
            Self::Forbidden => (StatusCode::FORBIDDEN, "FORBIDDEN", None),
            Self::NotModified => unreachable!("handled above"),
            Self::RateLimited => (StatusCode::TOO_MANY_REQUESTS, "RATE_LIMITED", None),
            Self::Validation { .. } => (StatusCode::BAD_REQUEST, "VALIDATION_ERROR", None),
            Self::SyncSequenceConflict => (StatusCode::CONFLICT, "SYNC_SEQUENCE_CONFLICT", None),
            Self::SyncSnapshotNotFound { snapshot_id } => (
                StatusCode::NOT_FOUND,
                "SYNC_SNAPSHOT_NOT_FOUND",
                Some(serde_json::json!({ "snapshotId": snapshot_id })),
            ),
            Self::SyncSnapshotNotUploaded { snapshot_id } => (
                StatusCode::CONFLICT,
                "SYNC_SNAPSHOT_NOT_UPLOADED",
                Some(serde_json::json!({ "snapshotId": snapshot_id })),
            ),
            Self::SyncSnapshotMismatch { message } => (
                StatusCode::CONFLICT,
                "SYNC_SNAPSHOT_MISMATCH",
                Some(serde_json::json!({ "reason": message })),
            ),
            Self::SyncAdoptConflict {
                entry_count,
                has_cursor,
                has_key_blob,
            } => (
                StatusCode::CONFLICT,
                "SYNC_ADOPT_CONFLICT",
                Some(serde_json::json!({
                    "entryCount": entry_count,
                    "hasCursor": has_cursor,
                    "hasKeyBlob": has_key_blob,
                })),
            ),
            Self::SyncAdoptNoAccount { callsign } => (
                StatusCode::UNPROCESSABLE_ENTITY,
                "SYNC_ADOPT_NO_ACCOUNT",
                Some(serde_json::json!({ "callsign": callsign })),
            ),
            Self::Database(_) => (StatusCode::INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", None),
            Self::Storage(_) => (StatusCode::INTERNAL_SERVER_ERROR, "STORAGE_ERROR", None),
            Self::Internal(_) => (StatusCode::INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", None),
        };

        let body = ErrorResponse {
            error: ErrorBody {
                code,
                message: self.to_string(),
                details,
            },
        };

        (status, Json(body)).into_response()
    }
}
