/* ==========================================================================
   views/landing.js - the public landing page
   Business name, short description, services menu, images and clear calls to
   action. No login required.
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var esc = App.UI.esc;

  var STEPS = [
    { t: 'Create your free account', d: 'Register with your name, email and a password. It takes about a minute and you only do it once.' },
    { t: 'Describe your concern', d: 'Pick a category, say how urgent it is, where it is, and describe the problem in your own words.' },
    { t: 'Get a reference number', d: 'Your report is filed immediately with a reference like BCR-2026-0001 so the office can track it.' },
    { t: 'Follow it until resolved', d: 'Sign in any time to see the status and read notes from the barangay committee.' }
  ];

  var COMMITMENTS = [
    { v: 'Free',    l: 'No fee to report' },
    { v: '24h',     l: 'Target acknowledgement' },
    { v: '8',       l: 'Puroks covered' },
    { v: '0',       l: 'Forms to walk in with' }
  ];

  var FAQS = [
    { q: 'Do I need an account to report a problem?',
      a: 'Yes. Reporting requires a free resident account so the barangay can send you updates and your contact details stay protected. Creating an account takes about a minute.' },
    { q: 'Can anybody see my report?',
      a: 'Only you and, in a real deployment, authorized barangay administrators. Residents can see their own reports only; they cannot browse reports filed by their neighbours.' },
    { q: 'What happens after I submit a report?',
      a: 'You immediately receive a reference number. The status moves from Pending to In Review and finally to Resolved, and you can read notes from the committee at any time.' },
    { q: 'Can I change or withdraw my report?',
      a: 'Yes. While your report is still Pending you can edit the details or delete it completely. Once the committee starts reviewing it the record is locked so the history stays accurate.' },
    { q: 'Is my password stored safely?',
      a: 'Yes. Passwords are hashed with PBKDF2-HMAC-SHA256 using a random salt per account and are never stored in plain text.' },
    { q: 'Where is my data kept?',
      a: 'This is a static website, so everything is kept in your own browser (localStorage) on this device. Nothing is uploaded. You can export a backup file from the Data page.' },
    { q: 'What if the problem is an emergency?',
      a: 'Call your local emergency services immediately. This system is for non-emergency concerns that the barangay can act on.' }
  ];

  function landing(ctx) {
    var user = ctx.user;
    var C = App.Layout.CONFIG;

    var services = App.Store.CATEGORIES.map(function (c, i) {
      var icon = App.Store.CATEGORY_ICONS[c.value] || 'cat-other.svg';
      // These icons are a few hundred bytes each, so they are always loaded
      // eagerly. loading="lazy" was unreliable here: in a single-page app the
      // browser can defer them indefinitely and the icons never appear.
      return '<article class="service-card">' +
        '<div class="service-icon"><img src="assets/img/' + esc(icon) + '" width="44" height="44" ' +
          'alt="Icon for ' + esc(c.value) + '" decoding="async"></div>' +
        '<h3 class="service-title">' + esc(c.value) + '</h3>' +
        '<p class="service-text">' + esc(c.hint) + '</p>' +
        '<p class="service-step"><span class="service-num">' + (i + 1) + '</span></p>' +
      '</article>';
    }).join('');

    var steps = STEPS.map(function (s, i) {
      return '<li class="step-card"><span class="step-num">' + (i + 1) + '</span>' +
             '<h3 class="step-title">' + esc(s.t) + '</h3>' +
             '<p class="step-text">' + esc(s.d) + '</p></li>';
    }).join('');

    var commitments = COMMITMENTS.map(function (c) {
      return '<div class="commit-tile"><p class="commit-value">' + esc(c.v) + '</p>' +
             '<p class="commit-label">' + esc(c.l) + '</p></div>';
    }).join('');

    var faqs = FAQS.map(function (f) {
      return '<details class="faq-item">' +
        '<summary class="faq-question"><span>' + esc(f.q) + '</span>' +
        '<span class="faq-plus" aria-hidden="true"></span></summary>' +
        '<div class="faq-answer"><p>' + esc(f.a) + '</p></div></details>';
    }).join('');

    var welcomeStrip = '';
    var ctaButtons;
    var heroNote;

    if (user) {
      var firstName = String(user.name).split(' ')[0];
      ctaButtons = '<a class="btn btn-primary btn-lg" href="#/complaints/new">Report a concern</a>' +
                   '<a class="btn btn-outline btn-lg" href="#/complaints">View my reports</a>';
      heroNote = '<p class="hero-note">Signed in as <strong>' + esc(user.name) + '</strong></p>';
      welcomeStrip = '<div class="container"><div class="welcome-strip">' +
        '<span class="welcome-icon" aria-hidden="true">&#128075;</span>' +
        '<p>Welcome back, ' + esc(firstName) + '. Would you like to report a new concern today?</p>' +
        '<a class="btn btn-primary btn-sm" href="#/complaints/new">+ New report</a>' +
        '</div></div>';
    } else {
      ctaButtons = '<a class="btn btn-primary btn-lg" href="#/register">Create a free account</a>' +
                   '<a class="btn btn-outline btn-lg" href="#/login">I already have an account</a>';
      heroNote = '<p class="hero-note">Free to use &middot; Takes about a minute &middot; Available 24/7</p>';
    }

    var html =
      welcomeStrip +
      App.Layout.storageWarningHtml() +

      '<section class="hero"><div class="container hero-grid">' +
        '<div class="hero-copy">' +
          '<p class="hero-eyebrow">' + esc(C.barangay) + ' &middot; ' + esc(C.municipality) + '</p>' +
          '<h1 class="hero-title">Report a barangay concern in under a minute</h1>' +
          '<p class="hero-text">' + esc(C.description) + '</p>' +
          '<div class="hero-actions">' + ctaButtons + '</div>' +
          heroNote +
        '</div>' +
        '<div class="hero-art">' +
          '<img src="assets/img/hero-barangay.svg" width="560" height="420" ' +
            'alt="Illustration of the Barangay Hall with a resident reporting a pothole and a broken streetlight">' +
        '</div>' +
      '</div></section>' +

      '<section class="commit-strip"><div class="container commit-grid">' + commitments + '</div></section>' +

      '<section class="section" id="services"><div class="container">' +
        App.UI.sectionHeading({
          eyebrow: 'What you can report',
          heading: 'Eight kinds of community concerns we handle',
          sub: 'Choose the category that fits your situation. Each one goes to the committee responsible for that service.'
        }) +
        '<div class="service-grid">' + services + '</div>' +
        '<div class="section-cta">' +
          '<a class="btn btn-primary btn-lg" href="#/register">Start reporting now</a>' +
          '<span class="section-cta-note">No account yet? Creating one is free and instant.</span>' +
        '</div>' +
      '</div></section>' +

      '<section class="section section-alt" id="how-it-works"><div class="container">' +
        App.UI.sectionHeading({
          eyebrow: 'How it works',
          heading: 'Four simple steps from problem to resolution',
          sub: 'You do not need to visit the Barangay Hall, queue at the window, or call the office during working hours.'
        }) +
        '<ol class="steps-grid">' + steps + '</ol>' +
      '</div></section>' +

      '<section class="section"><div class="container about-grid">' +
        '<div class="about-art">' +
          '<img src="assets/img/about-community.svg" width="520" height="400" ' +
            'alt="Illustration of residents working together on a clean, safe community">' +
        '</div>' +
        '<div class="about-copy">' +
          App.UI.sectionHeading({
            eyebrow: 'Why report through this system',
            heading: 'A clearer way to get your concerns heard',
            sub: 'Paper logs get lost, damaged by rain, or filed away without a reply. This system keeps a clear, timestamped record of every single report.'
          }) +
          '<ul class="check-list">' +
            checkItem('A permanent record', 'Your report is stored with a reference number and timestamps, so nothing gets lost or forgotten.') +
            checkItem('Transparent progress', 'See the status change from Pending to Resolved, plus notes from the committee, any time you sign in.') +
            checkItem('Works on your phone', 'The whole site is built mobile-first, so you can report a hazard while standing right in front of it.') +
            checkItem('Your details stay private', 'Only you and authorized barangay administrators can open your reports.') +
            checkItem('Available 24/7', 'Report a problem at two in the morning. The office sees it first thing in the morning.') +
          '</ul>' +
        '</div>' +
      '</div></section>' +

      '<section class="section section-alt"><div class="container contact-grid">' +
        '<div>' +
          App.UI.sectionHeading({
            eyebrow: 'Prefer to talk to a person?',
            heading: 'You can always come to the Barangay Hall',
            sub: 'Online reporting is one option, not the only one. Our office hours and contact details are below.'
          }) +
          '<dl class="detail-list detail-list-card">' +
            '<div><dt>Office hours</dt><dd>' + esc(C.officeHours) + '</dd></div>' +
            '<div><dt>Hotline</dt><dd>' + esc(C.hotline) + '</dd></div>' +
            '<div><dt>Email</dt><dd>' + esc(C.email) + '</dd></div>' +
            '<div><dt>Address</dt><dd>' + esc(C.address) + '</dd></div>' +
          '</dl>' +
        '</div>' +
        '<div class="contact-card">' +
          '<h3 class="contact-title">Barangay emergency contacts</h3>' +
          '<p class="contact-note">For emergencies, do not wait for an online report.</p>' +
          '<ul class="contact-list">' +
            '<li><span>Barangay Hall</span><strong>' + esc(C.hotline) + '</strong></li>' +
            '<li><span>Police</span><strong>911</strong></li>' +
            '<li><span>Fire and Rescue</span><strong>160</strong></li>' +
            '<li><span>National Emergency Hotline</span><strong>911</strong></li>' +
          '</ul>' +
        '</div>' +
      '</div></section>' +

      '<section class="section" id="faq"><div class="container container-narrow">' +
        App.UI.sectionHeading({
          eyebrow: 'Questions',
          heading: 'Frequently asked questions',
          sub: 'Everything residents usually ask before filing their first report.'
        }) +
        '<div class="faq-list">' + faqs + '</div>' +
      '</div></section>' +

      '<section class="final-cta"><div class="container final-cta-inner">' +
        '<div>' +
          '<h2 class="final-cta-title">' + esc(C.tagline) + '</h2>' +
          '<p class="final-cta-text">Register once and keep track of every concern you report to ' + esc(C.barangay) + '.</p>' +
        '</div>' +
        '<div class="final-cta-actions">' +
          '<a class="btn btn-light btn-lg" href="#/register">Create a free account</a>' +
          '<a class="btn btn-ghost-light btn-lg" href="#/login">Sign in</a>' +
        '</div>' +
      '</div></section>';

    return { html: html, title: 'Home', nav: 'home', user: user };
  }

  function checkItem(title, text) {
    return '<li><span class="check-icon" aria-hidden="true">&#10003;</span>' +
           '<div><strong>' + esc(title) + '</strong><p>' + esc(text) + '</p></div></li>';
  }

  App.Views = App.Views || {};
  App.Views.landing = landing;
})(window.App);