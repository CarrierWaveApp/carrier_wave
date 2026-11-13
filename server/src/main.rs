use activities_server::{
    aggregators, auth, config, handlers, metrics, observability, rbn, snapshots, storage,
};

use std::net::SocketAddr;
use std::sync::Arc;

use axum::{
    extract::DefaultBodyLimit,
    http::{header, HeaderValue, Method, StatusCode},
    middleware,
    response::IntoResponse,
    routing::{delete, get, post, put},
    Extension, Json, Router,
};
use tokio::signal;
use sqlx::postgres::PgPoolOptions;
use tower_governor::{governor::GovernorConfigBuilder, GovernorLayer};
use tower_http::cors::CorsLayer;
use tower_http::services::{ServeDir, ServeFile};

use config::Config;

#[tokio::main]
async fn main() {
    // `.env` first so LOG_FORMAT / RUST_LOG set there reach the subscriber.
    dotenvy::dotenv().ok();

    // Initialize tracing. Format from LOG_FORMAT (default json); filter from
    // RUST_LOG. See server/docs/logging.md (CAR-156).
    let (log_format, unrecognized) = config::LogFormat::from_env();
    observability::init_tracing(log_format, unrecognized.as_deref());

    // Load configuration
    let config = Config::from_env().expect("Failed to load configuration");

    // Create database pool. One pool is shared by every HTTP handler, the
    // aggregators and the background loops, so it needs headroom beyond the
    // request path (CAR-159). `DATABASE_MAX_CONNECTIONS` (default 16) must
    // stay well under Postgres' `max_connections` (default 100) *summed
    // across every process on the same server* — production + staging
    // activities-server, pg_dump backups, psql sessions and superuser
    // reserved slots (`superuser_reserved_connections`, default 3) all draw
    // from the same budget.
    let pool = PgPoolOptions::new()
        .max_connections(config.database_max_connections)
        .connect(&config.database_url)
        .await
        .expect("Failed to connect to database");

    // Run migrations
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    tracing::info!("Database connected and migrations complete");

    // Restore from snapshot if tables are empty and a fresh snapshot exists
    if config.snapshot_enabled {
        match snapshots::try_restore(&pool, &config).await {
            Ok(true) => tracing::info!("Snapshot restore succeeded"),
            Ok(false) => {}
            Err(e) => tracing::warn!("Snapshot restore failed: {e}"),
        }
    }

    // Install Prometheus metrics
    let metrics_handle = metrics::install();
    metrics::spawn_pool_metrics(pool.clone());

    // Spawn spot aggregators and TTL cleanup
    if config.spots_enabled {
        aggregators::spawn_aggregators(pool.clone(), &config);
        tracing::info!("Spots system enabled");
    }

    // Spawn POTA stats aggregator (independent of spots)
    if config.pota_stats_aggregator_enabled {
        aggregators::spawn_pota_stats_aggregator(pool.clone(), &config);
    }

    // Spawn achievement batch evaluator
    if config.achievement_evaluator_enabled {
        aggregators::spawn_achievement_evaluator(pool.clone(), &config);
    }

    // Spawn park boundaries aggregator (requires POTA stats for park catalog)
    if config.park_boundaries_enabled {
        aggregators::spawn_park_boundaries_aggregator(pool.clone(), &config);
    }

    // Spawn Polish park boundaries aggregator (requires POTA stats for park catalog)
    if config.polish_park_boundaries_enabled {
        aggregators::spawn_polish_park_boundaries_aggregator(pool.clone(), &config);
    }

    // Spawn historic trails aggregator
    if config.historic_trails_enabled {
        aggregators::spawn_historic_trails_aggregator(pool.clone(), &config);
    }

    // Spawn callsign enrichment aggregator (CWops, future SKCC, etc.)
    if config.callsign_enrichment_aggregator_enabled {
        aggregators::spawn_callsign_enrichment_aggregator(pool.clone(), &config);
    }

    if config.amsat_status_aggregator_enabled {
        aggregators::spawn_amsat_status_aggregator(pool.clone(), &config);
    }

    // Spawn club roster aggregator (reconciles notes-URL clubs like BKG)
    if config.club_roster_sync_enabled {
        aggregators::spawn_club_rosters_aggregator(pool.clone(), &config);
    }

    // Spawn radio-macros run-event retention + daily aggregation (CAR-271 T9)
    if config.macros_retention_enabled {
        aggregators::spawn_macros_retention(pool.clone(), &config);
    }

    // Spawn RBN telnet ingester
    let rbn_store = rbn::SpotStore::new();
    if config.rbn_proxy_enabled {
        rbn::spawn_rbn_ingester(rbn_store.clone(), config.rbn_proxy_callsign.clone());
        metrics::spawn_rbn_metrics(rbn_store.clone());
        tracing::info!("RBN proxy enabled (login: {})", config.rbn_proxy_callsign);
    }

    // Spawn snapshot background loop
    if config.snapshot_enabled {
        let snap_pool = pool.clone();
        let snap_config = config.clone();
        tokio::spawn(async move {
            snapshots::snapshot_loop(snap_pool, snap_config).await;
        });
        tracing::info!(
            interval_hours = config.snapshot_interval_hours,
            max_age_hours = config.snapshot_max_age_hours,
            dir = %config.snapshot_dir,
            "Snapshot persistence enabled"
        );
    }

    // Propagation sidecar client (cheap to construct even when disabled).
    let propagation_client = handlers::PropagationClient::from_config(&config);
    if config.propagation_enabled {
        tracing::info!(
            url = %config.propagation_service_url,
            "Propagation predictions enabled"
        );
    }

    // Sync server blob store: S3 when configured, otherwise the in-memory store
    // (with local dev blob routes). Selected by `SYNC_S3_BUCKET`.
    let (blob_store, memory_blob_store) =
        storage::from_config(&config).expect("Failed to construct blob store");
    if memory_blob_store.is_some() {
        tracing::info!("Sync blob store: in-memory (dev) — set SYNC_S3_BUCKET for S3");
    } else {
        tracing::info!("Sync blob store: S3");
    }

    // Build router
    let app = create_router(
        pool.clone(),
        config.clone(),
        rbn_store,
        metrics_handle,
        propagation_client,
        blob_store,
        memory_blob_store,
    );

    // Start server
    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    tracing::info!("Starting server on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    // tower-governor's PeerIpKeyExtractor reads ConnectInfo<SocketAddr>; without
    // it, every request 500s with "Unable to extract key!" (CAR-143 regression).
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await
    .unwrap();

    tracing::info!("Server shut down gracefully");
}

async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("Failed to install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => tracing::info!("Received SIGINT, starting graceful shutdown"),
        _ = terminate => tracing::info!("Received SIGTERM, starting graceful shutdown"),
    }
}

