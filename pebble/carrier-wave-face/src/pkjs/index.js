/* Carrier Wave Face — PebbleKit JS
 *
 * Fetches solar data from HamQSL and sends K/A/SFI/propagation to the watch.
 * Also fetches current temperature from Open-Meteo using phone geolocation.
 * Watchface-only — no bridge interaction needed.
 */

var ACTION_FETCH_SOLAR = 1;
var SOLAR_URL = 'https://www.hamqsl.com/solarxml.php';

/* C side treats a leading '-' as "no data" — always send '--', never ''. */
var NO_DATA = '--';

function send(payload, label) {
  Pebble.sendAppMessage(payload,
    function () {},
    function (err) {
      console.log('sendAppMessage failed for ' + label + ': ' + JSON.stringify(err));
    });
}

function extractTag(xml, tag) {
  var rx = new RegExp('<' + tag + '>([^<]*)</' + tag + '>', 'i');
  var m = xml.match(rx);
  var val = m ? m[1].trim() : '';
  return val === '' ? null : val;
}

function propagationRating(kIndex) {
  if (kIndex === null || isNaN(kIndex)) return null;
  if (kIndex < 2) return 'Excellent';
  if (kIndex < 3) return 'Good';
  if (kIndex < 4) return 'Fair';
  if (kIndex < 5) return 'Poor';
  return 'Very Poor';
}

function fetchSolar() {
  var req = new XMLHttpRequest();
  req.timeout = 8000;
  req.open('GET', SOLAR_URL, true);
  req.onload = function () {
    if (req.status === 200 && req.responseText) {
      var k = extractTag(req.responseText, 'kindex');
      var a = extractTag(req.responseText, 'aindex');
      var sfi = extractTag(req.responseText, 'solarflux');
      var kNum = k === null ? null : parseFloat(k);
      send({
        K_INDEX: k || NO_DATA,
        A_INDEX: a || NO_DATA,
        SOLAR_FLUX: sfi || NO_DATA,
        PROPAGATION: propagationRating(kNum) || ''
      }, 'solar');
    }
  };
  req.onerror = function () { console.log('solar fetch error'); };
  req.ontimeout = function () { console.log('solar fetch timeout'); };
  req.send();
}

function fetchWeather() {
  navigator.geolocation.getCurrentPosition(function (pos) {
    var url = 'https://api.open-meteo.com/v1/forecast' +
      '?latitude=' + pos.coords.latitude.toFixed(3) +
      '&longitude=' + pos.coords.longitude.toFixed(3) +
      '&current=temperature_2m&temperature_unit=fahrenheit';
    var req = new XMLHttpRequest();
    req.timeout = 8000;
    req.open('GET', url, true);
    req.onload = function () {
      if (req.status !== 200 || !req.responseText) return;
      try {
        var temp = JSON.parse(req.responseText).current.temperature_2m;
        if (typeof temp === 'number') {
          send({ TEMPERATURE: String(Math.round(temp)) }, 'weather');
        }
      } catch (e) {
        console.log('weather parse error: ' + e);
      }
    };
    req.onerror = function () { console.log('weather fetch error'); };
    req.ontimeout = function () { console.log('weather fetch timeout'); };
    req.send();
  }, function (err) {
    console.log('geolocation error: ' + err.message);
  }, { timeout: 10000, maximumAge: 30 * 60 * 1000 });
}

Pebble.addEventListener('ready', function () {
  console.log('CW Face JS ready');
  fetchSolar();
  fetchWeather();
});

Pebble.addEventListener('appmessage', function (event) {
  if (event.payload.ACTION === ACTION_FETCH_SOLAR) {
    fetchSolar();
    fetchWeather();
  }
});
