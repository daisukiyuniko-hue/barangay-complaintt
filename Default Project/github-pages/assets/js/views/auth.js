/* ==========================================================================
   views/auth.js - sign in, register, profile and password change
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var esc = App.UI.esc;

  // ------------------------------------------------------------------ login --
  function login(ctx) {
    if (ctx.user) {
      App.Router.go('/dashboard', { replace: true });
      return { html: '', title: 'Redirecting', nav: '' };
    }

    var next = ctx.query['next'] || '';
    if (next && next.charAt(0) !== '/') next = '';      // same-site only
    if (next && next.charAt(0, 2) === '//') next = '';  // no protocol-relative

    var values = ctx.form || {};
    var errors = ctx.errors || {};

    var html = '<section class="auth-shell"><div class="auth-card">' +
      '<div class="auth-head">' +
        '<img class="brand-mark brand-mark-lg" src="assets/img/logo.svg" width="64" height="64" alt="">' +
        '<p class="page-eyebrow">Barangay San Isidro</p>' +
        '<h1 class="auth-title">Sign in</h1>' +
        '<p class="auth-sub">Access your dashboard to submit and track your reports.</p>' +
      '</div>' +
      App.UI.errorSummary(errors) +
      '<form id="loginForm" class="form-stack" novalidate>' +
        (next ? '<input type="hidden" name="next" value="' + esc(next) + '">' : '') +
        field('Email address', 'email', 'email', 'you@example.com', values.email, errors, 'email') +
        '<div class="field">' +
          '<div class="field-head"><label for="loginPassword">Password</label>' +
          '<a class="field-hint-link" href="#/#faq">Forgot password?</a></div>' +
          '<div class="password-field">' +
            '<input type="password" id="loginPassword" name="password" autocomplete="current-password" ' +
              'placeholder="Your password" required data-password-input' + App.UI.invalidClass(errors, 'password') + '>' +
            '<button type="button" class="password-toggle" data-password-toggle="loginPassword">Show</button>' +
          '</div>' +
          App.UI.fieldError(errors, 'password') +
        '</div>' +
        '<button class="btn btn-primary btn-block" type="submit" data-submit>Sign in</button>' +
      '</form>' +
      '<p class="auth-alt">New to the system? <a href="#/register">Create a resident account</a></p>' +
      '<div class="demo-box">' +
        '<p class="demo-title">Demo accounts</p>' +
        '<table class="demo-table"><thead><tr><th>Role</th><th>Email</th><th>Password</th></tr></thead><tbody>' +
          '<tr><td data-label="Role">' + App.UI.rolePill('admin') + '</td>' +
            '<td data-label="Email"><code>admin@barangay.gov.ph</code></td>' +
            '<td data-label="Password"><code>Admin@12345</code></td></tr>' +
          '<tr><td data-label="Role">' + App.UI.rolePill('resident') + '</td>' +
            '<td data-label="Email"><code>resident@barangay.gov.ph</code></td>' +
            '<td data-label="Password"><code>Resident@12345</code></td></tr>' +
        '</tbody></table>' +
        '<p class="demo-hint">Passwords are stored only as salted PBKDF2 hashes.</p>' +
      '</div>' +
    '</div></section>';

    return {
      html: html,
      title: 'Sign in',
      nav: '',
      onMount: function (root) { wireLogin(root, next); }
    };
  }

  function field(label, name, type, placeholder, value, errors, key) {
    return '<div class="field"><label for="' + esc(name) + '">' + esc(label) + '</label>' +
      '<input type="' + esc(type) + '" id="' + esc(name) + '" name="' + esc(name) + '" ' +
      'placeholder="' + esc(placeholder) + '" required' +
      ' value="' + esc(value || '') + '"' + App.UI.invalidClass(errors, key) + '>' +
      App.UI.fieldError(errors, key) + '</div>';
  }

  function wireLogin(root, next) {
    var form = root.querySelector('#loginForm');
    if (!form) return;

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var data = {
        email: form.querySelector('[name=email]').value.trim(),
        password: form.querySelector('[name=password]').value
      };
      var errors = {};
      if (!data.email) errors.email = 'Please enter your email address.';
      if (!data.password) errors.password = 'Please enter your password.';

      if (Object.keys(errors).length) {
        return reRender({ errors: errors, values: data }, next);
      }

      var button = form.querySelector('[data-submit]');
      button.disabled = true;
      button.textContent = 'Signing in...';

      App.Auth.login(data.email, data.password).then(function (result) {
        if (result.ok) {
          App.Layout.setFlash('Welcome back, ' + result.user.name + '!', 'success');
          App.Router.go(next || '/dashboard', { replace: true });
        } else {
          var errs = {};
          errs[result.field] = result.message;
          reRender({ errors: errs, values: data }, next);
        }
      });
    });
  }

  function reRender(state, next) {
    App.Layout.setFlash(null, null);
    App.Router.render(App.Views.login({
      user: null,
      query: next ? { next: next } : {},
      errors: state.errors,
      form: state.values
    }));
    App.Layout.renderFlash(null);
  }

  // --------------------------------------------------------------- register --
  function register(ctx) {
    if (ctx.user) {
      App.Router.go('/dashboard', { replace: true });
      return { html: '', title: 'Redirecting', nav: '' };
    }

    var errors = ctx.errors || {};
    var values = ctx.form || {};

    var categoryRules = App.Store.CATEGORIES.map(function (c) {
      return '<li><strong>' + esc(c.value) + '</strong> &mdash; ' + esc(c.hint) + '</li>';
    }).join('');
    var priorityRules = App.Store.PRIORITIES.map(function (p) {
      return '<li><strong>' + esc(p.value) + '</strong> &mdash; ' + esc(p.hint) + '</li>';
    }).join('');

    var engine = App.Crypto.engine();

    var html = '<section class="auth-shell"><div class="auth-card auth-card-lg">' +
      '<div class="auth-head">' +
        '<img class="brand-mark brand-mark-lg" src="assets/img/logo.svg" width="64" height="64" alt="">' +
        '<p class="page-eyebrow">Resident registration</p>' +
        '<h1 class="auth-title">Create your account</h1>' +
        '<p class="auth-sub">Register once and you can submit and follow up on every report you file with the barangay.</p>' +
      '</div>' +
      App.UI.errorSummary(errors) +
      '<form id="registerForm" class="form-stack" novalidate>' +
        '<div class="field"><label for="name">Full name <span class="req">*</span></label>' +
          '<input type="text" id="name" name="name" autocomplete="name" maxlength="80" ' +
          'placeholder="Juan Dela Cruz" required value="' + esc(values.name || '') + '"' +
          App.UI.invalidClass(errors, 'name') + '>' + App.UI.fieldError(errors, 'name') + '</div>' +

        '<div class="field"><label for="email">Email address <span class="req">*</span></label>' +
          '<input type="email" id="email" name="email" autocomplete="email" maxlength="190" ' +
          'placeholder="you@example.com" required value="' + esc(values.email || '') + '"' +
          App.UI.invalidClass(errors, 'email') + '>' +
          '<p class="field-hint">Your email is your username.</p>' +
          App.UI.fieldError(errors, 'email') + '</div>' +

        '<div class="field"><label for="phone">Mobile number <span class="optional">optional</span></label>' +
          '<input type="tel" id="phone" name="phone" autocomplete="tel" maxlength="20" ' +
          'placeholder="0917 123 4567" value="' + esc(values.phone || '') + '"' +
          App.UI.invalidClass(errors, 'phone') + '>' + App.UI.fieldError(errors, 'phone') + '</div>' +

        '<div class="field"><label for="address">Home address / purok <span class="optional">optional</span></label>' +
          '<input type="text" id="address" name="address" autocomplete="street-address" maxlength="160" ' +
          'placeholder="Purok 5, San Isidro" value="' + esc(values.address || '') + '">' +
          App.UI.fieldError(errors, 'address') + '</div>' +

        '<div class="field"><label for="password">Password <span class="req">*</span></label>' +
          '<div class="password-field">' +
            '<input type="password" id="password" name="password" autocomplete="new-password" ' +
            'maxlength="128" placeholder="Create a strong password" required ' +
            'data-password-input data-strength-input' + App.UI.invalidClass(errors, 'password') + '>' +
            '<button type="button" class="password-toggle" data-password-toggle="password">Show</button>' +
          '</div>' +
          strengthMeterHtml() +
          '<ul class="rule-list">' +
            '<li data-rule="length">At least 8 characters</li>' +
            '<li data-rule="letter">Contains a letter</li>' +
            '<li data-rule="number">Contains a number</li>' +
            '<li data-rule="symbol">Contains a special character</li>' +
          '</ul>' +
          App.UI.fieldError(errors, 'password') + '</div>' +

        '<div class="field"><label for="passwordConfirm">Confirm password <span class="req">*</span></label>' +
          '<div class="password-field">' +
            '<input type="password" id="passwordConfirm" name="passwordConfirm" autocomplete="new-password" ' +
            'required data-password-input>' +
            '<button type="button" class="password-toggle" data-password-toggle="passwordConfirm">Show</button>' +
          '</div>' +
          '<p class="field-error" data-match-error hidden>The two passwords do not match.</p></div>' +

        '<label class="checkbox"><input type="checkbox" name="agree" value="yes" required>' +
          '<span>I confirm that the details I entered are correct.</span></label>' +

        '<button class="btn btn-primary btn-block" type="submit" data-submit>Create account</button>' +
        '<button class="btn btn-ghost btn-block" type="button" data-fill-demo>Fill demo credentials</button>' +
      '</form>' +

      '<p class="auth-alt">Already registered? <a href="#/login">Sign in instead</a></p>' +

      '<div class="demo-box">' +
        '<p class="demo-title">How your password is protected</p>' +
        '<p class="demo-hint">' + esc(engine.algorithm) + ' with ' + esc(String(engine.iterations)) +
          ' rounds and a random 16-byte salt per account. Plain text is never stored.' +
          (engine.strong ? '' : ' <strong>Heads up:</strong> this page is not in a secure context, so the built-in JavaScript implementation is used with fewer rounds.') +
        '</p>' +
      '</div>' +
    '</div></section>';

    return {
      html: html,
      title: 'Create an account',
      nav: '',
      onMount: function (root) { wireRegister(root, strengthMeterHtml()); }
    };
  }

  function strengthMeterHtml() {
    return '<div class="strength" data-strength-meter hidden>' +
      '<div class="strength-bar"><span data-strength-fill></span></div>' +
      '<p class="strength-label" data-strength-label>Strength: -</p></div>';
  }

  function wireRegister(root) {
    var form = root.querySelector('#registerForm');
    if (!form) return;

    wireStrength(form);

    form.addEventListener('submit', function (e) {
      e.preventDefault();

      var data = {
        name: form.querySelector('[name=name]').value,
        email: form.querySelector('[name=email]').value,
        phone: form.querySelector('[name=phone]').value,
        address: form.querySelector('[name=address]').value,
        password: form.querySelector('[name=password]').value
      };
      var confirm = form.querySelector('[name=passwordConfirm]').value;
      var agreed = form.querySelector('[name=agree]').checked;

      var result = App.Validate.validateRegistration(data, 'register');
      var errors = result.errors;

      if (!errors.passwordConfirm && confirm !== data.password) {
        errors.passwordConfirm = 'The two passwords do not match.';
      }
      if (!agreed) {
        errors.agree = 'Please tick the confirmation box before creating your account.';
      }

      if (Object.keys(errors).length) {
        App.Router.render(App.Views.register({
          user: null, query: {}, errors: errors, form: result.values
        }));
        App.Layout.renderFlash(null);
        return;
      }

      var button = form.querySelector('[data-submit]');
      button.disabled = true;
      button.textContent = 'Creating your account...';

      App.Auth.createUser({
        name: result.values.name,
        email: result.values.email,
        phone: result.values.phone,
        address: result.values.address,
        password: result.values.password,
        role: 'resident'
      }).then(function (user) {
        // Sign the new account in straight away so they are not bounced back
        // to the login page after registering.
        App.Auth.signIn(user);
        App.Layout.setFlash('Welcome, ' + user.name + '. Your account is ready.', 'success');
        App.Router.go('/dashboard', { replace: true });
      }).catch(function (error) {
        console.error(error);
        App.Layout.setFlash('Something went wrong while creating your account. Please try again.', 'error');
        App.Router.go('/register');
      });
    });

    var demoBtn = form.querySelector('[data-fill-demo]');
    if (demoBtn) {
      demoBtn.addEventListener('click', function () {
        form.querySelector('[name=name]').value = 'Juan Dela Cruz';
        form.querySelector('[name=email]').value = 'resident@barangay.gov.ph';
        form.querySelector('[name=phone]').value = '0918 123 4567';
        form.querySelector('[name=address]').value = 'Purok 5, San Isidro';
        var pw = form.querySelector('[name=password]');
        pw.value = 'Resident@12345';
        pw.dispatchEvent(new Event('input'));
        form.querySelector('[name=passwordConfirm]').value = 'Resident@12345';
        form.querySelector('[name=agree]').checked = true;
      });
    }
  }

  /** Live strength meter + rule checklist, shared by register and change-password. */
  function wireStrength(form) {
    var pw = form.querySelector('[data-strength-input]');
    var confirmInput = form.querySelector('[name=passwordConfirm]') || form.querySelector('[name=confirmPassword]');
    if (!pw) return;

    var meter = form.querySelector('[data-strength-meter]');
    var fill = form.querySelector('[data-strength-fill]');
    var label = form.querySelector('[data-strength-label]');

    function update() {
      var value = pw.value;
      if (meter) {
        meter.hidden = value.length === 0;
        var score = App.Validate.passwordScore(value);
        meter.classList.remove('is-weak', 'is-fair', 'is-good', 'is-strong');
        var pct = 0;
        if (score <= 1) { meter.classList.add('is-weak'); pct = 25; label.textContent = 'Strength: weak'; }
        else if (score === 2) { meter.classList.add('is-fair'); pct = 50; label.textContent = 'Strength: fair'; }
        else if (score === 3) { meter.classList.add('is-good'); pct = 75; label.textContent = 'Strength: good'; }
        else { meter.classList.add('is-strong'); pct = 100; label.textContent = 'Strength: strong'; }
        fill.style.width = pct + '%';
      }

      form.querySelectorAll('[data-rule]').forEach(function (li) {
        var rule = li.getAttribute('data-rule');
        var ok =
          rule === 'length' ? value.length >= 8 :
          rule === 'letter' ? /[A-Za-z]/.test(value) :
          rule === 'number' ? /[0-9]/.test(value) :
          rule === 'symbol' ? /[^A-Za-z0-9]/.test(value) : false;
        li.classList.toggle('is-met', !!value && ok);
      });

      if (confirmInput) {
        var box = form.querySelector('[data-match-error]');
        if (box) {
          var mismatch = confirmInput.value.length > 0 && confirmInput.value !== value;
          box.hidden = !mismatch;
          confirmInput.classList.toggle('is-invalid', mismatch);
        }
      }
    }

    pw.addEventListener('input', update);
    if (confirmInput) confirmInput.addEventListener('input', update);
    update();
  }

  // ---------------------------------------------------------------- profile --
  function profile(ctx) {
    var user = ctx.user;
    var errors = ctx.errors || {};
    var values = ctx.form || {};
    var C = App.Layout.CONFIG;

    var stats = App.Store.statsFor(user.id);
    var joined = App.UI.formatDateLong(user.createdAt);
    var lastLogin = user.lastLoginAt ? App.UI.formatDate(user.lastLoginAt, true) : 'This is your first sign-in';

    var html = '<section class="container section">' +
      App.UI.pageIntro({
        eyebrow: 'My account',
        heading: 'Profile and security',
        sub: 'Keep your contact details current so the barangay can reach you about your reports.'
      }) +
      App.UI.errorSummary(errors) +
      '<div class="split-grid">' +
        '<div class="card">' +
          '<div class="card-head"><h2 class="card-title">Personal information</h2>' + App.UI.rolePill(user.role) + '</div>' +
          '<form id="profileForm" class="form-stack" novalidate>' +
            '<div class="field"><label for="name">Full name</label>' +
              '<input type="text" id="name" name="name" maxlength="80" required ' +
              'value="' + esc(values.name !== undefined ? values.name : user.name) + '"' +
              App.UI.invalidClass(errors, 'name') + '>' + App.UI.fieldError(errors, 'name') + '</div>' +
            '<div class="field"><label for="email">Email address</label>' +
              '<input type="email" id="email" name="email" maxlength="190" required ' +
              'value="' + esc(values.email !== undefined ? values.email : user.email) + '"' +
              App.UI.invalidClass(errors, 'email') + '>' + App.UI.fieldError(errors, 'email') + '</div>' +
            '<div class="field"><label for="phone">Mobile number <span class="optional">optional</span></label>' +
              '<input type="tel" id="phone" name="phone" maxlength="20" value="' +
              esc(values.phone !== undefined ? values.phone : user.phone) + '">' +
              App.UI.fieldError(errors, 'phone') + '</div>' +
            '<div class="field"><label for="address">Home address / purok <span class="optional">optional</span></label>' +
              '<input type="text" id="address" name="address" maxlength="160" value="' +
              esc(values.address !== undefined ? values.address : user.address) + '"></div>' +
            '<div class="form-actions">' +
              '<button class="btn btn-primary" type="submit" data-submit>Save changes</button>' +
              '<a class="btn btn-ghost" href="#/dashboard">Cancel</a>' +
            '</div>' +
          '</form>' +
        '</div>' +
        '<div class="side-stack">' +
          '<div class="card card-flush">' +
            '<div class="card-head"><h2 class="card-title">Account summary</h2></div>' +
            '<dl class="detail-list">' +
              '<div><dt>Account type</dt><dd>' + App.UI.rolePill(user.role) + '</dd></div>' +
              '<div><dt>Member since</dt><dd>' + esc(joined) + '</dd></div>' +
              '<div><dt>Last sign-in</dt><dd>' + esc(lastLogin) + '</dd></div>' +
              '<div><dt>Reports filed</dt><dd>' + stats.total + '</dd></div>' +
              '<div><dt>Resolved</dt><dd>' + stats.resolved + '</dd></div>' +
            '</dl>' +
          '</div>' +
          '<div class="card">' +
            '<div class="card-head"><h2 class="card-title">Password</h2></div>' +
            '<p class="card-text">Your password is stored as a salted PBKDF2-HMAC-SHA256 hash. Plain text is never written to storage.</p>' +
            '<a class="btn btn-outline btn-block" href="#/profile/password">Change password</a>' +
          '</div>' +
          '<div class="card">' +
            '<div class="card-head"><h2 class="card-title">Your data</h2></div>' +
            '<p class="card-text">This site is static, so your reports live in this browser. Export a backup before clearing your browsing data.</p>' +
            '<a class="btn btn-outline btn-block" href="#/data">Manage stored data</a>' +
          '</div>' +
        '</div>' +
      '</div>' +
    '</section>';

    return {
      html: html,
      title: 'My profile',
      nav: 'profile',
      user: user,
      onMount: function (root) {
        var form = root.querySelector('#profileForm');
        form.addEventListener('submit', function (e) {
          e.preventDefault();
          var data = {
            name: form.querySelector('[name=name]').value,
            email: form.querySelector('[name=email]').value,
            phone: form.querySelector('[name=phone]').value,
            address: form.querySelector('[name=address]').value,
            userId: user.id
          };
          var result = App.Validate.validateRegistration(data, 'profile');
          if (Object.keys(result.errors).length) {
            App.Router.render(App.Views.profile({ user: user, errors: result.errors, form: result.values }));
            App.Layout.renderFlash(null);
            return;
          }
          user.name = result.values.name;
          user.email = result.values.email.toLowerCase();
          user.phone = result.values.phone;
          user.address = result.values.address;
          user.updatedAt = new Date().toISOString();
          App.Store.putUser(user);
          App.Store.logActivity('profile_update', user.id, 'Updated own profile details');
          App.Auth.refresh();
          App.Layout.setFlash('Your profile has been updated.', 'success');
          App.Router.render(App.Views.profile({ user: user }));
        });
      }
    };
  }

  // --------------------------------------------------------- change password --
  function changePassword(ctx) {
    var user = ctx.user;
    var errors = ctx.errors || {};

    var html = '<section class="container section-narrow">' +
      '<nav class="breadcrumb"><a href="#/profile">&larr; Back to profile</a></nav>' +
      App.UI.pageIntro({
        eyebrow: 'Security',
        heading: 'Change your password',
        sub: 'Choose a new password that is different from your current one.'
      }) +
      App.UI.errorSummary(errors) +
      '<div class="card"><form id="pwForm" class="form-stack" novalidate>' +
        '<div class="field"><label for="currentPassword">Current password</label>' +
          '<div class="password-field">' +
            '<input type="password" id="currentPassword" name="currentPassword" ' +
            'autocomplete="current-password" required data-password-input' +
            App.UI.invalidClass(errors, 'currentPassword') + '>' +
            '<button type="button" class="password-toggle" data-password-toggle="currentPassword">Show</button>' +
          '</div>' + App.UI.fieldError(errors, 'currentPassword') + '</div>' +

        '<div class="field"><label for="newPassword">New password</label>' +
          '<div class="password-field">' +
            '<input type="password" id="newPassword" name="newPassword" autocomplete="new-password" ' +
            'maxlength="128" required data-password-input data-strength-input' +
            App.UI.invalidClass(errors, 'newPassword') + '>' +
            '<button type="button" class="password-toggle" data-password-toggle="newPassword">Show</button>' +
          '</div>' +
          strengthMeterHtml() +
          '<ul class="rule-list">' +
            '<li data-rule="length">At least 8 characters</li>' +
            '<li data-rule="letter">Contains a letter</li>' +
            '<li data-rule="number">Contains a number</li>' +
            '<li data-rule="symbol">Contains a special character</li>' +
          '</ul>' +
          App.UI.fieldError(errors, 'newPassword') + '</div>' +

        '<div class="field"><label for="confirmPassword">Confirm new password</label>' +
          '<div class="password-field">' +
            '<input type="password" id="confirmPassword" name="confirmPassword" ' +
            'autocomplete="new-password" required>' +
            '<button type="button" class="password-toggle" data-password-toggle="confirmPassword">Show</button>' +
          '</div>' +
          '<p class="field-error" data-match-error hidden>The two passwords do not match.</p></div>' +

        '<div class="form-actions">' +
          '<button class="btn btn-primary" type="submit" data-submit>Update password</button>' +
          '<a class="btn btn-ghost" href="#/profile">Cancel</a>' +
        '</div>' +
      '</form></div>' +
    '</section>';

    return {
      html: html,
      title: 'Change password',
      nav: 'profile',
      user: user,
      onMount: function (root) {
        var form = root.querySelector('#pwForm');
        wireStrength(form);

        form.addEventListener('submit', function (e) {
          e.preventDefault();
          var current = form.querySelector('[name=currentPassword]').value;
          var next = form.querySelector('[name=newPassword]').value;
          var confirm = form.querySelector('[name=confirmPassword]').value;

          App.Crypto.verifyPassword(current, user).then(function (ok) {
            var errors = {};
            if (!ok) errors.currentPassword = 'Your current password is incorrect.';

            var policy = App.Validate.passwordPolicy(next);
            if (policy) errors.newPassword = policy;
            else if (next === current) errors.newPassword = 'Your new password must be different from your current password.';

            if (!confirm) errors.confirmPassword = 'Please type your new password again.';
            else if (confirm !== next) errors.confirmPassword = 'The two passwords do not match.';

            if (Object.keys(errors).length) {
              App.Router.render(App.Views.changePassword({ user: user, errors: errors }));
              App.Layout.renderFlash(null);
              return;
            }

            var button = form.querySelector('[data-submit]');
            button.disabled = true;
            button.textContent = 'Updating...';

            App.Auth.setPassword(user, next).then(function () {
              App.Store.logActivity('password_change', user.id, 'Changed own password');
              App.Layout.setFlash('Your password has been changed.', 'success');
              App.Router.render(App.Views.profile({ user: App.Auth.refresh() }));
            });
          });
        });
      }
    };
  }

  App.Views = App.Views || {};
  App.Views.login = login;
  App.Views.register = register;
  App.Views.profile = profile;
  App.Views.changePassword = changePassword;
  App.Views.wireStrength = wireStrength;
  App.Views.strengthMeterHtml = strengthMeterHtml;
})(window.App);