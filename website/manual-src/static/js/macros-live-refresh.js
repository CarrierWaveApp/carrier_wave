// Carrier Wave macros catalog — client-side live refresh + filtering.
// Behaviour:
//   1. On load, fetch GET /v1/macros from the public API and replace the
//      Hugo-rendered grid with fresh server data (no-op on network error
//      — the static fallback stays visible).
//   2. Wire up the search / radio-family / transmits-only filters to
//      hide/show cards without re-fetching.

(function () {
  'use strict';

  var API_BASE = 'https://api.carrierwave.app';
  var GRID_ID = 'macro-grid';
  var SEARCH_ID = 'macros-search';
  var RADIO_ID = 'macros-radio-filter';
  var TX_ID = 'macros-tx-filter';
  var EMPTY_ID = 'macros-empty';

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c];
    });
  }

  function renderCard(m) {
    var caps = m.capabilities || {};
    var appliesTo = (m.applies_to || []).map(esc).join(',');
    var chips = [];
    if (caps.transmits)        chips.push('<span class="chip chip-tx" title="Keys the transmitter">Transmits</span>');
    if (caps.changesFrequency) chips.push('<span class="chip">Changes frequency</span>');
    if (caps.changesMode)      chips.push('<span class="chip">Changes mode</span>');
    if (caps.changesPower)     chips.push('<span class="chip">Changes power</span>');
    if (caps.usesRawBytes)     chips.push('<span class="chip chip-warn" title="Sends raw bytes to the radio">Raw bytes</span>');

    return (
      '<article class="macro-card" data-slug="' + esc(m.slug) + '" data-name="' + esc((m.name || '').toLowerCase()) +
      '" data-applies-to="' + appliesTo + '" data-transmits="' + (caps.transmits ? 1 : 0) + '">' +
        '<header class="macro-card-head">' +
          '<h3 class="macro-card-title">' + esc(m.name) + '</h3>' +
          (m.author_callsign ? '<p class="macro-card-author">by ' + esc(m.author_callsign) + '</p>' : '') +
        '</header>' +
        (m.description ? '<p class="macro-card-desc">' + esc(m.description) + '</p>' : '') +
        '<div class="macro-chips">' + chips.join('') + '</div>' +
        '<footer class="macro-card-actions">' +
          '<a class="macro-btn" href="/m/' + esc(m.slug) + '/">View</a>' +
          '<a class="macro-btn macro-btn-primary" href="cwmacro://import?slug=' + esc(m.slug) + '" rel="nofollow">Open in Carrier Wave</a>' +
        '</footer>' +
      '</article>'
    );
  }

  function applyFilters() {
    var search = document.getElementById(SEARCH_ID);
    var radio = document.getElementById(RADIO_ID);
    var tx = document.getElementById(TX_ID);
    var empty = document.getElementById(EMPTY_ID);
    if (!search || !radio || !tx) return;

    var q = (search.value || '').trim().toLowerCase();
    var rf = radio.value;
    var txOnly = tx.checked;
    var visible = 0;

    document.querySelectorAll('.macro-card').forEach(function (card) {
      var name = card.dataset.name || '';
      var slug = (card.dataset.slug || '').toLowerCase();
      var applies = (card.dataset.appliesTo || '').toLowerCase();
      var isTx = card.dataset.transmits === '1';
      var matches =
        (!q || name.indexOf(q) !== -1 || slug.indexOf(q) !== -1) &&
        (!rf || applies.split(',').indexOf(rf) !== -1) &&
        (!txOnly || isTx);
      card.style.display = matches ? '' : 'none';
      if (matches) visible += 1;
    });

    if (empty) empty.hidden = visible !== 0;
  }

  function wireFilters() {
    ['macros-search', 'macros-radio-filter', 'macros-tx-filter'].forEach(function (id) {
      var el = document.getElementById(id);
      if (el) el.addEventListener('input', applyFilters);
    });
  }

  function refresh() {
    var grid = document.getElementById(GRID_ID);
    if (!grid) return;
    fetch(API_BASE + '/v1/macros?limit=200', { credentials: 'omit' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (payload) {
        if (!payload || !payload.entries) return;
        grid.innerHTML = payload.entries.map(renderCard).join('');
      })
      .catch(function () { /* keep static fallback */ });
  }

  document.addEventListener('DOMContentLoaded', function () {
    if (!document.getElementById(GRID_ID)) return;
    wireFilters();
    applyFilters();
    refresh();
  });
})();
