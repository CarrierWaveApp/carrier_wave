// Glossary Tooltip Enhancement for Carrier Wave Manual

(function() {
  function init() {
    // Find all glossary terms
    const terms = document.querySelectorAll('.glossary-term');

    terms.forEach(function(term) {
      // Position tooltip to avoid overflow
      term.addEventListener('mouseenter', function() {
        const tooltip = term.querySelector('.glossary-tooltip');
        if (!tooltip) return;

        const rect = tooltip.getBoundingClientRect();
        const viewportWidth = window.innerWidth;

        // Reset position
        tooltip.style.left = '50%';
        tooltip.style.transform = 'translateX(-50%)';

        // Check if tooltip overflows right
        if (rect.right > viewportWidth - 16) {
          tooltip.style.left = 'auto';
          tooltip.style.right = '0';
          tooltip.style.transform = 'none';
        }

        // Check if tooltip overflows left
        if (rect.left < 16) {
          tooltip.style.left = '0';
          tooltip.style.right = 'auto';
          tooltip.style.transform = 'none';
        }
      });
    });
  }

  // Run init when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
