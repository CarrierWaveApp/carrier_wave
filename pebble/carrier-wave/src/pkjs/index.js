/* Carrier Wave for Pebble — PebbleKit JS shim.
 *
 * Runs inside the Pebble phone app on iOS. Routes AppMessage actions from the
 * watch to either public APIs (HamQSL, POTA) or to the Carrier Wave: Field
 * loopback bridge running on the same iPhone.
 *
 * Mirrors swift/watch/Services/WatchNetworkService.swift — keep the parsing
 * logic in sync if Field's bridge response shape changes.
 */

var ACTION_FETCH_SOLAR = 1;
var ACTION_FETCH_SPOTS = 2;
var ACTION_FETCH_SESSION = 3;
var ACTION_LOG_QSO = 4;
var ACTION_FETCH_MEMORIES = 5;
var ACTION_RECALL_MEMORY = 6;

var STATUS_OK = 0;
var STATUS_NETWORK_ERROR = 2;
var STATUS_BRIDGE_ERROR = 3;
var STATUS_NO_SESSION = 4;

var DEFAULT_BRIDGE_URL = 'http://127.0.0.1:47373';
var BRIDGE_TIMEOUT_MS = 4000;
var SOLAR_URL = 'https://www.hamqsl.com/solarxml.php';
var POTA_SPOTS_URL = 'https://api.pota.app/spot/activator';
var SPOT_LIMIT = 20;

function bridgeURL() {
  return localStorage.getItem('bridgeURL') || DEFAULT_BRIDGE_URL;
}

function send(payload, label) {
  Pebble.sendAppMessage(payload,
    function () {},
    function (err) {
      console.log('sendAppMessage failed for ' + label + ': ' + JSON.stringify(err));
    });
}

function sendStatus(status, errorText) {
  var payload = { STATUS: status };
  if (errorText) {
    payload.ERROR_TEXT = errorText;
  }
  send(payload, 'status');
}

// --- Solar -----------------------------------------------------------------

function extractTag(xml, tag) {
  var rx = new RegExp('<' + tag + '>([^<]*)</' + tag + '>', 'i');
  var m = xml.match(rx);
  return m ? m[1].trim() : null;
}

function propagationRating(kIndex) {
  if (kIndex === null || isNaN(kIndex)) return null;
  if (kIndex < 2) return 'Excellent';
  if (kIndex < 3) return 'Good';
  if (kIndex < 4) return 'Fair';
  if (kIndex < 5) return 'Poor';
  return 'Very Poor';
}

function parseSolar(xml) {
  var k = extractTag(xml, 'kindex');
  var a = extractTag(xml, 'aindex');
  var sfi = extractTag(xml, 'solarflux');
  var sun = extractTag(xml, 'sunspots');
  var kNum = k === null ? null : parseFloat(k);
  return {
    K_INDEX: k || '',
    A_INDEX: a || '',
    SOLAR_FLUX: sfi || '',
    SUNSPOTS: sun || '',
    PROPAGATION: propagationRating(kNum) || ''
  };
}

function fetchSolar() {
  var req = new XMLHttpRequest();
  req.timeout = BRIDGE_TIMEOUT_MS;
  req.open('GET', SOLAR_URL, true);
  req.onload = function () {
    if (req.status === 200 && req.responseText) {
      send(parseSolar(req.responseText), 'solar');
    } else {
      sendStatus(STATUS_NETWORK_ERROR, 'HamQSL ' + req.status);
    }
  };
  req.onerror = function () { sendStatus(STATUS_NETWORK_ERROR, 'solar net'); };
  req.ontimeout = function () { sendStatus(STATUS_NETWORK_ERROR, 'solar timeout'); };
  req.send();
}

// --- Spots -----------------------------------------------------------------

function bandFromMHz(mhz) {
  if (mhz >= 1.8 && mhz < 2.0) return '160m';
  if (mhz >= 3.5 && mhz < 4.0) return '80m';
  if (mhz >= 5.3 && mhz < 5.5) return '60m';
  if (mhz >= 7.0 && mhz < 7.3) return '40m';
  if (mhz >= 10.1 && mhz < 10.15) return '30m';
  if (mhz >= 14.0 && mhz < 14.35) return '20m';
  if (mhz >= 18.068 && mhz < 18.168) return '17m';
  if (mhz >= 21.0 && mhz < 21.45) return '15m';
  if (mhz >= 24.89 && mhz < 24.99) return '12m';
  if (mhz >= 28.0 && mhz < 29.7) return '10m';
  if (mhz >= 50.0 && mhz < 54.0) return '6m';
  if (mhz >= 144.0 && mhz < 148.0) return '2m';
  if (mhz >= 420.0 && mhz < 450.0) return '70cm';
  return Math.round(mhz) + 'M';
}

function formatFreq(mhz) {
  return mhz.toFixed(3);
}

function sendSpots(spots) {
  var n = Math.min(spots.length, SPOT_LIMIT);
  send({ SPOT_COUNT: n }, 'spot_count');
  for (var idx = 0; idx < n; idx++) {
    var spot = spots[idx];
    var freqKHz = parseFloat(spot.frequency);
    var freqMHz = isNaN(freqKHz) ? 0 : freqKHz / 1000;
    var payload = {
      SPOT_INDEX: idx,
      SPOT_CALLSIGN: spot.activator || '',
      SPOT_FREQ_MHZ: formatFreq(freqMHz),
      SPOT_MODE: spot.mode || '',
      SPOT_BAND: bandFromMHz(freqMHz),
      SPOT_PARK_REF: spot.reference || '',
      // The rebuilt POTA API (Oct 2026) leaves parkName null; the name is in `name`.
      SPOT_PARK_NAME: spot.parkName || spot.name || ''
    };
    send(payload, 'spot');
  }
}

