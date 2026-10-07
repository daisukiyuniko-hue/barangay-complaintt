/* ==========================================================================
   Barangay Complaint & Concern Reporting System - front-end behaviour
   Progressive enhancement only: every page still works without JavaScript.
   ========================================================================== */
(function () {
  'use strict';

  /* ------------------------------------------------- mobile navigation --- */
  function initNav() {
    var toggle = document.querySelector('[data-nav-toggle]');
    var panel = document.querySelector('[data-nav-panel]');
    if (!toggle || !panel) return;

    toggle.addEventListener('click', function () {
      var open = panel.classList.toggle('is-open');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });

    // Close the menu when a link is used, or when tapping outside it.
    panel.addEventListener('click', function (e) {
      if (e.target.tagName === 'A' && window.innerWidth < 940) {
        panel.classList.remove('is-open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });

    document.addEventListener('click', function (e) {
      if (!panel.classList.contains('is-open')) return;
      if (panel.contains(e.target) || toggle.contains(e.target)) return;
      panel.classList.remove('is-open');
      toggle.setAttribute('aria-expanded', 'false');
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && panel.classList.contains('is-open')) {
        panel.classList.remove('is-open');
        toggle.setAttribute('aria-expanded', 'false');
        toggle.focus();
      }
    });
  }

  /* ---------------------------------------------- password show / hide --- */
  function initPasswordToggles() {
    document.querySelectorAll('[data-password-toggle]').forEach(function (btn) {
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

  /* -------------------------------------------------- password strength -- */
  function initStrength() {
    var inputs = document.querySelectorAll('[data-strength-input]');
    inputs.forEach(function (input) {
      var form = input.closest('form') || document;
      var meter = form.querySelector('[data-strength-meter]');
      if (!meter) return;
      var fill = meter.querySelector('[data-strength-fill]');
      var label = meter.querySelector('[data-strength-label]');
      var confirm = document.getElementById('passwordConfirm');

      function score(value) {
        if (!value) return 0;
        var s = 0;
        if (value.length >= 8) s++;
        if (value.length >= 12) s++;
        if (/[a-z]/.test(value) && /[A-Z]/.test(value)) s++;
        if (/[0-9]/.test(value)) s++;
        if (/[^A-Za-z0-9]/.test(value)) s++;
        return Math.min(s, 4);
      }

      function update() {
        var value = input.value;
        meter.hidden = value.length === 0;
        var s = score(value);
        meter.classList.remove('is-weak', 'is-fair', 'is-good', 'is-strong');
        var pct = 0;
        if (s <= 1) { meter.classList.add('is-weak');   pct = 25; label.textContent = 'Strength: weak'; }
        else if (s === 2) { meter.classList.add('is-fair');  pct = 50; label.textContent = 'Strength: fair'; }
        else if (s === 3) { meter.classList.add('is-good');  pct = 75; label.textContent = 'Strength: good'; }
        else if (s === 4) { meter.classList.add('is-strong'); pct = 100; label.textContent = 'Strength: strong'; }
        fill.style.width = pct + '%';

        // Tick off the checklist live.
        form.querySelectorAll('[data-rule]').forEach(function (li) {
          var rule = li.getAttribute('data-rule');
          var ok =
            rule === 'length' ? value.length >= 8 :
            rule === 'letter' ? /[A-Za-z]/.test(value) :
            rule === 'number' ? /[0-9]/.test(value) :
            rule === 'symbol' ? /[^A-Za-z0-9]/.test(value) : false;
          li.classList.toggle('is-met', !!value && ok);
        });

        // Live "do the passwords match" hint.
        if (confirm) {
          var box = form.querySelector('[data-match-error]');
          if (box) {
            var mismatch = confirm.value.length > 0 && confirm.value !== value;
            box.hidden = !mismatch;
            confirm.classList.toggle('is-invalid', mismatch);
          }
        }
      }

      input.addEventListener('input', update);
      if (confirm) confirm.addEventListener('input', update);
      update();
    });
  }

  /* ------------------------------------------------ character counting --- */
  function initCharCount() {
    document.querySelectorAll('[data-char-count]').forEach(function (area) {
      var form = area.closest('form') || document;
      var out = form.querySelector('[data-char-current]');
      if (!out) return;
      var update = function () { out.textContent = String(area.value.length); };
      area.addEventListener('input', update);
      update();
    });
  }

  /* --------------------------------------------------- delete confirms --- */
  function initConfirm() {
    // Inline destructive actions get an extra browser-level confirmation.
    document.querySelectorAll('[data-confirm]').forEach(function (el) {
      el.addEventListener('click', function (e) {
        if (!window.confirm(el.getAttribute('data-confirm'))) {
          e.preventDefault();
          e.stopPropagation();
        }
      });
    });
    document.querySelectorAll('[data-confirm-link]').forEach(function (el) {
      el.addEventListener('click', function (e) {
        if (!window.confirm(el.getAttribute('data-confirm-link'))) e.preventDefault();
      });
    });
  }

  /* ------------------------------------------------------- flash close --- */
  function initFlash() {
    document.querySelectorAll('[data-flash]').forEach(function (flash) {
      var close = flash.querySelector('[data-dismiss-flash]');
      if (close) close.addEventListener('click', function () { flash.remove(); });
    });
  }

  /* --------------------------------------------------- auto-submit form -- */
  function initAutoSubmit() {
    document.querySelectorAll('[data-auto-submit]').forEach(function (form) {
      form.querySelectorAll('select').forEach(function (sel) {
        sel.addEventListener('change', function () { form.submit(); });
      });
    });
  }

  /* ------------------------------------------------- demo credentials ---- */
  var DEMO_ACCOUNTS = {
    admin:    { name: 'Maria Dela Cruz',   email: 'admin@barangay.gov.ph',    password: 'Admin@12345',    phone: '0917 000 0001', address: 'Barangay Hall, Purok 3' },
    resident: { name: 'Juan Dela Cruz',    email: 'resident@barangay.gov.ph', password: 'Resident@12345', phone: '0918 123 4567', address: 'Purok 5, San Isidro' }
  };

  function initDemoFill() {
    document.querySelectorAll('[data-fill-demo]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var form = btn.closest('form');
        if (!form) return;
        // The register page creates residents, so use the resident account.
        var demo = DEMO_ACCOUNTS.resident;
        var name = form.querySelector('[name="name"]');
        var email = form.querySelector('[name="email"]');
        var phone = form.querySelector('[name="phone"]');
        var address = form.querySelector('[name="address"]');
        var pw = form.querySelector('[name="password"]');
        var pw2 = form.querySelector('[name="passwordConfirm"]');
        if (name) name.value = demo.name;
        if (email) email.value = demo.email;
        if (phone) phone.value = demo.phone;
        if (address) address.value = demo.address;
        if (pw) { pw.value = demo.password; pw.dispatchEvent(new Event('input')); }
        if (pw2) { pw2.value = demo.password; pw2.dispatchEvent(new Event('input')); }
      });
    });
  }

  /* ------------------------------------------------- client-side checks -- */
  function initValidation() {
    document.querySelectorAll('form[novalidate]').forEach(function (form) {
      form.addEventListener('submit', function (e) {
        var firstBad = null;

        form.querySelectorAll('input[required], select[required], textarea[required]').forEach(function (el) {
          var bad = el.type === 'checkbox' ? !el.checked : !el.value.trim();
          el.classList.toggle('is-invalid', bad);
          if (bad && !firstBad) firstBad = el;
        });

        if (firstBad) {
          e.preventDefault();
          firstBad.focus();
          firstBad.scrollIntoView({ behavior: 'smooth', block: 'center' });
          if (typeof firstBad.reportValidity === 'function' && firstBad.type !== 'checkbox') {
            // Let the browser show its own message too.
          }
          return;
        }

        // Never allow a double submit.
        var submit = form.querySelector('button[type="submit"]');
        if (submit && !form.hasAttribute('data-no-lock')) {
          submit.disabled = true;
          submit.dataset.originalText = submit.textContent;
          submit.textContent = 'Please wait...';
          window.setTimeout(function () {
            submit.disabled = false;
            submit.textContent = submit.dataset.originalText;
          }, 6000);
        }
      });
    });
  }

  /* ------------------------------------------------------------- start --- */
  function init() {
    initNav();
    initPasswordToggles();
    initStrength();
    initCharCount();
    initConfirm();
    initFlash();
    initAutoSubmit();
    initDemoFill();
    initValidation();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
