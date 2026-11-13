use chrono::{DateTime, Utc};
use sqlx::{FromRow, PgPool};
use uuid::Uuid;

use crate::error::AppError;
use crate::models::club::{Club, ClubMember};

// ---------------------------------------------------------------------------
// Helper structs for enriched queries
// ---------------------------------------------------------------------------

/// Club row with member count for list views.
#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct ClubWithCount {
    pub id: Uuid,
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
    pub notes_url: Option<String>,
    pub notes_title: Option<String>,
    pub has_logo: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub member_count: i64,
    pub roster_synced_at: Option<DateTime<Utc>>,
    pub roster_sync_status: Option<String>,
}

/// Club member enriched with participant presence data.
#[derive(Debug, Clone, FromRow)]
pub struct EnrichedClubMember {
    pub callsign: String,
    pub role: String,
    pub joined_at: DateTime<Utc>,
    pub last_seen_at: Option<DateTime<Utc>>,
    pub last_grid: Option<String>,
    pub is_carrier_wave_user: bool,
}

/// Activity row with the originating callsign (for club activity feeds).
#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct ActivityWithCallsign {
    pub id: Uuid,
    pub callsign: String,
    pub user_id: Uuid,
    pub activity_type: String,
    pub timestamp: DateTime<Utc>,
    pub details: serde_json::Value,
    pub created_at: DateTime<Utc>,
}

// ---------------------------------------------------------------------------
// Admin operations
// ---------------------------------------------------------------------------

/// Create a new club and return the inserted row.
pub async fn create_club(
    pool: &PgPool,
    name: &str,
    callsign: Option<&str>,
    description: Option<&str>,
) -> Result<Club, AppError> {
    let club = sqlx::query_as::<_, Club>(
        r#"
        INSERT INTO clubs (name, callsign, description)
        VALUES ($1, $2, $3)
        RETURNING id, name, callsign, description, notes_url, notes_title,
                  logo_content_type, created_at, updated_at
        "#,
    )
    .bind(name)
    .bind(callsign)
    .bind(description)
    .fetch_one(pool)
    .await?;

    Ok(club)
}

/// Update a club's metadata.
///
/// Uses COALESCE so only provided fields are updated -- `None` means "keep existing value".
/// For notes_url and notes_title, the outer Option controls whether the field is being updated,
/// and the inner Option controls whether to set a value or clear to NULL.
pub async fn update_club(
    pool: &PgPool,
    club_id: Uuid,
    name: Option<&str>,
    callsign: Option<Option<&str>>,
    description: Option<Option<&str>>,
    notes_url: Option<Option<&str>>,
    notes_title: Option<Option<&str>>,
) -> Result<Option<Club>, AppError> {
    // Flatten double-Option: None (outer) -> keep existing, Some(None) -> set NULL,
    // Some(Some(v)) -> set value. We use a sentinel approach: pass the inner value
    // (or NULL) and a boolean flag indicating whether to update.
    let update_callsign = callsign.is_some();
    let callsign_val = callsign.flatten();
    let update_description = description.is_some();
    let description_val = description.flatten();
    let update_notes_url = notes_url.is_some();
    let notes_url_val = notes_url.flatten();
    let update_notes_title = notes_title.is_some();
    let notes_title_val = notes_title.flatten();

    let club = sqlx::query_as::<_, Club>(
        r#"
        UPDATE clubs
        SET name        = COALESCE($2, name),
            callsign    = CASE WHEN $3 THEN $4 ELSE callsign END,
            description = CASE WHEN $5 THEN $6 ELSE description END,
            notes_url   = CASE WHEN $7 THEN $8 ELSE notes_url END,
            notes_title = CASE WHEN $9 THEN $10 ELSE notes_title END,
            updated_at  = now()
        WHERE id = $1
        RETURNING id, name, callsign, description, notes_url, notes_title,
                  logo_content_type, created_at, updated_at
        "#,
    )
    .bind(club_id)
    .bind(name)
    .bind(update_callsign)
    .bind(callsign_val)
    .bind(update_description)
    .bind(description_val)
    .bind(update_notes_url)
    .bind(notes_url_val)
    .bind(update_notes_title)
    .bind(notes_title_val)
    .fetch_optional(pool)
    .await?;

    Ok(club)
}