function fetchSpots() {
  var req = new XMLHttpRequest();
  req.timeout = BRIDGE_TIMEOUT_MS;
  req.open('GET', POTA_SPOTS_URL, true);
  req.onload = function () {
    if (req.status !== 200) {
      sendStatus(STATUS_NETWORK_ERROR, 'POTA ' + req.status);
      return;
    }
    try {
      var spots = JSON.parse(req.responseText);
      sendSpots(spots);
    } catch (err) {
      sendStatus(STATUS_NETWORK_ERROR, 'POTA parse');
    }
  };
  req.onerror = function () { sendStatus(STATUS_NETWORK_ERROR, 'POTA net'); };
  req.ontimeout = function () { sendStatus(STATUS_NETWORK_ERROR, 'POTA timeout'); };
  req.send();
}

// --- Bridge: session + log QSO --------------------------------------------

function callBridge(method, path, body, onJSON, onError) {
  var url = bridgeURL() + path;
  var req = new XMLHttpRequest();
  req.timeout = BRIDGE_TIMEOUT_MS;
  req.open(method, url, true);
  if (body) {
    req.setRequestHeader('Content-Type', 'application/json');
  }
  req.onload = function () {
    if (req.status >= 200 && req.status < 300) {
      try {
        onJSON(req.responseText ? JSON.parse(req.responseText) : {});
      } catch (err) {
        onError('bridge parse');
      }
    } else if (req.status === 404) {
      onError('no session', STATUS_NO_SESSION);
    } else {
      onError('bridge ' + req.status);
    }
  };
  req.onerror = function () { onError('bridge offline'); };
  req.ontimeout = function () { onError('bridge timeout'); };
  req.send(body || null);
}

function sendSession(snapshot) {
  if (!snapshot || snapshot.isActive === false) {
    send({ SESSION_ACTIVE: 0 }, 'session_idle');
    return;
  }
  send({
    SESSION_ACTIVE: 1,
    SESSION_PARK_REF: snapshot.parkReference || '',
    SESSION_PARK_NAME: snapshot.parkName || '',
    SESSION_FREQ: snapshot.frequency || '',
    SESSION_MODE: snapshot.mode || '',
    SESSION_QSO_COUNT: snapshot.qsoCount || 0,
    SESSION_LAST_CALL: snapshot.lastCallsign || '',
    SESSION_STARTED_AT: snapshot.startedAt || ''
  }, 'session');
}

function fetchSession() {
  callBridge('GET', '/v1/session', null,
    function (json) { sendSession(json); },
    function (msg, status) {
      sendStatus(status || STATUS_BRIDGE_ERROR, msg);
      send({ SESSION_ACTIVE: 0 }, 'session_idle');
    });
}

function logQSO() {
  var body = JSON.stringify({ rstSent: '599', rstReceived: '599' });
  callBridge('POST', '/v1/qso', body,
    function (json) {
      sendStatus(STATUS_OK);
      if (json && json.session) {
        sendSession(json.session);
      } else {
        fetchSession();
      }
    },
    function (msg, status) { sendStatus(status || STATUS_BRIDGE_ERROR, msg); });
}

// --- Memories ----------------------------------------------------------------

function fetchMemories() {
  callBridge('GET', '/v1/memories', null,
    function (json) {
      if (!Array.isArray(json) || json.length === 0) {
        send({ MEMORY_COUNT: 0 }, 'memory_count');
        return;
      }
      send({ MEMORY_COUNT: json.length }, 'memory_count');
      for (var idx = 0; idx < json.length; idx++) {
        var mem = json[idx];
        send({
          MEMORY_INDEX: idx,
          MEMORY_ID: mem.id,
          MEMORY_NAME: mem.label || '',
          MEMORY_FREQ: mem.text || ''
        }, 'memory');
      }
    },
    function (msg) {
      sendStatus(STATUS_BRIDGE_ERROR, msg);
      send({ MEMORY_COUNT: 0 }, 'memory_count');
    });
}

function recallMemory(memoryId) {
  var body = JSON.stringify({ id: memoryId });
  callBridge('POST', '/v1/memories/recall', body,
    function () { sendStatus(STATUS_OK); },
    function (msg) { sendStatus(STATUS_BRIDGE_ERROR, msg); });
}

// --- Dispatch --------------------------------------------------------------

Pebble.addEventListener('ready', function () {
  console.log('Carrier Wave Pebble JS ready');
});

Pebble.addEventListener('appmessage', function (event) {
  var action = event.payload.ACTION;
  switch (action) {
    case ACTION_FETCH_SOLAR: fetchSolar(); break;
    case ACTION_FETCH_SPOTS: fetchSpots(); break;
    case ACTION_FETCH_SESSION: fetchSession(); break;
    case ACTION_LOG_QSO: logQSO(); break;
    case ACTION_FETCH_MEMORIES: fetchMemories(); break;
    case ACTION_RECALL_MEMORY:
      var memId = event.payload.MEMORY_RECALL_ID;
      if (memId !== undefined) recallMemory(memId);
      break;
    default: console.log('Unknown action: ' + action);
  }
});

Pebble.addEventListener('showConfiguration', function () {
  var url = 'https://carrierwave.app/pebble/config?v=1' +
            '&bridge=' + encodeURIComponent(bridgeURL());
  Pebble.openURL(url);
});

Pebble.addEventListener('webviewclosed', function (event) {
  if (!event || !event.response) return;
  try {
    var cfg = JSON.parse(decodeURIComponent(event.response));
    if (cfg.bridgeURL) {
      localStorage.setItem('bridgeURL', cfg.bridgeURL);
    }
  } catch (err) {
    console.log('config parse: ' + err);
  }
});
