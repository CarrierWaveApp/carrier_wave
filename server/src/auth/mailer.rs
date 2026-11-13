//! Transactional email for magic-link verification — Phase 5 (D9: Resend).
//!
//! An enum rather than a trait to stay dependency-free (no `async_trait`). The
//! `Null` variant logs the link for local dev/tests and MUST NOT be used in
//! prod (F15: `from_env` only selects it when no API key is configured).
//!
//! Design: docs/plans/2026-06-21-phase5-oauth-overhaul.md (§3, §13 step 4).

use crate::error::AppError;

pub enum Mailer {
    /// Dev/test: logs the magic link instead of sending. Never in prod.
    Null,
    /// Resend transactional email API over HTTPS.
    Resend {
        api_key: String,
        from: String,
        http: reqwest::Client,
    },
}

impl Mailer {
    /// Select from env: Resend when `RESEND_API_KEY` is set, else `Null` (dev).
    pub fn from_env() -> Self {
        match std::env::var("RESEND_API_KEY") {
            Ok(api_key) if !api_key.is_empty() => {
                let from = std::env::var("EMAIL_FROM")
                    .unwrap_or_else(|_| "noreply@carrierwave.app".to_string());
                Mailer::Resend {
                    api_key,
                    from,
                    http: reqwest::Client::new(),
                }
            }
            _ => {
                tracing::warn!("RESEND_API_KEY not set — using NullMailer (dev only)");
                Mailer::Null
            }
        }
    }

    /// Send the verification email containing `link`.
    pub async fn send_magic_link(&self, to: &str, link: &str) -> Result<(), AppError> {
        match self {
            Mailer::Null => {
                tracing::info!(target: "auth_magic_link", to, link, "NullMailer magic link (dev)");
                Ok(())
            }
            Mailer::Resend { api_key, from, http } => {
                let subject = "Verify your callsign — Carrier Wave";
                let html = format!(
                    "<p>Tap the link below to verify your callsign and finish signing in to Carrier Wave. \
                     This link expires in 15 minutes.</p>\
                     <p><a href=\"{link}\">Verify my callsign</a></p>\
                     <p>If you didn't request this, you can ignore this email.</p>"
                );
                let body = serde_json::json!({
                    "from": from,
                    "to": [to],
                    "subject": subject,
                    "html": html,
                });
                let resp = http
                    .post("https://api.resend.com/emails")
                    .bearer_auth(api_key)
                    .json(&body)
                    .send()
                    .await
                    .map_err(|e| AppError::Internal(format!("email send failed: {e}")))?;
                if !resp.status().is_success() {
                    let status = resp.status();
                    return Err(AppError::Internal(format!("email provider returned {status}")));
                }
                Ok(())
            }
        }
    }
}
