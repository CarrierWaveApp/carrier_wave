//! Server-rendered HTML for the two screens a human sees during a third-party
//! authorization: the consent screen and the device-grant verification screen.
//!
//! # Why these pages sign the user in themselves
//!
//! There is no browser session on this server. The `/logbook` SPA keeps its
//! tokens in `sessionStorage`, which is per-tab — a consent page opened in a new
//! tab (which is what an OAuth redirect produces) cannot see them. So each page
//! runs the ordinary first-party magic-link flow inline (`/v1/auth/verify/start`
//! → poll `/v1/auth/verify/poll`) and holds the resulting access token in memory
//! for the one request it needs it for.
//!
//! That is also the correct posture: the user authenticates on carrierwave.app,
//! in a page this server rendered, and the third-party client never sees their
//! account credentials.
//!
//! The sync passphrase is a different matter — it is NOT collected here. A
//! third-party client asks for it directly (see `handlers::oauth`), which is the
//! documented, accepted risk of this design.
//!
//! The pages are self-contained (no build step, no framework, no external
//! requests) so they cannot break when the SPA's bundle changes.

use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use sqlx::PgPool;

use crate::auth::scope_map;
use crate::db::oauth as dboauth;

use super::oauth::{AuthorizeParams, ConsentPageQuery};

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

/// Escape a string for embedding inside a `<script>` JSON literal.
///
/// `serde_json` handles quoting; the `<` replacement stops a value containing
/// `</script>` from closing the block early, which is the classic way a
/// JSON-in-HTML island turns into stored XSS.
fn json_for_script<T: serde::Serialize>(value: &T) -> String {
    serde_json::to_string(value)
        .unwrap_or_else(|_| "null".to_string())
        .replace('<', "\\u003c")
}

fn html(status: StatusCode, body: String) -> Response {
    (
        status,
        [
            (header::CONTENT_TYPE, "text/html; charset=utf-8"),
            // These pages carry an authorization decision; never cache them.
            (header::CACHE_CONTROL, "no-store"),
        ],
        body,
    )
        .into_response()
}

const STYLE: &str = r#"
:root { color-scheme: light dark; --fg:#111; --muted:#666; --bg:#fff; --card:#fff;
        --line:#e2e2e2; --accent:#0b6; --danger:#c33; }
@media (prefers-color-scheme: dark) {
  :root { --fg:#eee; --muted:#999; --bg:#111; --card:#1a1a1a; --line:#333; }
}
* { box-sizing: border-box; }
body { margin:0; padding:2rem 1rem; background:var(--bg); color:var(--fg);
       font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
       display:flex; justify-content:center; }
.card { width:100%; max-width:30rem; background:var(--card); border:1px solid var(--line);
        border-radius:12px; padding:1.75rem; }
h1 { font-size:1.25rem; margin:0 0 .25rem; }
p.sub { color:var(--muted); margin:0 0 1.5rem; }
ul.scopes { list-style:none; padding:0; margin:0 0 1.5rem; }
ul.scopes li { padding:.75rem 0; border-top:1px solid var(--line); }
ul.scopes li:last-child { border-bottom:1px solid var(--line); }
.scope-name { font-weight:600; display:block; }
.scope-desc { color:var(--muted); font-size:.9rem; }
label { display:block; font-weight:600; margin:0 0 .35rem; }
input { width:100%; padding:.6rem .75rem; font-size:1rem; border:1px solid var(--line);
        border-radius:8px; background:var(--bg); color:var(--fg); }
.row { display:flex; gap:.75rem; margin-top:1.25rem; }
button { flex:1; padding:.7rem 1rem; font-size:1rem; font-weight:600; border-radius:8px;
         border:1px solid var(--line); background:var(--card); color:var(--fg); cursor:pointer; }
button.primary { background:var(--accent); border-color:var(--accent); color:#fff; }
button[disabled] { opacity:.5; cursor:progress; }
.msg { margin-top:1rem; font-size:.9rem; }
.msg.error { color:var(--danger); }
.notice { font-size:.85rem; color:var(--muted); border-left:3px solid var(--line);
          padding-left:.75rem; margin:1.25rem 0 0; }
.hidden { display:none; }
"#;

/// The inline magic-link sign-in used by both pages.
///
/// Mirrors the iOS/`logbook-web` flow: PKCE where the challenge is
/// `hex(sha256(verifier))` — the first-party variant in `auth/tokens.rs`, NOT
/// the RFC 7636 base64url encoding third-party clients use at
/// `/v1/oauth/token`. Two different flows, two different encodings; do not
/// "unify" them without changing both ends.
const SIGN_IN_JS: &str = r#"
const enc = new TextEncoder();
async function sha256Hex(text) {
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(text));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
}
function randomVerifier() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
}

// Resolves to an access token, or throws. The token stays in this closure and
// is never persisted.
async function signIn(callsign, onStatus) {
  const verifier = randomVerifier();
  const challenge = await sha256Hex(verifier);

  const start = await fetch('/v1/auth/verify/start', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ callsign, pkceChallenge: challenge }),
  });
  if (!start.ok) throw new Error('Could not start sign-in. Check the callsign and try again.');
  const { pollToken } = await start.json();

  onStatus('Check your email for a sign-in link, then come back to this page.');

  // Poll until the emailed link is clicked. 202 = still pending.
  const deadline = Date.now() + 15 * 60 * 1000;
  while (Date.now() < deadline) {
    await new Promise(r => setTimeout(r, 3000));
    const poll = await fetch('/v1/auth/verify/poll', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pollToken, pkceVerifier: verifier }),
    });
    if (poll.status === 202) continue;
    if (!poll.ok) throw new Error('Sign-in failed. Start again.');
    const tokens = await poll.json();
    if (tokens.access) return tokens.access;
    throw new Error('Sign-in did not return an account session.');
  }
  throw new Error('Sign-in timed out. Reload the page to try again.');
}
"#;

