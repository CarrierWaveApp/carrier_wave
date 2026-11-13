use axum::body::Body;
use axum::extract::{Extension, Query, State};
use axum::http::{header, HeaderMap, Response, StatusCode};
use chrono::{Duration, Utc};
use uuid::Uuid;

use crate::extractors::{Json, Path};
use sqlx::PgPool;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::models::club::{
    ClubDetailResponse, ClubMemberResponse, ClubMembershipEntry, ClubResponse, ClubSyncResponse,
    MemberOnlineStatus, MemberStatusResponse, SpotInfo, UpdateClubNotesRequest,
};

use super::DataResponse;

/// Optional query parameter shared across club endpoints. When present,
/// the listed callsigns are unioned with the authenticated callsign so
/// users who recently changed callsigns still see clubs they joined
/// under prior calls.
#[derive(Debug, Default, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubsQuery {
    /// Comma-separated extra callsigns to include in the lookup.
    /// Example: `?callsigns=W6JSV,W6JNZ`.
    pub callsigns: Option<String>,
}

impl ClubsQuery {
    /// Build the full callsign list (auth + any *owned* comma-separated extras),
    /// uppercased and deduplicated. Always includes the auth callsign.
    ///
    /// SECURITY (CAR-308): the `?callsigns=` list is populated device-side and is
    /// entirely unverified, so it cannot be trusted as an ownership claim. Each
    /// requested extra is honored only if it appears in the set of callsigns the
    /// caller provably owns (`db::clubs::owned_callsigns`); anything else is
    /// silently dropped so a token for one callsign can't enumerate another
    /// user's club memberships or rosters.
    async fn resolve(&self, pool: &PgPool, auth: &AuthContext) -> Result<Vec<String>, AppError> {
        let mut seen = std::collections::HashSet::new();
        let mut out = Vec::new();
        let primary = auth.callsign.to_uppercase();
        seen.insert(primary.clone());
        out.push(primary);

        let requested: Vec<String> = self
            .callsigns
            .as_deref()
            .unwrap_or("")
            .split(',')
            .map(|p| p.trim().to_uppercase())
            .filter(|p| !p.is_empty())
            .collect();

        if !requested.is_empty() {
            let owned = db::clubs::owned_callsigns(pool, &auth.callsign, auth.account_id).await?;
            for upper in requested {
                if owned.contains(&upper) && seen.insert(upper.clone()) {
                    out.push(upper);
                }
            }
        }

        Ok(out)
    }
}

/// GET /v1/clubs
/// Get clubs for the authenticated user (and any prior callsigns
/// supplied via `?callsigns=`).
pub async fn get_clubs(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Query(query): Query<ClubsQuery>,
) -> Result<Json<DataResponse<Vec<ClubResponse>>>, AppError> {
    let callsigns = query.resolve(&pool, &auth).await?;
    let clubs = db::clubs::get_clubs_for_callsigns(&pool, &callsigns).await?;

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
            roster_synced_at: None,
            roster_sync_status: None,
        })
        .collect();

    Ok(Json(DataResponse { data }))
}

/// GET /v1/clubs/sync
/// Return all clubs for the authenticated user with full member details in a single response.
/// Supports ETag-based conditional fetching via If-None-Match to skip re-downloading
/// when nothing has changed (the main use-case is fast app startup).
pub async fn sync_clubs(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Query(query): Query<ClubsQuery>,
    headers: HeaderMap,
) -> Result<(HeaderMap, Json<DataResponse<Vec<ClubSyncResponse>>>), AppError> {
    let callsigns = query.resolve(&pool, &auth).await?;

    // Compute ETag from the latest mutation timestamp across clubs + members for this user
    let fingerprint = db::clubs::get_clubs_fingerprint(&pool, &callsigns).await?;
    let etag = format!("\"clubs-{}\"", fingerprint);

    // Check If-None-Match
    if let Some(inm) = headers.get(header::IF_NONE_MATCH) {
        if let Ok(val) = inm.to_str() {
            if val == etag {
                let mut resp_headers = HeaderMap::new();
                resp_headers.insert(header::ETAG, etag.parse().unwrap());
                return Err(AppError::NotModified);
            }
        }
    }

    // Fetch all clubs with members in two queries (no N+1)
    let clubs = db::clubs::get_clubs_for_callsigns(&pool, &callsigns).await?;

    let club_ids: Vec<Uuid> = clubs.iter().map(|c| c.id).collect();
    let all_members = db::clubs::get_members_for_clubs(&pool, &club_ids).await?;

    // Group members by club_id
    let mut members_by_club: std::collections::HashMap<Uuid, Vec<ClubMemberResponse>> =
        std::collections::HashMap::new();
    for m in all_members {
        members_by_club
            .entry(m.club_id)
            .or_default()
            .push(ClubMemberResponse {
                callsign: m.callsign,
                role: m.role,
                joined_at: m.joined_at,
                last_seen_at: m.last_seen_at,
                last_grid: m.last_grid,
                is_carrier_wave_user: m.is_carrier_wave_user,
            });
    }

    let data = clubs
        .into_iter()
        .map(|c| {
            let members = members_by_club.remove(&c.id).unwrap_or_default();
            ClubSyncResponse {
                id: c.id,
                name: c.name,
                callsign: c.callsign,
                description: c.description,
                notes_url: c.notes_url,
                notes_title: c.notes_title,
                has_logo: c.has_logo,
                member_count: c.member_count,
                members,
            }
        })
        .collect();

    let mut resp_headers = HeaderMap::new();
    resp_headers.insert(header::ETAG, etag.parse().unwrap());

    Ok((resp_headers, Json(DataResponse { data })))
}

