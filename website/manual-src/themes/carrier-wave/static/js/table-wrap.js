// Wrap content tables in a horizontally scrolling box so a wide table never
// widens the page on phones. Newer Hugo versions do this at build time via
// layouts/_default/_markup/render-table.html; this covers builds on older
// Hugo (no table render hooks) and skips tables that are already wrapped.
(function () {
  var tables = document.querySelectorAll('.content table');
  for (var i = 0; i < tables.length; i++) {
    var table = tables[i];
    var parent = table.parentNode;
    if (parent && parent.classList && parent.classList.contains('table-wrap')) continue;
    var wrap = document.createElement('div');
    wrap.className = 'table-wrap';
    parent.insertBefore(wrap, table);
    wrap.appendChild(table);
  }
})();