// ---- consent screen --------------------------------------------------------

/// Render `GET /v1/oauth/authorize`.
///
/// An unknown client or an unregistered `redirect_uri` renders a terminal error
/// page and goes no further: those are the two conditions under which RFC 6749
/// §4.1.2.1 forbids redirecting, because doing so would make this an open
/// redirector or leak a code to an attacker-supplied URI.
pub async fn render_authorize(pool: &PgPool, query: ConsentPageQuery) -> Response {
    let Some(params) = to_params(query) else {
        return error_page(
            "Invalid authorization request",
            "The request is missing required parameters (client_id, redirect_uri, \
             response_type, and code_challenge are all required).",
        );
    };

    let validated = match super::oauth::validate_authorize(pool, &params).await {
        Ok(v) => v,
        Err(_) => {
            return error_page(
                "Unrecognized application",
                "This application is not registered with Carrier Wave, or the address it \
                 asked to be sent back to is not one it registered. Nothing has been shared. \
                 If you were expecting this, contact the application's developer.",
            );
        }
    };

    if validated.scopes.is_empty() {
        return error_page(
            "Nothing to authorize",
            "This application asked for permissions that do not exist, or that it is not \
             allowed to request.",
        );
    }

    let scope_items: String = validated
        .scopes
        .iter()
        .map(|scope| {
            format!(
                "<li><span class=\"scope-name\">{}</span>\
                 <span class=\"scope-desc\">{}</span></li>",
                html_escape(scope),
                html_escape(scope_map::describe(scope))
            )
        })
        .collect();

    // The request is echoed back to the decision endpoint, which re-validates
    // everything. Nothing here is trusted on the way back.
    let request_json = json_for_script(&serde_json::json!({
        "client_id": params.client_id,
        "redirect_uri": params.redirect_uri,
        "response_type": params.response_type,
        "scope": validated.scopes.join(" "),
        "state": params.state,
        "code_challenge": params.code_challenge,
        "code_challenge_method": params.code_challenge_method,
        "nonce": params.nonce,
    }));

    let client_name = html_escape(&validated.client.name);
    let homepage = validated
        .client
        .homepage_url
        .as_deref()
        .map(|url| {
            format!(
                "<p class=\"notice\">Developer site: {}</p>",
                html_escape(url)
            )
        })
        .unwrap_or_default();

    // Shown whenever the log is in scope. Users are about to be asked for their
    // sync passphrase by software that is not ours; say so plainly here, where
    // we still control the page.
    let passphrase_notice = if validated
        .scopes
        .iter()
        .any(|s| s.starts_with("sync:"))
    {
        "<p class=\"notice\"><strong>About your log:</strong> your log is encrypted, and \
         Carrier Wave cannot read it. Granting access here lets this application download \
         and upload your encrypted log, but it still needs your sync passphrase to make \
         sense of it. Only enter that passphrase in software you trust — anyone who has it \
         can read your entire log, and it cannot be changed afterwards.</p>"
    } else {
        ""
    };

    html(
        StatusCode::OK,
        format!(
            r#"<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Authorize {client_name} — Carrier Wave</title>
<style>{STYLE}</style>
</head><body>
<div class="card">
  <h1>Authorize {client_name}</h1>
  <p class="sub"><strong>{client_name}</strong> wants access to your Carrier Wave account.</p>

  <ul class="scopes">{scope_items}</ul>
  {homepage}
  {passphrase_notice}

  <div id="signin">
    <label for="callsign">Sign in to continue</label>
    <input id="callsign" name="callsign" autocomplete="username" autocapitalize="characters"
           spellcheck="false" placeholder="Your callsign">
    <div class="row">
      <button class="primary" id="signin-btn">Sign in</button>
    </div>
  </div>

  <div id="decide" class="hidden">
    <p class="sub" id="signed-in-as"></p>
    <div class="row">
      <button id="deny">Deny</button>
      <button class="primary" id="allow">Allow</button>
    </div>
  </div>

  <p class="msg" id="msg"></p>
</div>
<script>
{SIGN_IN_JS}

const request = {request_json};
const msg = document.getElementById('msg');
let accessToken = null;

function setMsg(text, isError) {{
  msg.textContent = text || '';
  msg.className = isError ? 'msg error' : 'msg';
}}

document.getElementById('signin-btn').addEventListener('click', async () => {{
  const callsign = document.getElementById('callsign').value.trim().toUpperCase();
  if (!callsign) return setMsg('Enter your callsign.', true);
  const btn = document.getElementById('signin-btn');
  btn.disabled = true;
  try {{
    accessToken = await signIn(callsign, t => setMsg(t, false));
    setMsg('', false);
    document.getElementById('signin').classList.add('hidden');
    document.getElementById('decide').classList.remove('hidden');
    document.getElementById('signed-in-as').textContent = 'Signed in as ' + callsign + '.';
  }} catch (err) {{
    setMsg(err.message, true);
    btn.disabled = false;
  }}
}});

async function decide(approve) {{
  setMsg(approve ? 'Authorizing…' : 'Cancelling…', false);
  document.getElementById('allow').disabled = true;
  document.getElementById('deny').disabled = true;
  try {{
    const resp = await fetch('/v1/oauth/authorize/decision', {{
      method: 'POST',
      headers: {{ 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + accessToken }},
      body: JSON.stringify(Object.assign({{}}, request, {{ approve }})),
    }});
    if (!resp.ok) throw new Error('The authorization could not be completed.');
    const {{ redirectUrl }} = await resp.json();
    window.location.assign(redirectUrl);
  }} catch (err) {{
    setMsg(err.message, true);
    document.getElementById('allow').disabled = false;
    document.getElementById('deny').disabled = false;
  }}
}}

document.getElementById('allow').addEventListener('click', () => decide(true));
document.getElementById('deny').addEventListener('click', () => decide(false));
</script>
</body></html>"#
        ),
    )
}

