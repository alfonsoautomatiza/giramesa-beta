// Simple i18n loader for Giramesa landing page
(function initI18n() {
  const DEFAULT_LANG = 'es';
  const SUPPORTED_LANGS = ['es', 'en'];

  // Get current language preference
  function getCurrentLang() {
    const saved = localStorage.getItem('giramesa-lang');
    if (saved && SUPPORTED_LANGS.includes(saved)) return saved;

    const browserLang = navigator.language.split('-')[0];
    const lang = SUPPORTED_LANGS.includes(browserLang) ? browserLang : DEFAULT_LANG;
    localStorage.setItem('giramesa-lang', lang);
    return lang;
  }

  // Apply language to UI
  function applyLanguage(lang) {
    document.documentElement.lang = lang;
    document.documentElement.dataset.lang = lang;
    localStorage.setItem('giramesa-lang', lang);

    // Update language switcher button
    const btn = document.querySelector('.lang-switch-btn');
    if (btn) {
      btn.textContent = lang === 'es' ? 'EN' : 'ES';
    }
  }

  // Initialize on page load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      const lang = getCurrentLang();
      applyLanguage(lang);
    });
  } else {
    const lang = getCurrentLang();
    applyLanguage(lang);
  }

  // Expose language switcher globally
  window.switchLanguage = function(lang) {
    if (!SUPPORTED_LANGS.includes(lang)) return;
    applyLanguage(lang);
    // Reload to apply translations
    window.location.reload();
  };
})();
