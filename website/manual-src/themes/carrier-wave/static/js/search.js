(function () {
  const input = document.getElementById('search-input');
  const resultsContainer = document.getElementById('search-results');
  if (!input || !resultsContainer) return;

  let pages = null;
  let debounceTimer = null;

  function loadIndex() {
    if (pages !== null) return Promise.resolve(pages);
    // Resolve index.json relative to the site base
    const base = document.querySelector('link[rel="icon"]')?.href?.replace(/images\/icon\.png$/, '') || '/manual/';
    return fetch(base + 'index.json')
      .then(function (r) { return r.json(); })
      .then(function (data) { pages = data; return pages; });
  }

  function highlight(text, terms) {
    if (!text) return '';
    var result = text;
    terms.forEach(function (term) {
      var re = new RegExp('(' + term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'gi');
      result = result.replace(re, '<mark>$1</mark>');
    });
    return result;
  }

  function getSnippet(content, terms) {
    var lower = content.toLowerCase();
    var bestPos = -1;
    terms.forEach(function (term) {
      var pos = lower.indexOf(term.toLowerCase());
      if (pos !== -1 && (bestPos === -1 || pos < bestPos)) bestPos = pos;
    });
    if (bestPos === -1) bestPos = 0;
    var start = Math.max(0, bestPos - 40);
    var end = Math.min(content.length, bestPos + 120);
    var snippet = (start > 0 ? '...' : '') + content.slice(start, end) + (end < content.length ? '...' : '');
    return highlight(snippet, terms);
  }

  function search(query) {
    if (!pages) return [];
    var terms = query.toLowerCase().split(/\s+/).filter(Boolean);
    if (terms.length === 0) return [];

    var scored = [];
    pages.forEach(function (page) {
      var titleLower = (page.title || '').toLowerCase();
      var descLower = (page.description || '').toLowerCase();
      var contentLower = (page.content || '').toLowerCase();
      var score = 0;

      terms.forEach(function (term) {
        if (titleLower.indexOf(term) !== -1) score += 10;
        if (descLower.indexOf(term) !== -1) score += 5;
        if (contentLower.indexOf(term) !== -1) score += 1;
      });

      if (score > 0) {
        scored.push({ page: page, score: score, terms: terms });
      }
    });

    scored.sort(function (a, b) { return b.score - a.score; });
    return scored.slice(0, 8);
  }

  function render(results) {
    if (results.length === 0) {
      resultsContainer.innerHTML = '<div class="search-no-results">No results found</div>';
      return;
    }
    var html = results.map(function (r) {
      var sectionLabel = r.page.section ? r.page.section.charAt(0).toUpperCase() + r.page.section.slice(1) : '';
      return '<a class="search-result-item" href="' + r.page.url + '">' +
        '<div class="search-result-title">' + highlight(r.page.title, r.terms) + '</div>' +
        (sectionLabel ? '<span class="search-result-section">' + sectionLabel + '</span>' : '') +
        '<div class="search-result-snippet">' + getSnippet(r.page.content, r.terms) + '</div>' +
        '</a>';
    }).join('');
    resultsContainer.innerHTML = html;
  }

  function showResults() { resultsContainer.classList.add('visible'); }
  function hideResults() { resultsContainer.classList.remove('visible'); }

  input.addEventListener('focus', function () {
    if (input.value.trim().length > 0) showResults();
  });

  input.addEventListener('input', function () {
    clearTimeout(debounceTimer);
    var query = input.value.trim();
    if (query.length < 2) {
      hideResults();
      resultsContainer.innerHTML = '';
      return;
    }
    debounceTimer = setTimeout(function () {
      loadIndex().then(function () {
        var results = search(query);
        render(results);
        showResults();
      });
    }, 150);
  });

  document.addEventListener('click', function (e) {
    if (!e.target.closest('#search-wrapper')) hideResults();
  });

  input.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      hideResults();
      input.blur();
    }
  });

  // Keyboard shortcut: / to focus search
  document.addEventListener('keydown', function (e) {
    if (e.key === '/' && !e.ctrlKey && !e.metaKey && !e.altKey) {
      var tag = (e.target.tagName || '').toLowerCase();
      if (tag === 'input' || tag === 'textarea' || e.target.isContentEditable) return;
      e.preventDefault();
      input.focus();
    }
  });
})();
