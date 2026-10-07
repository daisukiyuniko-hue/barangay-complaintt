/* ==========================================================================
   views/errors.js - shared error / not-found / forbidden panels
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var esc = App.UI.esc;

  function errorPanel(opts) {
    var icons = { 403: '&#128274;', 404: '&#128269;', 500: '&#9888;' };
    return '<section class="container section"><div class="error-panel">' +
      '<span class="error-code" aria-hidden="true">' + esc(opts.code) + '</span>' +
      '<span class="error-icon" aria-hidden="true">' + (icons[opts.code] || '&#9888;') + '</span>' +
      '<h1 class="error-heading">' + esc(opts.heading) + '</h1>' +
      '<p class="error-text">' + esc(opts.message) + '</p>' +
      '<div class="error-actions">' +
        '<a class="btn btn-primary" href="#/">Back to home page</a>' +
        '<a class="btn btn-outline" href="#/complaints">Go to reports</a>' +
      '</div>' +
    '</div></section>';
  }

  function notFound(code) {
    return {
      html: errorPanel({
        code: code || 404,
        heading: 'We could not find that page',
        message: 'The link may be old or mistyped. Try starting from the home page.'
      }),
      title: 'Page not found',
      nav: ''
    };
  }

  function forbidden() {
    return {
      html: errorPanel({
        code: 403,
        heading: 'Administrator access only',
        message: 'This page is limited to Barangay administrators. Your account is registered as a regular resident, so you can only view and manage your own reports.'
      }),
      title: 'Access denied',
      nav: ''
    };
  }

  App.Views = App.Views || {};
  App.Views.notFound = notFound;
  App.Views.forbidden = forbidden;
  App.Views.errorPage = function (opts) {
    return { html: errorPanel(opts), title: 'Error', nav: '' };
  };
})(window.App);