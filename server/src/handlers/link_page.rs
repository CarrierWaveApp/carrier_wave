// HTML landing pages for enriched share links.
//
// Routes: /link/{call,park,sum,qso,act}/:identifier
//
// The page ships a tiny inline shell + the link-card.js bundle, which decodes
// the URL fragment (`#d=<base64url(JSON)>`) and renders a card client-side.
// The fragment is never sent in HTTP requests, so log data never reaches the
// server. See docs/plans/2026-04-07-imessage-enriched-text-server-spec.md.
//
// AASA (apple-app-site-association) is also served from this module so iOS /
// macOS recipients with the app installed jump straight to the in-app detail
// view via a universal link.
use axum::{
    extract::Path,
    http::{header, HeaderName, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
};

const LINK_CARD_JS: &str = include_str!("../../static/link/link-card.js");

const HTML_CACHE: &str = "public, max-age=3600, s-maxage=86400";
const JS_CACHE: &str = "public, max-age=86400, s-maxage=604800";
const AASA_CACHE: &str = "public, max-age=3600";

/// Apple Developer team prefix for both bundle IDs.
const TEAM_ID: &str = "7UE4RDLUSX";
const IOS_BUNDLE_ID: &str = "com.jsvana.FullDuplex";
const MACOS_BUNDLE_ID: &str = "com.jsvana.CWSweep";

/// GET /link/qso/:token
pub async fn link_page_qso(Path(token): Path<String>) -> Response {
    render_page(LinkKind::Qso, &token)
}

/// GET /link/act/:token
pub async fn link_page_activation(Path(token): Path<String>) -> Response {
    render_page(LinkKind::Activation, &token)
}

/// GET /link/call/:callsign  (slashes encoded as `-`, e.g. `KD9LSV-P`)
pub async fn link_page_callsign(Path(raw): Path<String>) -> Response {
    render_page(LinkKind::Call, &raw)
}

/// GET /link/park/:reference
pub async fn link_page_park(Path(raw): Path<String>) -> Response {
    render_page(LinkKind::Park, &raw)
}

/// GET /link/sum/:reference  (SOTA summit, slashes encoded as `-`)
pub async fn link_page_summit(Path(raw): Path<String>) -> Response {
    render_page(LinkKind::Summit, &raw)
}

/// GET /link/static/link-card.js
pub async fn link_card_js() -> Response {
    (
        StatusCode::OK,
        [
            (
                header::CONTENT_TYPE,
                HeaderValue::from_static("application/javascript; charset=utf-8"),
            ),
            (header::CACHE_CONTROL, HeaderValue::from_static(JS_CACHE)),
        ],
        LINK_CARD_JS,
    )
        .into_response()
}

/// GET /.well-known/apple-app-site-association
pub async fn apple_app_site_association() -> Response {
    let body = serde_json::json!({
        "applinks": {
            "apps": [],
            "details": [
                {
                    "appID": format!("{TEAM_ID}.{IOS_BUNDLE_ID}"),
                    "paths": ["/link/*"],
                },
                {
                    "appID": format!("{TEAM_ID}.{MACOS_BUNDLE_ID}"),
                    "paths": ["/link/*"],
                },
            ],
        },
    });
    (
        StatusCode::OK,
        [
            (
                header::CONTENT_TYPE,
                HeaderValue::from_static("application/json"),
            ),
            (header::CACHE_CONTROL, HeaderValue::from_static(AASA_CACHE)),
        ],
        body.to_string(),
    )
        .into_response()
}

#[derive(Copy, Clone)]
enum LinkKind {
    Qso,
    Activation,
    Call,
    Park,
    Summit,
}

impl LinkKind {
    fn slug(self) -> &'static str {
        match self {
            LinkKind::Qso => "qso",
            LinkKind::Activation => "act",
            LinkKind::Call => "call",
            LinkKind::Park => "park",
            LinkKind::Summit => "sum",
        }
    }

    fn og_title(self, identifier: &str) -> String {
        let display = identifier.replace('-', "/").to_uppercase();
        match self {
            LinkKind::Qso => "Carrier Wave QSO".to_string(),
            LinkKind::Activation => "Carrier Wave Activation".to_string(),
            LinkKind::Call => format!("{display} on Carrier Wave"),
            LinkKind::Park => format!("{display} on Carrier Wave"),
            LinkKind::Summit => format!("{display} on Carrier Wave"),
        }
    }

    fn og_description(self) -> &'static str {
        match self {
            LinkKind::Qso => "A QSO shared from Carrier Wave. Open in the app for full details.",
            LinkKind::Activation => {
                "An activation shared from Carrier Wave. Open in the app for full details."
            }
            LinkKind::Call => "Callsign details shared from Carrier Wave.",
            LinkKind::Park => "Park details shared from Carrier Wave.",
            LinkKind::Summit => "SOTA summit details shared from Carrier Wave.",
        }
    }

    fn page_kicker(self) -> &'static str {
        match self {
            LinkKind::Qso => "QSO",
            LinkKind::Activation => "Activation",
            LinkKind::Call => "Callsign",
            LinkKind::Park => "Park",
            LinkKind::Summit => "Summit",
        }
    }
}

