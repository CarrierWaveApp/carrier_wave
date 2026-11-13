use axum::{
    extract::{Path, State},
    http::{header, StatusCode},
    response::{IntoResponse, Response},
};
use sqlx::PgPool;

use crate::db;

/// GET /invite/:token
/// Renders an HTML page for friend invite links opened in a browser.
/// Shows the inviter's callsign and a deep link to open in Carrier Wave.
pub async fn invite_page(State(pool): State<PgPool>, Path(token): Path<String>) -> Response {
    // Look up the invite and the inviter's callsign
    let page = match build_invite_page(&pool, &token).await {
        Ok(html) => html,
        Err(_) => render_invite_page(None, &token),
    };

    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "text/html; charset=utf-8")],
        page,
    )
        .into_response()
}

/// Escape a string for safe interpolation into HTML text or double-quoted
/// attribute contexts. Mirrors the helpers in `link_page.rs` / `oauth_pages.rs`.
fn html_escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
    }
    out
}

async fn build_invite_page(
    pool: &PgPool,
    token: &str,
) -> Result<String, Box<dyn std::error::Error>> {
    let invite = db::get_friend_invite(pool, token).await?;

    let callsign = match invite {
        Some(ref inv) if inv.used_at.is_none() && inv.expires_at > chrono::Utc::now() => {
            let user = db::get_user_by_id(pool, inv.user_id).await?;
            user.map(|u| u.callsign)
        }
        _ => None,
    };

    Ok(render_invite_page(callsign.as_deref(), token))
}

fn render_invite_page(callsign: Option<&str>, token: &str) -> String {
    // SECURITY (CAR-309): `token` is a percent-decoded path param under attacker
    // control. Issued invite tokens are `inv_` + alphanumerics, so anything with
    // other characters can't be a real invite — don't build a deep link from it.
    // The value is HTML-escaped regardless before it enters the `href` attribute.
    let token_is_valid =
        !token.is_empty() && token.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');
    let deep_link = if token_is_valid {
        html_escape(&format!("carrierwave://invite/{}", token))
    } else {
        "carrierwave://invite".to_string()
    };

    // SECURITY (CAR-310): the inviter callsign is written by unauthenticated
    // registration / callsign change with no charset validation, so escape every
    // interpolation before it reaches HTML text or attribute contexts.
    let (title, heading, description) = match callsign.map(html_escape) {
        Some(cs) => (
            format!("{} wants to be friends on Carrier Wave", cs),
            format!("{} wants to be friends!", cs),
            format!("Open this link in Carrier Wave to add {} as a friend.", cs),
        ),
        None => (
            "Friend invite on Carrier Wave".to_string(),
            "You've been invited!".to_string(),
            "Open this link in Carrier Wave to accept this friend invite.".to_string(),
        ),
    };

    format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{title}</title>
    <meta property="og:title" content="{title}">
    <meta property="og:description" content="{description}">
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            padding: 1rem;
        }}
        .card {{
            background: #1e293b;
            border-radius: 1rem;
            padding: 2.5rem 2rem;
            max-width: 400px;
            width: 100%;
            text-align: center;
        }}
        .icon {{
            font-size: 3rem;
            margin-bottom: 1rem;
        }}
        h1 {{
            font-size: 1.25rem;
            font-weight: 600;
            margin-bottom: 0.75rem;
            color: #f8fafc;
        }}
        p {{
            font-size: 0.95rem;
            line-height: 1.5;
            color: #94a3b8;
            margin-bottom: 1.5rem;
        }}
        .open-btn {{
            display: inline-block;
            background: #3b82f6;
            color: #fff;
            text-decoration: none;
            font-weight: 600;
            font-size: 1rem;
            padding: 0.75rem 1.5rem;
            border-radius: 0.5rem;
            transition: background 0.15s;
        }}
        .open-btn:hover {{
            background: #2563eb;
        }}
        .footer {{
            margin-top: 1.5rem;
            font-size: 0.8rem;
            color: #64748b;
        }}
    </style>
</head>
<body>
    <div class="card">
        <div class="icon">📡</div>
        <h1>{heading}</h1>
        <p>{description}</p>
        <a class="open-btn" href="{deep_link}">Open in Carrier Wave</a>
        <div class="footer">Carrier Wave &mdash; Ham Radio Challenges</div>
    </div>
</body>
</html>"#,
        title = title,
        description = description,
        heading = heading,
        deep_link = deep_link,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn callsign_markup_is_escaped() {
        // Stored-XSS payload (CAR-310): a callsign carrying markup must not
        // survive into the rendered HTML unescaped.
        let html = render_invite_page(Some("\"><script>alert(1)</script>"), "inv_abc123");
        assert!(!html.contains("<script>"));
        assert!(html.contains("&lt;script&gt;"));
    }

    #[test]
    fn malformed_token_cannot_break_out_of_href() {
        // Reflected-XSS payload (CAR-309): a token with attribute-breaking
        // characters is rejected, so no attacker markup lands in the href.
        let html = render_invite_page(None, "\"><script>alert(1)</script>");
        assert!(!html.contains("<script>"));
        assert!(html.contains(r#"href="carrierwave://invite""#));
    }

    #[test]
    fn valid_token_builds_deep_link() {
        let html = render_invite_page(None, "inv_abc123");
        assert!(html.contains("href=\"carrierwave://invite/inv_abc123\""));
    }
}
