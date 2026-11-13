//! Periodic batch evaluator for cumulative achievements.
//!
//! Sweeps callsigns with recent activity at a fixed cadence and runs the
//! batch-path evaluators against each one. Idempotent: re-awarding an
//! already-held achievement is a cheap no-op via the unique constraint.

use std::time::Duration;

use sqlx::PgPool;

use crate::achievements;

pub struct AchievementSweepConfig {
    pub interval_minutes: u64,
    pub recent_days: i32,
}

pub async fn poll_loop(pool: PgPool, config: AchievementSweepConfig) {
    let mut ticker =
        tokio::time::interval(Duration::from_secs(config.interval_minutes.max(1) * 60));
    // Skip the immediate-tick — let the server warm up first.
    ticker.tick().await;

    loop {
        ticker.tick().await;
        sweep_once(&pool, config.recent_days).await;
    }
}

async fn sweep_once(pool: &PgPool, recent_days: i32) {
    let callsigns = match achievements::recently_active_callsigns(pool, recent_days).await {
        Ok(rows) => rows,
        Err(err) => {
            tracing::warn!(error = %err, "Achievement sweep: failed to enumerate callsigns");
            return;
        }
    };

    let count = callsigns.len();
    if count == 0 {
        return;
    }

    for callsign in &callsigns {
        let ctx = achievements::EvalCtx {
            pool,
            callsign,
            triggering: None,
        };
        achievements::evaluate_batch(&ctx).await;
    }

    tracing::info!(callsigns = count, "Achievement batch sweep complete");
}