/// Directly set a club's notes URL and title.
///
/// Unlike `update_club`, this sets the values directly (NULL clears them).
pub async fn update_club_notes(
    pool: &PgPool,
    club_id: Uuid,
    notes_url: Option<&str>,
    notes_title: Option<&str>,
) -> Result<Option<Club>, AppError> {
    let club = sqlx::query_as::<_, Club>(
        r#"
        UPDATE clubs
        SET notes_url   = $2,
            notes_title = $3,
            updated_at  = now()
        WHERE id = $1
        RETURNING id, name, callsign, description, notes_url, notes_title,
                  logo_content_type, created_at, updated_at
        "#,
    )
    .bind(club_id)
    .bind(notes_url)
    .bind(notes_title)
    .fetch_optional(pool)
    .await?;

    Ok(club)
}

/// Delete a club by ID. Returns true if a row was deleted.
pub async fn delete_club(pool: &PgPool, club_id: Uuid) -> Result<bool, AppError> {
    let result = sqlx::query("DELETE FROM clubs WHERE id = $1")
        .bind(club_id)
        .execute(pool)
        .await?;

    Ok(result.rows_affected() > 0)
}

/// Bump `clubs.updated_at` so the `/v1/clubs` ETag fingerprint
/// (`get_clubs_fingerprint`) moves. Every roster mutation must call this:
/// the fingerprint only sees `clubs.updated_at` and `club_members.joined_at`,
/// so a removal or role change that doesn't touch the club would otherwise
/// leave clients on `304 Not Modified` with the old roster indefinitely.
async fn touch_club(
    conn: &mut sqlx::PgConnection,
    club_id: Uuid,
) -> Result<(), AppError> {
    sqlx::query("UPDATE clubs SET updated_at = now() WHERE id = $1")
        .bind(club_id)
        .execute(conn)
        .await?;
    Ok(())
}

/// Add (or upsert) members to a club. Each entry is (callsign, role).
/// On conflict the role is updated.
pub async fn add_members(
    pool: &PgPool,
    club_id: Uuid,
    members: &[(String, String)],
) -> Result<Vec<ClubMember>, AppError> {
    if members.is_empty() {
        return Ok(vec![]);
    }

    let mut tx = pool.begin().await?;
    let mut inserted = Vec::with_capacity(members.len());

    for (callsign, role) in members {
        let member = sqlx::query_as::<_, ClubMember>(
            r#"
            INSERT INTO club_members (club_id, callsign, role)
            VALUES ($1, $2, $3)
            ON CONFLICT (club_id, callsign)
            DO UPDATE SET role = EXCLUDED.role
            RETURNING id, club_id, callsign, role, joined_at
            "#,
        )
        .bind(club_id)
        .bind(callsign.to_uppercase())
        .bind(role)
        .fetch_one(&mut *tx)
        .await?;

        inserted.push(member);
    }

    touch_club(&mut tx, club_id).await?;
    tx.commit().await?;

    Ok(inserted)
}

/// Remove a member from a club. Returns true if a row was deleted.
pub async fn remove_member(pool: &PgPool, club_id: Uuid, callsign: &str) -> Result<bool, AppError> {
    let mut tx = pool.begin().await?;
    let result = sqlx::query(
        r#"
        DELETE FROM club_members
        WHERE club_id = $1 AND callsign = $2
        "#,
    )
    .bind(club_id)
    .bind(callsign.to_uppercase())
    .execute(&mut *tx)
    .await?;

    let removed = result.rows_affected() > 0;
    if removed {
        touch_club(&mut tx, club_id).await?;
    }
    tx.commit().await?;

    Ok(removed)
}

