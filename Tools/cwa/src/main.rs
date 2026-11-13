//! `cwa` — Carrier Wave admin CLI (CAR-271 T7).
//!
//! Talks to the activities-server admin endpoints over HTTPS. Configured
//! via env vars:
//!   `CWA_BASE_URL`  — server base, e.g. `https://activities.carrierwave.app`
//!   `CWA_ADMIN_TOKEN` — Bearer token (server's ADMIN_TOKEN)
//!
//! Subcommands:
//!   cwa macros sync <dir>           — POST/PUT every `.cwmacro` under dir
//!   cwa macros withdraw <slug>      — PATCH status=withdrawn
//!   cwa macros list [--status …]    — GET admin macros list
//!   cwa macros verify <file>        — local-only spec validation (no network)

use anyhow::{anyhow, bail, Context, Result};
use clap::{Parser, Subcommand};
use reqwest::blocking::Client;
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

#[derive(Parser)]
#[command(name = "cwa", version, about = "Carrier Wave admin CLI")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Manage the radio macros registry.
    Macros {
        #[command(subcommand)]
        action: MacrosAction,
    },
}

#[derive(Subcommand)]
enum MacrosAction {
    /// Walk a directory of .cwmacro files and POST/PUT each one.
    Sync {
        /// Directory to walk.
        dir: PathBuf,
        /// Dry-run — show what would be sent, don't issue requests.
        #[arg(long)]
        dry_run: bool,
    },
    /// Mark a slug withdrawn (server PATCH /v1/admin/macros/:slug).
    Withdraw {
        slug: String,
        /// Moderator notes recorded on the row.
        #[arg(long)]
        notes: Option<String>,
    },
    /// List admin macros, optionally filtered by status.
    List {
        #[arg(long)]
        status: Option<String>,
    },
    /// Validate a `.cwmacro` file offline (no server contact). Useful as
    /// a pre-commit gate. Returns non-zero on any verifier error.
    Verify {
        file: PathBuf,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Macros { action } => match action {
            MacrosAction::Sync { dir, dry_run } => sync(&dir, dry_run),
            MacrosAction::Withdraw { slug, notes } => withdraw(&slug, notes.as_deref()),
            MacrosAction::List { status } => list(status.as_deref()),
            MacrosAction::Verify { file } => verify(&file),
        },
    }
}

// ---------------------------------------------------------------------------
// Subcommands
// ---------------------------------------------------------------------------

fn sync(dir: &Path, dry_run: bool) -> Result<()> {
    let files = collect_cwmacro_files(dir)?;
    if files.is_empty() {
        eprintln!("no .cwmacro files found under {}", dir.display());
        return Ok(());
    }
    if dry_run {
        for path in &files {
            println!("WOULD UPSERT {}", path.display());
        }
        return Ok(());
    }
    let cfg = Config::from_env()?;
    let client = build_client()?;
    for path in &files {
        upsert_file(&client, &cfg, path)?;
    }
    println!("synced {} macros", files.len());
    Ok(())
}

fn withdraw(slug: &str, notes: Option<&str>) -> Result<()> {
    let cfg = Config::from_env()?;
    let client = build_client()?;
    let body = serde_json::json!({
        "status": "withdrawn",
        "moderator_notes": notes,
    });
    let url = format!("{}/v1/admin/macros/{slug}", cfg.base_url);
    let resp = client
        .patch(&url)
        .bearer_auth(&cfg.admin_token)
        .json(&body)
        .send()
        .with_context(|| format!("PATCH {url}"))?;
    if !resp.status().is_success() {
        bail!("withdraw failed: {} {}", resp.status(), resp.text().unwrap_or_default());
    }
    println!("withdrew {slug}");
    Ok(())
}

