/* ==========================================================================
   views/data.js - export, import and reset the local database
   Because this site is static, this page exists so the data is never a
   black box: a visitor can download a backup, restore one, or start over.
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var esc = App.UI.esc;

  function dataTools(ctx) {
    var user = ctx.user;
    var all = { users: App.Store.allUsers(), complaints: App.Store.allComplaints() };
    var engine = App.Crypto.engine();

    var html = '<section class="container section-narrow">' +
      '<nav class="breadcrumb"><a href="#/dashboard">&larr; Back to dashboard</a></nav>' +
      App.UI.pageIntro({
        eyebrow: 'Stored data',
        heading: 'Manage the database',
        sub: 'This site has no server, so everything is kept in this browser.'
      }) +
      App.Layout.localOnlyNoteHtml() +
      '<div class="stat-grid stat-grid-4">' +
        App.UI.statTile('Accounts', all.users.length, 'brand', 'In this browser') +
        App.UI.statTile('Reports', all.complaints.length, 'info', 'In this browser') +
        App.UI.statTile('Password hashing', engine.strong ? 'Strong' : 'Fallback', engine.strong ? 'success' : 'warning',
          engine.algorithm) +
        App.UI.statTile('Rounds', String(engine.iterations), 'neutral', 'PBKDF2 iterations') +
      '</div>' +

      (engine.strong ? '' :
        '<div class="storage-note"><strong>Reduced hashing strength is active.</strong>' +
        esc(engine.note) + '</div>') +

      '<div class="card">' +
        '<div class="card-head"><h2 class="card-title">Export a backup</h2></div>' +
        '<p class="card-text">Downloads every account and report as a JSON file. Keep it somewhere safe before clearing your browsing data.</p>' +
        '<button class="btn btn-primary" type="button" data-export>Download backup</button>' +
      '</div>' +

      '<div class="card">' +
        '<div class="card-head"><h2 class="card-title">Restore a backup</h2></div>' +
        '<p class="card-text">Replaces everything currently in this browser with the contents of a backup file. Accounts whose passwords were never hashed cannot be restored.</p>' +
        '<div class="field">' +
          '<label for="importFile">Choose a backup file</label>' +
          '<input type="file" id="importFile" accept="application/json,.json" data-import>' +
          '<p class="field-hint" data-import-result></p>' +
        '</div>' +
      '</div>' +

      '<div class="card card-danger">' +
        '<div class="card-head"><h2 class="card-title">Start over</h2></div>' +
        '<div class="danger-head">' +
          '<span class="danger-icon" aria-hidden="true">&#128465;</span>' +
          '<div><h2 class="danger-title">Erasing cannot be undone</h2>' +
          '<p class="danger-text">This deletes all ' + all.users.length + ' account(s) and ' +
            all.complaints.length + ' report(s) from this browser, then restores the demo data.</p></div>' +
        '</div>' +
        '<button class="btn btn-danger" type="button" data-reset>Erase and reseed demo data</button>' +
      '</div>' +
    '</section>';

    return {
      html: html,
      title: 'Manage data',
      nav: 'data',
      user: user,
      onMount: function (root) {
        root.querySelector('[data-export]').addEventListener('click', function () {
          var blob = new Blob([App.Store.exportJson()], { type: 'application/json' });
          var url = URL.createObjectURL(blob);
          var link = document.createElement('a');
          link.href = url;
          link.download = 'barangay-complaints-backup.json';
          document.body.appendChild(link);
          link.click();
          document.body.removeChild(link);
          setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
          App.UI.toast('Backup downloaded.', 'success');
        });

        var fileInput = root.querySelector('[data-import]');
        var result = root.querySelector('[data-import-result]');
        fileInput.addEventListener('change', function () {
          var file = fileInput.files && fileInput.files[0];
          if (!file) return;
          var reader = new FileReader();
          reader.onload = function () {
            try {
              var summary = App.Store.importJson(String(reader.result));
              result.textContent = 'Restored ' + summary.users + ' account(s) and ' +
                                   summary.complaints + ' report(s). Reloading...';
              result.className = 'field-hint';
              App.UI.toast('Backup restored. Reloading the page...', 'success');
              window.setTimeout(function () { window.location.reload(); }, 1200);
            } catch (error) {
              result.textContent = error.message;
              result.className = 'field-error';
            }
          };
          reader.readAsText(file);
        });

        root.querySelector('[data-reset]').addEventListener('click', function () {
          App.UI.confirmDialog({
            title: 'Erase everything?',
            message: 'All ' + all.users.length + ' account(s) and ' + all.complaints.length +
                     ' report(s) in this browser will be deleted and the demo data restored. ' +
                     'This cannot be undone.',
            confirmLabel: 'Erase everything'
          }).then(function (ok) {
            if (!ok) return;
            App.Store.reset();
            App.Auth.logout();
            App.UI.toast('Local data erased.', 'success');
            window.setTimeout(function () { window.location.reload(); }, 800);
          });
        });
      }
    };
  }

  App.Views = App.Views || {};
  App.Views.dataTools = dataTools;
})(window.App);