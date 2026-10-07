/* ==========================================================================
   auth.js - accounts, sessions and page guards
   --------------------------------------------------------------------------
   Passwords are hashed with PBKDF2-HMAC-SHA256 (see crypto.js). Only the
   salt, the derived key and the iteration count are kept on the account.
   There is no plain-text password field anywhere.

   Sessions live in sessionStorage with an expiry timestamp, so signing out in
   one tab does not fight with another tab.
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var SESSION_KEY = 'bcr.session.v1';
  var SESSION_HOURS = 8;

  var currentUser = null;
  var booted = false;

  // ---------------------------------------------------------------- create --
  function createUser(opts) {
    return App.Crypto.hashPassword(opts.password).then(function (record) {
      var user = {
        id: App.Crypto.randomId('usr'),
        name: String(opts.name).trim(),
        email: String(opts.email).trim().toLowerCase(),
        role: opts.role === 'admin' ? 'admin' : 'resident',
        phone: opts.phone || '',
        address: opts.address || '',
        active: opts.active !== false,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        lastLoginAt: '',
        passwordSalt: record.salt,
        passwordHash: record.hash,
        passwordAlgorithm: record.algorithm,
        passwordIterations: record.iterations
      };
      App.Store.putUser(user);
      App.Store.logActivity('user_create', user.id, 'Created ' + user.role + ' account ' + user.email);
      return user;
    });
  }

  function setPassword(user, password) {
    return App.Crypto.hashPassword(password).then(function (record) {
      user.passwordSalt = record.salt;
      user.passwordHash = record.hash;
      user.passwordAlgorithm = record.algorithm;
      user.passwordIterations = record.iterations;
      user.updatedAt = new Date().toISOString();
      App.Store.putUser(user);
      return user;
    });
  }

  // --------------------------------------------------------------- session --
  function readSession() {
    var raw = null;
    try { raw = window.sessionStorage.getItem(SESSION_KEY); } catch (e) { return null; }
    if (!raw) return null;
    try {
      var parsed = JSON.parse(raw);
      if (!parsed || !parsed.userId || !parsed.expiresAt) return null;
      if (new Date(parsed.expiresAt).getTime() <= Date.now()) {
        clearSession();
        return null;
      }
      var user = App.Store.userById(parsed.userId);
      if (!user || user.active === false) {
        clearSession();
        return null;
      }
      return parsed;
    } catch (e) {
      clearSession();
      return null;
    }
  }

  function writeSession(userId) {
    var expires = new Date(Date.now() + SESSION_HOURS * 3600 * 1000).toISOString();
    try {
      window.sessionStorage.setItem(SESSION_KEY, JSON.stringify({ userId: userId, expiresAt: expires }));
    } catch (e) { /* storage blocked - the session simply will not survive a reload */ }
  }

  function clearSession() {
    try { window.sessionStorage.removeItem(SESSION_KEY); } catch (e) { }
  }

  // Deliberately vague: the same wording is used whether the email is unknown
  // or the password is wrong, so the form cannot be used to discover which
  // email addresses have accounts.
  var LOGIN_FAILED = 'That email address and password combination did not match an account. Please check them and try again.';

  /** Starts a session for an already-verified user. */
  function signIn(user) {
    writeSession(user.id);
    currentUser = user;
    return user;
  }

  function login(email, password) {
    var user = App.Store.userByEmail(email);
    if (!user) {
      return Promise.resolve({ ok: false, field: 'email', message: LOGIN_FAILED });
    }
    if (user.active === false) {
      return Promise.resolve({ ok: false, field: 'email',
        message: 'This account has been deactivated. Please contact the Barangay Hall.' });
    }

    return App.Crypto.verifyPassword(password, user).then(function (valid) {
      if (!valid) {
        return { ok: false, field: 'password', message: LOGIN_FAILED };
      }
      signIn(user);
      user.lastLoginAt = new Date().toISOString();
      App.Store.putUser(user);
      App.Store.logActivity('login', user.id, 'Signed in as ' + user.role);
      return { ok: true, user: user };
    });
  }

  function logout() {
    if (currentUser) App.Store.logActivity('logout', currentUser.id, 'Signed out');
    clearSession();
    currentUser = null;
  }

  function refresh() {
    var session = readSession();
    currentUser = session ? App.Store.userById(session.userId) : null;
    if (currentUser && currentUser.active === false) { currentUser = null; clearSession(); }
    return currentUser;
  }

  function user() { return currentUser; }
  function isAdmin() { return App.Store.isAdmin(currentUser); }
  function isSignedIn() { return !!currentUser; }

  function initials(name) {
    var value = String(name || '').trim();
    if (!value) return '?';
    var parts = value.split(/\s+/).filter(function (p) { return p !== ''; });
    if (!parts.length) return '?';
    var first = parts[0].charAt(0).toUpperCase();
    var last = (parts.length > 1 ? parts[parts.length - 1] : parts[0]).charAt(0).toUpperCase();
    return (first + last).toUpperCase();
  }

  // ----------------------------------------------------------------- seed --
  var SAMPLE_COMPLAINTS = [
    { title: 'Deep pothole in front of Barangay Hall', category: 'Road & Infrastructure', priority: 'Urgent',
      location: 'Main Road, front of Barangay Hall',
      description: 'There is a very deep pothole right in front of the Barangay Hall entrance. Several motorcycles have already fallen into it and it is very dangerous at night because there is no lighting there.',
      status: 'In Review', notes: 'Road crew scheduled to patch this week. Temporary warning signs installed.', hoursAgo: 30 },
    { title: 'Streetlight not working since last week', category: 'Electricity & Utilities', priority: 'Medium',
      location: 'Purok 5 corner',
      description: 'The streetlight at the corner of Purok 5 has not been working for about a week. At night the area becomes very dark and unsafe for pedestrians, especially for children going to school.',
      status: 'Pending', notes: '', hoursAgo: 52 },
    { title: 'Garbage pile up near the creek', category: 'Water & Sanitation', priority: 'High',
      location: 'Purok 2, near the creek',
      description: 'Garbage has been piling up near the creek for more than two weeks. It smells bad and flies are everywhere. When it rains the waste flows into the creek and affects the households downstream.',
      status: 'Resolved', notes: 'Waste collection schedule moved to twice a week. Area cleared on site.', hoursAgo: 96 },
    { title: 'Loud videoke every weekend past midnight', category: 'Noise & Nuisance', priority: 'Medium',
      location: 'Purok 7',
      description: 'Our neighbour plays loud videoke music every weekend until past midnight. We cannot sleep and our small children are already exhausted by school time.',
      status: 'In Review', notes: 'Barangay Peace and Order officer scheduled to mediate.', hoursAgo: 140 },
    { title: 'Water supply interruption every afternoon', category: 'Water & Sanitation', priority: 'High',
      location: 'Purok 4',
      description: 'Our water supply is cut off almost every afternoon from 1 PM to about 5 PM. This has been happening for three weeks already and it is very inconvenient for the households in our purok.',
      status: 'Pending', notes: '', hoursAgo: 190 },
    { title: 'Broken railing on the basketball court', category: 'Health & Safety', priority: 'Urgent',
      location: 'Barangay Sports Complex',
      description: 'One side of the basketball court railing is broken and hanging. Children play there every day and the sharp metal could badly hurt somebody if they run into it.',
      status: 'Resolved', notes: 'Railing replaced with a new steel one. Court reopened.', hoursAgo: 260 }
  ];

  function seed() {
    if (App.Store.isSeeded()) return Promise.resolve(false);

    var admin = App.Store.userByEmail('admin@barangay.gov.ph');
    var resident = App.Store.userByEmail('resident@barangay.gov.ph');

    return createUser({
      name: 'Barangay Administrator', email: 'admin@barangay.gov.ph',
      password: 'Admin@12345', role: 'admin', phone: '0917 000 0000', address: 'Barangay Hall, Purok 3'
    }).then(function (createdAdmin) {
      admin = createdAdmin;
      return createUser({
        name: 'Juan Dela Cruz', email: 'resident@barangay.gov.ph',
        password: 'Resident@12345', role: 'resident', phone: '0918 123 4567', address: 'Purok 5, San Isidro'
      });
    }).then(function (createdResident) {
      resident = createdResident;
      var now = Date.now();
      SAMPLE_COMPLAINTS.forEach(function (s) {
        var created = new Date(now - s.hoursAgo * 3600 * 1000).toISOString();
        App.Store.putComplaint({
          id: App.Crypto.randomId('cmp'),
          referenceNo: App.Store.nextReference(),
          title: s.title,
          description: s.description,
          category: s.category,
          priority: s.priority,
          status: s.status,
          location: s.location,
          reporterId: resident.id,
          reporterName: resident.name,
          reporterEmail: resident.email,
          reporterPhone: resident.phone,
          adminNotes: s.notes,
          createdAt: created,
          updatedAt: created,
          updatedBy: s.status === 'Pending' ? '' : admin.id
        });
      });
      App.Store.save();
      return true;
    });
  }

  function boot() {
    if (booted) return Promise.resolve(user());
    return seed().then(function () {
      refresh();
      booted = true;
      return user();
    });
  }

  App.Auth = {
    SESSION_HOURS: SESSION_HOURS,
    boot: boot,
    refresh: refresh,
    createUser: createUser,
    setPassword: setPassword,
    signIn: signIn,
    login: login,
    logout: logout,
    user: user,
    isAdmin: isAdmin,
    isSignedIn: isSignedIn,
    initials: initials,
    seed: seed
  };
})(window.App);