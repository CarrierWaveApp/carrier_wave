use sqlx::PgPool;

use crate::error::AppError;
use crate::models::equipment_usage::EquipmentUsageEntry;

/// Record a batch of equipment usage events.
pub async fn record_usage(
    pool: &PgPool,
    entries: &[EquipmentUsageEntry],
    app_version: Option<&str>,
) -> Result<usize, AppError> {
    let mut count = 0;

    for entry in entries {
        sqlx::query(
            r#"
            INSERT INTO equipment_usage (
                catalog_id, category, is_custom,
                custom_name, custom_manufacturer,
                custom_bands, custom_modes,
                custom_max_power_watts, custom_portability,
                session_mode, session_band, session_program,
                paired_catalog_ids, app_version
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
            "#,
        )
        .bind(&entry.catalog_id)
        .bind(&entry.category)
        .bind(entry.is_custom)
        .bind(&entry.custom_name)
        .bind(&entry.custom_manufacturer)
        .bind(&entry.custom_bands)
        .bind(&entry.custom_modes)
        .bind(entry.custom_max_power_watts)
        .bind(&entry.custom_portability)
        .bind(&entry.session_mode)
        .bind(&entry.session_band)
        .bind(&entry.session_program)
        .bind(&entry.paired_with)
        .bind(app_version)
        .execute(pool)
        .await?;

        count += 1;
    }

    Ok(count)
}