/// Update a member's role. Returns true if the row was updated.
pub async fn update_member_role(
    pool: &PgPool,
    club_id: Uuid,
    callsign: &str,
    role: &str,
) -> Result<bool, AppError> {
    let mut tx = pool.begin().await?;
    let result = sqlx::query(
        r#"
        UPDATE club_members
        SET role = $3
        WHERE club_id = $1 AND callsign = $2
        "#,
    )
    .bind(club_id)
    .bind(callsign.to_uppercase())
    .bind(role)
    .execute(&mut *tx)
    .await?;

    let updated = result.rows_affected() > 0;
    if updated {
        touch_club(&mut tx, club_id).await?;
    }
    tx.commit().await?;

    Ok(updated)
}

// ---------------------------------------------------------------------------
// Roster sync (notes-URL reconciliation)
// ---------------------------------------------------------------------------

/// Outcome of reconciling a club roster against its upstream notes file.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct RosterReconcile {
    /// Callsigns inserted as `member`.
    pub added: Vec<String>,
    /// `member`-role callsigns deleted because they left the upstream list.
    pub removed: Vec<String>,
    /// Callsigns already on the roster and still upstream (any role).
    pub unchanged: usize,
}

/// Clubs that have a notes URL configured, i.e. every club the roster
/// aggregator should keep in sync.
pub async fn list_clubs_with_notes_url(pool: &PgPool) -> Result<Vec<Club>, AppError> {
    let clubs = sqlx::query_as::<_, Club>(
        r#"
        SELECT id, name, callsign, description, notes_url, notes_title,
               logo_content_type, created_at, updated_at
        FROM clubs
        WHERE notes_url IS NOT NULL AND notes_url <> ''
        ORDER BY name
        "#,
    )
    .fetch_all(pool)
    .await?;

    Ok(clubs)
}

/// Make the club's roster match `callsigns` (already uppercased, deduped):
/// missing callsigns are inserted as `member`; `member`-role rows not in the
/// list are deleted. `admin`-role rows are never removed — admins are
/// assigned by hand and the upstream list knows nothing about them. Runs in
/// one transaction and bumps `clubs.updated_at` when anything changed so the
/// ETag moves.
pub async fn reconcile_roster(
    pool: &PgPool,
    club_id: Uuid,
    callsigns: &[String],
) -> Result<RosterReconcile, AppError> {
    let mut tx = pool.begin().await?;

    let added: Vec<String> = sqlx::query_scalar(
        r#"
        INSERT INTO club_members (club_id, callsign, role)
        SELECT $1, cs, 'member'
        FROM UNNEST($2::text[]) AS cs
        ON CONFLICT (club_id, callsign) DO NOTHING
        RETURNING callsign
        "#,
    )
    .bind(club_id)
    .bind(callsigns)
    .fetch_all(&mut *tx)
    .await?;

    let removed: Vec<String> = sqlx::query_scalar(
        r#"
        DELETE FROM club_members
        WHERE club_id = $1
          AND role = 'member'
          AND callsign <> ALL($2::text[])
        RETURNING callsign
        "#,
    )
    .bind(club_id)
    .bind(callsigns)
    .fetch_all(&mut *tx)
    .await?;

    let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM club_members WHERE club_id = $1")
        .bind(club_id)
        .fetch_one(&mut *tx)
        .await?;

    if !added.is_empty() || !removed.is_empty() {
        touch_club(&mut tx, club_id).await?;
    }
    tx.commit().await?;

    // Admins that are also upstream count as unchanged; admins that are not
    // upstream are kept but aren't "unchanged from the list", so subtract
    // only what we inserted this pass.
    let unchanged = (total as usize).saturating_sub(added.len());

    Ok(RosterReconcile {
        added,
        removed,
        unchanged,
    })
}

/// Record the outcome of a roster sync attempt on the club row.
pub async fn record_roster_sync(
    pool: &PgPool,
    club_id: Uuid,
    status: &str,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        UPDATE clubs
        SET roster_synced_at = now(),
            roster_sync_status = $2
        WHERE id = $1
        "#,
    )
    .bind(club_id)
    .bind(status)
    .execute(pool)
    .await?;
    Ok(())
}

