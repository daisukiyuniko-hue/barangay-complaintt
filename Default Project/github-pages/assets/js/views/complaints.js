/* ==========================================================================
   views/complaints.js - the core entity: Create, Read, Update, Delete
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var esc = App.UI.esc;

  // ===================================================================== LIST =
  function complaintList(ctx) {
    var user = ctx.user;
    var isAdmin = App.Store.isAdmin(user);
    var pageSize = App.Layout.CONFIG.pageSize;

    var search = (ctx.query.q || '').trim();
    var status = ctx.query.status || '';
    var category = ctx.query.category || '';
    var priority = ctx.query.priority || '';
    var page = parseInt(ctx.query.page, 10);
    if (!page || page < 1) page = 1;

    // An unknown filter value would silently hide everything, so reset it.
    if (status && !hasValue(App.Store.STATUSES, status)) status = '';
    if (category && !hasValue(App.Store.CATEGORIES, category)) category = '';
    if (priority && !hasValue(App.Store.PRIORITIES, priority)) priority = '';

    var items = App.Store.visibleComplaints(user);

    if (search) {
      var needle = search.toLowerCase();
      items = items.filter(function (c) {
        return [c.title, c.description, c.referenceNo, c.location, c.reporterName]
          .some(function (field) { return String(field || '').toLowerCase().indexOf(needle) !== -1; });
      });
    }
    if (status) items = items.filter(function (c) { return c.status === status; });
    if (category) items = items.filter(function (c) { return c.category === category; });
    if (priority) items = items.filter(function (c) { return c.priority === priority; });

    items.sort(function (a, b) { return String(b.createdAt).localeCompare(String(a.createdAt)); });

    var total = items.length;
    var totalPages = Math.max(1, Math.ceil(total / pageSize));
    if (page > totalPages) page = totalPages;
    var visible = items.slice((page - 1) * pageSize, page * pageSize);

    var anyFilter = !!(search || status || category || priority);

    var rows = visible.map(function (c) {
      return App.UI.complaintRow(c, user, {});
    }).join('');

    if (!visible.length) {
      if (anyFilter) {
        rows = App.UI.emptyState({
          icon: '&#128269;',
          title: 'No matching reports',
          message: 'No report matches the filters you selected. Try clearing the search or choosing different values.',
          action: '<a class="btn btn-outline" href="#/complaints">Clear all filters</a>'
        });
      } else if (isAdmin) {
        rows = App.UI.emptyState({
          icon: '&#128203;',
          title: 'No reports yet',
          message: 'Nobody has filed a complaint yet. When a resident submits one it will appear here.',
          action: '<a class="btn btn-primary" href="#/complaints/new">File the first report</a>'
        });
      } else {
        rows = App.UI.emptyState({
          icon: '&#128221;',
          title: 'You have not filed any reports yet',
          message: 'When you report a concern about your purok, it will appear here so you can follow its progress.',
          action: '<a class="btn btn-primary" href="#/complaints/new">Report a concern</a>'
        });
      }
    }

    var stats = App.Store.statsFor(isAdmin ? '' : user.id);
    var scopeNote = isAdmin ? 'all residents' : 'filed by you';
    var heading = isAdmin ? 'All complaints' : 'My reports';
    var subtitle = isAdmin
      ? 'Every concern reported by residents of Barangay San Isidro. Update the status as each one is acted on.'
      : 'Every concern you have reported, newest first. You can edit or withdraw a report while it is still pending.';

    var clearLink = anyFilter ? '<a class="btn btn-ghost btn-sm" href="#/complaints">Clear filters</a>' : '';

    var baseHash = '#/complaints?q=' + encodeURIComponent(search) +
      '&status=' + encodeURIComponent(status) +
      '&category=' + encodeURIComponent(category) +
      '&priority=' + encodeURIComponent(priority);

    var html = '<section class="container section">' +
      App.UI.pageIntro({
        eyebrow: 'Complaint records',
        heading: heading,
        sub: subtitle,
        actions: '<a class="btn btn-primary" href="#/complaints/new">+ New report</a>' + clearLink
      }) +
      App.Layout.storageWarningHtml() +
      '<div class="stat-grid stat-grid-4">' +
        App.UI.statTile('Reports ' + scopeNote, stats.total, 'brand', 'Total on record') +
        App.UI.statTile('Pending', stats.pending, 'warning', 'Awaiting first response') +
        App.UI.statTile('In review', stats.inReview, 'info', 'Being worked on now') +
        App.UI.statTile('Resolved', stats.resolved, 'success', 'Completed and closed') +
      '</div>' +
      '<form class="filter-bar" method="get" data-filter>' +
        '<div class="field"><label for="q">Search</label>' +
          '<input type="search" id="q" name="q" placeholder="Reference number, title, location..." value="' + esc(search) + '"></div>' +
        '<div class="field"><label for="status">Status</label>' +
          '<select id="status" name="status">' + App.UI.selectOptions(App.Store.STATUSES, status, 'All statuses') + '</select></div>' +
        '<div class="field"><label for="category">Category</label>' +
          '<select id="category" name="category">' + App.UI.selectOptions(App.Store.CATEGORIES, category, 'All categories') + '</select></div>' +
        '<div class="field"><label for="priority">Priority</label>' +
          '<select id="priority" name="priority">' + App.UI.selectOptions(App.Store.PRIORITIES, priority, 'All priorities') + '</select></div>' +
        '<div class="filter-actions">' +
          '<button class="btn btn-primary btn-sm" type="submit">Apply</button>' +
          '<a class="btn btn-ghost btn-sm" href="#/complaints">Reset</a>' +
        '</div>' +
      '</form>' +
      '<p class="result-count">Showing <strong>' + visible.length + '</strong> of <strong>' + total + '</strong> report(s)' +
        (anyFilter ? ' matching your filters' : '') + '.</p>' +
      '<div class="row-list">' + rows + '</div>' +
      App.UI.pagination(page, totalPages, baseHash) +
    '</section>';

    return {
      html: html,
      title: heading,
      nav: 'complaints',
      user: user,
      onMount: function (root) {
        var form = root.querySelector('[data-filter]');
        form.addEventListener('submit', function (e) {
          e.preventDefault();
          var params = new URLSearchParams();
          ['q', 'status', 'category', 'priority'].forEach(function (key) {
            var value = form.querySelector('[name=' + key + ']').value.trim();
            if (value) params.set(key, value);
          });
          var query = params.toString();
          App.Router.go('/complaints' + (query ? '?' + query : ''));
        });
      }
    };
  }

  function hasValue(list, value) {
    return list.some(function (item) { return item.value === value; });
  }

  // =================================================================== DETAIL =
  function complaintDetail(ctx) {
    var user = ctx.user;
    var item = App.Store.complaintById(ctx.params.id);

    if (!item) {
      return App.Views.notFound(404);
    }
    if (!App.Store.canAccess(item, user)) {
      return App.Views.forbidden();
    }

    var isAdmin = App.Store.isAdmin(user);
    var pTone = App.UI.priorityTone(item.priority);
    var sTone = App.UI.statusTone(item.status);
    var path = '#/complaints/' + encodeURIComponent(item.id);

    var notesHtml = item.adminNotes
      ? '<div class="admin-note"><p class="admin-note-label">Update from the Barangay</p>' +
        '<p class="admin-note-text">' + esc(item.adminNotes) + '</p></div>'
      : '';

    var fields = [
      ['Reference number', esc(item.referenceNo)],
      ['Category', esc(item.category)],
      ['Location', esc(item.location)],
      ['Date reported', esc(App.UI.formatDateLong(item.createdAt))],
      ['Time reported', esc(App.UI.formatDate(item.createdAt, true).split(',').pop())],
      ['Last updated', esc(App.UI.formatDate(item.updatedAt, true))],
      ['Reported by', esc(item.reporterName)],
      ['Contact email', '<a href="mailto:' + esc(item.reporterEmail) + '">' + esc(item.reporterEmail) + '</a>']
    ].map(function (row) {
      return '<div><dt>' + esc(row[0]) + '</dt><dd>' + row[1] + '</dd></div>';
    }).join('');

    var canEdit = isAdmin || item.status === 'Pending';
    var editButton = canEdit ? '<a class="btn btn-outline" href="' + path + '/edit">Edit report</a>' : '';

    var statusPanel = '';
    if (isAdmin) {
      statusPanel = '<div class="card card-status">' +
        '<div class="card-head"><h2 class="card-title">Update status</h2></div>' +
        '<form class="form-stack" data-status-form>' +
          '<div class="field"><label for="status">Current status</label>' +
            '<select id="status" name="status">' +
              App.UI.selectOptions(App.Store.STATUSES, item.status) + '</select></div>' +
          '<div class="field"><label for="adminNotes">Note to the resident <span class="optional">optional</span></label>' +
            '<textarea id="adminNotes" name="adminNotes" rows="4" maxlength="1000" ' +
            'placeholder="What action was taken?">' + esc(item.adminNotes) + '</textarea>' +
            '<p class="field-hint">This note is shown to whoever filed the report.</p></div>' +
          '<button class="btn btn-primary btn-block" type="submit" data-submit>Save update</button>' +
        '</form>' +
      '</div>';
    }

    var C = App.Layout.CONFIG;

    var html = '<section class="container section">' +
      '<nav class="breadcrumb"><a href="#/complaints">&larr; Back to reports</a></nav>' +
      '<div class="detail-layout">' +
        '<article class="card detail-card">' +
          '<div class="detail-head">' +
            '<div class="row-badges">' +
              App.UI.badge(item.priority + ' priority', pTone) +
              App.UI.badge(item.status, sTone) +
              App.UI.badge(item.referenceNo, 'neutral') +
            '</div>' +
            '<h1 class="detail-title">' + esc(item.title) + '</h1>' +
            '<p class="detail-category">' + esc(item.category) + '</p>' +
          '</div>' +
          '<div class="detail-body">' +
            '<h2 class="detail-section-title">Description</h2>' +
            '<p class="detail-text">' + esc(item.description) + '</p>' +
            notesHtml +
          '</div>' +
          '<dl class="detail-list detail-list-grid">' + fields + '</dl>' +
          App.UI.timelineHtml(item) +
        '</article>' +
        '<aside class="side-stack">' +
          statusPanel +
          '<div class="card">' +
            '<div class="card-head"><h2 class="card-title">Actions</h2></div>' +
            '<div class="stack-actions">' +
              editButton +
              '<a class="btn btn-ghost" href="#/complaints/new">File another report</a>' +
              '<a class="btn btn-danger-ghost" href="' + path + '/delete">Delete report</a>' +
            '</div>' +
            '<p class="card-note">Deleting a report cannot be undone. You will be asked to confirm first.</p>' +
          '</div>' +
          '<div class="card card-quiet">' +
            '<div class="card-head"><h2 class="card-title">Need help?</h2></div>' +
            '<p class="card-text">Visit the Barangay Hall at ' + esc(C.address) + ' or call the hotline at ' + esc(C.hotline) + '.</p>' +
            '<p class="card-text">Office hours: ' + esc(C.officeHours) + '.</p>' +
          '</div>' +
        '</aside>' +
      '</div>' +
    '</section>';

    return {
      html: html,
      title: item.title,
      nav: 'complaints',
      user: user,
      onMount: function (root) {
        var form = root.querySelector('[data-status-form]');
        if (!form) return;
        form.addEventListener('submit', function (e) {
          e.preventDefault();
          var newStatus = form.querySelector('[name=status]').value;
          if (!hasValue(App.Store.STATUSES, newStatus)) return;
          item.status = newStatus;
          item.adminNotes = form.querySelector('[name=adminNotes]').value.trim();
          item.updatedAt = new Date().toISOString();
          item.updatedBy = user.id;
          App.Store.putComplaint(item);
          App.Store.logActivity('complaint_status', user.id, item.referenceNo + ': ' + newStatus);
          App.Layout.setFlash(item.referenceNo + ' is now marked as ' + newStatus + '.', 'success');
          App.Router.render(App.Views.complaintDetail({ params: ctx.params, query: ctx.query, user: user }));
        });
      }
    };
  }

  // ==================================================================== FORM ==
  function complaintForm(ctx) {
    var user = ctx.user;
    var isAdmin = App.Store.isAdmin(user);
    var item = ctx.existing || null;
    var errors = ctx.errors || {};
    var values = ctx.form || {};

    if (!values.title && item) {
      values = {
        title: item.title,
        category: item.category,
        priority: item.priority,
        location: item.location,
        description: item.description,
        adminNotes: item.adminNotes || ''
      };
    }

    var isEdit = !!item;
    var heading = isEdit ? 'Edit report' : 'Report a concern';
    var sub = isEdit
      ? 'Correct the details of your report. Your reference number and the date you filed it stay the same.'
      : 'Tell us what is wrong and where. Fields marked with * are required.';
    var action = isEdit ? '/complaints/' + encodeURIComponent(item.id) + '/edit' : '/complaints/new';

    var categoryHints = App.Store.CATEGORIES.map(function (c) {
      return '<li><strong>' + esc(c.value) + '</strong> &mdash; ' + esc(c.hint) + '</li>';
    }).join('');
    var priorityHints = App.Store.PRIORITIES.map(function (p) {
      return '<li><strong>' + esc(p.value) + '</strong> &mdash; ' + esc(p.hint) + '</li>';
    }).join('');

    var notesField = isAdmin
      ? '<div class="field"><label for="adminNotes">Internal note <span class="optional">optional</span></label>' +
        '<textarea id="adminNotes" name="adminNotes" rows="3" maxlength="1000" ' +
        'placeholder="Actions taken, referrals, follow-up schedule">' + esc(values.adminNotes || '') + '</textarea></div>'
      : '';

    var html = '<section class="container section-narrow">' +
      '<nav class="breadcrumb"><a href="#/complaints">&larr; Back to reports</a></nav>' +
      App.UI.pageIntro({ eyebrow: 'Complaint form', heading: heading, sub: sub }) +
      App.UI.errorSummary(errors) +
      '<div class="form-layout">' +
        '<div class="card">' +
          '<form class="form-stack" data-complaint-form novalidate>' +
            '<div class="field"><label for="title">Short title <span class="req">*</span></label>' +
              '<input type="text" id="title" name="title" maxlength="120" required ' +
              'placeholder="Example: Deep pothole in front of Barangay Hall" ' +
              'value="' + esc(values.title || '') + '"' + App.UI.invalidClass(errors, 'title') + '>' +
              '<p class="field-hint">In one line: what is the problem?</p>' +
              App.UI.fieldError(errors, 'title') + '</div>' +

            '<div class="field-grid">' +
              '<div class="field"><label for="category">Category <span class="req">*</span></label>' +
                '<select id="category" name="category" required' + App.UI.invalidClass(errors, 'category') + '>' +
                App.UI.selectOptions(App.Store.CATEGORIES, values.category, '-- Choose a category --') +
                '</select>' + App.UI.fieldError(errors, 'category') + '</div>' +
              '<div class="field"><label for="priority">How urgent is it? <span class="req">*</span></label>' +
                '<select id="priority" name="priority" required' + App.UI.invalidClass(errors, 'priority') + '>' +
                App.UI.selectOptions(App.Store.PRIORITIES, values.priority, '-- Choose a priority --') +
                '</select>' + App.UI.fieldError(errors, 'priority') + '</div>' +
            '</div>' +

            '<div class="field"><label for="location">Exact location <span class="req">*</span></label>' +
              '<input type="text" id="location" name="location" maxlength="140" required ' +
              'placeholder="Example: Purok 5, corner of Mabini Street" ' +
              'value="' + esc(values.location || '') + '"' + App.UI.invalidClass(errors, 'location') + '>' +
              '<p class="field-hint">Give the purok, street or nearest landmark so the crew can find it.</p>' +
              App.UI.fieldError(errors, 'location') + '</div>' +

            '<div class="field"><label for="description">Full description <span class="req">*</span></label>' +
              '<textarea id="description" name="description" rows="7" maxlength="2000" required ' +
              'placeholder="Describe what happened, how long it has been a problem, and who is affected." ' +
              'data-char-count' + App.UI.invalidClass(errors, 'description') + '>' +
              esc(values.description || '') + '</textarea>' +
              '<p class="field-hint char-count"><span data-char-current>0</span> / 2,000 characters</p>' +
              App.UI.fieldError(errors, 'description') + '</div>' +

            notesField +

            '<div class="reporter-preview">' +
              '<p class="reporter-label">This report will be filed under</p>' +
              '<p class="reporter-name">' + esc(user.name) + '</p>' +
              '<p class="reporter-meta">' + esc(user.email) + (user.address ? ' &middot; ' + esc(user.address) : '') + '</p>' +
            '</div>' +

            '<div class="form-actions">' +
              '<button class="btn btn-primary" type="submit" data-submit>' + (isEdit ? 'Save changes' : 'Submit report') + '</button>' +
              '<a class="btn btn-ghost" href="#/complaints">Cancel</a>' +
            '</div>' +
          '</form>' +
        '</div>' +

        '<aside class="side-stack">' +
          '<div class="card card-quiet">' +
            '<div class="card-head"><h2 class="card-title">What happens next?</h2></div>' +
            '<ol class="mini-steps">' +
              '<li>You get a reference number such as <code>BCR-' + new Date().getFullYear() + '-0001</code>.</li>' +
              '<li>The barangay reviews your report and sets a status.</li>' +
              '<li>You can check the status and read notes any time from your dashboard.</li>' +
              '<li>When the work is done the status becomes <strong>Resolved</strong>.</li>' +
            '</ol>' +
          '</div>' +
          '<div class="card card-quiet">' +
            '<div class="card-head"><h2 class="card-title">Categories</h2></div>' +
            '<ul class="hint-list">' + categoryHints + '</ul></div>' +
          '<div class="card card-quiet">' +
            '<div class="card-head"><h2 class="card-title">Priority guide</h2></div>' +
            '<ul class="hint-list">' + priorityHints + '</ul></div>' +
        '</aside>' +
      '</div>' +
    '</section>';

    return {
      html: html,
      title: heading,
      nav: isEdit ? 'complaints' : 'new',
      user: user,
      onMount: function (root) { wireForm(root, { action: action, isEdit: isEdit, item: item, user: user }); }
    };
  }

  function wireForm(root, opts) {
    var form = root.querySelector('[data-complaint-form]');
    if (!form) return;

    var area = form.querySelector('[data-char-count]');
    var counter = form.querySelector('[data-char-current]');
    if (area && counter) {
      var updateCount = function () { counter.textContent = String(area.value.length); };
      area.addEventListener('input', updateCount);
      updateCount();
    }

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var input = {
        title: form.querySelector('[name=title]').value,
        category: form.querySelector('[name=category]').value,
        priority: form.querySelector('[name=priority]').value,
        location: form.querySelector('[name=location]').value,
        description: form.querySelector('[name=description]').value,
        adminNotes: form.querySelector('[name=adminNotes]') ? form.querySelector('[name=adminNotes]').value : ''
      };

      var result = App.Validate.validateComplaint(input);
      if (Object.keys(result.errors).length) {
        App.Router.render(App.Views.complaintForm({
          user: opts.user,
          existing: opts.item,
          errors: result.errors,
          form: result.values
        }));
        App.Layout.renderFlash(null);
        return;
      }

      var button = form.querySelector('[data-submit]');
      button.disabled = true;
      button.textContent = 'Saving...';

      if (opts.isEdit) {
        opts.item.title = result.values.title;
        opts.item.category = result.values.category;
        opts.item.priority = result.values.priority;
        opts.item.location = result.values.location;
        opts.item.description = result.values.description;
        opts.item.updatedAt = new Date().toISOString();
        opts.item.updatedBy = opts.user.id;
        if (App.Store.isAdmin(opts.user)) opts.item.adminNotes = result.values.adminNotes;
        App.Store.putComplaint(opts.item);
        App.Store.logActivity('complaint_update', opts.user.id, 'Updated ' + opts.item.referenceNo);
        App.Layout.setFlash('Report ' + opts.item.referenceNo + ' has been updated.', 'success');
        App.Router.go('/complaints/' + encodeURIComponent(opts.item.id));
      } else {
        var record = {
          id: App.Crypto.randomId('cmp'),
          referenceNo: App.Store.nextReference(),
          title: result.values.title,
          description: result.values.description,
          category: result.values.category,
          priority: result.values.priority,
          status: 'Pending',
          location: result.values.location,
          reporterId: opts.user.id,
          reporterName: opts.user.name,
          reporterEmail: opts.user.email,
          reporterPhone: opts.user.phone,
          adminNotes: result.values.adminNotes,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
          updatedBy: opts.user.id
        };
        App.Store.putComplaint(record);
        App.Store.logActivity('complaint_create', opts.user.id, 'Created ' + record.referenceNo);
        App.Layout.setFlash('Report ' + record.referenceNo + ' was submitted successfully.', 'success');
        App.Router.go('/complaints/' + encodeURIComponent(record.id));
      }
    });
  }

  function complaintEdit(ctx) {
    var user = ctx.user;
    var item = App.Store.complaintById(ctx.params.id);
    if (!item) return App.Views.notFound(404);
    if (!App.Store.canAccess(item, user)) return App.Views.forbidden();
    if (!App.Store.isAdmin(user) && item.status !== 'Pending') {
      return App.Views.errorPage({
        code: 403,
        heading: 'This report can no longer be edited',
        message: 'Once the barangay starts reviewing a report it is locked so the record stays accurate.'
      });
    }
    return complaintForm({
      user: user,
      params: ctx.params,
      query: ctx.query,
      existing: item,
      errors: ctx.errors,
      form: ctx.form
    });
  }

  // =================================================================== DELETE =
  function complaintDelete(ctx) {
    var user = ctx.user;
    var item = App.Store.complaintById(ctx.params.id);

    if (!item) return App.Views.notFound(404);
    if (!App.Store.canAccess(item, user)) return App.Views.forbidden();

    var isAdmin = App.Store.isAdmin(user);
    var warning = isAdmin
      ? 'This will remove the report permanently for the resident as well.'
      : 'This report will be removed from the barangay records as well.';

    var path = '#/complaints/' + encodeURIComponent(item.id);

    var html = '<section class="container section-narrow">' +
      '<nav class="breadcrumb"><a href="' + path + '">&larr; Back to report</a></nav>' +
      App.UI.pageIntro({
        eyebrow: 'Confirm deletion',
        heading: 'Delete this report?',
        sub: warning
      }) +
      '<div class="card card-danger">' +
        '<div class="danger-head">' +
          '<span class="danger-icon" aria-hidden="true">&#128465;</span>' +
          '<div><h2 class="danger-title">This action cannot be undone</h2>' +
          '<p class="danger-text">Please review the details below before you continue.</p></div>' +
        '</div>' +
        '<dl class="detail-list">' +
          '<div><dt>Reference number</dt><dd>' + esc(item.referenceNo) + '</dd></div>' +
          '<div><dt>Title</dt><dd>' + esc(item.title) + '</dd></div>' +
          '<div><dt>Category</dt><dd>' + esc(item.category) + '</dd></div>' +
          '<div><dt>Location</dt><dd>' + esc(item.location) + '</dd></div>' +
          '<div><dt>Status</dt><dd>' + esc(item.status) + '</dd></div>' +
          '<div><dt>Reported on</dt><dd>' + esc(App.UI.formatDateLong(item.createdAt)) + '</dd></div>' +
        '</dl>' +
        '<div class="form-actions form-actions-split">' +
          '<button class="btn btn-danger" type="button" data-confirm-delete>Yes, delete this report</button>' +
          '<a class="btn btn-ghost" href="' + path + '">Cancel, keep the report</a>' +
        '</div>' +
      '</div>' +
    '</section>';

    return {
      html: html,
      title: 'Confirm deletion',
      nav: 'complaints',
      user: user,
      onMount: function (root) {
        var button = root.querySelector('[data-confirm-delete]');
        button.addEventListener('click', function () {
          App.UI.confirmDialog({
            title: 'Delete this report?',
            message: 'Report ' + item.referenceNo + ' will be permanently removed. This cannot be undone.',
            confirmLabel: 'Yes, delete'
          }).then(function (ok) {
            if (!ok) return;
            var reference = item.referenceNo;
            App.Store.deleteComplaint(item.id);
            App.Store.logActivity('complaint_delete', user.id, 'Deleted ' + reference);
            App.Layout.setFlash('Report ' + reference + ' has been permanently deleted.', 'success');
            App.Router.go('/complaints');
          });
        });
      }
    };
  }

  App.Views = App.Views || {};
  App.Views.complaintList = complaintList;
  App.Views.complaintDetail = complaintDetail;
  App.Views.complaintForm = complaintForm;
  App.Views.complaintEdit = complaintEdit;
  App.Views.complaintDelete = complaintDelete;
})(window.App);