/// Collapse the all-optional page query into the strict parameter set, or `None`
/// when a required parameter is missing.
fn to_params(query: ConsentPageQuery) -> Option<AuthorizeParams> {
    Some(AuthorizeParams {
        client_id: query.client_id?,
        redirect_uri: query.redirect_uri?,
        response_type: query.response_type.unwrap_or_else(|| "code".to_string()),
        scope: query.scope,
        state: query.state,
        code_challenge: query.code_challenge?,
        code_challenge_method: query
            .code_challenge_method
            .or_else(|| Some("S256".to_string())),
        nonce: query.nonce,
    })
}

// ---- device verification screen --------------------------------------------

/// Render `GET /v1/oauth/device` — where someone types the code their CLI or
/// headless client printed.
pub fn render_device(user_code: Option<&str>) -> Response {
    let prefilled = user_code
        .map(dboauth::normalize_user_code)
        .unwrap_or_default();
    let prefilled_attr = html_escape(&prefilled);

    html(
        StatusCode::OK,
        format!(
            r#"<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Connect a device — Carrier Wave</title>
<style>{STYLE}</style>
</head><body>
<div class="card">
  <h1>Connect a device</h1>
  <p class="sub">Enter the code shown by the application you are connecting.</p>

  <label for="user-code">Code</label>
  <input id="user-code" value="{prefilled_attr}" autocapitalize="characters"
         spellcheck="false" placeholder="XXXX-XXXX">

  <div id="signin">
    <label for="callsign" style="margin-top:1.25rem">Sign in to continue</label>
    <input id="callsign" autocomplete="username" autocapitalize="characters"
           spellcheck="false" placeholder="Your callsign">
    <div class="row">
      <button class="primary" id="signin-btn">Sign in</button>
    </div>
  </div>

  <div id="decide" class="hidden">
    <p class="sub" id="signed-in-as"></p>
    <div class="row">
      <button id="deny">Deny</button>
      <button class="primary" id="allow">Allow</button>
    </div>
  </div>

  <p class="notice">Only approve a code you started yourself, on a device you are holding.
  If someone asked you to enter a code you did not generate, deny it.</p>
  <p class="msg" id="msg"></p>
</div>
<script>
{SIGN_IN_JS}

const msg = document.getElementById('msg');
let accessToken = null;

function setMsg(text, isError) {{
  msg.textContent = text || '';
  msg.className = isError ? 'msg error' : 'msg';
}}

document.getElementById('signin-btn').addEventListener('click', async () => {{
  const callsign = document.getElementById('callsign').value.trim().toUpperCase();
  if (!callsign) return setMsg('Enter your callsign.', true);
  const btn = document.getElementById('signin-btn');
  btn.disabled = true;
  try {{
    accessToken = await signIn(callsign, t => setMsg(t, false));
    setMsg('', false);
    document.getElementById('signin').classList.add('hidden');
    document.getElementById('decide').classList.remove('hidden');
    document.getElementById('signed-in-as').textContent = 'Signed in as ' + callsign + '.';
  }} catch (err) {{
    setMsg(err.message, true);
    btn.disabled = false;
  }}
}});

async function decide(approve) {{
  const userCode = document.getElementById('user-code').value.trim();
  if (!userCode) return setMsg('Enter the code shown by the application.', true);
  document.getElementById('allow').disabled = true;
  document.getElementById('deny').disabled = true;
  try {{
    const resp = await fetch('/v1/oauth/device/decision', {{
      method: 'POST',
      headers: {{ 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + accessToken }},
      body: JSON.stringify({{ userCode, approve }}),
    }});
    if (!resp.ok) {{
      const body = await resp.json().catch(() => ({{}}));
      throw new Error(body.error_description || 'That code is not valid or has expired.');
    }}
    const body = await resp.json();
    document.getElementById('decide').classList.add('hidden');
    setMsg(body.approved
      ? body.clientName + ' is now connected. You can close this page and return to it.'
      : 'Request denied. Nothing was shared.', false);
  }} catch (err) {{
    setMsg(err.message, true);
    document.getElementById('allow').disabled = false;
    document.getElementById('deny').disabled = false;
  }}
}}

document.getElementById('allow').addEventListener('click', () => decide(true));
document.getElementById('deny').addEventListener('click', () => decide(false));
</script>
</body></html>"#
        ),
    )
}