/// List all clubs with member counts (admin).
pub async fn list_all_clubs(pool: &PgPool) -> Result<Vec<ClubWithCount>, AppError> {
    let clubs = sqlx::query_as::<_, ClubWithCount>(
        r#"
        SELECT c.id, c.name, c.callsign, c.description,
               c.notes_url, c.notes_title,
               (c.logo_data IS NOT NULL) AS has_logo,
               c.created_at, c.updated_at,
               COALESCE(counts.member_count, 0) AS member_count,
               c.roster_synced_at, c.roster_sync_status
        FROM clubs c
        LEFT JOIN (
            SELECT club_id, COUNT(*) AS member_count
            FROM club_members
            GROUP BY club_id
        ) counts ON counts.club_id = c.id
        ORDER BY c.name
        "#,
    )
    .fetch_all(pool)
    .await?;

    Ok(clubs)
}

// ---------------------------------------------------------------------------
// Authenticated queries
// ---------------------------------------------------------------------------

/// The set of callsigns the caller provably owns: their current callsign, every
/// callsign in their own `callsign_history`, and any callsign verified on their
/// Phase 5 account. Used to authorize the `?callsigns=` prior-callsign lookup so
/// a caller cannot read a foreign user's club memberships/rosters (CAR-308).
pub async fn owned_callsigns(
    pool: &PgPool,
    current: &str,
    account_id: Option<Uuid>,
) -> Result<std::collections::HashSet<String>, AppError> {
    let mut set = std::collections::HashSet::new();
    set.insert(current.to_uppercase());

    // Prior calls this user actually changed through (same users row).
    let history = sqlx::query_as::<_, (String, String)>(
        r#"
        SELECT ch.old_callsign, ch.new_callsign
        FROM callsign_history ch
        JOIN users u ON u.id = ch.user_id
        WHERE UPPER(u.callsign) = UPPER($1)
        "#,
    )
    .bind(current)
    .fetch_all(pool)
    .await?;
    for (old, new) in history {
        set.insert(old.to_uppercase());
        set.insert(new.to_uppercase());
    }

    // Callsigns verified on the caller's account (OAuth sessions only).
    if let Some(aid) = account_id {
        let verified =
            sqlx::query_scalar::<_, String>("SELECT callsign FROM account_callsigns WHERE account_id = $1")
                .bind(aid)
                .fetch_all(pool)
                .await?;
        for c in verified {
            set.insert(c.to_uppercase());
        }
    }

    Ok(set)
}

/// Get all clubs that any of the given callsigns belong to, with member
/// counts. Used to support users who recently changed callsigns and
/// still want to see clubs they joined under prior calls.
pub async fn get_clubs_for_callsigns(
    pool: &PgPool,
    callsigns: &[String],
) -> Result<Vec<ClubWithCount>, AppError> {
    let upper: Vec<String> = callsigns.iter().map(|c| c.to_uppercase()).collect();
    let clubs = sqlx::query_as::<_, ClubWithCount>(
        r#"
        SELECT DISTINCT c.id, c.name, c.callsign, c.description,
               c.notes_url, c.notes_title,
               (c.logo_data IS NOT NULL) AS has_logo,
               c.created_at, c.updated_at,
               counts.member_count,
               c.roster_synced_at, c.roster_sync_status
        FROM clubs c
        JOIN club_members cm ON cm.club_id = c.id
        JOIN (
            SELECT club_id, COUNT(*) AS member_count
            FROM club_members
            GROUP BY club_id
        ) counts ON counts.club_id = c.id
        WHERE cm.callsign = ANY($1)
        ORDER BY c.name
        "#,
    )
    .bind(&upper)
    .fetch_all(pool)
    .await?;

    Ok(clubs)
}

/// Get a single club by ID.
pub async fn get_club_detail(pool: &PgPool, club_id: Uuid) -> Result<Option<Club>, AppError> {
    let club = sqlx::query_as::<_, Club>(
        r#"
        SELECT id, name, callsign, description, notes_url, notes_title,
               logo_content_type, created_at, updated_at
        FROM clubs
        WHERE id = $1
        "#,
    )
    .bind(club_id)
    .fetch_optional(pool)
    .await?;

    Ok(club)
}

