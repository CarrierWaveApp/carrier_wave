//! HTTP handlers for the contest definition format.
//!
//! - Public: list and fetch contest definitions
//! - Admin: upsert (POST), delete, and validate-only

use axum::extract::{Query, State};
use axum::http::StatusCode;
use serde::Serialize;
use sqlx::PgPool;

use crate::contest::types::{Contest, ContestDefinition};
use crate::contest::validation::Severity;
use crate::db;
use crate::error::AppError;
use crate::extractors::{Json, Path};
use crate::models::contest_definition::{
    ContestDefinitionListItem, ContestDefinitionResponse, ListContestsQuery, ValidateContestsRequest,
    ValidateContestsResponse, ValidationProblem,
};

use super::DataResponse;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ListContestsResponse {
    pub contests: Vec<ContestDefinitionListItem>,
}

/// GET /v1/contests
pub async fn list_contests(
    State(pool): State<PgPool>,
    Query(query): Query<ListContestsQuery>,
) -> Result<Json<DataResponse<ListContestsResponse>>, AppError> {
    let rows = db::contest_definitions::list(&pool, query.include_inactive).await?;
    let contests = rows.into_iter().map(ContestDefinitionListItem::from).collect();
    Ok(Json(DataResponse {
        data: ListContestsResponse { contests },
    }))
}

/// GET /v1/contests/:id
pub async fn get_contest(
    State(pool): State<PgPool>,
    Path(id): Path<String>,
) -> Result<Json<DataResponse<ContestDefinitionResponse>>, AppError> {
    let row = db::contest_definitions::get(&pool, &id)
        .await?
        .ok_or(AppError::ContestDefinitionNotFound { contest_id: id })?;
    Ok(Json(DataResponse { data: row.into() }))
}

/// POST /v1/admin/contests
///
/// Body: a complete contest definition file (with `version` + `contests`).
/// Each contest in the file is upserted as its own row keyed by `contest.id`.
/// The definition is validated before any rows are written; if validation
/// produces errors, the request is rejected with 400 and the problem list.
pub async fn upsert_contests(
    State(pool): State<PgPool>,
    Json(def): Json<ContestDefinition>,
) -> Result<(StatusCode, Json<DataResponse<UpsertContestsResponse>>), AppError> {
    let problems: Vec<ValidationProblem> = def
        .validate()
        .into_iter()
        .map(to_problem)
        .collect();

    let has_errors = problems.iter().any(|p| p.severity == "error");
    if has_errors {
        return Err(AppError::InvalidContestDefinition {
            message: "contest definition failed validation".to_string(),
            problems,
        });
    }

    let rows = db::contest_definitions::upsert_all(&pool, &def).await?;
    let contests: Vec<ContestDefinitionResponse> =
        rows.into_iter().map(ContestDefinitionResponse::from).collect();

    Ok((
        StatusCode::OK,
        Json(DataResponse {
            data: UpsertContestsResponse {
                contests,
                warnings: problems,
            },
        }),
    ))
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertContestsResponse {
    pub contests: Vec<ContestDefinitionResponse>,
    /// Validation warnings produced during the upsert (errors block the
    /// upsert and are returned as a 400; warnings are surfaced here).
    pub warnings: Vec<ValidationProblem>,
}

/// DELETE /v1/admin/contests/:id
pub async fn delete_contest(
    State(pool): State<PgPool>,
    Path(id): Path<String>,
) -> Result<StatusCode, AppError> {
    let deleted = db::contest_definitions::delete(&pool, &id).await?;
    if !deleted {
        return Err(AppError::ContestDefinitionNotFound { contest_id: id });
    }
    Ok(StatusCode::NO_CONTENT)
}

/// POST /v1/admin/contests/validate
///
/// Validate a contest definition without persisting it. Accepts either a
/// full file (with `version` + `contests`) or a single contest object.
pub async fn validate_contests(
    Json(req): Json<ValidateContestsRequest>,
) -> Result<Json<DataResponse<ValidateContestsResponse>>, AppError> {
    let def = parse_definition_or_single_contest(req.definition)?;
    let problems: Vec<ValidationProblem> = def
        .validate()
        .into_iter()
        .map(to_problem)
        .collect();
    let has_errors = problems.iter().any(|p| p.severity == "error");

    Ok(Json(DataResponse {
        data: ValidateContestsResponse {
            valid: !has_errors,
            contest_count: def.contests.len(),
            problems,
        },
    }))
}

fn to_problem(v: crate::contest::ValidationError) -> ValidationProblem {
    ValidationProblem {
        severity: match v.severity {
            Severity::Error => "error",
            Severity::Warning => "warning",
        },
        contest_id: v.contest_id,
        path: v.path,
        message: v.message,
    }
}

/// Accept either a `ContestDefinition` (object with `version` + `contests`)
/// or a single `Contest` object. The single-contest form is wrapped into a
/// synthetic file with version `0.3.0` so the validator can run unchanged.
fn parse_definition_or_single_contest(
    value: serde_json::Value,
) -> Result<ContestDefinition, AppError> {
    if value.get("contests").is_some() {
        return serde_json::from_value(value).map_err(|e| AppError::Validation {
            message: format!("invalid contest definition: {e}"),
        });
    }
    let contest: Contest = serde_json::from_value(value).map_err(|e| AppError::Validation {
        message: format!("invalid contest object: {e}"),
    })?;
    Ok(ContestDefinition {
        schema: None,
        id: None,
        title: None,
        version: "0.3.0".to_string(),
        contests: vec![contest],
    })
}
