/* ==========================================================================
   app.js - bootstrap and shared page behaviours
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  function wirePasswordToggles(root) {
    (root || document).querySelectorAll('[data-password-toggle]').forEach(function (btn) {
      if (btn.dataset.wired) return;
      btn.dataset.wired = '1';
      btn.addEventListener('click', function () {
        var input = document.getElementById(btn.getAttribute('data-password-toggle'));
        if (!input) return;
        var hidden = input.type === 'password';
        input.type = hidden ? 'text' : 'password';
        btn.textContent = hidden ? 'Hide' : 'Show';
        btn.setAttribute('aria-label', hidden ? 'Hide password' : 'Show password');
      });
    });
  }

  // Note: there is deliberately no blanket "block submit if required is empty"
  // handler here. Every form in this app runs its own validator and re-renders
  // with a friendly message beside each field, which is far more useful than a
  // silent block with no explanation.

  function boot() {
    var yearEl = document.querySelector('[data-year]');
    if (yearEl) yearEl.textContent = String(new Date().getFullYear());

    App.Layout.wireShell();
    App.UI.wireModal();
    wirePasswordToggles(document);

    App.Auth.boot().then(function () {
      App.Router.start({
        afterRender: function () {
          wirePasswordToggles(document);
        }
      });

      var brand = document.getElementById('brandHost');
      if (brand) brand.hidden = false;
      var nav = document.getElementById('siteNav');
      if (nav) nav.hidden = false;

      // Land on the home page if there is no hash yet.
      if (!window.location.hash) {
        window.location.replace('#' + '/');
      }
    }).catch(function (error) {
      console.error('Failed to start', error);
      var outlet = document.getElementById('view');
      if (outlet) {
        outlet.innerHTML = '<section class="container section"><div class="error-panel">' +
          '<h1 class="error-heading">The app could not start</h1>' +
          '<p class="error-text">' + App.UI.esc(error.message || 'Unknown error') + '</p>' +
          '</div></section>';
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  App.boot = boot;
})(window.App);