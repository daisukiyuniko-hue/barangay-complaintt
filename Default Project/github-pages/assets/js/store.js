/* ==========================================================================
   store.js - the "database"
   --------------------------------------------------------------------------
   GitHub Pages can only serve static files, so the data lives in the browser's
   localStorage instead of a server. Everything (users, complaints, sessions)
   is one JSON document written under a single key, saved atomically.

   Honest limitations of a browser-only store, surfaced in the UI:
     - data belongs to ONE browser on ONE device
     - clearing site data deletes it
   DataBackup.exportJson() / importJson() let the work move between machines.
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var STORAGE_KEY = 'bcr.db.v1';
  var SCHEMA_VERSION = 1;

  var CATEGORIES = [
    { value: 'Road & Infrastructure',   hint: 'Potholes, unfinished roads, broken sidewalks, missing street signs' },
    { value: 'Water & Sanitation',      hint: 'Water interruptions, leaking pipes, solid waste, septic tank issues' },
    { value: 'Electricity & Utilities', hint: 'Power outages, downed electric lines, non-working streetlights' },
    { value: 'Health & Safety',         hint: 'Accident hazards, flooding, fire risk, public health concerns' },
    { value: 'Noise & Nuisance',        hint: 'Loud noise, barking dogs, foul odours, neighbour disputes' },
    { value: 'Peace & Order',           hint: 'Vandalism, theft, loitering, suspicious activity' },
    { value: 'Education & Youth',       hint: 'School concerns, sports facilities, youth programs' },
    { value: 'Other Concern',           hint: 'Anything else that affects your barangay' }
  ];

  var PRIORITIES = [
    { value: 'Low',    hint: 'Can wait for the next maintenance cycle' },
    { value: 'Medium', hint: 'Affects daily life and should be scheduled soon' },
    { value: 'High',   hint: 'Needs attention within a few days' },
    { value: 'Urgent', hint: 'Dangerous or blocking basic services right now' }
  ];

  var STATUSES = [
    { value: 'Pending',   hint: 'Report received and awaiting initial review' },
    { value: 'In Review', hint: 'A committee member is validating and acting on it' },
    { value: 'Resolved',  hint: 'Action completed and confirmed' },
    { value: 'Rejected',  hint: 'Outside the barangay scope or a duplicate of another report' }
  ];

  var CATEGORY_ICONS = {
    'Road & Infrastructure':   'cat-road.svg',
    'Water & Sanitation':      'cat-water.svg',
    'Electricity & Utilities': 'cat-power.svg',
    'Health & Safety':         'cat-health.svg',
    'Noise & Nuisance':        'cat-noise.svg',
    'Peace & Order':           'cat-peace.svg',
    'Education & Youth':       'cat-education.svg',
    'Other Concern':           'cat-other.svg'
  };

  var db = null;

  // ------------------------------------------------------------- plumbing --
  function isAvailable() {
    try {
      var probe = '__bcr_probe__';
      window.localStorage.setItem(probe, '1');
      window.localStorage.removeItem(probe);
      return true;
    } catch (e) { return false; }
  }

  function emptyDb() {
    return {
      meta: { schemaVersion: SCHEMA_VERSION, createdAt: new Date().toISOString() },
      users: [],
      complaints: [],
      sessions: [],
      activityLog: [],
      counters: { complaint: 0 }
    };
  }

  function load() {
    if (db) return db;
    var raw = null;
    try { raw = window.localStorage.getItem(STORAGE_KEY); } catch (e) { raw = null; }

    if (raw) {
      try {
        db = JSON.parse(raw);
        repair();
        return db;
      } catch (e) {
        console.warn('Stored data was unreadable and has been reset.', e);
      }
    }
    db = emptyDb();
    save();
    return db;
  }

  function repair() {
    var fresh = emptyDb();
    Object.keys(fresh).forEach(function (key) {
      if (db[key] === undefined || db[key] === null) db[key] = fresh[key];
    });
    ['users', 'complaints', 'sessions', 'activityLog'].forEach(function (key) {
      if (!Array.isArray(db[key])) db[key] = [];
    });
    if (typeof db.counters !== 'object' || db.counters === null) db.counters = { complaint: 0 };
    if (typeof db.counters.complaint !== 'number') db.counters.complaint = 0;
  }

  function save() {
    try {
      // Write-then-verify: if the browser refuses (private mode, quota) we must
      // not let the app carry on pretending the write succeeded.
      var payload = JSON.stringify(db);
      window.localStorage.setItem(STORAGE_KEY, payload);
      var readBack = window.localStorage.getItem(STORAGE_KEY);
      if (readBack !== payload) throw new Error('write verification failed');
      return true;
    } catch (e) {
      console.error('Could not save to localStorage', e);
      App.storeError = 'Changes cannot be saved. Your browser is blocking local storage ' +
                       '(private browsing, or storage is full).';
      return false;
    }
  }

  // ----------------------------------------------------------------- users --
  function allUsers() { return load().users.slice(); }

  function userById(id) {
    var list = load().users;
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
    return null;
  }

  function userByEmail(email) {
    var needle = String(email || '').trim().toLowerCase();
    if (!needle) return null;
    var list = load().users;
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].email).toLowerCase() === needle) return list[i];
    }
    return null;
  }

  function putUser(user) {
    var list = load().users;
    var index = -1;
    for (var i = 0; i < list.length; i++) if (list[i].id === user.id) { index = i; break; }
    if (index >= 0) list[index] = user; else list.push(user);
    save();
    return user;
  }

  function deleteUser(id) {
    load().users = load().users.filter(function (u) { return u.id !== id; });
    save();
  }

  function isAdmin(user) { return !!user && user.role === 'admin'; }

  function activeAdminCount() {
    return load().users.filter(function (u) { return u.role === 'admin' && u.active !== false; }).length;
  }

  // ------------------------------------------------------------ complaints --
  function allComplaints() { return load().complaints.slice(); }

  function complaintById(id) {
    var list = load().complaints;
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
    return null;
  }

  function putComplaint(complaint) {
    var list = load().complaints;
    var index = -1;
    for (var i = 0; i < list.length; i++) if (list[i].id === complaint.id) { index = i; break; }
    if (index >= 0) list[index] = complaint; else list.push(complaint);
    save();
    return complaint;
  }

  function deleteComplaint(id) {
    load().complaints = load().complaints.filter(function (c) { return c.id !== id; });
    save();
  }

  function nextReference() {
    var data = load();
    data.counters.complaint += 1;
    return 'BCR-' + new Date().getFullYear() + '-' + String(data.counters.complaint).padStart(4, '0');
  }

  function statsFor(userId) {
    var all = userId ? allComplaints().filter(function (c) { return c.reporterId === userId; })
                     : allComplaints();
    return {
      total:    all.length,
      pending:  all.filter(function (c) { return c.status === 'Pending'; }).length,
      inReview: all.filter(function (c) { return c.status === 'In Review'; }).length,
      resolved: all.filter(function (c) { return c.status === 'Resolved'; }).length,
      rejected: all.filter(function (c) { return c.status === 'Rejected'; }).length,
      urgent:   all.filter(function (c) { return c.priority === 'Urgent' && c.status !== 'Resolved'; }).length
    };
  }

  // Residents may only ever see their own reports; admins see everything.
  function visibleComplaints(user) {
    if (!user) return [];
    if (isAdmin(user)) return allComplaints();
    return allComplaints().filter(function (c) { return c.reporterId === user.id; });
  }

  function canAccess(complaint, user) {
    if (!complaint || !user) return false;
    if (isAdmin(user)) return true;
    return complaint.reporterId === user.id;
  }

  // ------------------------------------------------------------- activity --
  function logActivity(action, actorId, detail) {
    var data = load();
    data.activityLog.push({
      id: App.Crypto.randomId('log'),
      action: action,
      actorId: actorId || '',
      detail: detail || '',
      createdAt: new Date().toISOString()
    });
    if (data.activityLog.length > 200) {
      data.activityLog = data.activityLog.slice(-200);
    }
    // Persist immediately: logActivity is often the only write in a code path.
    save();
  }

  // ------------------------------------------------------- export / import --
  function exportJson() {
    return JSON.stringify(load(), null, 2);
  }

  function importJson(text) {
    var parsed;
    try { parsed = JSON.parse(text); }
    catch (e) { throw new Error('That file is not valid JSON.'); }

    if (!parsed || typeof parsed !== 'object') throw new Error('That file is not a database export.');
    if (!Array.isArray(parsed.users) || !Array.isArray(parsed.complaints)) {
      throw new Error('That file is missing the users or complaints list.');
    }
    // Never let an import silently drop the password material.
    parsed.users.forEach(function (u) {
      if (!u.passwordHash || !u.passwordSalt) throw new Error('Account ' + u.email + ' has no password hash.');
    });

    db = parsed;
    repair();
    save();
    return { users: db.users.length, complaints: db.complaints.length };
  }

  function reset() {
    db = emptyDb();
    save();
  }

  function isSeeded() {
    return load().users.length > 0;
  }

  App.Store = {
    STORAGE_KEY: STORAGE_KEY,
    CATEGORIES: CATEGORIES,
    PRIORITIES: PRIORITIES,
    STATUSES: STATUSES,
    CATEGORY_ICONS: CATEGORY_ICONS,

    isAvailable: isAvailable,
    load: load,
    save: save,
    reset: reset,
    isSeeded: isSeeded,

    allUsers: allUsers,
    userById: userById,
    userByEmail: userByEmail,
    putUser: putUser,
    deleteUser: deleteUser,
    isAdmin: isAdmin,
    activeAdminCount: activeAdminCount,

    allComplaints: allComplaints,
    complaintById: complaintById,
    putComplaint: putComplaint,
    deleteComplaint: deleteComplaint,
    nextReference: nextReference,
    statsFor: statsFor,
    visibleComplaints: visibleComplaints,
    canAccess: canAccess,

    logActivity: logActivity,
    exportJson: exportJson,
    importJson: importJson
  };
})(window.App);