fn list(status: Option<&str>) -> Result<()> {
    let cfg = Config::from_env()?;
    let client = build_client()?;
    let mut url = format!("{}/v1/admin/macros", cfg.base_url);
    if let Some(s) = status {
        url.push_str(&format!("?status={s}"));
    }
    let resp = client
        .get(&url)
        .bearer_auth(&cfg.admin_token)
        .send()
        .with_context(|| format!("GET {url}"))?;
    if !resp.status().is_success() {
        bail!("list failed: {} {}", resp.status(), resp.text().unwrap_or_default());
    }
    let body: Value = resp.json()?;
    println!("{}", serde_json::to_string_pretty(&body)?);
    Ok(())
}

fn verify(file: &Path) -> Result<()> {
    let data = fs::read_to_string(file)
        .with_context(|| format!("read {}", file.display()))?;
    let parsed: Value = serde_json::from_str(&data)
        .with_context(|| format!("parse {}", file.display()))?;
    // T7 ships an offline check that only re-parses the JSON. Cross-language
    // verifier reuse would require depending on the server crate, which
    // pulls in postgres + axum and breaks Tools/cwa's standalone build.
    // Instead we check the document shape and let the server verifier do
    // the real work on `sync`.
    require_field(&parsed, "slug")?;
    require_field(&parsed, "name")?;
    require_field(&parsed, "steps")?;
    println!(
        "{} parses as a .cwmacro (full verifier runs server-side on sync)",
        file.display()
    );
    Ok(())
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

struct Config {
    base_url: String,
    admin_token: String,
}

impl Config {
    fn from_env() -> Result<Self> {
        let base_url = std::env::var("CWA_BASE_URL")
            .map_err(|_| anyhow!("CWA_BASE_URL not set"))?;
        let admin_token = std::env::var("CWA_ADMIN_TOKEN")
            .map_err(|_| anyhow!("CWA_ADMIN_TOKEN not set"))?;
        Ok(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            admin_token,
        })
    }
}

fn build_client() -> Result<Client> {
    Client::builder()
        .user_agent(concat!("cwa/", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(Into::into)
}

fn collect_cwmacro_files(dir: &Path) -> Result<Vec<PathBuf>> {
    if !dir.exists() {
        bail!("directory not found: {}", dir.display());
    }
    let mut out = Vec::new();
    for entry in WalkDir::new(dir).into_iter().filter_map(Result::ok) {
        let path = entry.path();
        if path
            .extension()
            .and_then(|s| s.to_str())
            .map(|s| s.eq_ignore_ascii_case("cwmacro"))
            .unwrap_or(false)
        {
            out.push(path.to_path_buf());
        }
    }
    out.sort();
    Ok(out)
}

fn upsert_file(client: &Client, cfg: &Config, path: &Path) -> Result<()> {
    let data = fs::read_to_string(path)
        .with_context(|| format!("read {}", path.display()))?;
    let parsed: Value = serde_json::from_str(&data)
        .with_context(|| format!("parse {}", path.display()))?;
    let slug = parsed
        .get("slug")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("{}: missing slug field", path.display()))?;
    // Use POST /v1/admin/macros — the server upserts on slug-conflict.
    let url = format!("{}/v1/admin/macros", cfg.base_url);
    let resp = client
        .post(&url)
        .bearer_auth(&cfg.admin_token)
        .json(&parsed)
        .send()
        .with_context(|| format!("POST {url} (slug={slug})"))?;
    let status = resp.status();
    if !status.is_success() {
        let body = resp.text().unwrap_or_default();
        bail!("{} ({slug}) -> {status} {body}", path.display());
    }
    let result: Value = resp.json().unwrap_or_else(|_| serde_json::json!({}));
    let version = result.get("version").cloned().unwrap_or(Value::Null);
    println!("  {slug} ({}) -> v{version}", path.display());
    Ok(())
}

fn require_field(value: &Value, field: &str) -> Result<()> {
    if value.get(field).is_none() {
        bail!("missing required field `{field}`");
    }
    Ok(())
}