fn render_page(kind: LinkKind, identifier: &str) -> Response {
    let html = render_html(kind, identifier);
    let headers: [(HeaderName, HeaderValue); 2] = [
        (
            header::CONTENT_TYPE,
            HeaderValue::from_static("text/html; charset=utf-8"),
        ),
        (header::CACHE_CONTROL, HeaderValue::from_static(HTML_CACHE)),
    ];
    (StatusCode::OK, headers, html).into_response()
}

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

fn render_html(kind: LinkKind, identifier: &str) -> String {
    let title = html_escape(&kind.og_title(identifier));
    let description = html_escape(kind.og_description());
    let kicker = html_escape(kind.page_kicker());
    let canonical_path = format!("/link/{}/{}", kind.slug(), identifier);
    let canonical_url = format!("https://carrierwave.app{canonical_path}");
    let canonical_url_attr = html_escape(&canonical_url);
    let canonical_path_attr = html_escape(&canonical_path);
    let identifier_display = html_escape(&identifier.replace('-', "/").to_uppercase());

    format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Carrier Wave">
<meta property="og:url" content="{canonical_url_attr}">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:image" content="https://carrierwave.app/icon.png">
<meta property="og:image:width" content="512">
<meta property="og:image:height" content="512">
<meta name="twitter:card" content="summary_large_image">
<meta name="apple-itunes-app" content="app-id=APPID, app-argument={canonical_url_attr}">
<style>
:root{{
  --cw-orange:#f97316;
  --cw-orange-bright:#fb923c;
  --cw-cyan:#67e8f9;
  --cw-bg-1:#070b14;
  --cw-bg-2:#0f1729;
  --cw-bg-3:#1a2238;
  --cw-text:#f8fafc;
  --cw-muted:rgba(148,163,184,.78);
  --cw-faint:rgba(148,163,184,.45);
  --cw-card-border:rgba(249,115,22,.18);
  --cw-card-shadow:0 30px 60px rgba(0,0,0,.55),0 0 0 1px rgba(249,115,22,.08);
}}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{height:100%}}
body{{
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  background:
    radial-gradient(1200px 600px at 20% -10%,rgba(249,115,22,.18),transparent 70%),
    radial-gradient(900px 600px at 90% 10%,rgba(103,232,249,.10),transparent 65%),
    linear-gradient(180deg,var(--cw-bg-1) 0%,var(--cw-bg-2) 50%,var(--cw-bg-1) 100%);
  color:var(--cw-text);
  min-height:100vh;
  display:flex;
  flex-direction:column;
  align-items:center;
  justify-content:flex-start;
  padding:2rem 1.25rem 3rem;
}}
.brand-bar{{
  display:flex;align-items:center;gap:.65rem;
  margin-bottom:1.5rem;
  letter-spacing:.32em;
  text-transform:uppercase;
  font-size:.78rem;
  font-weight:700;
  color:rgba(241,245,249,.85);
}}
.brand-bar svg{{width:32px;height:32px;flex:0 0 auto}}
.brand-bar b{{color:var(--cw-orange);font-weight:800}}
.shell{{width:100%;max-width:760px;display:flex;flex-direction:column;gap:1.25rem}}
.card{{
  background:linear-gradient(160deg,#0c1426,#16213a);
  border:1px solid var(--cw-card-border);
  border-radius:1.5rem;
  padding:2rem 1.85rem 1.85rem;
  box-shadow:var(--cw-card-shadow);
  position:relative;
  overflow:hidden;
}}
.card::before{{
  content:"";
  position:absolute;left:0;right:0;top:0;height:3px;
  background:linear-gradient(90deg,transparent,var(--cw-orange) 30%,var(--cw-orange-bright) 70%,transparent);
  opacity:.85;
}}
.kicker{{
  font-size:.78rem;font-weight:700;letter-spacing:.42em;text-transform:uppercase;
  margin-bottom:.65rem;
  display:inline-flex;align-items:center;gap:.5rem;
}}
.kicker::before{{
  content:"";display:inline-block;width:14px;height:2px;background:currentColor;border-radius:2px;
  box-shadow:0 0 8px currentColor;opacity:.85;
}}
.headline{{
  display:flex;flex-wrap:wrap;align-items:baseline;
  gap:.4rem 1.25rem;
  margin-bottom:.6rem;
}}
.op-call{{
  font-family:ui-monospace,"SF Mono",Menlo,monospace;
  font-size:clamp(2.4rem,7vw,4rem);
  font-weight:800;color:var(--cw-text);letter-spacing:.02em;
  line-height:1;
}}
.op-arrow{{
  font-size:clamp(1.2rem,2.6vw,1.7rem);color:var(--cw-faint);font-weight:500;
}}
.op-mine{{
  font-family:ui-monospace,"SF Mono",Menlo,monospace;
  font-size:clamp(1.4rem,3.6vw,2.1rem);font-weight:500;color:rgba(241,245,249,.72);
  line-height:1;
}}
.subhead{{font-size:1.1rem;font-weight:500;color:rgba(241,245,249,.92);margin-bottom:.4rem}}
.operator{{
  font-family:ui-monospace,"SF Mono",Menlo,monospace;
  font-size:.95rem;color:var(--cw-muted);margin-bottom:.5rem;
}}
.chips{{display:flex;flex-direction:column;gap:.4rem;margin:.85rem 0 .25rem}}
.chips:empty{{margin:0}}
.chip-row{{display:flex;flex-wrap:wrap;align-items:center;gap:.45rem}}
.chip-row-label{{
  font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:.7rem;font-weight:600;
  letter-spacing:.18em;color:var(--cw-faint);text-transform:uppercase;margin-right:.25rem;
}}
.chip{{
  display:inline-flex;align-items:center;gap:.4rem;
  padding:.32rem .65rem;
  background:rgba(103,232,249,.08);
  border:1px solid rgba(103,232,249,.22);
  border-radius:9999px;
  font-size:.82rem;font-weight:600;color:var(--cw-text);
  white-space:nowrap;
}}
.chip-emoji{{font-size:.95rem;line-height:1}}
.map-wrap{{
  margin:1rem 0 .5rem;
  border-radius:.85rem;
  overflow:hidden;
  border:1px solid rgba(103,232,249,.16);
  background:#06101f;
  position:relative;
}}
.map-wrap::after{{
  content:"";position:absolute;inset:0;pointer-events:none;
  background:radial-gradient(circle at 50% 110%,rgba(249,115,22,.15),transparent 55%);
}}
.map{{display:block;width:100%;height:auto}}
.map-bg{{fill:#06101f}}
.map-grid line{{stroke:rgba(103,232,249,.08);stroke-width:.6}}
.map-continents path{{
  fill:rgba(103,232,249,.08);
  stroke:rgba(103,232,249,.32);
  stroke-width:.6;stroke-linejoin:round;
}}
.map-arc{{fill:none;stroke:var(--cw-orange);stroke-width:1.6;stroke-linecap:round}}
.map-arc-glow{{fill:none;stroke:var(--cw-orange);stroke-width:5;stroke-linecap:round;opacity:.18;filter:blur(2px)}}
.map-pin .dot{{fill:#fff}}
.map-pin .halo{{fill:none;stroke:#fff;stroke-width:.8;opacity:.65}}
.map-pin .halo-2{{opacity:.35}}
.map-pin-me .dot{{fill:var(--cw-orange)}}
.map-pin-me .halo{{stroke:var(--cw-orange)}}
.map-pin-them .dot{{fill:var(--cw-cyan)}}
.map-pin-them .halo{{stroke:var(--cw-cyan)}}
.map-pin text{{
  font-family:ui-monospace,"SF Mono",Menlo,monospace;
  font-size:11px;font-weight:700;text-anchor:middle;
  fill:#f8fafc;
  paint-order:stroke;stroke:#06101f;stroke-width:3;stroke-linejoin:round;
}}
.badges{{
  display:grid;
  grid-template-columns:repeat(auto-fit,minmax(110px,1fr));
  gap:.85rem 1.4rem;
  margin-top:1rem;
  padding-top:1rem;
  border-top:1px solid rgba(148,163,184,.12);
}}
.badge-label{{
  font-family:ui-monospace,"SF Mono",Menlo,monospace;
  font-size:.66rem;font-weight:600;letter-spacing:.18em;color:var(--cw-faint);text-transform:uppercase;
}}
.badge-value{{
  font-family:ui-monospace,"SF Mono",Menlo,monospace;
  font-size:1.05rem;font-weight:700;color:var(--cw-text);margin-top:.12rem;
}}
.footnote{{
  font-family:ui-monospace,"SF Mono",Menlo,monospace;
  font-size:.92rem;color:var(--cw-muted);margin-top:1rem;letter-spacing:.04em;
}}
.notes{{
  margin-top:.85rem;padding:.7rem .9rem;
  background:rgba(249,115,22,.08);
  border-left:3px solid var(--cw-orange);
  border-radius:.45rem;
  font-style:italic;color:rgba(241,245,249,.88);font-size:.92rem;
}}
.fallback-id{{
  font-family:ui-monospace,"SF Mono",Menlo,monospace;
  font-size:clamp(1.4rem,4vw,2rem);font-weight:700;color:var(--cw-text);
  letter-spacing:.04em;margin-bottom:.75rem;
}}
.fallback-msg{{color:var(--cw-muted);font-size:.93rem;line-height:1.55}}
.fallback-msg code{{
  font-family:ui-monospace,"SF Mono",Menlo,monospace;
  background:rgba(148,163,184,.12);padding:.05rem .35rem;border-radius:.25rem;
}}
.cta{{display:flex;flex-wrap:wrap;gap:.65rem;align-items:center;justify-content:center;margin-top:.25rem}}
.cta a{{
  display:inline-flex;align-items:center;gap:.5rem;
  background:var(--cw-orange);color:#0d121f;
  text-decoration:none;font-weight:700;font-size:.95rem;
  padding:.78rem 1.3rem;border-radius:.6rem;
  transition:transform .12s ease,background .12s ease,box-shadow .12s ease;
  box-shadow:0 8px 24px rgba(249,115,22,.25);
}}
.cta a:hover{{background:var(--cw-orange-bright);transform:translateY(-1px);box-shadow:0 12px 28px rgba(249,115,22,.35)}}
.cta a.ghost{{background:transparent;color:rgba(241,245,249,.85);border:1px solid rgba(148,163,184,.35);box-shadow:none}}
.cta a.ghost:hover{{background:rgba(148,163,184,.12);color:var(--cw-text)}}
.foot{{
  text-align:center;color:var(--cw-faint);font-size:.78rem;
  letter-spacing:.18em;text-transform:uppercase;margin-top:.5rem;
}}
.foot b{{color:var(--cw-orange);font-weight:700}}
@media (max-width:540px){{
  body{{padding:1.25rem .85rem 2rem}}
  .card{{padding:1.6rem 1.15rem 1.4rem;border-radius:1.1rem}}
  .badges{{grid-template-columns:repeat(auto-fit,minmax(96px,1fr));gap:.7rem 1rem}}
}}
</style>
</head>
<body>
<div class="brand-bar">
  <svg viewBox="0 0 64 64" aria-hidden="true">
    <defs>
      <linearGradient id="cwlogo" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0%" stop-color="#fb923c"/>
        <stop offset="100%" stop-color="#f97316"/>
      </linearGradient>
    </defs>
    <rect x="2" y="2" width="60" height="60" rx="14" fill="url(#cwlogo)"/>
    <path d="M10 38 Q18 18 26 38 T42 38 T58 38" fill="none" stroke="#fff" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>
    <circle cx="10" cy="38" r="2.6" fill="#fff"/>
    <circle cx="58" cy="38" r="2.6" fill="#fff"/>
  </svg>
  <span><b>Carrier Wave</b></span>
</div>
<div class="shell">
  <div class="card" id="card-container">
    <div class="kicker">{kicker}</div>
    <div class="fallback-id">{identifier_display}</div>
    <div class="fallback-msg">
      Open this link on a device with Carrier Wave installed for the full details.
      If this preview looks empty in a chat app, the rich data lives in the URL
      fragment (after the <code>#</code>) and is only visible when the page
      loads in a browser.
    </div>
  </div>
  <div class="cta">
    <a href="{canonical_path_attr}">Open in Carrier Wave</a>
    <a class="ghost" href="https://carrierwave.app/">Get Carrier Wave</a>
  </div>
  <div class="foot"><b>Carrier Wave</b> &middot; ham radio, signal first</div>
</div>
<script src="/link/static/link-card.js" defer></script>
</body>
</html>
"##
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qso_page_includes_og_metadata_and_decoder_script() {
        let html = render_html(LinkKind::Qso, "jZRcZAZMQI");
        assert!(html.contains("Carrier Wave QSO"), "missing OG title");
        assert!(html.contains("/link/qso/jZRcZAZMQI"), "missing canonical URL");
        assert!(
            html.contains("/link/static/link-card.js"),
            "missing decoder script"
        );
        assert!(html.contains("og:image"), "missing OG image");
    }

    #[test]
    fn callsign_page_displays_normalized_identifier() {
        let html = render_html(LinkKind::Call, "kd9lsv-p");
        // path identifier is preserved verbatim, but the visible fallback
        // is normalized so `kd9lsv-p` shows as `KD9LSV/P`.
        assert!(html.contains(">KD9LSV/P<"), "callsign not normalized");
        assert!(html.contains("/link/call/kd9lsv-p"), "canonical preserved");
    }

    #[test]
    fn html_escape_handles_dangerous_chars() {
        assert_eq!(
            html_escape("a<b>&\"'"),
            "a&lt;b&gt;&amp;&quot;&#39;"
        );
    }

    #[test]
    fn aasa_payload_lists_both_bundle_ids() {
        let payload = serde_json::json!({
            "applinks": {
                "apps": [],
                "details": [
                    {
                        "appID": format!("{TEAM_ID}.{IOS_BUNDLE_ID}"),
                        "paths": ["/link/*"],
                    },
                    {
                        "appID": format!("{TEAM_ID}.{MACOS_BUNDLE_ID}"),
                        "paths": ["/link/*"],
                    },
                ],
            },
        });
        let details = payload["applinks"]["details"].as_array().unwrap();
        assert_eq!(details.len(), 2);
        assert_eq!(
            details[0]["appID"],
            format!("{TEAM_ID}.{IOS_BUNDLE_ID}")
        );
        assert_eq!(
            details[1]["appID"],
            format!("{TEAM_ID}.{MACOS_BUNDLE_ID}")
        );
    }

    #[test]
    fn link_card_js_bundle_includes_payload_decoder() {
        // Sanity check that `include_str!` picked up the JS bundle and that
        // it carries the schema-version constant the iOS encoder uses.
        assert!(LINK_CARD_JS.contains("readFragmentPayload"));
        assert!(LINK_CARD_JS.contains("SCHEMA_VERSION"));
    }
}
