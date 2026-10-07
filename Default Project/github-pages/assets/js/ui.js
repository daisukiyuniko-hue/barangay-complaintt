/* ==========================================================================
   ui.js - escaping, formatting and reusable HTML components
   --------------------------------------------------------------------------
   Everything user supplied goes through esc() before it reaches innerHTML,
   which is what stops a report titled <script>...</script> from executing.
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  // ---------------------------------------------------------------- escape --
  var ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

  function esc(value) {
    if (value === null || value === undefined) return '';
    return String(value).replace(/[&<>"']/g, function (ch) { return ESCAPES[ch]; });
  }

  /** Escapes a value for use inside a URL query or path segment. */
  function escAttr(value) { return esc(value); }

  // -------------------------------------------------------------- formatting --
  function formatDate(iso, withTime) {
    if (!iso) return '-';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '-';
    var opts = { day: '2-digit', month: 'short', year: 'numeric' };
    if (withTime) { opts.hour = '2-digit'; opts.minute = '2-digit'; opts.hour12 = true; }
    try { return d.toLocaleDateString('en-GB', opts); }
    catch (e) { return d.toISOString().slice(0, 10); }
  }

  function formatDateLong(iso) {
    if (!iso) return '-';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '-';
    try { return d.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }); }
    catch (e) { return d.toISOString().slice(0, 10); }
  }

  function relativeTime(iso) {
    if (!iso) return '';
    var diff = Date.now() - new Date(iso).getTime();
    var mins = Math.floor(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return mins + ' min ago';
    var hours = Math.floor(mins / 60);
    if (hours < 24) return hours + ' hour' + (hours === 1 ? '' : 's') + ' ago';
    var days = Math.floor(hours / 24);
    if (days < 30) return days + ' day' + (days === 1 ? '' : 's') + ' ago';
    return formatDate(iso);
  }

  function truncate(text, limit) {
    var value = String(text || '');
    return value.length > limit ? value.slice(0, limit).replace(/\s+$/, '') + '…' : value;
  }

  function priorityTone(priority) {
    switch (priority) {
      case 'Urgent': return 'danger';
      case 'High': return 'warning';
      case 'Medium': return 'info';
      default: return 'neutral';
    }
  }

  function statusTone(status) {
    switch (status) {
      case 'Resolved': return 'success';
      case 'In Review': return 'info';
      case 'Rejected': return 'muted';
      default: return 'warning';
    }
  }

  // ------------------------------------------------------------- components --
  function badge(text, tone) {
    return '<span class="badge badge-' + esc(tone) + '">' + esc(text) + '</span>';
  }

  function rolePill(role) {
    var admin = role === 'admin';
    return '<span class="role-pill ' + (admin ? 'role-admin' : 'role-resident') + '">' +
           (admin ? 'Administrator' : 'Resident') + '</span>';
  }

  function avatar(user) {
    if (!user) return '';
    var tone = App.Store.isAdmin(user) ? 'avatar-admin' : 'avatar-resident';
    return '<span class="avatar ' + tone + '">' + esc(App.Auth.initials(user.name)) + '</span>';
  }

  function userChip(user) {
    if (!user) return '';
    return '<div class="user-chip">' + avatar(user) +
           '<span class="user-chip-text"><strong>' + esc(user.name) + '</strong>' +
           rolePill(user.role) + '</span></div>';
  }

  function pageIntro(opts) {
    var html = '<div class="page-intro">';
    if (opts.eyebrow) html += '<p class="page-eyebrow">' + esc(opts.eyebrow) + '</p>';
    html += '<h1 class="page-title">' + esc(opts.heading) + '</h1>';
    if (opts.sub) html += '<p class="page-sub">' + esc(opts.sub) + '</p>';
    if (opts.actions) html += '<div class="page-actions">' + opts.actions + '</div>';
    return html + '</div>';
  }

  function sectionHeading(opts) {
    var html = '<div class="section-head">';
    if (opts.eyebrow) html += '<p class="section-eyebrow">' + esc(opts.eyebrow) + '</p>';
    html += '<h2 class="section-title">' + esc(opts.heading) + '</h2>';
    if (opts.sub) html += '<p class="section-sub">' + esc(opts.sub) + '</p>';
    return html + '</div>';
  }

  function statTile(label, value, tone, hint) {
    var html = '<div class="stat-tile stat-' + esc(tone || 'brand') + '">' +
               '<p class="stat-value">' + esc(value) + '</p>' +
               '<p class="stat-label">' + esc(label) + '</p>';
    if (hint) html += '<p class="stat-hint">' + esc(hint) + '</p>';
    return html + '</div>';
  }

  function flashHtml(message, tone) {
    if (!message) return '';
    var icons = { success: '&#10003;', error: '&#33;', warning: '&#9888;', info: '&#8505;' };
    var icon = icons[tone] || icons.info;
    var dismiss = tone === 'success'
      ? '<button class="flash-close" type="button" data-dismiss-flash aria-label="Dismiss">&times;</button>' : '';
    return '<div class="flash flash-' + esc(tone) + '" role="status" data-flash>' +
           '<span class="flash-icon" aria-hidden="true">' + icon + '</span>' +
           '<p class="flash-text">' + esc(message) + '</p>' + dismiss + '</div>';
  }

  function errorSummary(errors) {
    var keys = Object.keys(errors || {});
    if (!keys.length) return '';
    var items = keys.map(function (k) { return '<li>' + esc(errors[k]) + '</li>'; }).join('');
    return '<div class="alert alert-error" role="alert">' +
           '<span class="alert-icon" aria-hidden="true">&#9888;</span><div>' +
           '<strong>Please fix the following before continuing:</strong>' +
           '<ul class="alert-list">' + items + '</ul></div></div>';
  }

  function fieldError(errors, field) {
    if (!errors || !errors[field]) return '';
    return '<p class="field-error" data-field-error="' + esc(field) + '">' + esc(errors[field]) + '</p>';
  }

  function invalidClass(errors, field) {
    return (errors && errors[field]) ? ' is-invalid' : '';
  }

  function emptyState(opts) {
    var action = opts.action ? '<div class="empty-action">' + opts.action + '</div>' : '';
    return '<div class="empty-state"><span class="empty-icon" aria-hidden="true">' +
           (opts.icon || '&#128196;') + '</span>' +
           '<h3 class="empty-title">' + esc(opts.title) + '</h3>' +
           '<p class="empty-text">' + esc(opts.message) + '</p>' + action + '</div>';
  }

  function selectOptions(items, selected, placeholder) {
    var html = placeholder ? '<option value="">' + esc(placeholder) + '</option>' : '';
    items.forEach(function (item) {
      var isSel = String(item.value) === String(selected) ? ' selected' : '';
      html += '<option value="' + esc(item.value) + '"' + isSel + '>' + esc(item.value) + '</option>';
    });
    return html;
  }

  function complaintRow(complaint, viewer, opts) {
    opts = opts || {};
    var isAdmin = App.Store.isAdmin(viewer);
    var pTone = priorityTone(complaint.priority);
    var sTone = statusTone(complaint.status);
    var path = '#/complaints/' + encodeURIComponent(complaint.id);

    var meta = [
      '<span class="meta-item"><span class="meta-label">Reference</span> ' + esc(complaint.referenceNo) + '</span>',
      '<span class="meta-item"><span class="meta-label">Category</span> ' + esc(complaint.category) + '</span>',
      '<span class="meta-item"><span class="meta-label">Location</span> ' + esc(complaint.location) + '</span>',
      '<span class="meta-item"><span class="meta-label">Reported</span> ' + esc(formatDate(complaint.createdAt)) + '</span>'
    ];
    if (isAdmin) {
      meta.push('<span class="meta-item"><span class="meta-label">Reported by</span> ' + esc(complaint.reporterName) + '</span>');
    }

    var descHtml = opts.compact ? '' :
      '<p class="row-desc">' + esc(truncate(complaint.description, 190)) + '</p>';

    var noteHtml = '';
    if (isAdmin && complaint.adminNotes) {
      noteHtml = '<p class="row-note"><span class="meta-label">Admin note</span> ' +
                 esc(truncate(complaint.adminNotes, 120)) + '</p>';
    }

    return '<article class="row-card" data-priority="' + esc(pTone) + '">' +
      '<div class="row-main">' +
        '<div class="row-badges">' + badge(complaint.priority, pTone) + badge(complaint.status, sTone) + '</div>' +
        '<h3 class="row-title"><a href="' + path + '">' + esc(complaint.title) + '</a></h3>' +
        '<div class="row-meta">' + meta.join('') + '</div>' +
        descHtml + noteHtml +
      '</div>' +
      '<div class="row-side"><a class="btn btn-outline btn-sm" href="' + path + '">View details</a></div>' +
    '</article>';
  }

  function timelineHtml(complaint) {
    var steps = [
      { name: 'Pending', hint: 'Report received' },
      { name: 'In Review', hint: 'Being validated by the committee' },
      { name: 'Resolved', hint: 'Action completed' }
    ];
    var index = 2;
    if (complaint.status === 'Pending') index = 0;
    else if (complaint.status === 'In Review') index = 1;
    else if (complaint.status === 'Rejected') index = 1;

    var items = steps.map(function (step, i) {
      var state = i < index ? 'done' : (i === index ? 'current' : 'pending');
      return '<li class="step step-' + state + '"><span class="step-dot" aria-hidden="true"></span>' +
             '<span class="step-body"><strong>' + esc(step.name) + '</strong>' +
             '<small>' + esc(step.hint) + '</small></span></li>';
    }).join('');

    if (complaint.status === 'Rejected') {
      items += '<li class="step step-rejected"><span class="step-dot" aria-hidden="true"></span>' +
               '<span class="step-body"><strong>Rejected</strong>' +
               '<small>Closed without action</small></span></li>';
    }
    return '<div class="detail-timeline"><h2 class="detail-section-title">Progress</h2>' +
           '<ol class="steps">' + items + '</ol></div>';
  }

  function pagination(page, totalPages, baseHash) {
    if (totalPages <= 1) return '';
    function link(p, label, rel) {
      if (p === page) return '<span aria-current="page">' + p + '</span>';
      return '<a href="' + esc(baseHash + '&page=' + p) + '"' + (rel ? ' rel="' + rel + '"' : '') + '>' + label + '</a>';
    }
    var items = '';
    for (var i = 1; i <= totalPages; i++) items += '<li class="page-item">' + link(i, i) + '</li>';
    var prev = page <= 1 ? '<a href="#" tabindex="-1" aria-disabled="true">&larr; Previous</a>'
                         : '<a href="' + esc(baseHash + '&page=' + (page - 1)) + '" rel="prev">&larr; Previous</a>';
    var next = page >= totalPages ? '<a href="#" tabindex="-1" aria-disabled="true">Next &rarr;</a>'
                                  : '<a href="' + esc(baseHash + '&page=' + (page + 1)) + '" rel="next">Next &rarr;</a>';
    return '<nav class="pagination" aria-label="Pagination"><ul>' +
           '<li class="page-item' + (page <= 1 ? ' is-disabled' : '') + '">' + prev + '</li>' +
           items +
           '<li class="page-item' + (page >= totalPages ? ' is-disabled' : '') + '">' + next + '</li>' +
           '</ul></nav>';
  }

  // ----------------------------------------------------------------- modal --
  var modalEl = null;
  var modalResolve = null;

  function initModal() {
    modalEl = document.getElementById('confirmModal');
  }

  /**
   * Shows a confirmation dialog. Resolves true when confirmed.
   * Used for destructive actions so nothing is removed by a mis-click.
   */
  function confirmDialog(opts) {
    if (!modalEl) initModal();
    if (!modalEl) return Promise.resolve(window.confirm(opts.message));

    modalEl.querySelector('[data-modal-title]').textContent = opts.title || 'Please confirm';
    modalEl.querySelector('[data-modal-text]').textContent = opts.message || '';
    var cancelBtn = modalEl.querySelector('[data-modal-cancel]');
    var okBtn = modalEl.querySelector('[data-modal-ok]');
    okBtn.textContent = opts.confirmLabel || 'Yes, delete';
    okBtn.className = 'btn ' + (opts.danger === false ? 'btn-primary' : 'btn-danger');
    cancelBtn.textContent = opts.cancelLabel || 'Cancel';
    modalEl.hidden = false;
    okBtn.focus();

    return new Promise(function (resolve) {
      modalResolve = resolve;
    });
  }

  function closeModal(result) {
    if (modalEl) modalEl.hidden = true;
    var resolve = modalResolve;
    modalResolve = null;
    if (resolve) resolve(result);
  }

  function wireModal() {
    initModal();
    if (!modalEl) return;
    modalEl.querySelector('[data-modal-ok]').addEventListener('click', function () { closeModal(true); });
    modalEl.querySelector('[data-modal-cancel]').addEventListener('click', function () { closeModal(false); });
    modalEl.querySelector('[data-modal-backdrop]').addEventListener('click', function () { closeModal(false); });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && modalEl && !modalEl.hidden) closeModal(false);
    });
  }

  // ----------------------------------------------------------------- busy --
  function busy(show) {
    var el = document.getElementById('busyOverlay');
    if (el) el.hidden = !show;
  }

  function toast(message, tone) {
    var host = document.getElementById('toastHost');
    if (!host) return;
    var el = document.createElement('div');
    el.className = 'flash flash-' + (tone || 'info');
    el.setAttribute('data-flash', '');
    el.setAttribute('role', 'status');
    el.innerHTML = '<p class="flash-text"></p>';
    el.querySelector('.flash-text').textContent = message;
    host.appendChild(el);
    window.setTimeout(function () {
      if (el.parentNode) el.parentNode.removeChild(el);
    }, 4500);
  }

  App.UI = {
    esc: esc,
    escAttr: escAttr,
    formatDate: formatDate,
    formatDateLong: formatDateLong,
    relativeTime: relativeTime,
    truncate: truncate,
    priorityTone: priorityTone,
    statusTone: statusTone,
    badge: badge,
    rolePill: rolePill,
    avatar: avatar,
    userChip: userChip,
    pageIntro: pageIntro,
    sectionHeading: sectionHeading,
    statTile: statTile,
    flashHtml: flashHtml,
    errorSummary: errorSummary,
    fieldError: fieldError,
    invalidClass: invalidClass,
    emptyState: emptyState,
    selectOptions: selectOptions,
    complaintRow: complaintRow,
    timelineHtml: timelineHtml,
    pagination: pagination,
    confirmDialog: confirmDialog,
    wireModal: wireModal,
    busy: busy,
    toast: toast
  };
})(window.App);