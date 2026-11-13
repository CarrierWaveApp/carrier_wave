// Carrier Wave enriched link card renderer.
//
// Decodes the `#d=<base64url(JSON)>` URL fragment shipped by the iOS / macOS
// share UIs (see swift/packages/CarrierWaveCore/Sources/CarrierWaveCore/Sharing/
// EnrichedLinkPayload.swift) and renders a styled card in the page so
// recipients without the app installed see the QSO/callsign/park/summit/
// activation details. The fragment is read locally by the browser — it
// never reaches the server.
//
// QSO/activation cards include:
//   - a great-circle map (computed from Maidenhead grids in the payload)
//   - club / membership chips (fetched async from the public
//     /v1/callsign-enrichment endpoint, public membership data only)
//   - distance + bearing
//
// Schema version 1.

(function () {
  "use strict";

  var SCHEMA_VERSION = 1;
  var ENRICHMENT_BASE = "https://activities.carrierwave.app/v1/callsign-enrichment/";

  // ---- fragment decoding -------------------------------------------------

  function base64UrlDecodeToString(input) {
    var s = String(input).replace(/-/g, "+").replace(/_/g, "/");
    while (s.length % 4 !== 0) s += "=";
    var binary;
    try {
      binary = atob(s);
    } catch (e) {
      throw new Error("invalid base64url");
    }
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    if (typeof TextDecoder === "function") {
      return new TextDecoder("utf-8").decode(bytes);
    }
    return decodeURIComponent(escape(binary));
  }

  function readFragmentPayload() {
    var hash = window.location.hash || "";
    if (hash[0] === "#") hash = hash.slice(1);
    if (!hash) return null;
    if (hash.indexOf("d=") === 0) hash = hash.slice(2);
    if (!hash) return null;
    var json;
    try {
      json = base64UrlDecodeToString(hash);
    } catch (e) {
      return null;
    }
    try {
      return JSON.parse(json);
    } catch (e) {
      return null;
    }
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  // ---- formatting --------------------------------------------------------

  function formatUtc(ts) {
    if (typeof ts !== "number") return "";
    var d = new Date(ts * 1000);
    if (isNaN(d.getTime())) return "";
    function pad(n) { return n < 10 ? "0" + n : "" + n; }
    return (
      d.getUTCFullYear() + "-" + pad(d.getUTCMonth() + 1) + "-" + pad(d.getUTCDate()) +
      " " + pad(d.getUTCHours()) + ":" + pad(d.getUTCMinutes()) + "Z"
    );
  }

  function formatFrequency(mhz) {
    if (typeof mhz !== "number" || !isFinite(mhz)) return "";
    return mhz.toFixed(4) + " MHz";
  }

  function formatDistance(km) {
    if (typeof km !== "number" || !isFinite(km)) return "";
    if (km < 1000) return Math.round(km) + " km";
    return Math.round(km).toLocaleString() + " km";
  }

  function formatBearing(deg) {
    if (typeof deg !== "number" || !isFinite(deg)) return "";
    var dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"];
    var dir = dirs[Math.round(deg / 22.5) % 16];
    return Math.round(deg) + "° " + dir;
  }

  // ---- maidenhead grid → lat/lon ----------------------------------------

  function gridToLatLon(grid) {
    if (!grid || typeof grid !== "string") return null;
    var g = grid.trim().toUpperCase();
    if (g.length < 4) return null;
    var A = "A".charCodeAt(0);
    var f1 = g.charCodeAt(0) - A;
    var f2 = g.charCodeAt(1) - A;
    var s1 = parseInt(g.charAt(2), 10);
    var s2 = parseInt(g.charAt(3), 10);
    if (f1 < 0 || f1 > 17 || f2 < 0 || f2 > 17 || isNaN(s1) || isNaN(s2)) return null;
    var lon = -180 + f1 * 20 + s1 * 2;
    var lat = -90 + f2 * 10 + s2 * 1;
    if (g.length >= 6) {
      var u1 = g.charCodeAt(4) - A;
      var u2 = g.charCodeAt(5) - A;
      if (u1 >= 0 && u1 <= 23 && u2 >= 0 && u2 <= 23) {
        lon += u1 * (5 / 60);
        lat += u2 * (2.5 / 60);
        lon += 2.5 / 60;        // center of subsquare
        lat += 1.25 / 60;
      } else {
        lon += 1; lat += 0.5;   // center of square
      }
    } else {
      lon += 1; lat += 0.5;
    }
    return { lat: lat, lon: lon };
  }

  function deg2rad(d) { return d * Math.PI / 180; }
  function rad2deg(r) { return r * 180 / Math.PI; }

  function greatCircleDistance(a, b) {
    var R = 6371; // km
    var dLat = deg2rad(b.lat - a.lat);
    var dLon = deg2rad(b.lon - a.lon);
    var lat1 = deg2rad(a.lat), lat2 = deg2rad(b.lat);
    var x = Math.sin(dLat/2) * Math.sin(dLat/2)
          + Math.sin(dLon/2) * Math.sin(dLon/2) * Math.cos(lat1) * Math.cos(lat2);
    return 2 * R * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
  }

  function bearing(a, b) {
    var lat1 = deg2rad(a.lat), lat2 = deg2rad(b.lat);
    var dLon = deg2rad(b.lon - a.lon);
    var y = Math.sin(dLon) * Math.cos(lat2);
    var x = Math.cos(lat1) * Math.sin(lat2)
          - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
    var theta = rad2deg(Math.atan2(y, x));
    return (theta + 360) % 360;
  }

  function greatCirclePath(a, b, samples) {
    // Slerp between two unit vectors on the sphere.
    samples = samples || 80;
    var lat1 = deg2rad(a.lat), lon1 = deg2rad(a.lon);
    var lat2 = deg2rad(b.lat), lon2 = deg2rad(b.lon);
    var ax = Math.cos(lat1) * Math.cos(lon1);
    var ay = Math.cos(lat1) * Math.sin(lon1);
    var az = Math.sin(lat1);
    var bx = Math.cos(lat2) * Math.cos(lon2);
    var by = Math.cos(lat2) * Math.sin(lon2);
    var bz = Math.sin(lat2);
    var dot = Math.max(-1, Math.min(1, ax*bx + ay*by + az*bz));
    var omega = Math.acos(dot);
    var sinOmega = Math.sin(omega);
    var pts = [];
    for (var i = 0; i <= samples; i++) {
      var t = i / samples;
      var s1, s2;
      if (sinOmega < 1e-9) { s1 = 1 - t; s2 = t; }
      else {
        s1 = Math.sin((1 - t) * omega) / sinOmega;
        s2 = Math.sin(t * omega) / sinOmega;
      }
      var x = s1 * ax + s2 * bx;
      var y = s1 * ay + s2 * by;
      var z = s1 * az + s2 * bz;
      var lat = rad2deg(Math.asin(z));
      var lon = rad2deg(Math.atan2(y, x));
      pts.push({ lat: lat, lon: lon });
    }
    return pts;
  }

  // ---- world map (equirectangular) --------------------------------------

  // Width and height of the SVG drawing area (viewBox units).
  var MAP_W = 720;
  var MAP_H = 320;

  function projectEquirect(p) {
    return {
      x: ((p.lon + 180) % 360) / 360 * MAP_W,
      y: (90 - p.lat) / 180 * MAP_H,
    };
  }

  // Very rough simplified continent outlines, hand-drawn from public-domain
  // world references and rounded to integer degrees. Coordinates are
  // [lon, lat] pairs forming a closed polygon. Good enough to communicate
  // "this is where the QSO happened" — nothing claims to be cartographic.
  var CONTINENTS = [
    // North America (including Greenland to the right)
    [[-168,66],[-160,71],[-140,71],[-130,69],[-128,57],[-122,49],[-125,40],[-117,33],[-110,23],
     [-100,18],[-92,16],[-83,9],[-78,8],[-66,11],[-57,49],[-66,50],[-53,60],[-44,60],[-30,72],
     [-50,82],[-90,82],[-128,77]],
    // South America
    [[-82,9],[-75,-2],[-72,-15],[-70,-23],[-72,-37],[-65,-54],[-55,-50],[-47,-30],[-37,-12],
     [-43,-5],[-49,1],[-58,7],[-66,11],[-77,9]],
    // Europe + Russia + Asia (Eurasia)
    [[-10,36],[-9,43],[2,50],[-5,58],[5,62],[15,68],[28,71],[40,68],[58,71],[70,75],[100,76],
     [140,73],[170,69],[180,67],[180,55],[170,60],[155,57],[140,55],[135,42],[125,38],[122,30],
     [110,20],[100,10],[95,5],[80,8],[72,20],[60,23],[55,12],[48,12],[42,15],[35,29],[30,32],
     [12,34],[3,37],[-6,36]],
    // Africa
    [[-17,21],[-17,15],[-12,8],[5,5],[10,3],[15,-5],[14,-15],[20,-35],[27,-34],[33,-29],[35,-21],
     [40,-15],[51,-2],[51,11],[43,12],[35,29],[30,32],[12,34],[-6,36],[-17,28]],
    // Australia
    [[114,-22],[122,-18],[131,-12],[143,-11],[152,-25],[150,-37],[140,-38],[130,-32],[115,-34]],
    // Antarctica (bottom strip)
    [[-180,-72],[-180,-90],[180,-90],[180,-72],[160,-78],[100,-72],[40,-72],[-30,-78],[-90,-78],[-150,-74]],
  ];

  function continentPath(poly) {
    if (!poly.length) return "";
    var d = "M ";
    for (var i = 0; i < poly.length; i++) {
      var p = projectEquirect({ lon: poly[i][0], lat: poly[i][1] });
      d += (i ? " L " : "") + p.x.toFixed(1) + "," + p.y.toFixed(1);
    }
    return d + " Z";
  }

  function gridLinesSvg() {
    var lines = [];
    for (var lon = -180; lon <= 180; lon += 30) {
      var x = ((lon + 180) / 360) * MAP_W;
      lines.push('<line x1="' + x + '" y1="0" x2="' + x + '" y2="' + MAP_H + '"/>');
    }
    for (var lat = -60; lat <= 60; lat += 30) {
      var y = ((90 - lat) / 180) * MAP_H;
      lines.push('<line x1="0" y1="' + y + '" x2="' + MAP_W + '" y2="' + y + '"/>');
    }
    return '<g class="map-grid">' + lines.join("") + "</g>";
  }

  function continentsSvg() {
    return '<g class="map-continents">' +
      CONTINENTS.map(function (poly) { return '<path d="' + continentPath(poly) + '"/>'; }).join("") +
      "</g>";
  }

  // Split a great-circle path into segments that don't cross the antimeridian.
  function pathToPolylines(path) {
    var lines = [];
    var current = [];
    for (var i = 0; i < path.length; i++) {
      var p = path[i];
      if (current.length) {
        var prev = current[current.length - 1].raw;
        if (Math.abs(prev.lon - p.lon) > 180) {
          // wrap — close this segment, start a new one
          lines.push(current);
          current = [];
        }
      }
      current.push({ raw: p, proj: projectEquirect(p) });
    }
    if (current.length) lines.push(current);
    return lines;
  }

  function arcSvg(a, b) {
    var path = greatCirclePath(a, b, 96);
    var segments = pathToPolylines(path);
    var pieces = segments.map(function (seg) {
      if (seg.length < 2) return "";
      var d = "M " + seg.map(function (s) { return s.proj.x.toFixed(1) + "," + s.proj.y.toFixed(1); })
                       .join(" L ");
      return '<path class="map-arc-glow" d="' + d + '"/>' +
             '<path class="map-arc" d="' + d + '"/>';
    }).join("");
    return pieces;
  }

  function dotSvg(point, klass, label) {
    if (!point) return "";
    var p = projectEquirect(point);
    return (
      '<g class="map-pin ' + klass + '" transform="translate(' + p.x.toFixed(1) + ',' + p.y.toFixed(1) + ')">' +
      '<circle class="halo" r="14"/>' +
      '<circle class="halo halo-2" r="9"/>' +
      '<circle class="dot" r="5"/>' +
      (label ? '<text y="-14">' + escapeHtml(label) + "</text>" : "") +
      "</g>"
    );
  }

  function buildMap(myPoint, theirPoint, myLabel, theirLabel) {
    if (!myPoint && !theirPoint) return "";
    var arcMarkup = "";
    if (myPoint && theirPoint) arcMarkup = arcSvg(myPoint, theirPoint);
    return (
      '<svg class="map" viewBox="0 0 ' + MAP_W + " " + MAP_H + '" preserveAspectRatio="xMidYMid meet" aria-hidden="true">' +
      '<rect class="map-bg" width="' + MAP_W + '" height="' + MAP_H + '"/>' +
      gridLinesSvg() +
      continentsSvg() +
      arcMarkup +
      dotSvg(theirPoint, "map-pin-them", theirLabel) +
      dotSvg(myPoint, "map-pin-me", myLabel) +
      "</svg>"
    );
  }

  // ---- club enrichment ---------------------------------------------------

  function fetchEnrichment(callsign) {
    if (!callsign) return Promise.resolve(null);
    var url = ENRICHMENT_BASE + encodeURIComponent(callsign);
    return fetch(url, { headers: { Accept: "application/json" } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; });
  }

  function chipsHtml(label, response) {
    if (!response || !response.memberships || !response.memberships.length) return "";
    var chips = response.memberships.map(function (m) {
      var emoji = m.emoji || "";
      var src = m.source_name || m.source_slug || "";
      var num = m.member_number ? " #" + m.member_number : "";
      return (
        '<span class="chip">' +
        (emoji ? '<span class="chip-emoji">' + escapeHtml(emoji) + "</span>" : "") +
        '<span class="chip-text">' + escapeHtml(src + num) + "</span>" +
        "</span>"
      );
    }).join("");
    return (
      '<div class="chip-row"><span class="chip-row-label">' + escapeHtml(label) + "</span>" +
      chips + "</div>"
    );
  }

  // ---- card renderers ----------------------------------------------------

  function badge(label, value, tint) {
    if (value === undefined || value === null || value === "") return "";
    var color = tint || "#f8fafc";
    return (
      '<div class="badge">' +
      '<div class="badge-label">' + escapeHtml(label) + "</div>" +
      '<div class="badge-value" style="color:' + color + '">' + escapeHtml(value) + "</div>" +
      "</div>"
    );
  }

  function renderQso(p) {
    var their = (p.c || "").toString().toUpperCase();
    var mine  = (p.me || "").toString().toUpperCase();
    var rstSent = p.rs, rstRecv = p.rr;
    var rst = rstSent && rstRecv ? rstSent + "/" + rstRecv : null;
    var myPoint = gridToLatLon(p.mg);
    var theirPoint = gridToLatLon(p.tg);
    var distKm = (myPoint && theirPoint) ? greatCircleDistance(myPoint, theirPoint) : null;
    var bear   = (myPoint && theirPoint) ? bearing(myPoint, theirPoint) : null;
    var headline = mine
      ? '<span class="op-call">' + escapeHtml(their) + "</span>" +
        '<span class="op-arrow" aria-hidden="true">←</span>' +
        '<span class="op-mine">' + escapeHtml(mine) + "</span>"
      : '<span class="op-call">' + escapeHtml(their) + "</span>";
    var badges =
      badge("BAND", p.b) +
      badge("MODE", p.md) +
      badge("RST", rst) +
      badge("FREQ", formatFrequency(p.f)) +
      badge("DISTANCE", formatDistance(distKm)) +
      badge("BEARING", formatBearing(bear)) +
      badge("MY GRID", p.mg) +
      badge("THEIR GRID", p.tg) +
      badge("PARK", p.p, "#86efac");
    var map = buildMap(myPoint, theirPoint, mine || null, their || null);
    return {
      kicker: "QSO",
      kickerColor: "#67e8f9",
      headline: headline,
      mapHtml: map,
      badges: badges,
      footnote: formatUtc(p.ts),
      notes: p.nt || null,
      enrichmentCalls: { their: their || null, mine: mine || null },
    };
  }

  function renderCallsign(p) {
    var call = (p.c || "").toString().toUpperCase();
    var point = gridToLatLon(p.g);
    var badges =
      badge("GRID", p.g) +
      badge("DXCC", p.co) +
      badge("QTH", p.q) +
      badge("WORKED", p.wc ? p.wc + "×" : null) +
      badge("LAST BAND", p.lb) +
      badge("LAST MODE", p.lm);
    var map = point ? buildMap(null, point, null, call) : "";
    return {
      kicker: "CALLSIGN",
      kickerColor: "#fdba74",
      headline: '<span class="op-call">' + escapeHtml(call) + "</span>",
      subhead: p.nm || null,
      mapHtml: map,
      badges: badges,
      footnote: p.ph || null,
      enrichmentCalls: { their: call || null, mine: null },
    };
  }

  function renderPark(p) {
    var ref = (p.r || "").toString().toUpperCase();
    var point = (typeof p.la === "number" && typeof p.lo === "number")
      ? { lat: p.la, lon: p.lo } : null;
    var badges =
      badge("STATE", p.st) +
      badge("COUNTRY", p.co) +
      badge("ACTIVATIONS", p.ua) +
      badge("HUNTS", p.uh) +
      (p.an === true ? badge("STATUS", "ACTIVE NOW", "#86efac") : "");
    var map = point ? buildMap(null, point, null, ref) : "";
    return {
      kicker: "PARK",
      kickerColor: "#86efac",
      headline: '<span class="op-call">' + escapeHtml(ref) + "</span>",
      subhead: p.nm || null,
      mapHtml: map,
      badges: badges,
    };
  }

  function renderSummit(p) {
    var ref = (p.r || "").toString().toUpperCase();
    var point = (typeof p.la === "number" && typeof p.lo === "number")
      ? { lat: p.la, lon: p.lo } : null;
    var badges =
      badge("ALTITUDE", p.am ? p.am + " m" : null) +
      badge("POINTS", p.pt, "#fdba74") +
      badge("REGION", p.rn) +
      badge("ASSOC", p.as) +
      badge("ACTIVATIONS", p.ac) +
      badge("MY ACTIVATIONS", p.ua) +
      badge("MY CHASES", p.uc);
    var map = point ? buildMap(null, point, null, ref) : "";
    return {
      kicker: "SUMMIT",
      kickerColor: "#fdba74",
      headline: '<span class="op-call">' + escapeHtml(ref) + "</span>",
      subhead: p.nm || null,
      mapHtml: map,
      badges: badges,
    };
  }

  function renderActivation(p) {
    var ref = (p.p || "").toString().toUpperCase();
    var op = (p.me || "").toString().toUpperCase();
    var badges =
      badge("QSOs", p.qc) +
      badge("BANDS", Array.isArray(p.bs) ? p.bs.join(" ") : null) +
      badge("MODES", Array.isArray(p.ms) ? p.ms.join(" ") : null) +
      badge("P2P", p.p2p) +
      badge("DXCC", p.dx);
    return {
      kicker: "ACTIVATION",
      kickerColor: "#facc15",
      headline: '<span class="op-call">' + escapeHtml(ref) + "</span>",
      subhead: p.pn || null,
      operator: op ? "by " + op : null,
      badges: badges,
      footnote: formatUtc(p.st),
      notes: p.nt || null,
      enrichmentCalls: { their: null, mine: op || null },
    };
  }

  function renderForKind(payload) {
    if (!payload || typeof payload !== "object") return null;
    if (payload.v && payload.v > SCHEMA_VERSION) {
      return {
        kicker: "CARRIER WAVE",
        kickerColor: "#fdba74",
        headline: '<span class="op-mine">Update Carrier Wave to view this share.</span>',
        subhead: "This link uses a newer schema than this page knows about.",
      };
    }
    switch (payload.k) {
      case "qso":  return renderQso(payload);
      case "call": return renderCallsign(payload);
      case "park": return renderPark(payload);
      case "sum":  return renderSummit(payload);
      case "act":  return renderActivation(payload);
      default:     return null;
    }
  }

  // ---- assembly ----------------------------------------------------------

  function buildCard(card) {
    var html = "";
    html += '<div class="kicker" style="color:' + card.kickerColor + '">' +
            escapeHtml(card.kicker) + "</div>";
    html += '<div class="headline">' + card.headline + "</div>";
    if (card.subhead) {
      html += '<div class="subhead">' + escapeHtml(card.subhead) + "</div>";
    }
    if (card.operator) {
      html += '<div class="operator">' + escapeHtml(card.operator) + "</div>";
    }
    html += '<div class="chips" data-chips></div>';
    if (card.mapHtml) {
      html += '<div class="map-wrap">' + card.mapHtml + "</div>";
    }
    if (card.badges) {
      html += '<div class="badges">' + card.badges + "</div>";
    }
    if (card.footnote) {
      html += '<div class="footnote">' + escapeHtml(card.footnote) + "</div>";
    }
    if (card.notes) {
      html += '<div class="notes">' + escapeHtml(card.notes) + "</div>";
    }
    return html;
  }

  function loadEnrichment(card, container) {
    var calls = card.enrichmentCalls || {};
    var slot = container.querySelector("[data-chips]");
    if (!slot) return;
    var promises = [];
    if (calls.their) promises.push(
      fetchEnrichment(calls.their).then(function (r) { return chipsHtml(calls.their, r); })
    );
    if (calls.mine) promises.push(
      fetchEnrichment(calls.mine).then(function (r) { return chipsHtml(calls.mine, r); })
    );
    if (!promises.length) return;
    Promise.all(promises).then(function (parts) {
      var html = parts.filter(Boolean).join("");
      if (html) slot.innerHTML = html;
    });
  }

  function init() {
    var container = document.getElementById("card-container");
    if (!container) return;
    var payload = readFragmentPayload();
    if (!payload) return; // leave the static fallback in place
    var card = renderForKind(payload);
    if (!card) return;
    container.innerHTML = buildCard(card);
    container.classList.add("rendered");
    loadEnrichment(card, container);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
