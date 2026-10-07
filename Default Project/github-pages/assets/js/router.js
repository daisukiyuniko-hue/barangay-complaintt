/* ==========================================================================
   router.js - hash routing and page guards
   --------------------------------------------------------------------------
   Hash routes (#/complaints/abc123) are used because GitHub Pages serves only
   static files: there is no server to rewrite clean URLs, and hash routes work
   with zero configuration.

   Routes marked public can be opened by anyone. Every other route is
   "protected": an anonymous visitor is redirected to the login page and
   returned to the page they wanted once they sign in.
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var routes = [];
  var outlet = null;
  var afterRender = null;

  function define(pattern, handler, options) {
    options = options || {};
    var keys = [];
    var regexSource = pattern
      .replace(/[.+?^${}()|[\]\\]/g, '\\$&')
      .replace(/:(\w+)/g, function (_, key) { keys.push(key); return '([^/]+)'; });
    routes.push({
      regex: new RegExp('^' + regexSource + '/?$'),
      keys: keys,
      handler: handler,
      public: !!options.public,
      admin: !!options.admin
    });
  }

  function route() { return window.location.hash.replace(/^#/, '') || '/'; }

  function parseQuery(hash) {
    var index = hash.indexOf('?');
    if (index < 0) return {};
    var out = {};
    hash.slice(index + 1).split('&').forEach(function (pair) {
      if (!pair) return;
      var eq = pair.indexOf('=');
      var key = decodeURIComponent(eq < 0 ? pair : pair.slice(0, eq));
      var value = eq < 0 ? '' : decodeURIComponent(pair.slice(eq + 1).replace(/\+/g, ' '));
      out[key] = value;
    });
    return out;
  }

  function pathOf(hash) {
    var index = hash.indexOf('?');
    return index < 0 ? hash : hash.slice(0, index);
  }

  function match(path) {
    for (var i = 0; i < routes.length; i++) {
      var found = path.match(routes[i].regex);
      if (!found) continue;
      var params = {};
      routes[i].keys.forEach(function (key, index) {
        params[key] = decodeURIComponent(found[index + 1] || '');
      });
      return { route: routes[i], params: params };
    }
    return null;
  }

  function go(hash, options) {
    options = options || {};
    if (options.replace) {
      window.location.replace('#' + hash);
    } else {
      window.location.hash = hash;
    }
  }

  function resolve() {
    var hash = route();
    var path = pathOf(hash);
    var query = parseQuery(hash);
    var found = match(path);

    if (!found) {
      render(App.Views.notFound(404));
      return;
    }

    var user = App.Auth.user();

    // ---- guards ---------------------------------------------------------
    if (!found.route.public && !user) {
      var next = encodeURIComponent(hash);
      go('/login?next=' + next, { replace: true });
      return;
    }
    if (found.route.admin && !App.Auth.isAdmin()) {
      render(App.Views.forbidden());
      return;
    }

    function errorView() {
      return App.Views.errorPage({
        code: 500,
        heading: 'Something went wrong on our side',
        message: 'This page could not be displayed. Please go back and try again.'
      });
    }

    // ---- render ---------------------------------------------------------
    var result;
    try {
      result = found.route.handler({ params: found.params, query: query, hash: hash, user: user });
    } catch (error) {
      console.error('Failed to render ' + path, error);
      App.UI.busy(false);
      render(errorView());
      return;
    }

    if (result && typeof result.then === 'function') {
      App.UI.busy(true);
      result.then(function (view) {
        App.UI.busy(false);
        render(view);
      }).catch(function (error) {
        App.UI.busy(false);
        console.error('Failed to render ' + path, error);
        render(errorView());
      });
    } else {
      render(result || { html: '', title: '', nav: '' });
    }
  }

  function render(view) {
    if (!outlet) outlet = document.getElementById('view');
    if (!outlet) return;

    outlet.innerHTML = view.html || '';
    outlet.setAttribute('aria-busy', 'false');
    document.title = view.title ? (view.title + ' - Barangay San Isidro') : 'Barangay San Isidro';

    App.Layout.renderNav(view.nav || '', view.user !== undefined ? view.user : App.Auth.user());
    App.Layout.renderFlash(view.flash || null);

    if (afterRender) afterRender(view);
    if (typeof view.onMount === 'function') {
      try { view.onMount(outlet); } catch (e) { console.error(e); }
    }

    // Close the mobile menu and move focus to the new content.
    App.Layout.closeMobileNav();
    if (!view.keepScroll) window.scrollTo(0, 0);
  }

  function start(options) {
    outlet = document.getElementById('view');
    afterRender = options && options.afterRender;

    define('/', App.Views.landing, { public: true });
    define('/login', App.Views.login, { public: true });
    define('/register', App.Views.register, { public: true });

    define('/dashboard', App.Views.dashboard);
    define('/complaints', App.Views.complaintList);
    define('/complaints/new', App.Views.complaintForm);
    define('/complaints/:id', App.Views.complaintDetail);
    define('/complaints/:id/edit', App.Views.complaintEdit);
    define('/complaints/:id/delete', App.Views.complaintDelete);
    define('/users', App.Views.userList, { admin: true });
    define('/users/new', App.Views.userCreate, { admin: true });
    define('/users/:id/delete', App.Views.userDelete, { admin: true });
    define('/profile', App.Views.profile);
    define('/profile/password', App.Views.changePassword);
    define('/data', App.Views.dataTools);

    window.addEventListener('hashchange', resolve);
    resolve();
  }

  App.Router = {
    define: define,
    start: start,
    resolve: resolve,
    go: go,
    route: route,
    parseQuery: parseQuery,
    pathOf: pathOf,
    render: render
  };
})(window.App);