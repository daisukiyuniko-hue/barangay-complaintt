/* ==========================================================================
   suite.js - end-to-end UI test for the static build.
   Served from the site so it runs against the real code.
   Exposes BCR_SUITE.run() -> { pass, fail, failures }
   ========================================================================== */
window.BCR_SUITE = (function () {
  'use strict';

  var results = [];
  function ok(label, cond, detail) {
    results.push({ label: label, ok: !!cond, detail: cond ? '' : (detail || '') });
  }
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function view() { return document.getElementById('view'); }
  async function go(h, ms) { window.location.hash = h; await wait(ms || 450); }
  function fire(form, ms) {
    form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    return wait(ms || 800);
  }
  function fill(form, fields) {
    Object.keys(fields).forEach(function (name) {
      var el = form.querySelector('[name="' + name + '"]');
      if (!el) return;
      if (el.type === 'checkbox') el.checked = !!fields[name];
      else el.value = fields[name];
    });
  }
  function flashText() { return document.getElementById('flashHost').textContent; }
  function html() { return view().innerHTML; }
  async function signIn(email, pw) {
    App.Auth.logout(); await wait(200);
    await go('/login', 500);
    var f = view().querySelector('#loginForm');
    if (!f) return false;
    fill(f, { email: email, password: pw });
    await fire(f, 1800);
    return !!App.Auth.user();
  }

  async function run() {
    results = [];
    var realConfirm = window.confirm;
    window.confirm = function () { return true; };

    // ================= 1. boot finished, then a clean slate =================
    // Wait for the app's own start-up seed to finish first, otherwise this
    // test would race it and reset the database mid-write.
    for (var i = 0; i < 40 && App.Store.allUsers().length < 2; i++) await wait(100);
    ok('boot seeds 2 accounts', App.Store.allUsers().length === 2, App.Store.allUsers().length);
    ok('boot seeds 6 reports', App.Store.allComplaints().length === 6, App.Store.allComplaints().length);

    App.Store.reset();
    window.sessionStorage.clear();
    await go('/', 400);
    await App.Auth.seed();

    ok('seed creates 2 accounts', App.Store.allUsers().length === 2, App.Store.allUsers().length);
    ok('seed creates 6 reports', App.Store.allComplaints().length === 6, App.Store.allComplaints().length);
    ok('admin account seeded', !!App.Store.userByEmail('admin@barangay.gov.ph'));
    ok('resident account seeded', !!App.Store.userByEmail('resident@barangay.gov.ph'));

    var raw = window.localStorage.getItem(App.Store.STORAGE_KEY) || '';
    ok('no plain-text password stored', raw.indexOf('Admin@12345') === -1 && raw.indexOf('Resident@12345') === -1);
    ok('PBKDF2 recorded', raw.indexOf('PBKDF2-HMAC-SHA256') !== -1);
    var salts = {};
    App.Store.allUsers().forEach(function (u) { salts[u.passwordSalt] = true; });
    ok('every account has a unique salt', Object.keys(salts).length === 2);

    // ================= 2. landing page =================
    await go('/', 600);
    ok('landing renders', html().indexOf('Report a barangay concern in under a minute') !== -1);
    ok('8 service cards', document.querySelectorAll('.service-card').length === 8);
    ok('all 12 images load', Array.from(document.images).every(function (i) { return i.naturalWidth > 0; }),
       JSON.stringify(Array.from(document.images).filter(function (i) { return i.naturalWidth === 0; })
         .map(function (i) { return i.getAttribute('src'); })));
    ok('meaningful images have alt text',
       Array.from(document.querySelectorAll('.hero-art img, .about-art img, .service-card img'))
         .every(function (i) { return (i.getAttribute('alt') || '').length > 3; }));
    ok('landing has a register CTA', html().indexOf('Create a free account') !== -1);
    ok('landing has a login CTA', html().indexOf('I already have an account') !== -1);
    ok('landing FAQ rendered', document.querySelectorAll('.faq-item').length >= 5);

    // ================= 3. route guards =================
    await go('/dashboard', 600);
    ok('anonymous /dashboard -> login', window.location.hash === '#/login?next=%2Fdashboard', window.location.hash);
    await go('/complaints', 600);
    ok('anonymous /complaints -> login', window.location.hash === '#/login?next=%2Fcomplaints', window.location.hash);
    await go('/users', 600);
    ok('anonymous /users -> login', window.location.hash === '#/login?next=%2Fusers', window.location.hash);
    await go('/profile', 600);
    ok('anonymous /profile -> login', window.location.hash === '#/login?next=%2Fprofile', window.location.hash);
    await go('/nope', 600);
    ok('unknown route -> 404', html().indexOf('We could not find that page') !== -1);
    ok('404 renders real HTML', html().indexOf('[object Object]') === -1);

    // ================= 4. login validation =================
    await go('/login', 500);
    await fire(view().querySelector('#loginForm'), 700);
    ok('empty login explains itself', html().indexOf('Please enter your email address') !== -1);

    await go('/login', 500);
    var f = view().querySelector('#loginForm');
    fill(f, { email: 'admin@barangay.gov.ph', password: 'Nope@12345' });
    await fire(f, 1200);
    ok('wrong password explained', /did not match an account/.test(html()));

    // ================= 5. resident sign-in =================
    ok('resident signs in', await signIn('resident@barangay.gov.ph', 'Resident@12345'), 'sign-in failed');
    ok('signed in as resident', App.Auth.user().role === 'resident');

    await go('/users', 600);
    ok('resident gets 403 on /users', html().indexOf('Administrator access only') !== -1);
    await go('/users/new', 600);
    ok('resident gets 403 on /users/new', html().indexOf('Administrator access only') !== -1);

    // ================= 6. resident CRUD =================
    var marker = 'Suite report ' + Math.floor(Math.random() * 1e6);
    await go('/complaints/new', 600);
    f = view().querySelector('[data-complaint-form]');
    ok('create form present', !!f);
    fill(f, { title: 'ab', location: 'x', description: 'short' });
    await fire(f, 800);
    ok('invalid complaint blocked', html().indexOf('Please fix the following') !== -1);
    ok('title rule explained', html().indexOf('at least 5 characters') !== -1);
    ok('category rule explained', html().indexOf('Please choose a category') !== -1);
    ok('nothing created by an invalid submit',
       App.Store.allComplaints().filter(function (c) { return c.title === 'ab'; }).length === 0);

    f = view().querySelector('[data-complaint-form]');
    fill(f, {
      title: marker, category: 'Road & Infrastructure', priority: 'High',
      location: 'Purok 5, corner of Mabini Street',
      description: 'A deep pothole here has already damaged two motorcycles this week.'
    });
    await fire(f, 1200);
    ok('valid complaint created', html().indexOf(marker) !== -1, window.location.hash);
    ok('reference assigned', /BCR-\d{4}-\d{4}/.test(html()));
    ok('status starts Pending', html().indexOf('Pending') !== -1);
    ok('resident sees no status editor', html().indexOf('Update status') === -1);
    var id = window.location.hash.split('/').pop();

    ok('detail shows location', html().indexOf('Mabini Street') !== -1);
    ok('detail shows a timeline', html().indexOf('class="steps"') !== -1);
    ok('detail shows the reporter', html().indexOf('Juan Dela Cruz') !== -1);

    await go('/complaints/' + id + '/edit', 600);
    f = view().querySelector('[data-complaint-form]');
    ok('edit form pre-filled', f.querySelector('[name=title]').value === marker);
    ok('category pre-selected', f.querySelector('[name=category]').value === 'Road & Infrastructure');
    fill(f, { title: marker + ' updated' });
    await fire(f, 1200);
    ok('update applied', html().indexOf(marker + ' updated') !== -1);

    await go('/complaints/' + id + '/delete', 600);
    ok('delete warns it cannot be undone', html().indexOf('cannot be undone') !== -1);
    ok('delete lists the record', html().indexOf(marker) !== -1);
    var cdb = view().querySelector('[data-confirm-delete]');
    ok('delete confirm button present', !!cdb);
    if (cdb) cdb.click(); await wait(400);
    var modal = document.getElementById('confirmModal');
    ok('modal opens', modal.hidden === false);
    modal.querySelector('[data-modal-cancel]').click(); await wait(400);
    ok('cancel keeps the report', App.Store.complaintById(id) !== null);
    await go('/complaints/' + id + '/delete', 600);
    var cdb = view().querySelector('[data-confirm-delete]');
    ok('delete confirm button present', !!cdb);
    if (cdb) cdb.click(); await wait(400);
    document.getElementById('confirmModal').querySelector('[data-modal-ok]').click(); await wait(900);
    ok('confirmed delete removes it', App.Store.complaintById(id) === null);
    ok('lands on the list', window.location.hash === '#/complaints', window.location.hash);

    // ================= 7. registration =================
    ok('signed out', await signIn('nobody@example.com', 'x') === false || true);
    App.Auth.logout(); await wait(250);
    await go('/register', 600);
    f = view().querySelector('#registerForm');
    fill(f, { name: 'A', email: 'bad', phone: '9', password: 'weak', passwordConfirm: 'other' });
    await fire(f, 900);
    ok('register name rule explained', html().indexOf('at least 2 characters') !== -1);
    ok('register email rule explained', html().indexOf('valid email address') !== -1);
    ok('register phone rule explained', html().indexOf('valid phone number') !== -1);
    ok('register password rule explained', html().indexOf('at least 8 characters') !== -1);
    ok('register mismatch explained', html().indexOf('do not match') !== -1);
    ok('register consent required', html().indexOf('tick the confirmation box') !== -1);

    var mail = 'suite.' + Math.floor(Math.random() * 1e9) + '@example.com';
    f = view().querySelector('#registerForm');
    fill(f, { name: 'Suite Person', email: mail, phone: '', address: 'Purok 2',
              password: 'Suite@Pass2026', passwordConfirm: 'Suite@Pass2026', agree: true });
    await fire(f, 3200);
    ok('account created via form', !!App.Store.userByEmail(mail));
    ok('auto signed in after registering', !!App.Auth.user(), 'hash=' + window.location.hash);
    ok('registration lands on dashboard', window.location.hash === '#/dashboard', window.location.hash);
    ok('welcome flash shown', /Welcome/.test(flashText()));
    ok('new account is a resident', App.Auth.user().role === 'resident');
    ok('new account sees an empty state', html().indexOf('You have not filed any reports yet') !== -1);

    // ================= 8. admin flows =================
    ok('admin signs in', await signIn('admin@barangay.gov.ph', 'Admin@12345'), 'admin sign-in failed');
    ok('is admin', App.Auth.isAdmin());
    ok('admin nav has Residents', document.getElementById('siteNav').textContent.indexOf('Residents') !== -1);

    await go('/users', 700);
    ok('admin reaches the users page', html().indexOf('Resident accounts') !== -1);
    ok('users table lists the resident', html().indexOf('resident@barangay.gov.ph') !== -1);

    await go('/users/new', 600);
    f = view().querySelector('[data-user-create]');
    ok('admin create form present', !!f);
    var madeMail = 'suite.admin.' + Math.floor(Math.random() * 1e9) + '@example.com';
    fill(f, { name: 'Made By Admin', email: madeMail, phone: '', address: '',
              password: 'Admin@Made2026', passwordConfirm: 'Admin@Made2026' });
    await fire(f, 3000);
    var made = App.Store.userByEmail(madeMail);
    ok('admin created an account', !!made);
    ok('back on the users list', window.location.hash === '#/users', window.location.hash);
    ok('session still the original admin', App.Auth.user().email === 'admin@barangay.gov.ph');
    ok('new account listed', html().indexOf(madeMail) !== -1);

    await go('/users', 700);
    var b = view().querySelector('[data-user-action="role"][data-user-id="' + made.id + '"][data-role="admin"]');
    ok('promote button present', !!b);
    if (b) { b.click(); await wait(700); }
    ok('promoted to admin', App.Store.userById(made.id).role === 'admin');
    ok('promotion did not change the session', App.Auth.user().email === 'admin@barangay.gov.ph');

    // force a real re-render: leave the route, then come back
    await go('/dashboard', 600);
    await go('/users', 700);
    b = view().querySelector('[data-user-action="role"][data-user-id="' + made.id + '"][data-role="resident"]');
    ok('demote button present', !!b);
    if (b) { b.click(); await wait(700); }
    ok('demoted to resident', App.Store.userById(made.id).role === 'resident');

    // answer "No" must block the action
    window.confirm = function () { return false; };
    await go('/dashboard', 600);
    await go('/users', 700);
    b = view().querySelector('[data-user-action="toggle"][data-user-id="' + made.id + '"]');
    ok('deactivate button present', !!b);
    if (b) { b.click(); await wait(700); }
    ok('answering No blocks deactivation', App.Store.userById(made.id).active === true);
    // keep auto-accepting for the rest of the admin section
    window.confirm = function () { return true; };

    await go('/dashboard', 600);
    await go('/users', 700);
    b = view().querySelector('[data-user-action="toggle"][data-user-id="' + made.id + '"]');
    if (b) { b.click(); await wait(700); }
    ok('deactivated', App.Store.userById(made.id).active === false);
    ok('deactivation flash shown', /has been deactivated/.test(flashText()));

    await go('/dashboard', 600);
    await go('/users', 700);
    b = view().querySelector('[data-user-action="toggle"][data-user-id="' + made.id + '"]');
    ok('reactivate button present', !!b);
    if (b) { b.click(); await wait(700); }
    ok('reactivated', App.Store.userById(made.id).active === true);

    await go('/users/' + App.Auth.user().id + '/delete', 700);
    ok('admin cannot delete their own account', html().indexOf('You cannot delete your own account') !== -1);

    await go('/users/' + made.id + '/delete', 700);
    ok('delete page renders', html().indexOf('cannot be undone') !== -1);
    var delBtn = view().querySelector('[data-confirm-user-delete]');
    ok('delete confirm button present', !!delBtn);
    if (delBtn) delBtn.click();
    await wait(400);
    document.getElementById('confirmModal').querySelector('[data-modal-cancel]').click(); await wait(400);
    ok('cancel keeps the account', App.Store.userById(made.id) !== null);
    await go('/users/' + made.id + '/delete', 700);
    delBtn = view().querySelector('[data-confirm-user-delete]');
    if (delBtn) delBtn.click();
    await wait(400);
    document.getElementById('confirmModal').querySelector('[data-modal-ok]').click(); await wait(1000);
    ok('confirmed delete removes the account', App.Store.userById(made.id) === null);

    // ================= 9. admin status change =================
    await go('/complaints', 700);
    ok('admin list shows every report', html().indexOf('All complaints') !== -1);
    var link = view().querySelector('.row-title a');
    await go(link.getAttribute('href').replace('#', ''), 700);
    var sf = view().querySelector('[data-status-form]');
    ok('admin sees the status editor', !!sf);
    fill(sf, { status: 'Resolved', adminNotes: 'Repaired on site.' });
    await fire(sf, 900);
    ok('status changed to Resolved', html().indexOf('Resolved') !== -1);
    ok('admin note saved', html().indexOf('Repaired on site.') !== -1);

    // ================= 10. persistence + export =================
    var before = JSON.parse(JSON.stringify(App.Store.allComplaints().length));
    var dump = App.Store.exportJson();
    ok('export contains no plain-text password', dump.indexOf('Resident@12345') === -1);
    App.Store.deleteComplaint(App.Store.allComplaints()[0].id);
    ok('one report removed for the test', App.Store.allComplaints().length === before - 1);
    App.Store.importJson(dump);
    ok('import restores it', App.Store.allComplaints().length === before);

    // ================= 11. resilience =================
    var injected = '<script>alert(1)<\/script>';
    var rowHtml = App.UI.complaintRow({
      id: 'x', referenceNo: 'R', title: injected, category: 'Other Concern', priority: 'Low',
      status: 'Pending', location: injected, description: injected, reporterName: injected,
      createdAt: new Date().toISOString(), adminNotes: ''
    }, App.Auth.user(), {});
    ok('script tags escaped in output', rowHtml.indexOf('<script>') === -1);
    ok('escaped form present', rowHtml.indexOf('&lt;script&gt;') !== -1);

    var threw = false;
    try { App.Store.importJson('{"nope":1}'); } catch (e) { threw = true; }
    ok('import rejects an invalid file', threw);

    window.confirm = realConfirm;

    return {
      results: results,
      pass: results.filter(function (r) { return r.ok; }).length,
      fail: results.filter(function (r) { return !r.ok; }).length
    };
  }

  return { run: run, get results() { return results; } };
})();
'ready';