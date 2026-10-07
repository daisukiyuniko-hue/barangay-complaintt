/* ==========================================================================
   views/users.js - administrator-only account management (second access level)
   Create, read, update and delete resident accounts.
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var esc = App.UI.esc;

  function userList(ctx) {
    var admin = ctx.user;
    var search = (ctx.query.q || '').trim();
    var role = ctx.query.role || '';
    var state = ctx.query.state || '';
    if (role && ['admin', 'resident'].indexOf(role) < 0) role = '';
    if (state && ['active', 'inactive'].indexOf(state) < 0) state = '';

    var users = App.Store.allUsers();

    if (search) {
      var needle = search.toLowerCase();
      users = users.filter(function (u) {
        return [u.name, u.email, u.address].some(function (field) {
          return String(field || '').toLowerCase().indexOf(needle) !== -1;
        });
      });
    }
    if (role) users = users.filter(function (u) { return u.role === role; });
    if (state) {
      users = users.filter(function (u) {
        return state === 'active' ? u.active !== false : u.active === false;
      });
    }

    users.sort(function (a, b) { return String(b.createdAt).localeCompare(String(a.createdAt)); });

    var all = App.Store.allUsers();
    var statAll = all.length;
    var statAdmins = all.filter(function (u) { return u.role === 'admin'; }).length;
    var statActive = all.filter(function (u) { return u.active !== false; }).length;
    var statOff = statAll - statActive;

    var rows = users.map(function (u) { return userRow(u, admin); }).join('');
    if (!users.length) {
      rows = App.UI.emptyState({
        icon: '&#128101;',
        title: 'No accounts match',
        message: 'Try a different search term or clear the filters.',
        action: '<a class="btn btn-outline" href="#/users">Clear filters</a>'
      });
    }

    var clearLink = (search || role || state) ? '<a class="btn btn-ghost btn-sm" href="#/users">Clear filters</a>' : '';

    var html = '<section class="container section">' +
      App.UI.pageIntro({
        eyebrow: 'Administrator tools',
        heading: 'Resident accounts',
        sub: 'Create accounts, promote residents to administrator, deactivate access and reset passwords.',
        actions: '<a class="btn btn-primary" href="#/users/new">+ Add resident</a>' + clearLink
      }) +
      '<div class="stat-grid stat-grid-4">' +
        App.UI.statTile('Total accounts', statAll, 'brand', 'Residents and admins') +
        App.UI.statTile('Administrators', statAdmins, 'info', 'Full management access') +
        App.UI.statTile('Active', statActive, 'success', 'Can sign in') +
        App.UI.statTile('Deactivated', statOff, 'warning', 'Access blocked') +
      '</div>' +
      '<form class="filter-bar" data-user-filter>' +
        '<div class="field"><label for="q">Search</label>' +
          '<input type="search" id="q" name="q" placeholder="Name, email or address..." value="' + esc(search) + '"></div>' +
        '<div class="field"><label for="role">Role</label>' +
          '<select id="role" name="role">' +
            '<option value="">All roles</option>' +
            '<option value="resident"' + (role === 'resident' ? ' selected' : '') + '>Resident</option>' +
            '<option value="admin"' + (role === 'admin' ? ' selected' : '') + '>Administrator</option>' +
          '</select></div>' +
        '<div class="field"><label for="state">Status</label>' +
          '<select id="state" name="state">' +
            '<option value="">Any status</option>' +
            '<option value="active"' + (state === 'active' ? ' selected' : '') + '>Active</option>' +
            '<option value="inactive"' + (state === 'inactive' ? ' selected' : '') + '>Deactivated</option>' +
          '</select></div>' +
        '<div class="filter-actions">' +
          '<button class="btn btn-primary btn-sm" type="submit">Apply</button>' +
          '<a class="btn btn-ghost btn-sm" href="#/users">Reset</a>' +
        '</div>' +
      '</form>' +
      '<p class="result-count">Showing <strong>' + users.length + '</strong> of <strong>' + all.length + '</strong> account(s).</p>' +
      '<div class="table-wrap"><table class="table">' +
        '<thead><tr>' +
          '<th scope="col">Name</th><th scope="col">Role</th><th scope="col">Contact</th>' +
          '<th scope="col">Reports</th><th scope="col">Status</th>' +
          '<th scope="col" class="col-actions">Actions</th>' +
        '</tr></thead><tbody>' + rows + '</tbody>' +
      '</table></div>' +
    '</section>';

    return {
      html: html,
      title: 'Resident accounts',
      nav: 'users',
      user: admin,
      onMount: function (root) {
        var form = root.querySelector('[data-user-filter]');
        form.addEventListener('submit', function (e) {
          e.preventDefault();
          var params = new URLSearchParams();
          ['q', 'role', 'state'].forEach(function (key) {
            var value = form.querySelector('[name=' + key + ']').value.trim();
            if (value) params.set(key, value);
          });
          var query = params.toString();
          App.Router.go('/users' + (query ? '?' + query : ''));
        });

        // Delegated row actions.
        // The outlet element persists across renders, so this listener must be
        // attached exactly once. Attaching it on every visit would stack up
        // duplicates and a single click would fire the action several times
        // (promoting a user and then immediately demoting them again).
        if (!root.dataset.userActionsWired) {
          root.dataset.userActionsWired = '1';
          root.addEventListener('click', function (e) {
            var button = e.target.closest('[data-user-action]');
            if (!button) return;
            e.preventDefault();
            // Ask BEFORE doing anything. A document-level confirm handler runs
            // after this one (bubbling order), so relying on it would let the
            // action complete even when the answer is "No".
            var question = button.getAttribute('data-confirm');
            if (question && !window.confirm(question)) return;
            // Read the current admin at click time, not at render time.
            handleUserAction(button.getAttribute('data-user-action'),
                             button.getAttribute('data-user-id'), App.Auth.user());
          });
        }
      }
    };
  }

  function userRow(user, admin) {
    var isSelf = user.id === admin.id;
    var isAdminRow = user.role === 'admin';
    var isActive = user.active !== false;
    var stats = App.Store.statsFor(user.id);

    var contact = esc(user.email);
    if (user.phone) contact += '<br><span class="table-sub">' + esc(user.phone) + '</span>';
    if (user.address) contact += '<br><span class="table-sub">' + esc(user.address) + '</span>';

    var roleAction;
    if (isSelf) {
      roleAction = '<span class="action-note">This is you</span>';
    } else if (isAdminRow) {
      roleAction = '<button class="btn btn-ghost btn-xs" data-user-action="role" data-user-id="' +
        esc(user.id) + '" data-role="resident" data-confirm="Demote ' + esc(user.name) +
        ' to a regular resident? They will lose access to all reports and accounts.">Demote</button>';
    } else {
      roleAction = '<button class="btn btn-outline btn-xs" data-user-action="role" data-user-id="' +
        esc(user.id) + '" data-role="admin" data-confirm="Promote ' + esc(user.name) +
        ' to administrator? They will gain full access to all reports and accounts.">Promote</button>';
    }

    var activeAction;
    if (isSelf) {
      activeAction = '<span class="action-note">&mdash;</span>';
    } else if (isActive) {
      activeAction = '<button class="btn btn-ghost btn-xs" data-user-action="toggle" data-user-id="' +
        esc(user.id) + '" data-confirm="Deactivate ' + esc(user.name) +
        '? They will not be able to sign in.">Deactivate</button>';
    } else {
      activeAction = '<button class="btn btn-outline btn-xs" data-user-action="toggle" data-user-id="' +
        esc(user.id) + '">Reactivate</button>';
    }

    var deleteAction = isSelf
      ? '<span class="action-note">&mdash;</span>'
      : '<a class="btn btn-danger-ghost btn-xs" href="#/users/' + encodeURIComponent(user.id) + '/delete">Delete</a>';

    return '<tr class="' + (isActive ? '' : 'is-inactive') + '">' +
      '<th scope="row"><div class="cell-user">' + App.UI.avatar(user) +
        '<span class="cell-user-text">' + esc(user.name) + '</span></div></th>' +
      '<td data-label="Role">' + App.UI.rolePill(user.role) + '</td>' +
      '<td data-label="Contact" class="table-contact">' + contact + '</td>' +
      '<td data-label="Reports">' + stats.total + '</td>' +
      '<td data-label="Status">' + App.UI.badge(isActive ? 'Active' : 'Deactivated', isActive ? 'success' : 'muted') + '</td>' +
      '<td data-label="Actions" class="col-actions"><div class="row-actions">' +
        roleAction + activeAction + deleteAction +
      '</div></td>' +
    '</tr>';
  }

  function handleUserAction(action, id, admin) {
    var user = App.Store.userById(id);
    if (!user) return App.UI.toast('That account no longer exists.', 'error');

    if (user.id === admin.id) {
      return App.UI.toast('You cannot change your own access level or status.', 'warning');
    }

    if (action === 'toggle') {
      var activate = user.active === false;
      user.active = activate;
      user.updatedAt = new Date().toISOString();
      App.Store.putUser(user);
      App.Store.logActivity('user_toggle', admin.id, user.email + ' -> ' + (activate ? 'active' : 'deactivated'));
      App.Layout.setFlash(user.name + ' has been ' + (activate ? 'reactivated' : 'deactivated') + '.', activate ? 'success' : 'warning');
      App.Router.render(App.Views.userList({ user: admin, query: App.Router.parseQuery(App.Router.route()) }));
      return;
    }

    if (action === 'role') {
      var nextRole = document.querySelector('[data-user-action="role"][data-user-id="' + id + '"]').getAttribute('data-role');
      if (['admin', 'resident'].indexOf(nextRole) < 0) return;

      if (user.role === 'admin' && nextRole === 'resident' && App.Store.activeAdminCount() <= 1) {
        return App.UI.toast('You cannot demote the last active administrator.', 'error');
      }
      user.role = nextRole;
      user.updatedAt = new Date().toISOString();
      App.Store.putUser(user);
      App.Store.logActivity('user_role', admin.id, user.email + ' -> ' + nextRole);
      App.Layout.setFlash(user.name + ' is now ' + (nextRole === 'admin' ? 'an administrator' : 'a resident') + '.', 'success');
      App.Router.render(App.Views.userList({ user: admin, query: App.Router.parseQuery(App.Router.route()) }));
    }
  }

  // -------------------------------------------------------------- create ----
  function userCreate(ctx) {
    var admin = ctx.user;
    var errors = ctx.errors || {};
    var values = ctx.form || {};
    var role = values.role === 'admin' ? 'admin' : 'resident';

    var html = '<section class="container section-narrow">' +
      '<nav class="breadcrumb"><a href="#/users">&larr; Back to accounts</a></nav>' +
      App.UI.pageIntro({
        eyebrow: 'Administrator tools',
        heading: 'Add a resident account',
        sub: 'Create an account for someone who cannot register online yet. You can change the role later.'
      }) +
      App.UI.errorSummary(errors) +
      '<div class="card"><form class="form-stack" data-user-create novalidate>' +
        '<div class="field"><label for="name">Full name <span class="req">*</span></label>' +
          '<input type="text" id="name" name="name" maxlength="80" required ' +
          'placeholder="Maria Santos" value="' + esc(values.name || '') + '"' +
          App.UI.invalidClass(errors, 'name') + '>' + App.UI.fieldError(errors, 'name') + '</div>' +
        '<div class="field"><label for="email">Email address <span class="req">*</span></label>' +
          '<input type="email" id="email" name="email" maxlength="190" required ' +
          'placeholder="maria@example.com" value="' + esc(values.email || '') + '"' +
          App.UI.invalidClass(errors, 'email') + '>' + App.UI.fieldError(errors, 'email') + '</div>' +
        '<div class="field-grid">' +
          '<div class="field"><label for="phone">Mobile number <span class="optional">optional</span></label>' +
            '<input type="tel" id="phone" name="phone" maxlength="20" ' +
            'value="' + esc(values.phone || '') + '"' + App.UI.invalidClass(errors, 'phone') + '>' +
            App.UI.fieldError(errors, 'phone') + '</div>' +
          '<div class="field"><label for="role">Access level <span class="req">*</span></label>' +
            '<select id="role" name="role" required>' +
              '<option value="resident"' + (role === 'resident' ? ' selected' : '') + '>Resident - own reports only</option>' +
              '<option value="admin"' + (role === 'admin' ? ' selected' : '') + '>Administrator - full access</option>' +
            '</select></div>' +
        '</div>' +
        '<div class="field"><label for="address">Home address / purok <span class="optional">optional</span></label>' +
          '<input type="text" id="address" name="address" maxlength="160" ' +
          'value="' + esc(values.address || '') + '"></div>' +
        '<div class="field"><label for="password">Temporary password <span class="req">*</span></label>' +
          '<div class="password-field">' +
            '<input type="password" id="password" name="password" maxlength="128" required ' +
            'data-password-input data-strength-input' + App.UI.invalidClass(errors, 'password') + '>' +
            '<button type="button" class="password-toggle" data-password-toggle="password">Show</button>' +
          '</div>' +
          App.Views.strengthMeterHtml() +
          '<p class="field-hint">Share this with the resident and ask them to change it later.</p>' +
          App.UI.fieldError(errors, 'password') + '</div>' +
        '<div class="field"><label for="passwordConfirm">Confirm password <span class="req">*</span></label>' +
          '<div class="password-field">' +
            '<input type="password" id="passwordConfirm" name="passwordConfirm" maxlength="128" required>' +
            '<button type="button" class="password-toggle" data-password-toggle="passwordConfirm">Show</button>' +
          '</div>' +
          '<p class="field-error" data-match-error hidden>The two passwords do not match.</p></div>' +
        '<div class="form-actions">' +
          '<button class="btn btn-primary" type="submit" data-submit>Create account</button>' +
          '<a class="btn btn-ghost" href="#/users">Cancel</a>' +
        '</div>' +
      '</form></div>' +
    '</section>';

    return {
      html: html,
      title: 'Add a resident account',
      nav: 'users',
      user: admin,
      onMount: function (root) {
        var form = root.querySelector('[data-user-create]');
        App.Views.wireStrength(form);

        form.addEventListener('submit', function (e) {
          e.preventDefault();
          var input = {
            name: form.querySelector('[name=name]').value,
            email: form.querySelector('[name=email]').value,
            phone: form.querySelector('[name=phone]').value,
            address: form.querySelector('[name=address]').value,
            password: form.querySelector('[name=password]').value
          };
          var newRole = form.querySelector('[name=role]').value;
          var confirm = form.querySelector('[name=passwordConfirm]').value;

          var result = App.Validate.validateRegistration(input, 'register');
          var errors = result.errors;

          if (!errors.passwordConfirm && confirm !== input.password) {
            errors.passwordConfirm = 'The two passwords do not match.';
          }

          if (Object.keys(errors).length) {
            result.values.role = newRole;
            App.Router.render(App.Views.userCreate({ user: admin, errors: errors, form: result.values }));
            App.Layout.renderFlash(null);
            return;
          }

          var button = form.querySelector('[data-submit]');
          button.disabled = true;
          button.textContent = 'Creating...';

          App.Auth.createUser({
            name: result.values.name,
            email: result.values.email,
            phone: result.values.phone,
            address: result.values.address,
            password: result.values.password,
            role: newRole
          }).then(function (created) {
            App.Layout.setFlash('Account created for ' + created.name + ' (' + created.email + ').', 'success');
            App.Router.go('/users');
          }).catch(function (error) {
            console.error(error);
            App.UI.toast('Could not create that account.', 'error');
          });
        });
      }
    };
  }

  // -------------------------------------------------------------- delete ----
  function userDelete(ctx) {
    var admin = ctx.user;
    var user = App.Store.userById(ctx.params.id);

    if (!user) return App.Views.notFound(404);
    if (user.id === admin.id) {
      return App.Views.errorPage({
        code: 403,
        heading: 'You cannot delete your own account',
        message: 'Ask another administrator to remove this account for you.'
      });
    }

    var stats = App.Store.statsFor(user.id);
    var warning = '';
    if (stats.total > 0) {
      warning = '<div class="alert alert-warning"><span class="alert-icon" aria-hidden="true">&#9888;</span>' +
        '<div><strong>This account owns ' + stats.total + ' report(s).</strong><ul class="alert-list">' +
        '<li>' + stats.pending + ' pending, ' + stats.inReview + ' in review, ' + stats.resolved + ' resolved</li>' +
        '</ul>Those reports will also be permanently removed.</div></div>';
    }

    var html = '<section class="container section-narrow">' +
      '<nav class="breadcrumb"><a href="#/users">&larr; Back to accounts</a></nav>' +
      App.UI.pageIntro({
        eyebrow: 'Confirm deletion',
        heading: 'Delete this account?',
        sub: 'The account will be removed permanently and will no longer be able to sign in.'
      }) +
      '<div class="card card-danger">' +
        '<div class="danger-head">' +
          '<span class="danger-icon" aria-hidden="true">&#128465;</span>' +
          '<div><h2 class="danger-title">This action cannot be undone</h2>' +
          '<p class="danger-text">Please review the account details below before you continue.</p></div>' +
        '</div>' +
        warning +
        '<dl class="detail-list">' +
          '<div><dt>Full name</dt><dd>' + esc(user.name) + '</dd></div>' +
          '<div><dt>Email address</dt><dd>' + esc(user.email) + '</dd></div>' +
          '<div><dt>Access level</dt><dd>' + App.UI.rolePill(user.role) + '</dd></div>' +
          '<div><dt>Registered on</dt><dd>' + esc(App.UI.formatDateLong(user.createdAt)) + '</dd></div>' +
          '<div><dt>Reports owned</dt><dd>' + stats.total + '</dd></div>' +
        '</dl>' +
        '<div class="form-actions form-actions-split">' +
          '<button class="btn btn-danger" type="button" data-confirm-user-delete>Yes, delete this account</button>' +
          '<a class="btn btn-ghost" href="#/users">Cancel, keep the account</a>' +
        '</div>' +
      '</div>' +
    '</section>';

    return {
      html: html,
      title: 'Confirm account deletion',
      nav: 'users',
      user: admin,
      onMount: function (root) {
        var button = root.querySelector('[data-confirm-user-delete]');
        button.addEventListener('click', function () {
          if (user.role === 'admin' && App.Store.activeAdminCount() <= 1) {
            return App.UI.toast('You cannot delete the last active administrator account.', 'error');
          }
          App.UI.confirmDialog({
            title: 'Delete this account?',
            message: user.name + ' (' + user.email + ') will be permanently removed' +
                     (stats.total ? ', together with ' + stats.total + ' report(s)' : '') + '.',
            confirmLabel: 'Yes, delete'
          }).then(function (ok) {
            if (!ok) return;
            var name = user.name;
            var owned = App.Store.allComplaints().filter(function (c) { return c.reporterId === user.id; });
            owned.forEach(function (c) { App.Store.deleteComplaint(c.id); });
            App.Store.deleteUser(user.id);
            App.Store.logActivity('user_delete', admin.id, 'Deleted ' + name + ' and ' + owned.length + ' report(s)');
            App.Layout.setFlash('Account for ' + name + ' deleted, together with ' + owned.length + ' report(s).', 'success');
            App.Router.go('/users');
          });
        });
      }
    };
  }

  App.Views = App.Views || {};
  App.Views.userList = userList;
  App.Views.userCreate = userCreate;
  App.Views.userDelete = userDelete;
})(window.App);