use sqlx::PgPool;

use crate::error::AppError;
use crate::models::program::{CreateProgramRequest, ProgramRow, UpdateProgramRequest};

/// List all active programs ordered by sort_order.
pub async fn list_programs(pool: &PgPool) -> Result<Vec<ProgramRow>, AppError> {
    let rows = sqlx::query_as::<_, ProgramRow>(
        r#"
        SELECT slug, name, short_name, icon, icon_url, website, server_base_url,
               reference_label, reference_format, reference_example,
               multi_ref_allowed, activation_threshold, supports_rove, capabilities,
               adif_my_sig, adif_my_sig_info, adif_sig_field, adif_sig_info_field,
               data_entry_label, data_entry_placeholder, data_entry_format,
               sort_order, is_active, created_at, updated_at
        FROM programs
        WHERE is_active = true
        ORDER BY sort_order
        "#,
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Get a single active program by slug.
pub async fn get_program(pool: &PgPool, slug: &str) -> Result<Option<ProgramRow>, AppError> {
    let row = sqlx::query_as::<_, ProgramRow>(
        r#"
        SELECT slug, name, short_name, icon, icon_url, website, server_base_url,
               reference_label, reference_format, reference_example,
               multi_ref_allowed, activation_threshold, supports_rove, capabilities,
               adif_my_sig, adif_my_sig_info, adif_sig_field, adif_sig_info_field,
               data_entry_label, data_entry_placeholder, data_entry_format,
               sort_order, is_active, created_at, updated_at
        FROM programs
        WHERE slug = $1 AND is_active = true
        "#,
    )
    .bind(slug)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

/// List all programs (including inactive) ordered by sort_order. Admin use.
pub async fn list_all_programs(pool: &PgPool) -> Result<Vec<ProgramRow>, AppError> {
    let rows = sqlx::query_as::<_, ProgramRow>(
        r#"
        SELECT slug, name, short_name, icon, icon_url, website, server_base_url,
               reference_label, reference_format, reference_example,
               multi_ref_allowed, activation_threshold, supports_rove, capabilities,
               adif_my_sig, adif_my_sig_info, adif_sig_field, adif_sig_info_field,
               data_entry_label, data_entry_placeholder, data_entry_format,
               sort_order, is_active, created_at, updated_at
        FROM programs
        ORDER BY sort_order
        "#,
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Get any program by slug (including inactive). Admin use.
pub async fn get_any_program(pool: &PgPool, slug: &str) -> Result<Option<ProgramRow>, AppError> {
    let row = sqlx::query_as::<_, ProgramRow>(
        r#"
        SELECT slug, name, short_name, icon, icon_url, website, server_base_url,
               reference_label, reference_format, reference_example,
               multi_ref_allowed, activation_threshold, supports_rove, capabilities,
               adif_my_sig, adif_my_sig_info, adif_sig_field, adif_sig_info_field,
               data_entry_label, data_entry_placeholder, data_entry_format,
               sort_order, is_active, created_at, updated_at
        FROM programs
        WHERE slug = $1
        "#,
    )
    .bind(slug)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

/// Create a new program.
pub async fn create_program(
    pool: &PgPool,
    req: &CreateProgramRequest,
) -> Result<ProgramRow, AppError> {
    let row = sqlx::query_as::<_, ProgramRow>(
        r#"
        INSERT INTO programs (
            slug, name, short_name, icon, icon_url, website, server_base_url,
            reference_label, reference_format, reference_example,
            multi_ref_allowed, activation_threshold, supports_rove, capabilities,
            adif_my_sig, adif_my_sig_info, adif_sig_field, adif_sig_info_field,
            data_entry_label, data_entry_placeholder, data_entry_format,
            sort_order
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
                $15, $16, $17, $18, $19, $20, $21, $22)
        RETURNING slug, name, short_name, icon, icon_url, website, server_base_url,
                  reference_label, reference_format, reference_example,
                  multi_ref_allowed, activation_threshold, supports_rove, capabilities,
                  adif_my_sig, adif_my_sig_info, adif_sig_field, adif_sig_info_field,
                  data_entry_label, data_entry_placeholder, data_entry_format,
                  sort_order, is_active, created_at, updated_at
        "#,
    )
    .bind(&req.slug)
    .bind(&req.name)
    .bind(&req.short_name)
    .bind(&req.icon)
    .bind(&req.icon_url)
    .bind(&req.website)
    .bind(&req.server_base_url)
    .bind(&req.reference_label)
    .bind(&req.reference_format)
    .bind(&req.reference_example)
    .bind(req.multi_ref_allowed)
    .bind(req.activation_threshold)
    .bind(req.supports_rove)
    .bind(&req.capabilities)
    .bind(&req.adif_my_sig)
    .bind(&req.adif_my_sig_info)
    .bind(&req.adif_sig_field)
    .bind(&req.adif_sig_info_field)
    .bind(&req.data_entry_label)
    .bind(&req.data_entry_placeholder)
    .bind(&req.data_entry_format)
    .bind(req.sort_order)
    .fetch_one(pool)
    .await?;

    Ok(row)
}

/// Update an existing program. Only provided fields are changed.
pub async fn update_program(
    pool: &PgPool,
    slug: &str,
    req: &UpdateProgramRequest,
) -> Result<Option<ProgramRow>, AppError> {
    let row = sqlx::query_as::<_, ProgramRow>(
        r#"
        UPDATE programs SET
            name = COALESCE($2, name),
            short_name = COALESCE($3, short_name),
            icon = COALESCE($4, icon),
            icon_url = CASE WHEN $5::boolean THEN $6 ELSE icon_url END,
            website = CASE WHEN $7::boolean THEN $8 ELSE website END,
            server_base_url = CASE WHEN $9::boolean THEN $10 ELSE server_base_url END,
            reference_label = COALESCE($11, reference_label),
            reference_format = CASE WHEN $12::boolean THEN $13 ELSE reference_format END,
            reference_example = CASE WHEN $14::boolean THEN $15 ELSE reference_example END,
            multi_ref_allowed = COALESCE($16, multi_ref_allowed),
            activation_threshold = CASE WHEN $17::boolean THEN $18 ELSE activation_threshold END,
            supports_rove = COALESCE($19, supports_rove),
            capabilities = COALESCE($20, capabilities),
            adif_my_sig = CASE WHEN $21::boolean THEN $22 ELSE adif_my_sig END,
            adif_my_sig_info = CASE WHEN $23::boolean THEN $24 ELSE adif_my_sig_info END,
            adif_sig_field = CASE WHEN $25::boolean THEN $26 ELSE adif_sig_field END,
            adif_sig_info_field = CASE WHEN $27::boolean THEN $28 ELSE adif_sig_info_field END,
            data_entry_label = CASE WHEN $29::boolean THEN $30 ELSE data_entry_label END,
            data_entry_placeholder = CASE WHEN $31::boolean THEN $32 ELSE data_entry_placeholder END,
            data_entry_format = CASE WHEN $33::boolean THEN $34 ELSE data_entry_format END,
            sort_order = COALESCE($35, sort_order),
            is_active = COALESCE($36, is_active),
            updated_at = now()
        WHERE slug = $1
        RETURNING slug, name, short_name, icon, icon_url, website, server_base_url,
                  reference_label, reference_format, reference_example,
                  multi_ref_allowed, activation_threshold, supports_rove, capabilities,
                  adif_my_sig, adif_my_sig_info, adif_sig_field, adif_sig_info_field,
                  data_entry_label, data_entry_placeholder, data_entry_format,
                  sort_order, is_active, created_at, updated_at
        "#,
    )
    .bind(slug)
    .bind(req.name.as_deref())
    .bind(req.short_name.as_deref())
    .bind(req.icon.as_deref())
    // icon_url: Option<Option<String>> — outer Some means "set this", None means "don't touch"
    .bind(req.icon_url.is_some())
    .bind(req.icon_url.as_ref().and_then(|v| v.as_deref()))
    .bind(req.website.is_some())
    .bind(req.website.as_ref().and_then(|v| v.as_deref()))
    .bind(req.server_base_url.is_some())
    .bind(req.server_base_url.as_ref().and_then(|v| v.as_deref()))
    .bind(req.reference_label.as_deref())
    .bind(req.reference_format.is_some())
    .bind(req.reference_format.as_ref().and_then(|v| v.as_deref()))
    .bind(req.reference_example.is_some())
    .bind(req.reference_example.as_ref().and_then(|v| v.as_deref()))
    .bind(req.multi_ref_allowed)
    .bind(req.activation_threshold.is_some())
    .bind(req.activation_threshold.as_ref().and_then(|v| v.as_ref()))
    .bind(req.supports_rove)
    .bind(req.capabilities.as_deref())
    .bind(req.adif_my_sig.is_some())
    .bind(req.adif_my_sig.as_ref().and_then(|v| v.as_deref()))
    .bind(req.adif_my_sig_info.is_some())
    .bind(req.adif_my_sig_info.as_ref().and_then(|v| v.as_deref()))
    .bind(req.adif_sig_field.is_some())
    .bind(req.adif_sig_field.as_ref().and_then(|v| v.as_deref()))
    .bind(req.adif_sig_info_field.is_some())
    .bind(req.adif_sig_info_field.as_ref().and_then(|v| v.as_deref()))
    .bind(req.data_entry_label.is_some())
    .bind(req.data_entry_label.as_ref().and_then(|v| v.as_deref()))
    .bind(req.data_entry_placeholder.is_some())
    .bind(req.data_entry_placeholder.as_ref().and_then(|v| v.as_deref()))
    .bind(req.data_entry_format.is_some())
    .bind(req.data_entry_format.as_ref().and_then(|v| v.as_deref()))
    .bind(req.sort_order)
    .bind(req.is_active)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

/// Delete a program by slug. Returns true if deleted.
pub async fn delete_program(pool: &PgPool, slug: &str) -> Result<bool, AppError> {
    let result = sqlx::query("DELETE FROM programs WHERE slug = $1")
        .bind(slug)
        .execute(pool)
        .await?;

    Ok(result.rows_affected() > 0)
}

/// Get the version (max updated_at as epoch seconds) for active programs.
pub async fn get_programs_version(pool: &PgPool) -> Result<i64, AppError> {
    let version: Option<i64> = sqlx::query_scalar(
        "SELECT EXTRACT(EPOCH FROM MAX(updated_at))::bigint FROM programs WHERE is_active = true",
    )
    .fetch_one(pool)
    .await?;

    Ok(version.unwrap_or(0))
}
