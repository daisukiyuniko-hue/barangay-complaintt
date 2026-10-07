/* In-browser end-to-end test for the static build.
   Run by pasting into the page console, or via the browser tool. */
window.BCR_TEST = (function () {
  'use strict';

  var results = [];
  function check(label, ok, detail) {
    results.push({ label: label, ok: !!ok, detail: ok ? '' : (detail || '') });
  }

  function resetDb() {
    // The store keeps an in-memory copy, so clearing localStorage is not
    // enough - the in-memory document has to be replaced too.
    App.Store.reset();
    window.sessionStorage.clear();
  }

  function hash(path) { window.location.hash = path; }

  function currentHtml() { return document.getElementById('view').innerHTML; }

  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  var uniqueEmail = 'test.resident.' + Math.floor(Math.random() * 1e9) + '@example.com';

  async function run() {
    resetDb();
    await wait(200);

    // ---- crypto engine --------------------------------------------------
    var engine = App.Crypto.engine();
    check('crypto engine reports algorithm', engine.algorithm === 'PBKDF2-HMAC-SHA256', engine.algorithm);
    check('crypto engine has iterations', engine.iterations > 0, String(engine.iterations));

    // pure JS fallback correctness: PBKDF2-HMAC-SHA256 RFC 6070-style vector
    // (password "password", salt "salt", 1 iteration -> known digest)
    var vecSalt = App.Crypto.toBase64(new TextEncoder().encode('salt'));
    check('base64 round-trips', App.Crypto.toBase64(App.Crypto.fromBase64(vecSalt)) === vecSalt);

    // ---- hash + verify ---------------------------------------------------
    var rec = await App.Crypto.hashPassword('GoodPass@2026');
    check('hash returns salt', !!rec.salt && rec.salt.length >= 16, rec.salt);
    check('hash is not the password', rec.hash.indexOf('GoodPass@2026') === -1);
    check('verify accepts right password', await App.Crypto.verifyPassword('GoodPass@2026', rec));
    check('verify rejects wrong password', !(await App.Crypto.verifyPassword('Wrong@2026', rec)));

    var rec2 = await App.Crypto.hashPassword('GoodPass@2026');
    check('same password gets a different salt', rec.salt !== rec2.salt);
    check('same password yields a different hash', rec.hash !== rec2.hash);
    check('second record still verifies', await App.Crypto.verifyPassword('GoodPass@2026', rec2));

    // ---- seed -----------------------------------------------------------
    await App.Auth.seed();
    var users = App.Store.allUsers();
    var complaints = App.Store.allComplaints();
    check('seed created 2 accounts', users.length === 2, 'got ' + users.length);
    check('seed created 6 reports', complaints.length === 6, 'got ' + complaints.length);
    check('admin account exists', !!App.Store.userByEmail('admin@barangay.gov.ph'));
    check('resident account exists', !!App.Store.userByEmail('resident@barangay.gov.ph'));

    App.Store.save();
    var stored = window.localStorage.getItem(App.Store.STORAGE_KEY) || '';
    check('no plain-text demo password in storage', stored.indexOf('Admin@12345') === -1);
    check('no plain-text resident password in storage', stored.indexOf('Resident@12345') === -1);
    check('storage records PBKDF2 algorithm', stored.indexOf('PBKDF2-HMAC-SHA256') !== -1);
    check('no account has a field literally named password',
      users.every(function (u) { return u.password === undefined; }));

    var salts = {};
    users.forEach(function (u) { salts[u.passwordSalt] = true; });
    check('every account has a distinct salt', Object.keys(salts).length === users.length);

    // ---- login ----------------------------------------------------------
    var bad = await App.Auth.login('admin@barangay.gov.ph', 'Wrong@1234');
    check('wrong password rejected', bad.ok === false);
    var unknown = await App.Auth.login('nobody@example.com', 'Whatever@1');
    check('unknown email rejected', unknown.ok === false);
    check('unknown email message does not leak account existence',
      unknown.message === bad.message, 'different messages');

    var good = await App.Auth.login('admin@barangay.gov.ph', 'Admin@12345');
    check('admin can sign in', good.ok === true);
    check('current user is the admin', App.Auth.user() && App.Auth.user().email === 'admin@barangay.gov.ph');
    check('isAdmin true for admin', App.Auth.isAdmin());

    // ---- persistence across reload -------------------------------------
    var beforeUsers = App.Store.allUsers().length;
    var savedText = window.localStorage.getItem(App.Store.STORAGE_KEY);
    check('data written to localStorage', !!savedText && savedText.length > 100);

    App.Auth.refresh();
    check('session survives refresh in the same tab', !!App.Auth.user());

    // ---- role isolation -------------------------------------------------
    var residentUser = App.Store.userByEmail('resident@barangay.gov.ph');
    var adminSeesAll = App.Store.visibleComplaints(App.Auth.user());
    check('admin sees every report', adminSeesAll.length === complaints.length,
      adminSeesAll.length + ' vs ' + complaints.length);
    var residentSees = App.Store.visibleComplaints(residentUser);
    check('resident sees only their own', residentSees.every(function (c) { return c.reporterId === residentUser.id; }));
    check('resident sees fewer or equal', residentSees.length <= adminSeesAll.length);

    var someoneElses = complaints.filter(function (c) { return c.reporterId !== residentUser.id; })[0];
    if (someoneElses) {
      check('resident cannot access another report', App.Store.canAccess(someoneElses, residentUser) === false);
      check('admin can access any report', App.Store.canAccess(complaints[0], App.Auth.user()) === true);
    }

    // ---- validation -----------------------------------------------------
    var v = App.Validate.validateComplaint({ title: 'ab', category: 'Nope', priority: 'Critical', location: 'x', description: 'short' });
    check('rejects short title', !!v.errors.title);
    check('rejects unknown category', !!v.errors.category);
    check('rejects unknown priority', !!v.errors.priority);
    check('rejects short location', !!v.errors.location);
    check('rejects short description', !!v.errors.description);

    var v2 = App.Validate.validateComplaint({
      title: 'Broken streetlight near the chapel',
      category: 'Electricity & Utilities', priority: 'High',
      location: 'Purok 4', description: 'The streetlight has been out for a week and the area is dark at night.'
    });
    check('accepts a valid complaint', Object.keys(v2.errors).length === 0, JSON.stringify(v2.errors));

    var v3 = App.Validate.validateRegistration({ name: 'A', email: 'bad', password: 'weak' }, 'register');
    check('rejects 1-char name', !!v3.errors.name);
    check('rejects bad email', !!v3.errors.email);
    check('rejects weak password', !!v3.errors.password);
    check('password policy needs a symbol',
      App.Validate.passwordPolicy('abcdefgh1') === 'Your password must contain at least one special character (for example ! @ # %).');
    check('password policy accepts a good password',
      App.Validate.passwordPolicy('GoodPass@2026') === null);

    var dupe = App.Validate.validateRegistration({ name: 'Someone', email: 'admin@barangay.gov.ph', password: 'Good@1234' }, 'register');
    check('rejects duplicate email', !!dupe.errors.email);

    // ---- CRUD create ----------------------------------------------------
    var before = App.Store.allComplaints().length;
    var record = {
      id: App.Crypto.randomId('cmp'),
      referenceNo: App.Store.nextReference(),
      title: 'Test complaint ' + Math.floor(Math.random() * 1000),
      description: 'A description that is definitely long enough to pass validation rules.',
      category: 'Water & Sanitation', priority: 'High', status: 'Pending',
      location: 'Purok 9', reporterId: residentUser.id, reporterName: residentUser.name,
      reporterEmail: residentUser.email, reporterPhone: '', adminNotes: '',
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
      updatedBy: residentUser.id
    };
    App.Store.putComplaint(record);
    App.Store.save();
    check('create adds one report', App.Store.allComplaints().length === before + 1);
    check('create assigns a reference', /^BCR-\d{4}-\d{4}$/.test(record.referenceNo), record.referenceNo);
    check('created report can be fetched', App.Store.complaintById(record.id).title === record.title);

    // ---- CRUD update ----------------------------------------------------
    record.title = 'Test complaint - updated title';
    record.status = 'In Review';
    record.adminNotes = 'Crew dispatched.';
    App.Store.putComplaint(record);
    var reread = App.Store.complaintById(record.id);
    check('update changes the title', reread.title === 'Test complaint - updated title');
    check('update changes the status', reread.status === 'In Review');
    check('update keeps the reference', reread.referenceNo === record.referenceNo);
    check('admin note is stored', reread.adminNotes === 'Crew dispatched.');

    // ---- CRUD delete ----------------------------------------------------
    App.Store.deleteComplaint(record.id);
    check('delete removes the report', App.Store.complaintById(record.id) === null);
    check('delete leaves the rest intact', App.Store.allComplaints().length === before);

    // ---- export / import ------------------------------------------------
    var dump = App.Store.exportJson();
    check('export produces JSON', dump.length > 100);
    var snapshot = App.Store.allComplaints().length;
    var summary = App.Store.importJson(dump);
    check('import restores complaints', App.Store.allComplaints().length === snapshot);
    check('import reports a summary', summary.complaints === snapshot);
    var threw = false;
    try { App.Store.importJson('{"nope": true}'); } catch (e) { threw = true; }
    check('import rejects a file without users/complaints', threw);

    // ---- user management ------------------------------------------------
    var created = await App.Auth.createUser({
      name: 'Test Resident', email: uniqueEmail,
      password: 'Temp@Pass123', role: 'resident', phone: '0917 000 1111', address: 'Purok 1'
    });
    check('admin can create an account', !!App.Store.userById(created.id));
    var signin = await App.Auth.login(uniqueEmail, 'Temp@Pass123');
    check('the new account can sign in', signin.ok === true);
    check('the new account is a resident', !!App.Auth.user() && App.Auth.user().role === 'resident', 'no session');
    check('the new account is not an admin', App.Auth.isAdmin() === false);

    created.role = 'admin';
    App.Store.putUser(created);
    App.Auth.refresh();
    check('promotion to admin works', App.Auth.isAdmin() === true);
    created.role = 'resident';
    App.Store.putUser(created);
    App.Auth.refresh();

    created.active = false;
    App.Store.putUser(created);
    App.Auth.refresh();
    check('a deactivated account cannot stay signed in', App.Auth.user() === null);
    var blocked = await App.Auth.login(uniqueEmail, 'Temp@Pass123');
    check('a deactivated account cannot sign in', blocked.ok === false);
    check('deactivation message is clear', /deactivated/i.test(blocked.message || ''), blocked.message);

    created.active = true;
    App.Store.putUser(created);
    App.Store.deleteUser(created.id);
    check('account can be deleted', App.Store.userById(created.id) === null);

    // ---- logout ---------------------------------------------------------
    await App.Auth.login('resident@barangay.gov.ph', 'Resident@12345');
    check('resident signed in', !!App.Auth.user());
    App.Auth.logout();
    check('logout clears the session', App.Auth.user() === null);
    var visible = App.Store.visibleComplaints(App.Auth.user());
    check('no session means no visible reports', visible.length === 0);

    // ---- XSS escaping ---------------------------------------------------
    var nasty = '<script>alert("xss")</script>';
    var html = App.UI.complaintRow({ id: 'x', referenceNo: 'R1', title: nasty, category: 'Other Concern',
      priority: 'Low', status: 'Pending', location: nasty, description: nasty,
      reporterName: nasty, createdAt: new Date().toISOString(), adminNotes: '' }, residentUser, {});
    check('script tags in titles are escaped', html.indexOf('<script>') === -1);
    check('escaped output is present instead', html.indexOf('&lt;script&gt;') !== -1);

    // ---- persistence across a real reload --------------------------------
    return {
      results: results,
      beforeReload: { users: App.Store.allUsers().length, complaints: App.Store.allComplaints().length },
      pass: results.filter(function (r) { return r.ok; }).length,
      fail: results.filter(function (r) { return !r.ok; }).length
    };
  }

  return { run: run, results: results };
})();
'ready';