/// Get club members enriched with participant presence data.
/// LEFT JOINs participants for last_seen_at and Carrier Wave user detection.
pub async fn get_club_members_enriched(
    pool: &PgPool,
    club_id: Uuid,
) -> Result<Vec<EnrichedClubMember>, AppError> {
    let members = sqlx::query_as::<_, EnrichedClubMember>(
        r#"
        SELECT cm.callsign,
               cm.role,
               cm.joined_at,
               p.last_seen_at,
               CAST(NULL AS TEXT) AS last_grid,
               COALESCE(p.id IS NOT NULL, false) AS is_carrier_wave_user
        FROM club_members cm
        LEFT JOIN participants p ON UPPER(p.callsign) = cm.callsign
        WHERE cm.club_id = $1
        ORDER BY cm.role = 'admin' DESC, cm.callsign
        "#,
    )
    .bind(club_id)
    .fetch_all(pool)
    .await?;

    Ok(members)
}

/// Get activities from club members, cursor-paginated by created_at DESC.
pub async fn get_club_activity(
    pool: &PgPool,
    club_id: Uuid,
    cursor: Option<DateTime<Utc>>,
    limit: i64,
) -> Result<Vec<ActivityWithCallsign>, AppError> {
    let limit = limit.clamp(1, 100);

    let rows = if let Some(before) = cursor {
        sqlx::query_as::<_, ActivityWithCallsign>(
            r#"
            SELECT a.id, a.callsign, a.user_id, a.activity_type,
                   a.timestamp, a.details, a.created_at
            FROM activities a
            JOIN club_members cm ON cm.callsign = UPPER(a.callsign)
            WHERE cm.club_id = $1
              AND a.created_at < $2
            ORDER BY a.created_at DESC
            LIMIT $3
            "#,
        )
        .bind(club_id)
        .bind(before)
        .bind(limit)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, ActivityWithCallsign>(
            r#"
            SELECT a.id, a.callsign, a.user_id, a.activity_type,
                   a.timestamp, a.details, a.created_at
            FROM activities a
            JOIN club_members cm ON cm.callsign = UPPER(a.callsign)
            WHERE cm.club_id = $1
            ORDER BY a.created_at DESC
            LIMIT $2
            "#,
        )
        .bind(club_id)
        .bind(limit)
        .fetch_all(pool)
        .await?
    };

    Ok(rows)
}

/// Enriched member row that includes club_id for batch loading across multiple clubs.
#[derive(Debug, Clone, FromRow)]
pub struct EnrichedClubMemberWithClub {
    pub club_id: Uuid,
    pub callsign: String,
    pub role: String,
    pub joined_at: DateTime<Utc>,
    pub last_seen_at: Option<DateTime<Utc>>,
    pub last_grid: Option<String>,
    pub is_carrier_wave_user: bool,
}

/// Get enriched members for multiple clubs in a single query (avoids N+1).
pub async fn get_members_for_clubs(
    pool: &PgPool,
    club_ids: &[Uuid],
) -> Result<Vec<EnrichedClubMemberWithClub>, AppError> {
    if club_ids.is_empty() {
        return Ok(vec![]);
    }

    let members = sqlx::query_as::<_, EnrichedClubMemberWithClub>(
        r#"
        SELECT cm.club_id,
               cm.callsign,
               cm.role,
               cm.joined_at,
               p.last_seen_at,
               CAST(NULL AS TEXT) AS last_grid,
               COALESCE(p.id IS NOT NULL, false) AS is_carrier_wave_user
        FROM club_members cm
        LEFT JOIN participants p ON UPPER(p.callsign) = cm.callsign
        WHERE cm.club_id = ANY($1)
        ORDER BY cm.club_id, cm.role = 'admin' DESC, cm.callsign
        "#,
    )
    .bind(club_ids)
    .fetch_all(pool)
    .await?;

    Ok(members)
}

