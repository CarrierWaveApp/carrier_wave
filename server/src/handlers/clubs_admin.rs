use axum::extract::State;
use axum::http::StatusCode;
use axum_extra::extract::Multipart;
use uuid::Uuid;

use crate::extractors::{Json, Path};
use sqlx::PgPool;

use crate::aggregators::club_rosters;
use crate::db;
use crate::error::AppError;
use crate::models::club::{
    AddMembersRequest, ClubMemberResponse, ClubResponse, CreateClubRequest, ImportNotesResponse,
    UpdateClubRequest, UpdateMemberRoleRequest,
};

use super::DataResponse;

/// GET /v1/admin/clubs
/// List all clubs with member counts.
pub async fn list_clubs_admin(
    State(pool): State<PgPool>,
) -> Result<Json<DataResponse<Vec<ClubResponse>>>, AppError> {
    let clubs = db::clubs::list_all_clubs(&pool).await?;

    let data = clubs
        .into_iter()
        .map(|c| ClubResponse {
            id: c.id,
            name: c.name,
            callsign: c.callsign,
            description: c.description,
            notes_url: c.notes_url,
            notes_title: c.notes_title,
            has_logo: c.has_logo,
            member_count: c.member_count,
            roster_synced_at: c.roster_synced_at,
            roster_sync_status: c.roster_sync_status,
        })
        .collect();

    Ok(Json(DataResponse { data }))
}

/// GET /v1/admin/clubs/:id/members
/// List members of a club.
pub async fn list_club_members_admin(
    State(pool): State<PgPool>,
    Path(club_id): Path<Uuid>,
) -> Result<Json<DataResponse<Vec<ClubMemberResponse>>>, AppError> {
    // Verify club exists
    db::clubs::get_club_detail(&pool, club_id)
        .await?
        .ok_or(AppError::ClubNotFound { club_id })?;

    let members = db::clubs::get_club_members_enriched(&pool, club_id).await?;

    let data = members
        .into_iter()
        .map(|m| ClubMemberResponse {
            callsign: m.callsign,
            role: m.role,
            joined_at: m.joined_at,
            last_seen_at: m.last_seen_at,
            last_grid: m.last_grid,
            is_carrier_wave_user: m.is_carrier_wave_user,
        })
        .collect();

    Ok(Json(DataResponse { data }))
}

/// POST /v1/admin/clubs
/// Create a new club.
pub async fn create_club(
    State(pool): State<PgPool>,
    Json(body): Json<CreateClubRequest>,
) -> Result<(StatusCode, Json<DataResponse<ClubResponse>>), AppError> {
    let club = db::clubs::create_club(
        &pool,
        &body.name,
        body.callsign.as_deref(),
        body.description.as_deref(),
    )
    .await?;

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: ClubResponse {
                id: club.id,
                name: club.name,
                callsign: club.callsign,
                description: club.description,
                notes_url: club.notes_url,
                notes_title: club.notes_title,
                has_logo: club.logo_content_type.is_some(),
                member_count: 0,
                roster_synced_at: None,
                roster_sync_status: None,
            },
        }),
    ))
}

/// PUT /v1/admin/clubs/:id
/// Update a club's metadata.
pub async fn update_club(
    State(pool): State<PgPool>,
    Path(club_id): Path<Uuid>,
    Json(body): Json<UpdateClubRequest>,
) -> Result<Json<DataResponse<ClubResponse>>, AppError> {
    // Convert double-Option fields for DB layer
    let callsign = body.callsign.as_ref().map(|o| o.as_deref());
    let description = body.description.as_ref().map(|o| o.as_deref());
    let notes_url = body.notes_url.as_ref().map(|o| o.as_deref());
    let notes_title = body.notes_title.as_ref().map(|o| o.as_deref());

    let club = db::clubs::update_club(
        &pool,
        club_id,
        body.name.as_deref(),
        callsign,
        description,
        notes_url,
        notes_title,
    )
    .await?
    .ok_or(AppError::ClubNotFound { club_id })?;

    // Fetch current member count
    let members = db::clubs::get_club_members_enriched(&pool, club_id).await?;

    Ok(Json(DataResponse {
        data: ClubResponse {
            id: club.id,
            name: club.name,
            callsign: club.callsign,
            description: club.description,
            notes_url: club.notes_url,
            notes_title: club.notes_title,
            has_logo: club.logo_content_type.is_some(),
            member_count: members.len() as i64,
            roster_synced_at: None,
            roster_sync_status: None,
        },
    }))
}

/// DELETE /v1/admin/clubs/:id
/// Delete a club.
pub async fn delete_club(
    State(pool): State<PgPool>,
    Path(club_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let deleted = db::clubs::delete_club(&pool, club_id).await?;

    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::ClubNotFound { club_id })
    }
}

/// POST /v1/admin/clubs/:id/members
/// Add members to a club.
pub async fn add_club_members(
    State(pool): State<PgPool>,
    Path(club_id): Path<Uuid>,
    Json(body): Json<AddMembersRequest>,
) -> Result<(StatusCode, Json<DataResponse<Vec<ClubMemberResponse>>>), AppError> {
    // Verify club exists
    db::clubs::get_club_detail(&pool, club_id)
        .await?
        .ok_or(AppError::ClubNotFound { club_id })?;

    let member_tuples: Vec<(String, String)> = body
        .members
        .into_iter()
        .map(|m| (m.callsign, m.role))
        .collect();

    let members = db::clubs::add_members(&pool, club_id, &member_tuples).await?;

    let data = members
        .into_iter()
        .map(|m| ClubMemberResponse {
            callsign: m.callsign,
            role: m.role,
            joined_at: m.joined_at,
            last_seen_at: None,
            last_grid: None,
            is_carrier_wave_user: false,
        })
        .collect();

    Ok((StatusCode::CREATED, Json(DataResponse { data })))
}