#[allow(clippy::too_many_arguments)]
fn create_router(
    pool: sqlx::PgPool,
    config: Config,
    rbn_store: rbn::SpotStore,
    metrics_handle: metrics_exporter_prometheus::PrometheusHandle,
    propagation_client: handlers::PropagationClient,
    blob_store: Arc<dyn storage::BlobStore>,
    memory_blob_store: Option<Arc<storage::MemoryStore>>,
) -> Router {
    let propagation_enabled = config.propagation_enabled;

    // CAR-143: restrict CORS to the browser surfaces that actually call this
    // server. iOS Field + CW Sweep are native clients and ignore CORS, so the
    // allowlist only needs to cover the marketing site, the activities-server
    // host (admin web UI in prod), and the Vite dev server for local work on
    // server/web/. Methods and headers are tightened so a malicious origin
    // can't smuggle in PATCH/OPTIONS abuse.
    let cors = CorsLayer::new()
        .allow_origin(vec![
            HeaderValue::from_static("https://carrierwave.app"),
            HeaderValue::from_static("https://activities.carrierwave.app"),
            HeaderValue::from_static("http://localhost:5173"),
        ])
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PUT,
            Method::DELETE,
            Method::OPTIONS,
        ])
        .allow_headers([header::AUTHORIZATION, header::CONTENT_TYPE]);

    // CAR-143: per-IP rate limit for the public API. 10 req/s with a burst of
    // 20 — well above what either native client polls at, low enough to make
    // scripted abuse expensive. Excess requests get 429s automatically.
    let global_governor = Arc::new(
        GovernorConfigBuilder::default()
            .per_millisecond(100)
            .burst_size(20)
            .finish()
            .expect("global rate-limit config"),
    );

    // CAR-143: extra-tight limit on the /register vector. Creating a user is
    // the only public path that mints persistent rows, so cap it at 1/min/IP
    // (burst 1). A real user signs up once; anything else is abuse.
    let register_governor = Arc::new(
        GovernorConfigBuilder::default()
            .per_second(60)
            .burst_size(1)
            .finish()
            .expect("register rate-limit config"),
    );

    // Phase 5: build the OAuth verifier ONCE (JWT keys + revocation cache +
    // LISTEN/NOTIFY listener). Shared by the dual-auth middleware on the legacy
    // social routes AND the new /v1/auth/* routes. `None` when keys aren't
    // configured → only legacy `fd_` device tokens are accepted.
    let oauth_verifier = match auth::jwt::JwtKeys::from_env() {
        Ok(keys) => {
            let jwt = Arc::new(keys);
            let cache = Arc::new(auth::revocation::RevocationCache::new());
            tokio::spawn(auth::revocation::run_revocation_listener(
                pool.clone(),
                cache.clone(),
            ));
            Some(auth::middleware::OAuthVerifier { jwt, cache })
        }
        Err(e) => {
            tracing::warn!("OAuth disabled (JWT keys not configured): {e}");
            None
        }
    };
    let api_auth_state = auth::middleware::ApiAuthState {
        pool: pool.clone(),
        oauth: oauth_verifier.clone(),
    };

    // Shared by the /v1/auth/* routes and the third-party OAuth provider (which
    // needs it for the discovery document's endpoint URLs, mounted at the domain
    // root rather than under /v1).
    let auth_settings = Arc::new(handlers::auth::AuthSettings {
        base_url: config
            .base_url
            .clone()
            .unwrap_or_else(|| "https://activities.carrierwave.app".to_string()),
    });

    // Public routes
    let public_routes = Router::new()
        .route("/challenges", get(handlers::list_challenges))
        .route("/challenges/:id", get(handlers::get_challenge))
        .route("/challenges/:id/join", post(handlers::join_challenge))
        .route(
            "/challenges/:id/leaderboard",
            get(handlers::get_leaderboard),
        )
        .route("/contests", get(handlers::list_contests))
        .route("/contests/:id", get(handlers::get_contest))
        .route("/badges/:id/image", get(handlers::get_badge_image))
        .route("/achievements", get(handlers::list_achievements_catalog))
        .route(
            "/users/:callsign/achievements",
            get(handlers::list_user_achievements),
        )
        .route("/programs", get(handlers::list_programs))
        .route("/programs/:slug", get(handlers::get_program))
        .route("/spots", get(handlers::list_spots))
        .route(
            "/callsign-enrichment/dataset",
            get(handlers::get_callsign_enrichment_dataset),
        )
        .route(
            "/callsign-enrichment/:callsign",
            get(handlers::get_callsign_enrichment),
        )
        .route(
            "/satellites/amsat-status",
            get(handlers::get_amsat_status),
        )
        .route(
            "/satellites/amsat-status/activity",
            get(handlers::get_amsat_activity),
        )
        .route(
            "/satellites/amsat-status/reports",
            get(handlers::get_amsat_reports),
        )
        .route("/health", get(handlers::health_check))
        .route("/users/search", get(handlers::search_users))
        .route(
            "/register",
            post(handlers::register).route_layer(GovernorLayer {
                config: register_governor,
            }),
        )
        .route("/pota/stats/activator", get(handlers::get_activator_stats))
        .route("/pota/stats/hunter", get(handlers::get_hunter_stats))
        .route("/pota/stats/state/:state", get(handlers::get_state_stats))
        .route("/pota/stats/park/:reference", get(handlers::get_park_stats))
        .route(
            "/pota/stats/rankings/activators",
            get(handlers::get_activator_rankings),
        )
        .route("/pota/stats/status", get(handlers::get_sync_status))
        .route("/parks/boundaries", get(handlers::get_boundaries))
        .route(
            "/parks/boundaries/status",
            get(handlers::get_boundary_status),
        )
        .route("/parks/boundaries/:reference", get(handlers::get_boundary))
        .route("/admin/boundaries", get(handlers::get_admin_boundaries))
        // NOTE: POST /sota/zones is intentionally NOT here. It lets the request
        // body define both the cache key and the geometry for a permanently
        // cached, all-clients-trust dataset, so it lives on auth_routes (CAR-312)
        // — an anonymous caller must not be able to seed or poison zones.
        .route("/trails", get(handlers::get_trails))
        .route("/trails/status", get(handlers::get_trail_status))
        .route("/trails/:reference", get(handlers::get_trail))
        .route("/clubs/:id/logo", get(handlers::get_club_logo))
        .route("/equipment/catalog", get(handlers::get_catalog))
        .route("/equipment/search", get(handlers::search_equipment))
        .route(
            "/equipment/submissions",
            post(handlers::submit_equipment),
        )
        .route("/events", get(handlers::list_events))
        .route("/events/:id", get(handlers::get_event))
        // Radio Macros — Phase 1 public reads (CAR-271 T5). Approved-only,
        // tombstones propagate via /v1/macros/tombstones.
        .route("/macros", get(handlers::macros::list_macros))
        .route("/macros/versions", get(handlers::macros::versions_for_slugs))
        .route("/macros/tombstones", get(handlers::macros::tombstones))
        .route("/macros/:slug", get(handlers::macros::get_macro))
        .route("/macros/:slug/versions", get(handlers::macros::list_macro_versions))
        .route("/rbn/spots", get(handlers::rbn_spots))
        .route("/rbn/stats", get(handlers::rbn_stats))
        .route("/rbn/skimmers", get(handlers::rbn_skimmers))
        // WebSDR proxies for the logbook viewer's Spots page: directory cache,
        // /status probe, and the KiwiSDR websocket byte bridge.
        .route("/websdr/directory", get(handlers::websdr_directory))
        .route("/websdr/status", get(handlers::websdr_status))
        .route("/websdr/stream", get(handlers::websdr_stream))
        .route("/twilio/sms", post(handlers::twilio_sms_webhook))
        .route("/metrics", post(handlers::ingest_metrics))
        .route("/diagnostics", post(handlers::ingest_diagnostics))
        .route(
            "/telemetry/equipment-usage",
            post(handlers::report_equipment_usage),
        )
        .layer(Extension(rbn_store))
        .layer(Extension(handlers::WebSdrState::new()))
        .layer(middleware::from_fn_with_state(
            api_auth_state.clone(),
            auth::optional_auth,
        ));

    // Authenticated routes
    let auth_routes = Router::new()
        .route("/challenges/:id/progress", post(handlers::report_progress))
        .route("/challenges/:id/progress", get(handlers::get_progress))
        .route("/challenges/:id/leave", delete(handlers::leave_challenge))
        .route(
            "/challenges/:id/participants/:callsign",
            get(handlers::get_participation_status),
        )
        .route(
            "/participants/:callsign/challenges",
            get(handlers::list_challenges_for_callsign),
        )
        .route("/friends/invite-link", get(handlers::get_invite_link))
        .route("/friends/requests", post(handlers::create_friend_request))
        .route(
            "/friends/suggestions",
            post(handlers::get_friend_suggestions),
        )
        .route("/friends", get(handlers::list_friends))
        .route(
            "/friends/requests/pending",
            get(handlers::list_pending_requests),
        )
        .route(
            "/friends/requests/:id/accept",
            post(handlers::accept_friend_request),
        )
        .route(
            "/friends/requests/:id/decline",
            post(handlers::decline_friend_request),
        )
        .route("/friends/:id", delete(handlers::remove_friend))
        .route("/activities", post(handlers::report_activity))
        .route("/activities/:id", delete(handlers::delete_activity))
        .route("/spots", post(handlers::create_self_spot))
        .route("/spots/:id", delete(handlers::delete_own_spot))
        .route("/feed", get(handlers::get_feed))
        .route("/clubs", get(handlers::get_clubs))
        .route("/clubs/sync", get(handlers::sync_clubs))
        .route("/clubs/membership", get(handlers::get_club_membership))
        .route("/clubs/:id", get(handlers::get_club_details))
        .route("/clubs/:id/activity", get(handlers::get_club_activity))
        .route("/clubs/:id/status", get(handlers::get_club_status))
        .route("/clubs/:id/notes", put(handlers::update_club_notes))
        .route("/events", post(handlers::create_event))
        .route("/events/mine", get(handlers::list_my_events))
        .route(
            "/events/:id",
            put(handlers::update_event).delete(handlers::delete_event),
        )
        .route(
            "/telemetry/upload-errors",
            post(handlers::report_upload_errors),
        )
        .route("/spot-markers", post(handlers::create_spot_marker))
        // SECURITY (CAR-312): authenticated so zone submissions are attributable
        // and rate-limited per account, not anonymous. Read consumers (GET
        // /v1/spots, cached-zone reads) stay public.
        .route("/sota/zones", post(handlers::post_sota_zones))
        .route("/account", delete(handlers::delete_account))
        .route(
            "/users/me/achievements/signal",
            post(handlers::report_signal),
        )
        .route("/account/callsign", put(handlers::change_callsign))
        .route(
            "/account/claim-previous",
            post(handlers::claim_previous_account),
        )
        // Radio Macros — authenticated run-event telemetry (CAR-271 T6).
        .route(
            "/macros/:slug/run-event",
            post(handlers::macros_telemetry::run_event),
        )
        // Sync server — E2E-blind journal (Phase 4). Blob store injected via
        // the `Extension<Arc<dyn BlobStore>>` layered on `v1_routes` below.
        .route("/sync/push", post(handlers::sync::push))
        .route("/sync/changes", get(handlers::sync::changes))
        .route("/sync/snapshot", post(handlers::sync::snapshot))
        .route(
            "/sync/snapshot/commit",
            post(handlers::sync::snapshot_commit),
        )
        .route("/sync/bootstrap", get(handlers::sync::bootstrap))
        .route(
            "/sync/key",
            put(handlers::sync::put_key).get(handlers::sync::get_key),
        )
        // Third-party OAuth provider, authenticated half. These ride the same
        // dual-auth middleware as everything else here, which is what applies
        // the default-deny gate in auth::scope_map — /oauth/userinfo is the one
        // route below that a third-party token may reach (scope `openid`).
        .route(
            "/oauth/authorize/decision",
            post(handlers::oauth::authorize_decision),
        )
        .route(
            "/oauth/device/decision",
            post(handlers::oauth::device_decision),
        )
        .route("/oauth/userinfo", get(handlers::oauth::userinfo))
        .route("/oauth/grants", get(handlers::oauth::list_grants))
        .route(
            "/oauth/grants/:client_id",
            delete(handlers::oauth::revoke_grant),
        )
        .layer(Extension(handlers::macros_telemetry::build_rate_limiter()))
        .layer(Extension(config.clone()))
        .layer(middleware::from_fn_with_state(
            api_auth_state.clone(),
            auth::require_auth,
        ));

    // Admin routes
    let admin_routes = Router::new()
        // Curated OAuth client registration. There is deliberately no
        // self-serve portal and no RFC 7591 dynamic registration: the consent
        // screen's protection is that a human vetted the name shown on it.
        .route(
            "/admin/oauth/clients",
            get(handlers::oauth::list_clients).post(handlers::oauth::create_client),
        )
        .route(
            "/admin/oauth/clients/:client_id",
            delete(handlers::oauth::suspend_client),
        )
        // Orphaned sync tenants (legacy fd_-token data) — list + adopt onto an
        // account tenant. See handlers::sync_admin.
        .route(
            "/admin/sync/orphans",
            get(handlers::sync_admin::list_sync_orphans),
        )
        .route(
            "/admin/sync/orphans/:participant_id/adopt",
            post(handlers::sync_admin::adopt_sync_orphan),
        )
        .route("/admin/challenges", post(handlers::create_challenge))
        .route("/admin/challenges/:id", put(handlers::update_challenge))
        .route("/admin/challenges/:id", delete(handlers::delete_challenge))
        .route("/admin/contests", post(handlers::upsert_contests))
        .route("/admin/contests/:id", delete(handlers::delete_contest))
        .route(
            "/admin/contests/validate",
            post(handlers::validate_contests),
        )
        .route(
            "/admin/challenges/:id/badges",
            post(handlers::upload_badge).get(handlers::list_badges),
        )
        .route("/admin/badges/:id", delete(handlers::delete_badge))
        .route(
            "/admin/achievements/:id/award",
            post(handlers::admin_award_achievement),
        )
        .route(
            "/admin/achievements/:id/award/:callsign",
            delete(handlers::admin_revoke_achievement),
        )
        .route(
            "/admin/achievements/:id/award/batch",
            post(handlers::admin_batch_award),
        )
        .route(
            "/admin/achievements/backfill",
            post(handlers::admin_backfill_achievements),
        )
        .route(
            "/admin/challenges/:id/invites",
            post(handlers::generate_invite).get(handlers::list_invites),
        )
        .route("/admin/invites/:token", delete(handlers::revoke_invite))
        .route(
            "/admin/programs",
            post(handlers::create_program).get(handlers::admin_list_programs),
        )
        .route(
            "/admin/programs/:slug",
            put(handlers::update_program)
                .get(handlers::admin_get_program)
                .delete(handlers::delete_program),
        )
        .route(
            "/admin/clubs",
            post(handlers::create_club).get(handlers::list_clubs_admin),
        )
        .route(
            "/admin/clubs/:id",
            put(handlers::update_club).delete(handlers::delete_club),
        )
        .route(
            "/admin/clubs/:id/members",
            post(handlers::add_club_members).get(handlers::list_club_members_admin),
        )
        .route(
            "/admin/clubs/:id/import-notes",
            post(handlers::import_notes_members),
        )
        .route(
            "/admin/clubs/:id/logo",
            put(handlers::upload_club_logo).delete(handlers::delete_club_logo),
        )
        .route(
            "/admin/clubs/:id/members/:callsign",
            delete(handlers::remove_club_member).put(handlers::update_club_member_role),
        )
        .route(
            "/admin/equipment",
            post(handlers::create_equipment),
        )
        .route(
            "/admin/equipment/:id",
            put(handlers::update_equipment).delete(handlers::delete_equipment),
        )
        .route(
            "/admin/equipment/submissions",
            get(handlers::list_equipment_submissions),
        )
        .route(
            "/admin/equipment/submissions/:id/review",
            put(handlers::review_equipment_submission),
        )
        .route(
            "/admin/events",
            get(handlers::list_events_admin),
        )
        .route(
            "/admin/events/:id",
            get(handlers::admin_get_event)
                .put(handlers::admin_update_event)
                .delete(handlers::admin_delete_event),
        )
        .route(
            "/admin/events/:id/review",
            put(handlers::review_event),
        )
        .route(
            "/admin/events/submitter/:callsign",
            get(handlers::get_submitter_history),
        )
        .route(
            "/admin/telemetry/upload-errors",
            get(handlers::get_telemetry_summary),
        )
        .route(
            "/admin/metrickit",
            get(handlers::get_metrickit_summary),
        )
        // Radio Macros — admin endpoints (CAR-271 T7).
        .route(
            "/admin/macros",
            post(handlers::macros_admin::create_macro)
                .get(handlers::macros_admin::list_macros),
        )
        .route(
            "/admin/macros/:slug",
            put(handlers::macros_admin::update_macro)
                .patch(handlers::macros_admin::patch_macro)
                .delete(handlers::macros_admin::delete_macro),
        )
        .route("/admin/spots/:id", delete(handlers::admin_delete_spot))
        .route("/admin/trails/status", get(handlers::get_trail_status))
        .route("/admin/stats", get(handlers::admin_stats))
        .route(
            "/admin/stats/users-by-hour",
            get(handlers::admin_users_by_hour),
        )
        .layer(middleware::from_fn_with_state(
            config.admin_token,
            auth::require_admin,
        ));

    // Propagation proxy routes (optional sidecar dependency).
    let propagation_routes = if propagation_enabled {
        Router::new()
            .route(
                "/propagation/p2p",
                post(handlers::propagation_point_to_point),
            )
            .route("/propagation/wheel", post(handlers::propagation_wheel))
            .layer(Extension(propagation_client))
    } else {
        Router::new()
    };

    // Phase 5 OAuth routes (`/v1/auth/*`) — ADDITIVE. Only mounted when JWT
    // signing keys are configured; otherwise the legacy `fd_` auth continues to
    // guard everything and these endpoints simply don't exist yet.
    let oauth_routes = match &oauth_verifier {
        Some(verifier) => {
            // Reuse the verifier (JWT keys + revocation cache + listener) built
            // once above for the dual-auth middleware.
            let jwt = verifier.jwt.clone();
            let settings = auth_settings.clone();
            let mailer = Arc::new(auth::mailer::Mailer::from_env());
            let directory = Arc::new(auth::directory::CallsignDirectory::from_env());

            let jwt_auth_state = auth::jwt_middleware::JwtAuthState {
                pool: pool.clone(),
                jwt: jwt.clone(),
                cache: verifier.cache.clone(),
            };

            // F7/O6: email-bomb protection on the unauthenticated send vector.
            let verify_governor = Arc::new(
                GovernorConfigBuilder::default()
                    .per_second(20)
                    .burst_size(3)
                    .finish()
                    .expect("verify rate-limit config"),
            );

            // Public (no bearer) auth flow.
            let public_auth = Router::new()
                .route(
                    "/auth/verify/start",
                    post(handlers::auth::verify_start).route_layer(GovernorLayer {
                        config: verify_governor,
                    }),
                )
                .route("/auth/verify/complete", get(handlers::auth::verify_complete))
                .route("/auth/verify/poll", post(handlers::auth::verify_poll))
                .route("/auth/token", post(handlers::auth::issue_token))
                .route("/auth/token/refresh", post(handlers::auth::refresh_token))
                .route("/auth/logout", post(handlers::auth::logout))
                .layer(Extension(jwt.clone()))
                .layer(Extension(mailer.clone()))
                .layer(Extension(directory.clone()))
                .layer(Extension(settings.clone()));

            // Authenticated account management (JWT bearer).
            let authed_auth = Router::new()
                .route("/auth/logout/all", post(handlers::auth::logout_all))
                .route("/auth/devices", get(handlers::auth::list_devices))
                .route("/auth/devices/:id", delete(handlers::auth::delete_device))
                .route(
                    "/auth/callsigns/verify/start",
                    post(handlers::auth::add_callsign_start),
                )
                .layer(Extension(mailer))
                .layer(Extension(directory))
                .layer(Extension(settings.clone()))
                .layer(axum::middleware::from_fn_with_state(
                    jwt_auth_state,
                    auth::jwt_middleware::require_jwt_auth,
                ));

            // Third-party OAuth provider, unauthenticated half: the two
            // browser-facing screens plus the endpoints clients authenticate to
            // with their OWN credentials (client_id/secret or PKCE), never with
            // a user's bearer token. The authenticated half — the consent and
            // device decisions, userinfo, and connected-app management — lives
            // on `auth_routes` so it shares the dual-auth middleware and its
            // default-deny scope gate.
            let oauth_provider = Router::new()
                .route("/oauth/authorize", get(handlers::oauth::authorize_page))
                .route("/oauth/token", post(handlers::oauth::token))
                .route("/oauth/device", get(handlers::oauth::device_page))
                .route("/oauth/device/code", post(handlers::oauth::device_code))
                .route("/oauth/revoke", post(handlers::oauth::revoke))
                .layer(Extension(jwt.clone()))
                .layer(Extension(settings));

            public_auth.merge(authed_auth).merge(oauth_provider)
        }
        None => Router::new(),
    };

    // Published JWKS at the domain root (NOT under /v1) so external verifiers
    // can fetch it at the conventional well-known path. Only when OAuth is on.
    let wellknown_routes = match &oauth_verifier {
        Some(verifier) => Router::new()
            .route("/.well-known/jwks.json", get(handlers::auth::jwks))
            // OIDC discovery, plus its RFC 8414 alias. Generic OAuth libraries
            // and MCP clients self-configure from these, so publishing them is
            // most of what makes the provider usable without hand-written docs.
            .route(
                "/.well-known/openid-configuration",
                get(handlers::oauth::discovery),
            )
            .route(
                "/.well-known/oauth-authorization-server",
                get(handlers::oauth::discovery),
            )
            .layer(Extension(auth_settings.clone()))
            .layer(Extension(verifier.jwt.clone())),
        None => Router::new(),
    };

    // Merge all v1 routes with a JSON 404 fallback for unmatched API paths.
    // The blob store is shared with all v1 routes so Phase 4 sync handlers can
    // presign/delete blobs via `Extension<Arc<dyn BlobStore>>`.
    let v1_routes = public_routes
        .merge(auth_routes)
        .merge(admin_routes)
        .merge(propagation_routes)
        .merge(oauth_routes)
        .fallback(api_not_found)
        .layer(Extension(blob_store))
        .layer(axum::middleware::from_fn(metrics::http_metrics));

    // Friend invite page (server-rendered HTML for links opened in browsers)
    let invite_route = Router::new().route("/invite/:token", get(handlers::invite_page));

    // Enriched share link landing pages. The fragment (#d=...) holds the
    // payload and is decoded by /link/static/link-card.js client-side; the
    // server never sees QSO/activation data.
    let link_routes = Router::new()
        .route("/link/qso/:token", get(handlers::link_page_qso))
        .route("/link/act/:token", get(handlers::link_page_activation))
        .route("/link/call/:callsign", get(handlers::link_page_callsign))
        .route("/link/park/:reference", get(handlers::link_page_park))
        .route("/link/sum/:reference", get(handlers::link_page_summit))
        .route("/link/static/link-card.js", get(handlers::link_card_js))
        .route(
            "/.well-known/apple-app-site-association",
            get(handlers::apple_app_site_association),
        );

    // Static file serving for SPA (fallback to index.html for client-side routing)
    let serve_dir = ServeDir::new("web/dist").fallback(ServeFile::new("web/dist/index.html"));

    // Contest visualizer served at /contests
    let contest_visualizer =
        ServeFile::new("static/contest-visualizer/index.html");

    // Logbook web viewer (E2E sync) — its own SPA under /logbook. The prefix is
    // stripped before ServeDir, and unknown sub-paths fall back to its index for
    // client-side routing. Built assets use base `/logbook/` (see its vite config).
    let logbook_web = ServeDir::new("logbook-web/dist")
        .fallback(ServeFile::new("logbook-web/dist/index.html"));

    // Dev/test-only blob routes backing the in-memory store's presigned URLs.
    // These carry their own `/v1/sync/blob/*key` paths (so the presigned URLs
    // resolve directly) and are mounted only when the in-memory store is
    // active. Real deploys use S3 presigned URLs and never mount these.
    let dev_blob_routes = match memory_blob_store {
        Some(store) => storage::dev_blob_routes().layer(Extension(store)),
        None => Router::new(),
    };

    let app = Router::new()
        .nest("/v1", v1_routes)
        .merge(dev_blob_routes)
        .route("/metrics", get(handlers::get_metrics))
        .merge(invite_route)
        .merge(link_routes)
        .merge(wellknown_routes)
        .route_service("/contests", contest_visualizer)
        .nest_service("/logbook", logbook_web)
        .fallback_service(serve_dir)
        .layer(Extension(metrics_handle))
        .layer(cors)
        .layer(GovernorLayer {
            config: global_governor,
        })
        // CAR-143: cap request bodies at 1 MiB so a malicious caller can't
        // pin memory by streaming gigantic JSON. Upload endpoints that need
        // more must override locally with DefaultBodyLimit::max(...).
        .layer(DefaultBodyLimit::max(1024 * 1024));

    // CAR-156: X-Request-Id + per-request span/completion log. Outermost so
    // rate-limited (429) and CORS responses carry the id too. This replaces
    // the old `TraceLayer::new_for_http()` (its DEBUG start/finish pair had no
    // correlation id); the Prometheus middleware stays on the /v1 sub-router.
    observability::instrument(app).with_state(pool)
}

async fn api_not_found() -> impl IntoResponse {
    (
        StatusCode::NOT_FOUND,
        Json(serde_json::json!({
            "error": {
                "code": "NOT_FOUND",
                "message": "Endpoint not found"
            }
        })),
    )
}
