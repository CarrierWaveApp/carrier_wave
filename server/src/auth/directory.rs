//! Callsign → on-file email resolution (D6 directory-email tier).
//!
//! The magic link for the **directory** tier is sent to the address a callsign
//! directory has on file FOR THAT EXACT CALLSIGN (never an attacker-supplied
//! "match"), so completing it proves control of the registered address — the
//! only tier permitted to inherit legacy callsign-keyed data (F1/F2).
//!
//! QRZ.com XML is the directory. When no credentials are configured the resolver
//! is `Null` (everything falls back to the weaker `user_email` tier, which can't
//! inherit data — fail-closed).
//!
//! Design: docs/plans/2026-06-21-phase5-oauth-overhaul.md (§3).

use std::collections::HashMap;

use tokio::sync::Mutex;

use crate::error::AppError;

const QRZ_BASE: &str = "https://xmldata.qrz.com/xml/current/";
const QRZ_AGENT: &str = "carrierwave-server1.0";

pub enum CallsignDirectory {
    /// No directory configured — every verification falls back to `user_email`.
    Null,
    /// QRZ.com XML API.
    Qrz(QrzClient),
    /// Fixed map (callsign UPPER → email) for tests / manual overrides.
    Fixed(HashMap<String, String>),
}

impl CallsignDirectory {
    /// QRZ when `QRZ_USERNAME` + `QRZ_PASSWORD` are set, else `Null`.
    pub fn from_env() -> Self {
        match (std::env::var("QRZ_USERNAME"), std::env::var("QRZ_PASSWORD")) {
            (Ok(u), Ok(p)) if !u.is_empty() && !p.is_empty() => {
                CallsignDirectory::Qrz(QrzClient::new(u, p))
            }
            _ => {
                tracing::warn!("QRZ credentials not set — directory-email tier disabled");
                CallsignDirectory::Null
            }
        }
    }

    /// The email a directory has on file for `callsign`, if any. Errors degrade
    /// to `Ok(None)` at the call site (fall back to user-supplied).
    pub async fn resolve_email(&self, callsign: &str) -> Result<Option<String>, AppError> {
        match self {
            CallsignDirectory::Null => Ok(None),
            CallsignDirectory::Fixed(m) => Ok(m.get(&callsign.to_uppercase()).cloned()),
            CallsignDirectory::Qrz(c) => c.resolve_email(callsign).await,
        }
    }
}

pub struct QrzClient {
    username: String,
    password: String,
    http: reqwest::Client,
    session: Mutex<Option<String>>,
}

impl QrzClient {
    pub fn new(username: String, password: String) -> Self {
        Self {
            username,
            password,
            http: reqwest::Client::new(),
            session: Mutex::new(None),
        }
    }

    async fn session_key(&self) -> Result<String, AppError> {
        let mut guard = self.session.lock().await;
        if let Some(k) = guard.as_ref() {
            return Ok(k.clone());
        }
        let key = self.login().await?;
        *guard = Some(key.clone());
        Ok(key)
    }

    async fn login(&self) -> Result<String, AppError> {
        let xml = self
            .http
            .get(QRZ_BASE)
            .query(&[
                ("username", self.username.as_str()),
                ("password", self.password.as_str()),
                ("agent", QRZ_AGENT),
            ])
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("QRZ login request failed: {e}")))?
            .text()
            .await
            .map_err(|e| AppError::Internal(format!("QRZ login read failed: {e}")))?;
        tag(&xml, "Key").map(str::to_string).ok_or_else(|| {
            AppError::Internal(format!(
                "QRZ login rejected: {}",
                tag(&xml, "Error").unwrap_or("unknown")
            ))
        })
    }

    async fn lookup(&self, key: &str, callsign: &str) -> Result<String, AppError> {
        self.http
            .get(QRZ_BASE)
            .query(&[("s", key), ("callsign", callsign)])
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("QRZ lookup request failed: {e}")))?
            .text()
            .await
            .map_err(|e| AppError::Internal(format!("QRZ lookup read failed: {e}")))
    }

    async fn resolve_email(&self, callsign: &str) -> Result<Option<String>, AppError> {
        let key = self.session_key().await?;
        let xml = self.lookup(&key, callsign).await?;
        // Session expired mid-flight → drop the cached key, re-auth once, retry.
        if session_expired(&xml) {
            *self.session.lock().await = None;
            let key = self.session_key().await?;
            let xml = self.lookup(&key, callsign).await?;
            return Ok(extract_email(&xml));
        }
        Ok(extract_email(&xml))
    }
}

/// Pull the trimmed, non-empty contents of `<name>…</name>` (first occurrence).
fn tag<'a>(xml: &'a str, name: &str) -> Option<&'a str> {
    let open = format!("<{name}>");
    let close = format!("</{name}>");
    let start = xml.find(&open)? + open.len();
    let end = xml[start..].find(&close)? + start;
    let value = xml[start..end].trim();
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

fn session_expired(xml: &str) -> bool {
    matches!(tag(xml, "Error"), Some(e) if e.contains("Session Timeout") || e.contains("Invalid session"))
}

fn extract_email(xml: &str) -> Option<String> {
    let email = tag(xml, "email")?;
    if email.contains('@') {
        Some(email.to_string())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_email_from_callsign_response() {
        let xml = r#"<?xml version="1.0"?><QRZDatabase><Session><Key>K</Key></Session>
            <Callsign><call>W6JY</call><fname>Jay</fname><email>jay@example.com</email></Callsign></QRZDatabase>"#;
        assert_eq!(extract_email(xml).as_deref(), Some("jay@example.com"));
    }

    #[test]
    fn no_email_field_returns_none() {
        let xml = r#"<QRZDatabase><Callsign><call>W6JY</call></Callsign></QRZDatabase>"#;
        assert_eq!(extract_email(xml), None);
    }

    #[test]
    fn empty_email_field_returns_none() {
        let xml = r#"<Callsign><email></email></Callsign>"#;
        assert_eq!(extract_email(xml), None);
    }

    #[test]
    fn detects_session_timeout() {
        let xml = r#"<QRZDatabase><Session><Error>Session Timeout</Error></Session></QRZDatabase>"#;
        assert!(session_expired(xml));
        let ok = r#"<QRZDatabase><Session><Key>abc</Key></Session></QRZDatabase>"#;
        assert!(!session_expired(ok));
    }

    #[test]
    fn login_key_parsed() {
        let xml = r#"<QRZDatabase><Session><Key>sk123</Key><SubExp>2026-12-31</SubExp></Session></QRZDatabase>"#;
        assert_eq!(tag(xml, "Key"), Some("sk123"));
    }

    #[tokio::test]
    async fn null_directory_resolves_nothing() {
        assert_eq!(CallsignDirectory::Null.resolve_email("W6JY").await.unwrap(), None);
    }

    #[tokio::test]
    async fn fixed_directory_is_case_insensitive() {
        let mut m = HashMap::new();
        m.insert("W6JY".to_string(), "jay@example.com".to_string());
        let dir = CallsignDirectory::Fixed(m);
        assert_eq!(
            dir.resolve_email("w6jy").await.unwrap().as_deref(),
            Some("jay@example.com")
        );
        assert_eq!(dir.resolve_email("ZZ9ZZ").await.unwrap(), None);
    }
}