/// Compute a fingerprint for all clubs any of the given callsigns
/// belong to. Returns epoch-seconds of the latest mutation (club update
/// or member change). Used to generate ETags for conditional sync.
pub async fn get_clubs_fingerprint(
    pool: &PgPool,
    callsigns: &[String],
) -> Result<i64, AppError> {
    let upper: Vec<String> = callsigns.iter().map(|c| c.to_uppercase()).collect();
    let ts: Option<DateTime<Utc>> = sqlx::query_scalar(
        r#"
        SELECT GREATEST(
            (SELECT MAX(c.updated_at)
             FROM clubs c
             JOIN club_members cm ON cm.club_id = c.id
             WHERE cm.callsign = ANY($1)),
            (SELECT MAX(cm2.joined_at)
             FROM club_members cm2
             JOIN club_members my ON my.club_id = cm2.club_id
             WHERE my.callsign = ANY($1))
        )
        "#,
    )
    .bind(&upper)
    .fetch_one(pool)
    .await?;

    Ok(ts.map(|t| t.timestamp()).unwrap_or(0))
}

/// Lightweight membership row: just callsign + club name for the cache.
#[derive(Debug, Clone, FromRow)]
pub struct MembershipRow {
    pub club_name: String,
    pub callsign: String,
}

/// Get all member callsigns grouped by club name for any of the given
/// callsigns' clubs. Returns only (club_name, callsign) pairs — no
/// roles, dates, or enrichment.
pub async fn get_membership_callsigns(
    pool: &PgPool,
    callsigns: &[String],
) -> Result<Vec<MembershipRow>, AppError> {
    let upper: Vec<String> = callsigns.iter().map(|c| c.to_uppercase()).collect();
    let rows = sqlx::query_as::<_, MembershipRow>(
        r#"
        SELECT c.name AS club_name, cm2.callsign
        FROM club_members cm2
        JOIN clubs c ON c.id = cm2.club_id
        WHERE cm2.club_id IN (
            SELECT club_id FROM club_members WHERE callsign = ANY($1)
        )
        ORDER BY c.name, cm2.callsign
        "#,
    )
    .bind(&upper)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Check whether a callsign is a member of a given club.
pub async fn is_club_member(
    pool: &PgPool,
    club_id: Uuid,
    callsign: &str,
) -> Result<bool, AppError> {
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM club_members WHERE club_id = $1 AND callsign = $2)",
    )
    .bind(club_id)
    .bind(callsign.to_uppercase())
    .fetch_one(pool)
    .await?;

    Ok(exists)
}

// ---------------------------------------------------------------------------
// Logo operations
// ---------------------------------------------------------------------------

/// Logo data row (image bytes + content type).
#[derive(Debug, Clone, FromRow)]
pub struct ClubLogo {
    pub logo_data: Vec<u8>,
    pub logo_content_type: String,
}

/// Get a club's logo data and content type.
pub async fn get_club_logo(pool: &PgPool, club_id: Uuid) -> Result<Option<ClubLogo>, AppError> {
    let row = sqlx::query_as::<_, ClubLogo>(
        r#"
        SELECT logo_data, logo_content_type
        FROM clubs
        WHERE id = $1 AND logo_data IS NOT NULL
        "#,
    )
    .bind(club_id)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

/// Store or replace a club's logo.
pub async fn set_club_logo(
    pool: &PgPool,
    club_id: Uuid,
    logo_data: &[u8],
    content_type: &str,
) -> Result<bool, AppError> {
    let result = sqlx::query(
        r#"
        UPDATE clubs
        SET logo_data = $2,
            logo_content_type = $3,
            updated_at = now()
        WHERE id = $1
        "#,
    )
    .bind(club_id)
    .bind(logo_data)
    .bind(content_type)
    .execute(pool)
    .await?;

    Ok(result.rows_affected() > 0)
}

/// Remove a club's logo.
pub async fn delete_club_logo(pool: &PgPool, club_id: Uuid) -> Result<bool, AppError> {
    let result = sqlx::query(
        r#"
        UPDATE clubs
        SET logo_data = NULL,
            logo_content_type = NULL,
            updated_at = now()
        WHERE id = $1
        "#,
    )
    .bind(club_id)
    .execute(pool)
    .await?;

    Ok(result.rows_affected() > 0)
}