/// GET /v1/clubs/:id
/// Get club details (requires membership).
pub async fn get_club_details(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Path(club_id): Path<Uuid>,
) -> Result<Json<DataResponse<ClubDetailResponse>>, AppError> {
    // Verify caller is a member
    if !db::clubs::is_club_member(&pool, club_id, &auth.callsign).await? {
        return Err(AppError::Forbidden);
    }

    let club = db::clubs::get_club_detail(&pool, club_id)
        .await?
        .ok_or(AppError::ClubNotFound { club_id })?;

    let members = db::clubs::get_club_members_enriched(&pool, club_id).await?;

    let member_responses = members
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

    Ok(Json(DataResponse {
        data: ClubDetailResponse {
            id: club.id,
            name: club.name,
            callsign: club.callsign,
            description: club.description,
            notes_url: club.notes_url,
            notes_title: club.notes_title,
            has_logo: club.logo_content_type.is_some(),
            members: member_responses,
        },
    }))
}

#[derive(serde::Deserialize)]
pub struct ClubActivityQuery {
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubActivityResponse {
    pub items: Vec<ClubActivityItem>,
    pub pagination: ClubActivityPagination,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubActivityItem {
    pub id: Uuid,
    pub callsign: String,
    pub activity_type: String,
    pub timestamp: chrono::DateTime<Utc>,
    pub details: serde_json::Value,
    pub created_at: chrono::DateTime<Utc>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubActivityPagination {
    pub has_more: bool,
    pub next_cursor: Option<String>,
}

/// GET /v1/clubs/:id/activity
/// Get activity feed for a club (requires membership).
pub async fn get_club_activity(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Path(club_id): Path<Uuid>,
    Query(params): Query<ClubActivityQuery>,
) -> Result<Json<DataResponse<ClubActivityResponse>>, AppError> {
    // Verify membership
    if !db::clubs::is_club_member(&pool, club_id, &auth.callsign).await? {
        return Err(AppError::Forbidden);
    }

    let limit = params.limit.unwrap_or(20).clamp(1, 100);

    // Parse cursor (ISO 8601 timestamp)
    let cursor = params.cursor.as_deref().and_then(|s| {
        chrono::DateTime::parse_from_rfc3339(s)
            .ok()
            .map(|dt| dt.with_timezone(&Utc))
    });

    // Fetch one extra to determine has_more
    let rows = db::clubs::get_club_activity(&pool, club_id, cursor, limit + 1).await?;

    let has_more = rows.len() as i64 > limit;
    let truncated: Vec<_> = rows.into_iter().take(limit as usize).collect();

    let next_cursor = if has_more {
        truncated.last().map(|row| row.created_at.to_rfc3339())
    } else {
        None
    };

    let items = truncated
        .into_iter()
        .map(|row| ClubActivityItem {
            id: row.id,
            callsign: row.callsign,
            activity_type: row.activity_type,
            timestamp: row.timestamp,
            details: row.details,
            created_at: row.created_at,
        })
        .collect();

    Ok(Json(DataResponse {
        data: ClubActivityResponse {
            items,
            pagination: ClubActivityPagination {
                has_more,
                next_cursor,
            },
        },
    }))
}

/// GET /v1/clubs/:id/status
/// Get real-time status for club members (requires membership).
pub async fn get_club_status(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Path(club_id): Path<Uuid>,
) -> Result<Json<DataResponse<Vec<MemberStatusResponse>>>, AppError> {
    // Verify membership
    if !db::clubs::is_club_member(&pool, club_id, &auth.callsign).await? {
        return Err(AppError::Forbidden);
    }

    let members = db::clubs::get_club_members_enriched(&pool, club_id).await?;
    let now = Utc::now();
    let spot_cutoff = now - Duration::minutes(30);
    let active_cutoff = now - Duration::minutes(15);

    let mut statuses = Vec::with_capacity(members.len());

    for member in &members {
        // Check for recent spot (on_air)
        let spot = find_recent_spot(&pool, &member.callsign, spot_cutoff).await?;

        let (status, spot_info) = if let Some(spot) = spot {
            (
                MemberOnlineStatus::OnAir,
                Some(SpotInfo {
                    frequency: spot.frequency_khz,
                    mode: Some(spot.mode),
                    source: format!("{:?}", spot.source).to_lowercase(),
                    spotted_at: spot.spotted_at,
                }),
            )
        } else if member.last_seen_at.is_some_and(|seen| seen > active_cutoff) {
            (MemberOnlineStatus::RecentlyActive, None)
        } else {
            (MemberOnlineStatus::Inactive, None)
        };

        statuses.push(MemberStatusResponse {
            callsign: member.callsign.clone(),
            status,
            spot_info,
            last_seen_at: member.last_seen_at,
        });
    }

    Ok(Json(DataResponse { data: statuses }))
}

/// PUT /v1/clubs/:id/notes
/// Update club notes (requires club admin role).
pub async fn update_club_notes(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Path(club_id): Path<Uuid>,
    Json(body): Json<UpdateClubNotesRequest>,
) -> Result<Json<DataResponse<ClubResponse>>, AppError> {
    // Verify caller is a club member
    if !db::clubs::is_club_member(&pool, club_id, &auth.callsign).await? {
        return Err(AppError::Forbidden);
    }

    // Verify caller is a club admin
    let members = db::clubs::get_club_members_enriched(&pool, club_id).await?;
    let caller_upper = auth.callsign.to_uppercase();
    let caller = members.iter().find(|m| m.callsign == caller_upper);

    match caller {
        Some(m) if m.role == "admin" => {}
        _ => return Err(AppError::Forbidden),
    }

    // Validate URL starts with https:// if provided
    if let Some(ref url) = body.notes_url {
        if !url.starts_with("https://") {
            return Err(AppError::Validation {
                message: "notes_url must start with https://".to_string(),
            });
        }
    }

    // Update notes
    let club = db::clubs::update_club_notes(
        &pool,
        club_id,
        body.notes_url.as_deref(),
        body.notes_title.as_deref(),
    )
    .await?
    .ok_or(AppError::ClubNotFound { club_id })?;

    // Get member count for response
    let member_count = members.len() as i64;

    Ok(Json(DataResponse {
        data: ClubResponse {
            id: club.id,
            name: club.name,
            callsign: club.callsign,
            description: club.description,
            notes_url: club.notes_url,
            notes_title: club.notes_title,
            has_logo: club.logo_content_type.is_some(),
            member_count,
            roster_synced_at: None,
            roster_sync_status: None,
        },
    }))
}

/// GET /v1/clubs/membership
/// Return a compact callsign→club mapping for building the in-memory cache.
/// Much lighter than /sync — only callsigns and club names, no member details.
/// Supports ETag-based conditional fetching.
pub async fn get_club_membership(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Query(query): Query<ClubsQuery>,
    headers: HeaderMap,
) -> Result<(HeaderMap, Json<DataResponse<Vec<ClubMembershipEntry>>>), AppError> {
    let callsigns = query.resolve(&pool, &auth).await?;
    let fingerprint = db::clubs::get_clubs_fingerprint(&pool, &callsigns).await?;
    let etag = format!("\"membership-{}\"", fingerprint);

    if let Some(inm) = headers.get(header::IF_NONE_MATCH) {
        if let Ok(val) = inm.to_str() {
            if val == etag {
                return Err(AppError::NotModified);
            }
        }
    }

    let rows = db::clubs::get_membership_callsigns(&pool, &callsigns).await?;

    // Group by club name
    let mut by_club: std::collections::HashMap<String, Vec<String>> =
        std::collections::HashMap::new();
    for row in rows {
        by_club.entry(row.club_name).or_default().push(row.callsign);
    }

    let data: Vec<ClubMembershipEntry> = by_club
        .into_iter()
        .map(|(name, callsigns)| ClubMembershipEntry { name, callsigns })
        .collect();

    let mut resp_headers = HeaderMap::new();
    resp_headers.insert(header::ETAG, etag.parse().unwrap());

    Ok((resp_headers, Json(DataResponse { data })))
}

/// GET /v1/clubs/:id/logo
/// Serve the club's logo image (public, no auth required).
pub async fn get_club_logo(
    State(pool): State<PgPool>,
    Path(club_id): Path<Uuid>,
) -> Result<Response<Body>, AppError> {
    let logo = db::clubs::get_club_logo(&pool, club_id)
        .await?
        .ok_or(AppError::ClubNotFound { club_id })?;

    let response = Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, logo.logo_content_type)
        .header(header::CACHE_CONTROL, "public, max-age=86400")
        .body(Body::from(logo.logo_data))
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(response)
}

/// Internal: partial spot row for status queries.
#[derive(sqlx::FromRow)]
struct SpotSummary {
    frequency_khz: f64,
    mode: String,
    source: crate::models::spot::SpotSource,
    spotted_at: chrono::DateTime<Utc>,
}

/// Find the most recent unexpired spot for a callsign since `since`.
async fn find_recent_spot(
    pool: &PgPool,
    callsign: &str,
    since: chrono::DateTime<Utc>,
) -> Result<Option<SpotSummary>, AppError> {
    let row = sqlx::query_as::<_, SpotSummary>(
        r#"
        SELECT frequency_khz, mode, source, spotted_at
        FROM spots
        WHERE callsign = $1
          AND spotted_at >= $2
          AND expires_at > now()
        ORDER BY spotted_at DESC
        LIMIT 1
        "#,
    )
    .bind(callsign)
    .bind(since)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}