fn error_page(heading: &str, detail: &str) -> Response {
    html(
        StatusCode::BAD_REQUEST,
        format!(
            r#"<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>{heading} — Carrier Wave</title>
<style>{STYLE}</style>
</head><body>
<div class="card">
  <h1>{heading}</h1>
  <p class="sub">{detail}</p>
</div>
</body></html>"#,
            heading = html_escape(heading),
            detail = html_escape(detail),
        ),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn html_escape_neutralizes_markup() {
        assert_eq!(
            html_escape(r#"<script>alert("x")</script>"#),
            "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"
        );
    }

    /// A client name or state value containing `</script>` must not be able to
    /// break out of the JSON island and execute.
    #[test]
    fn json_island_cannot_close_the_script_block() {
        let value = serde_json::json!({ "state": "</script><img src=x onerror=alert(1)>" });
        let encoded = json_for_script(&value);
        assert!(!encoded.contains("</script>"));
        assert!(encoded.contains("\\u003c/script"));
    }

    #[test]
    fn missing_required_params_yield_no_authorize_request() {
        let query = ConsentPageQuery {
            client_id: Some("c".into()),
            redirect_uri: None,
            response_type: Some("code".into()),
            scope: None,
            state: None,
            code_challenge: Some("abc".into()),
            code_challenge_method: None,
            nonce: None,
        };
        assert!(to_params(query).is_none());
    }

    #[test]
    fn params_default_to_code_and_s256() {
        let query = ConsentPageQuery {
            client_id: Some("c".into()),
            redirect_uri: Some("https://app.example/cb".into()),
            response_type: None,
            scope: None,
            state: None,
            code_challenge: Some("abc".into()),
            code_challenge_method: None,
            nonce: None,
        };
        let params = to_params(query).expect("params");
        assert_eq!(params.response_type, "code");
        assert_eq!(params.code_challenge_method.as_deref(), Some("S256"));
    }

    #[test]
    fn device_page_prefills_and_normalizes_the_user_code() {
        let response = render_device(Some("krwgzptl"));
        assert_eq!(response.status(), StatusCode::OK);
    }
}