/// DELETE /v1/admin/clubs/:id/members/:callsign
/// Remove a member from a club.
pub async fn remove_club_member(
    State(pool): State<PgPool>,
    Path((club_id, callsign)): Path<(Uuid, String)>,
) -> Result<StatusCode, AppError> {
    let removed = db::clubs::remove_member(&pool, club_id, &callsign).await?;

    if removed {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::ClubMemberNotFound { club_id, callsign })
    }
}

/// PUT /v1/admin/clubs/:id/members/:callsign
/// Update a member's role.
pub async fn update_club_member_role(
    State(pool): State<PgPool>,
    Path((club_id, callsign)): Path<(Uuid, String)>,
    Json(body): Json<UpdateMemberRoleRequest>,
) -> Result<Json<DataResponse<ClubMemberResponse>>, AppError> {
    let updated = db::clubs::update_member_role(&pool, club_id, &callsign, &body.role).await?;

    if !updated {
        return Err(AppError::ClubMemberNotFound { club_id, callsign });
    }

    // Fetch the updated member from the enriched view
    let members = db::clubs::get_club_members_enriched(&pool, club_id).await?;
    let callsign_upper = callsign.to_uppercase();
    let member = members
        .into_iter()
        .find(|m| m.callsign == callsign_upper)
        .ok_or(AppError::ClubMemberNotFound {
            club_id,
            callsign: callsign_upper,
        })?;

    Ok(Json(DataResponse {
        data: ClubMemberResponse {
            callsign: member.callsign,
            role: member.role,
            joined_at: member.joined_at,
            last_seen_at: member.last_seen_at,
            last_grid: member.last_grid,
            is_carrier_wave_user: member.is_carrier_wave_user,
        },
    }))
}

/// POST /v1/admin/clubs/:id/import-notes
/// Reconcile the roster against the club's callsign notes URL right now.
///
/// Same routine the `club_rosters` aggregator runs on its schedule: callsigns
/// new to the file are added as `member`, `member`-role rows missing from the
/// file are removed, admins are left alone.
pub async fn import_notes_members(
    State(pool): State<PgPool>,
    Path(club_id): Path<Uuid>,
) -> Result<Json<DataResponse<ImportNotesResponse>>, AppError> {
    let club = db::clubs::get_club_detail(&pool, club_id)
        .await?
        .ok_or(AppError::ClubNotFound { club_id })?;

    if club.notes_url.as_deref().is_none_or(|u| u.trim().is_empty()) {
        return Err(AppError::Validation {
            message: "Club has no notes URL configured".to_string(),
        });
    }

    let client = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(10))
        .build()
        .map_err(|e| AppError::Internal(format!("Failed to build HTTP client: {}", e)))?;

    let outcome = club_rosters::sync_club_roster(&pool, &client, &club)
        .await
        .map_err(|e| AppError::Internal(format!("Roster import failed: {}", e)))?;

    Ok(Json(DataResponse {
        data: ImportNotesResponse {
            imported: outcome.added.len(),
            skipped: outcome.unchanged,
            removed: outcome.removed.len(),
            callsigns: outcome.added,
            removed_callsigns: outcome.removed,
        },
    }))
}

const MAX_LOGO_SIZE: usize = 2 * 1024 * 1024; // 2MB
const ALLOWED_LOGO_TYPES: &[&str] = &["image/png", "image/jpeg", "image/svg+xml", "image/gif", "image/webp"];

/// PUT /v1/admin/clubs/:id/logo
/// Upload or replace a club's logo.
pub async fn upload_club_logo(
    State(pool): State<PgPool>,
    Path(club_id): Path<Uuid>,
    mut multipart: Multipart,
) -> Result<StatusCode, AppError> {
    // Verify club exists
    db::clubs::get_club_detail(&pool, club_id)
        .await?
        .ok_or(AppError::ClubNotFound { club_id })?;

    let mut image_data: Option<Vec<u8>> = None;
    let mut content_type: Option<String> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::Validation {
            message: format!("Failed to read multipart field: {}", e),
        })?
    {
        let field_name = field.name().unwrap_or("").to_string();

        if field_name == "image" {
            let ct = field
                .content_type()
                .map(|s| s.to_string())
                .unwrap_or_default();

            if !ALLOWED_LOGO_TYPES.contains(&ct.as_str()) {
                return Err(AppError::Validation {
                    message: format!(
                        "Invalid content type '{}'. Allowed: PNG, JPEG, SVG, GIF, WebP",
                        ct
                    ),
                });
            }

            let data = field.bytes().await.map_err(|e| AppError::Validation {
                message: format!("Failed to read image data: {}", e),
            })?;

            if data.len() > MAX_LOGO_SIZE {
                return Err(AppError::Validation {
                    message: format!("Logo too large. Maximum size is {} bytes", MAX_LOGO_SIZE),
                });
            }

            content_type = Some(ct);
            image_data = Some(data.to_vec());
        }
    }

    let image_data = image_data.ok_or(AppError::Validation {
        message: "Missing required field: image".to_string(),
    })?;
    let content_type = content_type.ok_or(AppError::Validation {
        message: "Missing image content type".to_string(),
    })?;

    db::clubs::set_club_logo(&pool, club_id, &image_data, &content_type).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /v1/admin/clubs/:id/logo
/// Remove a club's logo.
pub async fn delete_club_logo(
    State(pool): State<PgPool>,
    Path(club_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let deleted = db::clubs::delete_club_logo(&pool, club_id).await?;

    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::ClubNotFound { club_id })
    }
}
