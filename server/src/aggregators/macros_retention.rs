//! 90-day retention + daily aggregation for `macro_run_events` (CAR-271 T9).
//!
//! Wakes once a day, rolls every day-bucket that still has raw run events up
//! into `macro_run_aggregates`, then deletes raw events older than the
//! retention horizon.
//!
//! The horizon is **day-aligned** — `date_trunc('day', now - retain_days)` —
//! so a day-bucket is either kept whole or deleted whole. The delete never
//! leaves a partially-emptied bucket behind for the next sweep to
//! re-aggregate from (CAR-325). As a second guard the aggregate upsert is
//! monotonic: on conflict it keeps the larger of the stored and the freshly
//! computed counts, so re-aggregating a bucket from a subset of its rows
//! (late-arriving events, a manual cleanup) can never lower a roll-up.
//!
//! Re-running a sweep is therefore safe: the upsert keys on `(macro_id, day)`
//! and never shrinks a row, and the delete is a no-op once nothing is older
//! than the horizon. Note this is "safe to repeat" rather than strictly
//! idempotent — a sweep that sees new rows for a still-retained day raises
//! that day's counts, which is the intended behaviour.

use std::time::Duration;

use chrono::{DateTime, Utc};
use sqlx::PgPool;

/// One sweep — rolls up *all* days that have raw events, then deletes raw
/// events older than `retain_days` (day-aligned). Called once per
/// `interval_hours` from [`poll_loop`].
pub async fn sweep(pool: &PgPool, retain_days: i32) -> Result<RetentionStats, sqlx::Error> {
    sweep_at(pool, retain_days, None).await
}

/// [`sweep`] with an explicit "now". `None` uses the database clock; tests
/// pass a fixed instant so a sequence of daily sweeps can be replayed
/// deterministically.
pub async fn sweep_at(
    pool: &PgPool,
    retain_days: i32,
    now: Option<DateTime<Utc>>,
) -> Result<RetentionStats, sqlx::Error> {
    let mut stats = RetentionStats::default();
    let mut tx = pool.begin().await?;

    // Aggregate every day-bucket that has raw rows. The upsert is monotonic:
    // a re-run for the same day can raise a count (new rows arrived) but
    // never lower it (rows have since been deleted). `failures_by_step`
    // follows whichever failure_count wins so the two stay consistent.
    let aggregated = sqlx::query(
        "INSERT INTO macro_run_aggregates (macro_id, day, success_count, failure_count, failures_by_step) \
         SELECT \
            macro_id, \
            date_trunc('day', occurred_at)::date AS day, \
            COUNT(*) FILTER (WHERE success) AS success_count, \
            COUNT(*) FILTER (WHERE NOT success) AS failure_count, \
            COALESCE( \
                jsonb_object_agg( \
                    COALESCE(failed_step_index::text, 'null'), \
                    1 \
                ) FILTER (WHERE NOT success), \
                '{}'::jsonb \
            ) AS failures_by_step \
         FROM macro_run_events \
         GROUP BY macro_id, day \
         ON CONFLICT (macro_id, day) DO UPDATE SET \
            success_count = GREATEST(macro_run_aggregates.success_count, EXCLUDED.success_count), \
            failure_count = GREATEST(macro_run_aggregates.failure_count, EXCLUDED.failure_count), \
            failures_by_step = CASE \
                WHEN EXCLUDED.failure_count >= macro_run_aggregates.failure_count \
                    THEN EXCLUDED.failures_by_step \
                ELSE macro_run_aggregates.failures_by_step \
            END",
    )
    .execute(&mut *tx)
    .await?;
    stats.aggregated_rows = aggregated.rows_affected() as i64;

    // Delete raw events past the retention horizon. The horizon is truncated
    // to the start of its day so whole day-buckets go at once — a bucket is
    // never left half-deleted for the next sweep to re-aggregate from.
    let deleted = sqlx::query(
        "DELETE FROM macro_run_events \
         WHERE occurred_at < date_trunc( \
            'day', \
            COALESCE($2::timestamptz, NOW()) - make_interval(days => $1) \
         )",
    )
    .bind(retain_days)
    .bind(now)
    .execute(&mut *tx)
    .await?;
    stats.deleted_rows = deleted.rows_affected() as i64;

    tx.commit().await?;
    Ok(stats)
}

