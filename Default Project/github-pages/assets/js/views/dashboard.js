/* ==========================================================================
   views/dashboard.js - the signed-in landing page
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var esc = App.UI.esc;

  function dashboard(ctx) {
    var user = ctx.user;
    var isAdmin = App.Store.isAdmin(user);
    var stats = App.Store.statsFor(isAdmin ? '' : user.id);

    var heading = isAdmin
      ? 'Administrator dashboard'
      : 'Welcome back, ' + String(user.name).split(' ')[0];
    var sub = isAdmin
      ? 'Verify incoming reports, update their status and keep a clear record of every action taken.'
      : 'Here is everything you have reported so far, newest first.';

    var visible = App.Store.visibleComplaints(user);
    var recent = visible.slice().sort(function (a, b) {
      return String(b.createdAt).localeCompare(String(a.createdAt));
    }).slice(0, 5);

    var recentHtml = recent.map(function (c) {
      return App.UI.complaintRow(c, user, { compact: true });
    }).join('');

    if (!recent.length) {
      recentHtml = isAdmin
        ? App.UI.emptyState({
            icon: '&#128203;',
            title: 'No reports have been filed yet',
            message: 'As soon as a resident submits a report it will appear here for verification and action.',
            action: '<a class="btn btn-primary" href="#/complaints/new">File a report</a>'
          })
        : App.UI.emptyState({
            icon: '&#128221;',
            title: 'You have not filed any reports yet',
            message: 'Spotted a pothole, a broken streetlight or a pile of garbage? Tell the barangay about it in under a minute.',
            action: '<a class="btn btn-primary" href="#/complaints/new">Report a concern</a>'
          });
    }

    var side = '';
    if (isAdmin) {
      var allUsers = App.Store.allUsers();
      side += '<div class="card">' +
        '<div class="card-head"><h2 class="card-title">Community overview</h2></div>' +
        '<dl class="detail-list">' +
          '<div><dt>Registered accounts</dt><dd>' + allUsers.length + '</dd></div>' +
          '<div><dt>Administrators</dt><dd>' +
            allUsers.filter(function (u) { return u.role === 'admin'; }).length + '</dd></div>' +
          '<div><dt>Reports on record</dt><dd>' + stats.total + '</dd></div>' +
          '<div><dt>Resolved</dt><dd>' + stats.resolved + '</dd></div>' +
          '<div><dt>Awaiting action</dt><dd>' + (stats.pending + stats.inReview) + '</dd></div>' +
        '</dl>' +
        '<a class="btn btn-outline btn-block" href="#/users">Manage resident accounts</a>' +
      '</div>';

      var urgent = visible.filter(function (c) {
        return (c.priority === 'Urgent' || c.priority === 'High') && c.status !== 'Resolved';
      }).sort(function (a, b) { return String(b.createdAt).localeCompare(String(a.createdAt)); });

      var urgentHtml = urgent.length
        ? urgent.slice(0, 4).map(function (c) {
            return '<li class="urgent-item"><a href="#/complaints/' + encodeURIComponent(c.id) + '">' +
              App.UI.badge(c.priority, App.UI.priorityTone(c.priority)) +
              '<span class="urgent-title">' + esc(c.title) + '</span>' +
              App.UI.badge(c.status, App.UI.statusTone(c.status)) +
              '</a></li>';
          }).join('')
        : '<li class="urgent-empty">No high or urgent reports are waiting.</li>';

      side += '<div class="card">' +
        '<div class="card-head"><h2 class="card-title">Needs attention</h2></div>' +
        '<ul class="urgent-list">' + urgentHtml + '</ul></div>';

      // Category breakdown bar chart
      if (visible.length) {
        var groups = {};
        visible.forEach(function (c) { groups[c.category] = (groups[c.category] || 0) + 1; });
        var max = 1;
        Object.keys(groups).forEach(function (k) { if (groups[k] > max) max = groups[k]; });
        var sorted = Object.keys(groups).sort(function (a, b) { return groups[b] - groups[a]; });
        var bars = sorted.map(function (k) {
          var pct = Math.round((groups[k] / max) * 100);
          return '<li class="bar-item"><span class="bar-label">' + esc(k) + '</span>' +
                 '<span class="bar-value">' + groups[k] + '</span>' +
                 '<span class="bar-track"><span class="bar-fill" style="width:' + pct + '%"></span></span></li>';
        }).join('');
        side += '<div class="card"><div class="card-head"><h2 class="card-title">Reports by category</h2></div>' +
                '<ul class="bar-list">' + bars + '</ul></div>';
      }
    } else {
      side += '<div class="card card-quiet">' +
        '<div class="card-head"><h2 class="card-title">Your status at a glance</h2></div>' +
        '<dl class="detail-list">' +
          '<div><dt>Reports filed</dt><dd>' + stats.total + '</dd></div>' +
          '<div><dt>Pending</dt><dd>' + stats.pending + '</dd></div>' +
          '<div><dt>In review</dt><dd>' + stats.inReview + '</dd></div>' +
          '<div><dt>Resolved</dt><dd>' + stats.resolved + '</dd></div>' +
        '</dl>' +
        '<a class="btn btn-primary btn-block" href="#/complaints/new">+ Report a new concern</a>' +
      '</div>';

      var C = App.Layout.CONFIG;
      side += '<div class="card card-quiet">' +
        '<div class="card-head"><h2 class="card-title">Barangay office</h2></div>' +
        '<p class="card-text">Hotline: ' + esc(C.hotline) + '</p>' +
        '<p class="card-text">' + esc(C.officeHours) + '</p>' +
        '<p class="card-text">' + esc(C.address) + '</p>' +
      '</div>';
    }

    var listLink = isAdmin
      ? '<a class="btn btn-outline" href="#/complaints">See all reports</a>'
      : '<a class="btn btn-outline" href="#/complaints">See all my reports</a>';

    var html = '<section class="container section">' +
      App.UI.pageIntro({
        eyebrow: 'Dashboard',
        heading: heading,
        sub: sub,
        actions: '<a class="btn btn-primary" href="#/complaints/new">+ New report</a>' + listLink
      }) +
      App.Layout.storageWarningHtml() +
      '<div class="stat-grid stat-grid-4">' +
        App.UI.statTile('Total reports', stats.total, 'brand', 'On record') +
        App.UI.statTile('Pending', stats.pending, 'warning', 'Awaiting first response') +
        App.UI.statTile('In review', stats.inReview, 'info', 'Being worked on now') +
        App.UI.statTile('Resolved', stats.resolved, 'success', 'Completed and closed') +
      '</div>' +
      '<div class="dashboard-grid">' +
        '<section class="dash-main">' +
          '<div class="section-head"><div>' +
            '<p class="section-eyebrow">Activity</p>' +
            '<h2 class="section-title section-title-sm">' +
              (isAdmin ? 'Latest reports from residents' : 'Your latest reports') + '</h2>' +
          '</div>' + listLink + '</div>' +
          '<div class="row-list">' + recentHtml + '</div>' +
        '</section>' +
        '<aside class="side-stack">' + side + '</aside>' +
      '</div>' +
    '</section>';

    return { html: html, title: 'Dashboard', nav: 'dashboard', user: user };
  }

  App.Views = App.Views || {};
  App.Views.dashboard = dashboard;
})(window.App);