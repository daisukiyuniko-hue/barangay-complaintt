/* ==========================================================================
   layout.js - the persistent shell: header, navigation and footer
   The shell is built once in index.html and only the nav + flash are updated
   on route changes.
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var CONFIG = {
    siteName: 'Barangay Complaint & Concern Reporting System',
    barangay: 'Barangay San Isidro',
    municipality: 'City of Antipolo',
    tagline: 'Your voice, our action. Report a concern in under a minute.',
    description: 'The official online complaint and concern reporting system of Barangay San Isidro. Report potholes, broken streetlights, water interruptions, waste buildup, noise disturbances and other community concerns online, then track every report from Pending to Resolved without visiting the Barangay Hall.',
    officeHours: 'Monday - Friday, 8:00 AM - 5:00 PM',
    hotline: '+63 900 000 0000',
    email: 'barangay.sanisidro@example.gov.ph',
    address: 'Barangay Hall, Purok 3, San Isidro, Antipolo City',
    pageSize: 8
  };

  var pendingFlash = null;

  function renderNav(active, user) {
    var host = document.getElementById('siteNav');
    var brandHost = document.getElementById('brandHost');
    var footerLinks = document.getElementById('footerLinks');
    if (!host) return;

    var esc = App.UI.esc;
    var html = '';

    if (!user) {
      html += '<div class="nav-links">' +
        navLink('/', 'Home', active === 'home') +
        navLink('/#services', 'Services', active === 'services') +
        navLink('/#how-it-works', 'How It Works', active === 'how') +
        navLink('/#faq', 'FAQ', active === 'faq') +
        '</div>' +
        '<div class="nav-actions">' +
        '<a class="btn btn-ghost" href="#/login">Sign in</a>' +
        '<a class="btn btn-primary" href="#/register">Create account</a>' +
        '</div>';
    } else {
      var isAdmin = App.Store.isAdmin(user);
      html += '<div class="nav-links">' +
        navLink('/dashboard', 'Dashboard', active === 'dashboard') +
        navLink('/complaints', isAdmin ? 'All Reports' : 'My Reports', active === 'complaints') +
        (isAdmin ? navLink('/users', 'Residents', active === 'users') : '') +
        navLink('/complaints/new', 'New Report', active === 'new') +
        '</div>' +
        '<div class="nav-actions">' +
        App.UI.userChip(user) +
        '<a class="btn btn-ghost btn-sm" href="#/data" data-nav="data">Data</a>' +
        '<button class="btn btn-ghost btn-sm" type="button" data-signout>Sign out</button>' +
        '</div>';
    }

    host.innerHTML = html;
    host.hidden = false;

    var signout = host.querySelector('[data-signout]');
    if (signout) {
      signout.addEventListener('click', function () {
        App.Auth.logout();
        pendingFlash = { message: 'You have been signed out. Thank you.', type: 'success' };
        App.Router.go('/');
      });
    }

    if (brandHost) {
      brandHost.innerHTML = '<img class="brand-mark" src="assets/img/logo.svg" width="44" height="44" alt="">' +
        '<span class="brand-text"><strong>' + esc(CONFIG.barangay) + '</strong>' +
        '<small>Complaint &amp; Concern Reporting</small></span>';
    }

    if (footerLinks) {
      footerLinks.innerHTML =
        '<li><a href="#/complaints/new">Submit a report</a></li>' +
        '<li><a href="#/complaints">Track a report</a></li>';
    }
  }

  function navLink(hash, label, active) {
    return '<a href="#' + App.UI.esc(hash) + '"' + (active ? ' class="is-active"' : '') + '>' +
           App.UI.esc(label) + '</a>';
  }

  function renderFlash(flash) {
    var host = document.getElementById('flashHost');
    if (!host) return;
    var data = flash || pendingFlash;
    pendingFlash = null;
    host.innerHTML = data ? App.UI.flashHtml(data.message, data.type) : '';
  }

  /** Queues a message for the next page render (e.g. after a successful save). */
  function setFlash(message, type) {
    pendingFlash = { message: message, type: type || 'success' };
  }

  function toggleMobileNav(force) {
    var panel = document.getElementById('siteNav');
    var toggle = document.querySelector('[data-nav-toggle]');
    if (!panel || !toggle) return;
    var open = typeof force === 'boolean' ? force : !panel.classList.contains('is-open');
    panel.classList.toggle('is-open', open);
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
  }

  function closeMobileNav() { toggleMobileNav(false); }

  function wireShell() {
    var toggle = document.querySelector('[data-nav-toggle]');
    if (toggle) {
      toggle.addEventListener('click', function () {
        toggleMobileNav();
      });
    }

    document.addEventListener('click', function (e) {
      var panel = document.getElementById('siteNav');
      if (!panel || !panel.classList.contains('is-open')) return;
      if (panel.contains(e.target) || (toggle && toggle.contains(e.target))) return;
      toggleMobileNav(false);
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') toggleMobileNav(false);
    });

    // Flash dismissal
    document.addEventListener('click', function (e) {
      var btn = e.target.closest ? e.target.closest('[data-dismiss-flash]') : null;
      if (btn && btn.parentNode) btn.parentNode.removeChild(btn);
    });

    // Delegated confirmations: any link/button with data-confirm asks first.
    document.addEventListener('click', function (e) {
      var el = e.target.closest ? e.target.closest('[data-confirm]') : null;
      if (!el) return;
      var message = el.getAttribute('data-confirm');
      if (!window.confirm(message)) {
        e.preventDefault();
        e.stopPropagation();
      }
    });
  }

  /** Storage warning shown on data-heavy pages when localStorage is blocked. */
  function storageWarningHtml() {
    if (App.Store.isAvailable()) return '';
    return '<div class="storage-note"><strong>Your browser is blocking storage.</strong>' +
      'This app keeps its data in the browser, so nothing can be saved. Turn off private ' +
      'browsing or allow site data, then reload.</div>';
  }

  /** Shown on the Data page so the localStorage trade-off is never hidden. */
  function localOnlyNoteHtml() {
    return '<div class="storage-note">' +
      '<strong>This is a static website, so the data lives in this browser only.</strong>' +
      'Reports are saved in localStorage on this device - they are not uploaded to a server, ' +
      'they are not shared with anyone, and clearing your browsing data will remove them. ' +
      'Use the Export button below to download a backup you can load again later.' +
      '</div>';
  }

  App.Layout = {
    CONFIG: CONFIG,
    renderNav: renderNav,
    renderFlash: renderFlash,
    setFlash: setFlash,
    wireShell: wireShell,
    toggleMobileNav: toggleMobileNav,
    closeMobileNav: closeMobileNav,
    storageWarningHtml: storageWarningHtml,
    localOnlyNoteHtml: localOnlyNoteHtml
  };
})(window.App);