#[derive(Debug, Default, Clone, Copy)]
pub struct RetentionStats {
    pub aggregated_rows: i64,
    pub deleted_rows: i64,
}

pub struct MacrosRetentionConfig {
    pub interval_hours: u64,
    pub retain_days: i32,
}

pub async fn poll_loop(pool: PgPool, config: MacrosRetentionConfig) {
    let mut ticker = tokio::time::interval(Duration::from_secs(
        config.interval_hours.max(1) * 3600,
    ));
    ticker.tick().await; // skip immediate fire — let the server warm up

    loop {
        ticker.tick().await;
        match sweep(&pool, config.retain_days).await {
            Ok(stats) => {
                tracing::info!(
                    aggregated = stats.aggregated_rows,
                    deleted = stats.deleted_rows,
                    "macros retention sweep complete"
                );
            }
            Err(err) => {
                tracing::warn!(error = %err, "macros retention sweep failed");
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::OnceLock;
    use tokio::sync::Mutex;
    use uuid::Uuid;

    const RETAIN_DAYS: i32 = 90;

    /// Retention tests share the same `macro_run_events` table and the
    /// `sweep` query is global. Without a guard, parallel test runs delete
    /// rows out from under one another. Lock so they run serially while
    /// the rest of the test suite stays parallel.
    fn lock() -> &'static Mutex<()> {
        static M: OnceLock<Mutex<()>> = OnceLock::new();
        M.get_or_init(|| Mutex::new(()))
    }

    async fn pool() -> Option<PgPool> {
        let url = std::env::var("TEST_DATABASE_URL").ok()?;
        PgPool::connect(&url).await.ok()
    }

    async fn seed_macro(pool: &PgPool, slug: &str) -> Uuid {
        let id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO macros (id, slug, name, capabilities, args, steps, format, status, tags, applies_to) \
             VALUES ($1, $2, 'test', '{}'::jsonb, '[]'::jsonb, '[]'::jsonb, 2, 'approved', '{}', '{}')",
        )
        .bind(id)
        .bind(slug)
        .execute(pool)
        .await
        .unwrap();
        id
    }

    async fn cleanup(pool: &PgPool, slug: &str) {
        // Cascades to macro_run_events and macro_run_aggregates.
        sqlx::query("DELETE FROM macros WHERE slug = $1")
            .bind(slug)
            .execute(pool)
            .await
            .ok();
    }

    /// A fixed "now" at noon (database session timezone) so that the
    /// un-aligned horizon `now - RETAIN_DAYS` falls squarely inside a day
    /// bucket regardless of when the test runs.
    async fn fixed_noon(pool: &PgPool) -> DateTime<Utc> {
        let (noon,): (DateTime<Utc>,) =
            sqlx::query_as("SELECT date_trunc('day', NOW()) + interval '12 hours'")
                .fetch_one(pool)
                .await
                .unwrap();
        noon
    }

    /// Insert one successful run event at `date_trunc('day', now - RETAIN_DAYS)
    /// + offset` — i.e. relative to the start of the day bucket that sits
    /// exactly on the retention horizon for a sweep at `now`.
    async fn insert_on_horizon_day(
        pool: &PgPool,
        macro_id: Uuid,
        now: DateTime<Utc>,
        offset: &str,
    ) {
        sqlx::query(
            "INSERT INTO macro_run_events (macro_id, device_hash, success, occurred_at) \
             VALUES ($1, 'h', true, \
                date_trunc('day', $2::timestamptz - make_interval(days => $3)) + $4::interval)",
        )
        .bind(macro_id)
        .bind(now)
        .bind(RETAIN_DAYS)
        .bind(offset)
        .execute(pool)
        .await
        .unwrap();
    }

    async fn raw_count(pool: &PgPool, macro_id: Uuid) -> i64 {
        let (n,): (i64,) =
            sqlx::query_as("SELECT COUNT(*) FROM macro_run_events WHERE macro_id = $1")
                .bind(macro_id)
                .fetch_one(pool)
                .await
                .unwrap();
        n
    }

    /// `(success_count, failure_count)` summed over every aggregate row for
    /// the macro.
    async fn aggregate_totals(pool: &PgPool, macro_id: Uuid) -> (i64, i64) {
        sqlx::query_as(
            "SELECT COALESCE(SUM(success_count), 0)::bigint, \
                    COALESCE(SUM(failure_count), 0)::bigint \
             FROM macro_run_aggregates WHERE macro_id = $1",
        )
        .bind(macro_id)
        .fetch_one(pool)
        .await
        .unwrap()
    }

    #[tokio::test]
    async fn sweep_aggregates_and_deletes() {
        let _guard = lock().lock().await;
        let Some(pool) = pool().await else { return };
        let slug = format!("retention-{}", Uuid::new_v4());
        let macro_id = seed_macro(&pool, &slug).await;

        // 3 fresh successes + 1 fresh failure
        for ok in [true, true, true, false] {
            sqlx::query(
                "INSERT INTO macro_run_events (macro_id, device_hash, success, failed_step_index, occurred_at) \
                 VALUES ($1, 'h', $2, $3, NOW())",
            )
            .bind(macro_id)
            .bind(ok)
            .bind(if ok { None } else { Some(2_i32) })
            .execute(&pool)
            .await
            .unwrap();
        }
        // 1 old row (100 days back) so the delete branch fires.
        sqlx::query(
            "INSERT INTO macro_run_events (macro_id, device_hash, success, occurred_at) \
             VALUES ($1, 'h', true, NOW() - interval '100 days')",
        )
        .bind(macro_id)
        .execute(&pool)
        .await
        .unwrap();

        let stats = sweep(&pool, RETAIN_DAYS).await.unwrap();
        assert!(stats.deleted_rows >= 1, "expected to delete 100-day-old row");

        let (successes, failures) = aggregate_totals(&pool, macro_id).await;
        assert!(successes >= 3, "expected >=3 successes, got {successes}");
        assert!(failures >= 1, "expected >=1 failure, got {failures}");

        cleanup(&pool, &slug).await;
    }

    #[tokio::test]
    async fn sweep_is_idempotent() {
        let _guard = lock().lock().await;
        let Some(pool) = pool().await else { return };
        let slug = format!("retention-idem-{}", Uuid::new_v4());
        let macro_id = seed_macro(&pool, &slug).await;
        sqlx::query(
            "INSERT INTO macro_run_events (macro_id, device_hash, success, occurred_at) \
             VALUES ($1, 'h', true, NOW())",
        )
        .bind(macro_id)
        .execute(&pool)
        .await
        .unwrap();

        sweep(&pool, RETAIN_DAYS).await.unwrap();
        // Re-running must not duplicate the aggregate row.
        sweep(&pool, RETAIN_DAYS).await.unwrap();
        let count: (i64,) =
            sqlx::query_as("SELECT COUNT(*) FROM macro_run_aggregates WHERE macro_id = $1")
                .bind(macro_id)
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(count.0, 1);

        cleanup(&pool, &slug).await;
    }

    /// CAR-325: the delete horizon must be day-aligned. A row one minute into
    /// the horizon day survives even though it is older than `now - 90 days`;
    /// a row one minute before that day is deleted.
    #[tokio::test]
    async fn delete_horizon_is_day_aligned() {
        let _guard = lock().lock().await;
        let Some(pool) = pool().await else { return };
        let slug = format!("retention-align-{}", Uuid::new_v4());
        let macro_id = seed_macro(&pool, &slug).await;
        let now = fixed_noon(&pool).await;

        insert_on_horizon_day(&pool, macro_id, now, "1 minute").await; // keep
        insert_on_horizon_day(&pool, macro_id, now, "-1 minute").await; // delete

        sweep_at(&pool, RETAIN_DAYS, Some(now)).await.unwrap();

        let survivors: Vec<(bool,)> = sqlx::query_as(
            "SELECT occurred_at >= date_trunc('day', $2::timestamptz - make_interval(days => $3)) \
             FROM macro_run_events WHERE macro_id = $1",
        )
        .bind(macro_id)
        .bind(now)
        .bind(RETAIN_DAYS)
        .fetch_all(&pool)
        .await
        .unwrap();
        assert_eq!(survivors.len(), 1, "exactly one raw row should survive");
        assert!(
            survivors[0].0,
            "the surviving row must be inside the horizon day"
        );

        cleanup(&pool, &slug).await;
    }

    /// CAR-325 regression: replay three daily sweeps over a bucket that sits
    /// on the retention horizon. Before the fix, sweep k aggregated the
    /// bucket then deleted the part of it older than the un-aligned cutoff;
    /// sweep k+1 re-aggregated from the survivors (overwriting the correct
    /// count with an undercount) and deleted the rest; sweep k+2 froze the
    /// undercount forever. The roll-up must end at the true total.
    #[tokio::test]
    async fn consecutive_sweeps_preserve_horizon_bucket_count() {
        let _guard = lock().lock().await;
        let Some(pool) = pool().await else { return };
        let slug = format!("retention-seq-{}", Uuid::new_v4());
        let macro_id = seed_macro(&pool, &slug).await;
        let now = fixed_noon(&pool).await;

        // Five runs spread across the horizon day: two before noon (older
        // than the un-aligned `now - 90d`), three after.
        for offset in ["1 hour", "6 hours", "13 hours", "18 hours", "23 hours"] {
            insert_on_horizon_day(&pool, macro_id, now, offset).await;
        }

        // Sweep k: bucket is on the horizon — aggregated, kept whole.
        sweep_at(&pool, RETAIN_DAYS, Some(now)).await.unwrap();
        assert_eq!(aggregate_totals(&pool, macro_id).await.0, 5, "sweep k");
        assert_eq!(
            raw_count(&pool, macro_id).await,
            5,
            "sweep k keeps the whole bucket"
        );

        // Sweep k+1: bucket is now a full day past the horizon — deleted whole.
        sweep_at(&pool, RETAIN_DAYS, Some(now + chrono::Duration::days(1)))
            .await
            .unwrap();
        assert_eq!(aggregate_totals(&pool, macro_id).await.0, 5, "sweep k+1");
        assert_eq!(
            raw_count(&pool, macro_id).await,
            0,
            "sweep k+1 deletes the whole bucket"
        );

        // Sweep k+2: nothing left to re-aggregate; the roll-up stays correct.
        sweep_at(&pool, RETAIN_DAYS, Some(now + chrono::Duration::days(2)))
            .await
            .unwrap();
        assert_eq!(aggregate_totals(&pool, macro_id).await.0, 5, "sweep k+2");

        cleanup(&pool, &slug).await;
    }

    /// CAR-325 second guard: re-aggregating a bucket from a subset of its
    /// raw rows must never lower the stored counts.
    #[tokio::test]
    async fn reaggregation_never_lowers_stored_counts() {
        let _guard = lock().lock().await;
        let Some(pool) = pool().await else { return };
        let slug = format!("retention-mono-{}", Uuid::new_v4());
        let macro_id = seed_macro(&pool, &slug).await;

        // 3 successes + 2 failures, all today.
        for ok in [true, true, true, false, false] {
            sqlx::query(
                "INSERT INTO macro_run_events (macro_id, device_hash, success, failed_step_index, occurred_at) \
                 VALUES ($1, 'h', $2, $3, NOW())",
            )
            .bind(macro_id)
            .bind(ok)
            .bind(if ok { None } else { Some(1_i32) })
            .execute(&pool)
            .await
            .unwrap();
        }
        sweep(&pool, RETAIN_DAYS).await.unwrap();
        assert_eq!(aggregate_totals(&pool, macro_id).await, (3, 2));

        // Simulate rows vanishing underneath the aggregate (partial delete,
        // manual cleanup) — one success and one failure.
        sqlx::query(
            "DELETE FROM macro_run_events WHERE id IN ( \
                (SELECT id FROM macro_run_events WHERE macro_id = $1 AND success LIMIT 1), \
                (SELECT id FROM macro_run_events WHERE macro_id = $1 AND NOT success LIMIT 1))",
        )
        .bind(macro_id)
        .execute(&pool)
        .await
        .unwrap();
        assert_eq!(raw_count(&pool, macro_id).await, 3);

        sweep(&pool, RETAIN_DAYS).await.unwrap();
        assert_eq!(
            aggregate_totals(&pool, macro_id).await,
            (3, 2),
            "re-aggregation from a subset must not lower the roll-up"
        );

        cleanup(&pool, &slug).await;
    }
}
